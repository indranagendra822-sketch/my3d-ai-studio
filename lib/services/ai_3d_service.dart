import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class _UploadResult {
  final String path;
  final String prefix;

  const _UploadResult(this.path, this.prefix);
}

class Ai3dService {
  static const String _baseUrl = 'https://frogleo-image-to-3d.hf.space';

  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    'Referer': '$_baseUrl/',
    'Origin': _baseUrl,
    'Accept': '*/*',
  };

  static Future<String> generate3DModel({
    required File imageFile,
    void Function(String status)? onStatus,
  }) async {
    final client = http.Client();
    try {
      onStatus?.call('Uploading image to AI server...');
      final uploadResult = await _uploadImage(imageFile);

      onStatus?.call('Starting AI 3D generation...');
      final eventId = await _startGeneration(
        uploadedPath: uploadResult.path,
        apiPrefix: uploadResult.prefix,
      );

      onStatus?.call('AI is building your 3D model (30-90 sec)...');
      final candidates = await _waitForCandidates(
        client: client,
        eventId: eventId,
        apiPrefix: uploadResult.prefix,
      );

      onStatus?.call('Downloading 3D model...');
      final localPath = await _downloadFirstValid3dModel(candidates, onStatus);
      return localPath;
    } finally {
      client.close();
    }
  }

  static Future<_UploadResult> _uploadImage(File imageFile) async {
    for (final prefix in ['', '/gradio_api']) {
      final uri = Uri.parse('$_baseUrl$prefix/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_browserHeaders);
      request.files.add(
        await http.MultipartFile.fromPath('files', imageFile.path),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          return _UploadResult(decoded.first.toString(), prefix);
        }
      }
      if (response.statusCode != 404 && response.statusCode != 405) {
        throw Exception('Image upload failed (${response.statusCode})');
      }
    }
    throw Exception('AI server upload endpoint not found.');
  }

  static Future<String> _startGeneration({
    required String uploadedPath,
    required String apiPrefix,
  }) async {
    final uri = Uri.parse('$_baseUrl$apiPrefix/call/gen_shape');
    final payload = {
      'data': [
        {
          'path': uploadedPath,
          'meta': {'_type': 'gradio.FileData'},
        },
        5,
        5.5,
        1234,
        256,
        8000,
        10000,
        true,
      ],
    };

    final headers = Map<String, String>.from(_browserHeaders);
    headers['Content-Type'] = 'application/json';

    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
        'AI server error (${response.statusCode}): ${_truncate(response.body, 150)}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['event_id'] != null) {
      return decoded['event_id'].toString();
    }
    throw Exception('Invalid response from AI server.');
  }

  static Future<List<String>> _waitForCandidates({
    required http.Client client,
    required String eventId,
    required String apiPrefix,
  }) async {
    final uri = Uri.parse('$_baseUrl$apiPrefix/call/gen_shape/$eventId');
    final request = http.Request('GET', uri);
    request.headers.addAll(_browserHeaders);
    request.headers['Accept'] = 'text/event-stream';

    final response = await client.send(request).timeout(
      const Duration(minutes: 4),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to read AI result (${response.statusCode})');
    }

    String currentEvent = '';
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines.timeout(const Duration(minutes: 4))) {
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final dataStr = line.substring(5).trim();

        if (currentEvent == 'error') {
          if (dataStr.toLowerCase().contains('quota')) {
            throw Exception(
              'Free AI server quota limit reached. Please try again later.',
            );
          }
          throw Exception(
            'AI generation failed: ${dataStr.isEmpty ? "Server busy" : _truncate(dataStr, 180)}',
          );
        }

        if (currentEvent == 'complete') {
          final decoded = jsonDecode(dataStr);
          final candidates = _extractCandidates(decoded, apiPrefix);
          if (candidates.isNotEmpty) {
            return candidates;
          }
          throw Exception(
            '3D model link not found. Response: ${_truncate(dataStr, 200)}',
          );
        }
      }
    }

    throw Exception('Connection closed before 3D model finished.');
  }

  static List<String> _extractCandidates(dynamic decoded, String apiPrefix) {
    final List<String> urls = [];

    void addUnique(String url) {
      if (url.isNotEmpty && !urls.contains(url)) {
        urls.add(url);
      }
    }

    void addCandidate(String raw) {
      final value = raw.trim();
      if (value.isEmpty) return;

      if (value.startsWith('data:')) {
        addUnique(value);
        return;
      }

      if (value.startsWith('/static/')) {
        addUnique('$_baseUrl${Uri.encodeFull(value)}');
      } else if (value.startsWith('static/')) {
        addUnique('$_baseUrl/${Uri.encodeFull(value)}');
      }

      if (value.startsWith('http://') || value.startsWith('https://')) {
        final fixed = value.replaceFirst(
          'http://frogleo-image-to-3d.hf.space',
          _baseUrl,
        );
        if (fixed.contains('/file=/static/')) {
          addUnique(fixed.replaceFirst('/file=/static/', '/static/'));
        }
        addUnique(fixed);
        if (fixed.contains('$_baseUrl/file=') &&
            !fixed.contains('/gradio_api/file=')) {
          addUnique(
            fixed.replaceFirst('$_baseUrl/file=', '$_baseUrl/gradio_api/file='),
          );
        } else if (fixed.contains('$_baseUrl/gradio_api/file=')) {
          addUnique(
            fixed.replaceFirst('$_baseUrl/gradio_api/file=', '$_baseUrl/file='),
          );
        }
        return;
      }

      if (value.startsWith('/gradio_api/file=') || value.startsWith('/file=')) {
        addCandidate('$_baseUrl$value');
        return;
      }

      if (value.startsWith('gradio_api/file=') || value.startsWith('file=')) {
        addCandidate('$_baseUrl/$value');
        return;
      }

      final cleaned = value.startsWith('./') ? value.substring(2) : value;
      final encoded = Uri.encodeFull(cleaned);
      addUnique('$_baseUrl$apiPrefix/file=$encoded');
      addUnique('$_baseUrl/gradio_api/file=$encoded');
      addUnique('$_baseUrl/file=$encoded');
    }

    void collectFromItem(dynamic item) {
      if (item == null) return;

      if (item is String) {
        if (item.contains('<')) {
          final dataUriRegex = RegExp(
            r'''data:[^"'\s<>]+;base64,[A-Za-z0-9+/=]+''',
            caseSensitive: false,
          );
          for (final match in dataUriRegex.allMatches(item)) {
            final found = match.group(0);
            if (found != null) addCandidate(found);
          }

          final urlRegex = RegExp(
            r'''(https?:\/\/[^\s"'<>]+\.(?:glb|obj)[^\s"'<>]*|\/?static\/[^\s"'<>]+\.(?:glb|obj)[^\s"'<>]*|\/?(?:gradio_api\/)?file=[^\s"'<>]+\.(?:glb|obj)[^\s"'<>]*)''',
            caseSensitive: false,
          );
          for (final match in urlRegex.allMatches(item)) {
            final found = match.group(0);
            if (found != null) addCandidate(found);
          }
        } else {
          addCandidate(item);
        }
        return;
      }

      if (item is Map) {
        collectFromItem(item['url']);
        collectFromItem(item['value']);
        collectFromItem(item['path']);
        collectFromItem(item['name']);
        return;
      }

      if (item is List) {
        for (final element in item) {
          collectFromItem(element);
        }
      }
    }

    if (decoded is List) {
      if (decoded.length > 2) collectFromItem(decoded[2]);
      if (decoded.isNotEmpty) collectFromItem(decoded[0]);
      if (decoded.length > 1) collectFromItem(decoded[1]);
      if (decoded.length > 3) collectFromItem(decoded[3]);
    } else {
      collectFromItem(decoded);
    }

    final List<String> directStaticGlb = [];
    final List<String> otherGlb = [];
    final List<String> objUrls = [];
    final List<String> others = [];

    for (final u in urls) {
      final lower = u.toLowerCase();
      if (lower.contains('/static/') &&
          !lower.contains('/file=') &&
          lower.contains('.glb')) {
        directStaticGlb.add(u);
      } else if (lower.contains('.glb') || lower.startsWith('data:')) {
        otherGlb.add(u);
      } else if (lower.contains('.obj')) {
        objUrls.add(u);
      } else {
        others.add(u);
      }
    }
    return [...directStaticGlb, ...otherGlb, ...objUrls, ...others];
  }

  static List<int>? _extractValidGlbBytes(List<int> raw) {
    if (_hasGlbHeader(raw)) return raw;

    if (raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B) {
      try {
        final unzipped = gzip.decode(raw);
        if (_hasGlbHeader(unzipped)) return unzipped;
      } catch (_) {}
    }

    return null;
  }

  static bool _hasGlbHeader(List<int> bytes) {
    return bytes.length >= 12 &&
        bytes[0] == 0x67 &&
        bytes[1] == 0x6C &&
        bytes[2] == 0x54 &&
        bytes[3] == 0x46;
  }

  static Future<String> _downloadFirstValid3dModel(
    List<String> candidates,
    void Function(String status)? onStatus,
  ) async {
    final List<String> attemptLogs = [];

    for (final url in candidates) {
      try {
        if (url.startsWith('data:')) {
          final commaIndex = url.indexOf(',');
          if (commaIndex != -1) {
            final bytes = base64Decode(url.substring(commaIndex + 1));
            final validGlb = _extractValidGlbBytes(bytes);
            if (validGlb != null) {
              return _saveGlbBytes(validGlb);
            }
          }
          continue;
        }

        final response = await http
            .get(Uri.parse(url), headers: _browserHeaders)
            .timeout(const Duration(minutes: 2));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final validGlb = _extractValidGlbBytes(response.bodyBytes);
          if (validGlb != null) {
            return _saveGlbBytes(validGlb);
          }

          final text = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (_looksLikeObj(text)) {
            onStatus?.call('Converting 3D mesh to GLB...');
            final converted = _convertObjToGlb(text);
            if (converted != null) {
              return _saveGlbBytes(converted);
            }
          }

          attemptLogs.add(
            'Unsupported (${response.bodyBytes.length}B) ${_shortUrl(url)}',
          );
        } else {
          attemptLogs.add('HTTP ${response.statusCode} ${_shortUrl(url)}');
        }
      } catch (e) {
        attemptLogs.add('ERR ${_shortUrl(url)}: $e');
      }
    }

    final details = attemptLogs.isEmpty
        ? 'No download URLs'
        : attemptLogs.take(4).join('\n');
    throw Exception('Could not load 3D model.\n$details');
  }

  static bool _looksLikeObj(String text) {
    return RegExp(r'^v\s+-?\d', multiLine: true).hasMatch(text) &&
        RegExp(r'^f\s+\d', multiLine: true).hasMatch(text);
  }

  static Uint8List? _convertObjToGlb(String objText) {
    final List<double> posList = [];
    final List<int> idxList = [];

    for (final rawLine in const LineSplitter().convert(objText)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('v ')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final x = double.tryParse(parts[1]);
          final y = double.tryParse(parts[2]);
          final z = double.tryParse(parts[3]);
          if (x != null && y != null && z != null) {
            posList.add(x);
            posList.add(y);
            posList.add(z);
          }
        }
      } else if (line.startsWith('f ')) {
        final parts = line.split(RegExp(r'\s+'));
        final vertexCount = posList.length ~/ 3;
        final List<int> faceIndices = [];

        for (int i = 1; i < parts.length; i++) {
          final token = parts[i].split('/')[0];
          final parsed = int.tryParse(token);
          if (parsed == null) continue;
          final idx = parsed > 0 ? parsed - 1 : vertexCount + parsed;
          if (idx >= 0 && idx < vertexCount) {
            faceIndices.add(idx);
          }
        }

        if (faceIndices.length >= 3) {
          for (int i = 1; i < faceIndices.length - 1; i++) {
            idxList.add(faceIndices[0]);
            idxList.add(faceIndices[i]);
            idxList.add(faceIndices[i + 1]);
          }
        }
      }
    }

    final vertexCount = posList.length ~/ 3;
    if (vertexCount < 3 || idxList.length < 3) return null;

    double minX = posList[0], maxX = posList[0];
    double minY = posList[1], maxY = posList[1];
    double minZ = posList[2], maxZ = posList[2];

    for (int i = 0; i < posList.length; i += 3) {
      final x = posList[i];
      final y = posList[i + 1];
      final z = posList[i + 2];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }

    final positions = Float32List.fromList(posList);
    final normals = Float32List(posList.length);
    final indices = Uint32List.fromList(idxList);

    for (int i = 0; i < indices.length; i += 3) {
      final i0 = indices[i] * 3;
      final i1 = indices[i + 1] * 3;
      final i2 = indices[i + 2] * 3;

      final ax = positions[i1] - positions[i0];
      final ay = positions[i1 + 1] - positions[i0 + 1];
      final az = positions[i1 + 2] - positions[i0 + 2];

      final bx = positions[i2] - positions[i0];
      final by = positions[i2 + 1] - positions[i0 + 1];
      final bz = positions[i2 + 2] - positions[i0 + 2];

      final nx = ay * bz - az * by;
      final ny = az * bx - ax * bz;
      final nz = ax * by - ay * bx;

      normals[i0] += nx;
      normals[i0 + 1] += ny;
      normals[i0 + 2] += nz;

      normals[i1] += nx;
      normals[i1 + 1] += ny;
      normals[i1 + 2] += nz;

      normals[i2] += nx;
      normals[i2 + 1] += ny;
      normals[i2 + 2] += nz;
    }

    for (int i = 0; i < normals.length; i += 3) {
      final nx = normals[i];
      final ny = normals[i + 1];
      final nz = normals[i + 2];
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-8) {
        normals[i] = nx / len;
        normals[i + 1] = ny / len;
        normals[i + 2] = nz / len;
      } else {
        normals[i] = 0.0;
        normals[i + 1] = 1.0;
        normals[i + 2] = 0.0;
      }
    }

    final posByteLen = positions.length * 4;
    final normByteLen = normals.length * 4;
    final idxByteLen = indices.length * 4;
    final binLength = posByteLen + normByteLen + idxByteLen;

    final binData = ByteData(binLength);
    int offset = 0;
    for (int i = 0; i < positions.length; i++) {
      binData.setFloat32(offset, positions[i], Endian.little);
      offset += 4;
    }
    for (int i = 0; i < normals.length; i++) {
      binData.setFloat32(offset, normals[i], Endian.little);
      offset += 4;
    }
    for (int i = 0; i < indices.length; i++) {
      binData.setUint32(offset, indices[i], Endian.little);
      offset += 4;
    }

    final gltf = {
      'asset': {'version': '2.0', 'generator': 'My3D AI Studio'},
      'scene': 0,
      'scenes': [
        {
          'nodes': [0]
        }
      ],
      'nodes': [
        {'mesh': 0}
      ],
      'materials': [
        {
          'pbrMetallicRoughness': {
            'baseColorFactor': [0.85, 0.85, 0.88, 1.0],
            'metallicFactor': 0.1,
            'roughnessFactor': 0.7,
          },
          'doubleSided': true,
        }
      ],
      'meshes': [
        {
          'primitives': [
            {
              'attributes': {'POSITION': 0, 'NORMAL': 1},
              'indices': 2,
              'material': 0,
            }
          ]
        }
      ],
      'buffers': [
        {'byteLength': binLength}
      ],
      'bufferViews': [
        {
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': posByteLen,
          'target': 34962,
        },
        {
          'buffer': 0,
          'byteOffset': posByteLen,
          'byteLength': normByteLen,
          'target': 34962,
        },
        {
          'buffer': 0,
          'byteOffset': posByteLen + normByteLen,
          'byteLength': idxByteLen,
          'target': 34963,
        },
      ],
      'accessors': [
        {
          'bufferView': 0,
          'componentType': 5126,
          'count': vertexCount,
          'type': 'VEC3',
          'min': [minX, minY, minZ],
          'max': [maxX, maxY, maxZ],
        },
        {
          'bufferView': 1,
          'componentType': 5126,
          'count': vertexCount,
          'type': 'VEC3',
        },
        {
          'bufferView': 2,
          'componentType': 5125,
          'count': indices.length,
          'type': 'SCALAR',
        },
      ],
    };

    final jsonBytesRaw = utf8.encode(jsonEncode(gltf));
    final jsonPad = (4 - (jsonBytesRaw.length % 4)) % 4;
    final jsonChunkLen = jsonBytesRaw.length + jsonPad;
    final totalLength = 12 + 8 + jsonChunkLen + 8 + binLength;

    final glbBytes = Uint8List(totalLength);
    final header = ByteData.sublistView(glbBytes);
    header.setUint32(0, 0x46546C67, Endian.little);
    header.setUint32(4, 2, Endian.little);
    header.setUint32(8, totalLength, Endian.little);

    header.setUint32(12, jsonChunkLen, Endian.little);
    header.setUint32(16, 0x4E4F534A, Endian.little);
    glbBytes.setRange(20, 20 + jsonBytesRaw.length, jsonBytesRaw);
    for (int i = 0; i < jsonPad; i++) {
      glbBytes[20 + jsonBytesRaw.length + i] = 0x20;
    }

    final binChunkOffset = 20 + jsonChunkLen;
    header.setUint32(binChunkOffset, binLength, Endian.little);
    header.setUint32(binChunkOffset + 4, 0x004E4942, Endian.little);
    glbBytes.setRange(
      binChunkOffset + 8,
      binChunkOffset + 8 + binLength,
      binData.buffer.asUint8List(),
    );

    return glbBytes;
  }

  static String _shortUrl(String url) {
    return url.replaceFirst(_baseUrl, '');
  }

  static Future<String> _saveGlbBytes(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/my3d_$timestamp.glb');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
