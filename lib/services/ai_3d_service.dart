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

class _StartResult {
  final String eventId;
  final String prefix;
  const _StartResult(this.eventId, this.prefix);
}

class Ai3dService {
  static const String _fastBaseUrl = 'https://frogleo-image-to-3d.hf.space';
  static const String _texturedBaseUrl =
      'https://imagine-io-webinar-image-to-3d.hf.space';

  static Map<String, String> _headersFor(String baseUrl) => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        'Referer': '$baseUrl/',
        'Origin': baseUrl,
        'Accept': '*/*',
      };

  static Future<String> generate3DModel({
    required File imageFile,
    bool withTexture = false,
    void Function(String status)? onStatus,
  }) async {
    final baseUrl = withTexture ? _texturedBaseUrl : _fastBaseUrl;
    final endpoint = withTexture ? '/generation_all' : '/gen_shape';
    final client = http.Client();

    try {
      onStatus?.call(withTexture
          ? 'Uploading image to Color & Texture AI...'
          : 'Uploading image to Fast AI server...');
      final upload = await _uploadImage(baseUrl, imageFile);

      onStatus?.call(withTexture
          ? 'Starting Textured 3D generation...'
          : 'Starting Fast 3D generation...');

      final payload = withTexture
          ? {
              'data': [
                {'path': upload.path, 'meta': {'_type': 'gradio.FileData'}},
                null, null, null, null,
                5, 5.5, 1234, 256, true, 8000, true,
              ],
            }
          : {
              'data': [
                {'path': upload.path, 'meta': {'_type': 'gradio.FileData'}},
                5, 5.5, 1234, 256, 8000, 10000, true,
              ],
            };

      final start = await _startGeneration(
        baseUrl: baseUrl,
        apiPrefix: upload.prefix,
        endpoint: endpoint,
        payload: payload,
      );

      onStatus?.call(withTexture
          ? 'AI is building 3D shape & painting color texture (1-3 min)...'
          : 'AI is building your 3D model (30-90 sec)...');

      final urls = await _waitForCandidates(
        client: client,
        baseUrl: baseUrl,
        apiPrefix: start.prefix,
        endpoint: endpoint,
        eventId: start.eventId,
        withTexture: withTexture,
      );

      onStatus?.call('Downloading 3D model (.glb)...');
      return await _downloadFirstValid3dModel(baseUrl, urls, onStatus);
    } finally {
      client.close();
    }
  }

  static Future<_UploadResult> _uploadImage(String baseUrl, File file) async {
    for (final prefix in ['', '/gradio_api']) {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$prefix/upload'));
      req.headers.addAll(_headersFor(baseUrl));
      req.files.add(await http.MultipartFile.fromPath('files', file.path));
      final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 60)),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List && decoded.isNotEmpty) {
          return _UploadResult(decoded.first.toString(), prefix);
        }
      }
      if (res.statusCode != 404 && res.statusCode != 405) {
        throw Exception('Image upload failed (${res.statusCode})');
      }
    }
    throw Exception('AI server upload endpoint not found.');
  }

  static Future<_StartResult> _startGeneration({
    required String baseUrl,
    required String apiPrefix,
    required String endpoint,
    required Map<String, dynamic> payload,
  }) async {
    final headers = _headersFor(baseUrl)..['Content-Type'] = 'application/json';
    String lastError = 'AI server did not respond.';

    for (final prefix in [apiPrefix, apiPrefix.isEmpty ? '/gradio_api' : '']) {
      final res = await http
          .post(Uri.parse('$baseUrl$prefix/call$endpoint'),
              headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['event_id'] != null) {
          return _StartResult(decoded['event_id'].toString(), prefix);
        }
      }
      lastError = 'AI server error (${res.statusCode}):${_truncate(res.body, 140)}';
      if (res.statusCode != 404 && res.statusCode != 405) {
        throw Exception(lastError);
      }
    }
    throw Exception(lastError);
  }

  static Future<List<String>> _waitForCandidates({
    required http.Client client,
    required String baseUrl,
    required String apiPrefix,
    required String endpoint,
    required String eventId,
    required bool withTexture,
  }) async {
    final req = http.Request('GET', Uri.parse('$baseUrl$apiPrefix/call$endpoint/$eventId'));
    req.headers.addAll(_headersFor(baseUrl));
    req.headers['Accept'] = 'text/event-stream';

    final timeout = Duration(minutes: withTexture ? 6 : 4);
    final res = await client.send(req).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('Failed to read AI result (${res.statusCode})');
    }

    String currentEvent = '';
    final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines.timeout(timeout)) {
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final dataStr = line.substring(5).trim();
        if (currentEvent == 'error') {
          if (dataStr.toLowerCase().contains('quota')) {
            throw Exception('Free GPU quota limit reached. Try Fast mode or try later.');
          }
          throw Exception('AI generation failed: ${dataStr.isEmpty ? "Server busy" : _truncate(dataStr, 160)}');
        }
        if (currentEvent == 'complete') {
          final candidates = _extractCandidates(
            jsonDecode(dataStr), baseUrl, apiPrefix, withTexture,
          );
          if (candidates.isNotEmpty) return candidates;
          throw Exception('3D model link not found.');
        }
      }
    }
    throw Exception('Connection closed before 3D model finished.');
  }

  static List<String> _extractCandidates(
    dynamic decoded, String baseUrl, String apiPrefix, bool withTexture,
  ) {
    final urls = <String>[];
    void addUnique(String u) {
      if (u.isNotEmpty && !urls.contains(u)) urls.add(u);
    }

    void addCandidate(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      if (v.startsWith('data:')) return addUnique(v);
      if (v.startsWith('/static/')) addUnique('$baseUrl${Uri.encodeFull(v)}');
      if (v.startsWith('static/')) addUnique('$baseUrl/${Uri.encodeFull(v)}');

      if (v.startsWith('http://') || v.startsWith('https://')) {
        final fixed = v.replaceFirst(baseUrl.replaceFirst('https://', 'http://'), baseUrl);
        if (fixed.contains('/file=/static/')) {
          addUnique(fixed.replaceFirst('/file=/static/', '/static/'));
        }
        addUnique(fixed);
        if (fixed.contains('$baseUrl/file=') && !fixed.contains('/gradio_api/file=')) {
          addUnique(fixed.replaceFirst('$baseUrl/file=', '$baseUrl/gradio_api/file='));
        } else if (fixed.contains('$baseUrl/gradio_api/file=')) {
          addUnique(fixed.replaceFirst('$baseUrl/gradio_api/file=', '$baseUrl/file='));
        }
        return;
      }

      if (v.startsWith('/gradio_api/file=') || v.startsWith('/file=')) {
        return addCandidate('$baseUrl$v');
      }
      if (v.startsWith('gradio_api/file=') || v.startsWith('file=')) {
        return addCandidate('$baseUrl/$v');
      }

      final enc = Uri.encodeFull(v.startsWith('./') ? v.substring(2) : v);
      addUnique('$baseUrl$apiPrefix/file=$enc');
      addUnique('$baseUrl/gradio_api/file=$enc');
      addUnique('$baseUrl/file=$enc');
    }

    void collect(dynamic item) {
      if (item == null) return;
      if (item is String) {
        if (item.contains('<')) {
          final reg = RegExp(
            r'''(data:[^"'\s<>]+;base64,[A-Za-z0-9+/=]+|https?:\/\/[^\s"'<>]+\.(?:glb|obj)[^\s"'<>]*|\/?static\/[^\s"'<>]+\.(?:glb|obj)[^\s"'<>]*|\/?(?:gradio_api\/)?file=[^\s"'<>]+\.(?:glb|obj)[^\s"'<>]*)''',
            caseSensitive: false,
          );
          for (final m in reg.allMatches(item)) {
            if (m.group(0) != null) addCandidate(m.group(0)!);
          }
        } else {
          addCandidate(item);
        }
      } else if (item is Map) {
        collect(item['url']);
        collect(item['value']);
        collect(item['path']);
        collect(item['name']);
      } else if (item is List) {
        for (final e in item) {
          collect(e);
        }
      }
    }

    if (decoded is List) {
      final order = withTexture ? [1, 2, 0] : [2, 0, 1, 3];
      for (final i in order) {
        if (i < decoded.length) collect(decoded[i]);
      }
    } else {
      collect(decoded);
    }

    final glbs = urls.where((u) => u.toLowerCase().contains('.glb') || u.startsWith('data:')).toList();
    final objs = urls.where((u) => u.toLowerCase().contains('.obj') && !glbs.contains(u)).toList();
    final rest = urls.where((u) => !glbs.contains(u) && !objs.contains(u)).toList();
    return [...glbs, ...objs, ...rest];
  }

  static bool _isGlb(List<int> b) =>
      b.length >= 12 && b[0] == 0x67 && b[1] == 0x6C && b[2] == 0x54 && b[3] == 0x46;

  static List<int>? _validGlb(List<int> raw) {
    if (_isGlb(raw)) return raw;
    if (raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B) {
      try {
        final u = gzip.decode(raw);
        if (_isGlb(u)) return u;
      } catch (_) {}
    }
    return null;
  }

  static Future<String> _downloadFirstValid3dModel(
    String baseUrl, List<String> urls, void Function(String)? onStatus,
  ) async {
    final logs = <String>[];
    final headers = _headersFor(baseUrl);

    for (final url in urls) {
      try {
        if (url.startsWith('data:')) {
          final i = url.indexOf(',');
          if (i != -1) {
            final g = _validGlb(base64Decode(url.substring(i + 1)));
            if (g != null) return _saveGlb(g);
          }
          continue;
        }
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(minutes: 3));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final g = _validGlb(res.bodyBytes);
          if (g != null) return _saveGlb(g);
          final txt = utf8.decode(res.bodyBytes, allowMalformed: true);
          if (RegExp(r'^v\s+-?\d', multiLine: true).hasMatch(txt) &&
              RegExp(r'^f\s+\d', multiLine: true).hasMatch(txt)) {
            onStatus?.call('Converting 3D mesh to GLB...');
            final converted = _objToGlb(txt);
            if (converted != null) return _saveGlb(converted);
          }
          logs.add('Unsupported ${url.replaceFirst(baseUrl, '')}');
        } else {
          logs.add('HTTP ${res.statusCode}${url.replaceFirst(baseUrl, '')}');
        }
      } catch (e) {
        logs.add('ERR: $e');
      }
    }
    throw Exception('Could not load 3D model.\n${logs.take(4).join('\n')}');
  }

  static Uint8List? _objToGlb(String objText) {
    final pos = <double>[];
    final idx = <int>[];
    for (final raw in const LineSplitter().convert(objText)) {
      final line = raw.trim();
      if (line.startsWith('v ')) {
        final p = line.split(RegExp(r'\s+'));
        if (p.length >= 4) {
          final x = double.tryParse(p[1]), y = double.tryParse(p[2]), z = double.tryParse(p[3]);
          if (x != null && y != null && z != null) pos.addAll([x, y, z]);
        }
      } else if (line.startsWith('f ')) {
        final p = line.split(RegExp(r'\s+'));
        final vc = pos.length ~/ 3;
        final face = <int>[];
        for (int i = 1; i < p.length; i++) {
          final v = int.tryParse(p[i].split('/')[0]);
          if (v != null) {
            final k = v > 0 ? v - 1 : vc + v;
            if (k >= 0 && k < vc) face.add(k);
          }
        }
        for (int i = 1; i + 1 < face.length; i++) {
          idx.addAll([face[0], face[i], face[i + 1]]);
        }
      }
    }
    final vc = pos.length ~/ 3;
    if (vc < 3 || idx.length < 3) return null;

    double minX = pos[0], maxX = pos[0], minY = pos[1], maxY = pos[1], minZ = pos[2], maxZ = pos[2];
    for (int i = 0; i < pos.length; i += 3) {
      minX = math.min(minX, pos[i]); maxX = math.max(maxX, pos[i]);
      minY = math.min(minY, pos[i + 1]); maxY = math.max(maxY, pos[i + 1]);
      minZ = math.min(minZ, pos[i + 2]); maxZ = math.max(maxZ, pos[i + 2]);
    }

    final positions = Float32List.fromList(pos);
    final normals = Float32List(pos.length);
    final indices = Uint32List.fromList(idx);

    for (int i = 0; i < indices.length; i += 3) {
      final i0 = indices[i] * 3, i1 = indices[i + 1] * 3, i2 = indices[i + 2] * 3;
      final ax = positions[i1] - positions[i0], ay = positions[i1 + 1] - positions[i0 + 1], az = positions[i1 + 2] - positions[i0 + 2];
      final bx = positions[i2] - positions[i0], by = positions[i2 + 1] - positions[i0 + 1], bz = positions[i2 + 2] - positions[i0 + 2];
      final nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
      for (final j in [i0, i1, i2]) {
        normals[j] += nx; normals[j + 1] += ny; normals[j + 2] += nz;
      }
    }
    for (int i = 0; i < normals.length; i += 3) {
      final len = math.sqrt(normals[i] * normals[i] + normals[i + 1] * normals[i + 1] + normals[i + 2] * normals[i + 2]);
      if (len > 1e-8) {
        normals[i] /= len; normals[i + 1] /= len; normals[i + 2] /= len;
      } else {
        normals[i + 1] = 1.0;
      }
    }

    final pLen = positions.length * 4, nLen = normals.length * 4, iLen = indices.length * 4;
    final binLen = pLen + nLen + iLen;
    final bin = ByteData(binLen);
    int off = 0;
    for (final v in positions) { bin.setFloat32(off, v, Endian.little); off += 4; }
    for (final v in normals) { bin.setFloat32(off, v, Endian.little); off += 4; }
    for (final v in indices) { bin.setUint32(off, v, Endian.little); off += 4; }

    final gltf = {
      'asset': {'version': '2.0', 'generator': 'My3D AI Studio'},
      'scene': 0,
      'scenes': [{'nodes': [0]}],
      'nodes': [{'mesh': 0}],
      'materials': [{
        'pbrMetallicRoughness': {'baseColorFactor': [0.85, 0.85, 0.88, 1.0], 'metallicFactor': 0.1, 'roughnessFactor': 0.7},
        'doubleSided': true,
      }],
      'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1}, 'indices': 2, 'material': 0}]}],
      'buffers': [{'byteLength': binLen}],
      'bufferViews': [
        {'buffer': 0, 'byteOffset': 0, 'byteLength': pLen, 'target': 34962},
        {'buffer': 0, 'byteOffset': pLen, 'byteLength': nLen, 'target': 34962},
        {'buffer': 0, 'byteOffset': pLen + nLen, 'byteLength': iLen, 'target': 34963},
      ],
      'accessors': [
        {'bufferView': 0, 'componentType': 5126, 'count': vc, 'type': 'VEC3', 'min': [minX, minY, minZ], 'max': [maxX, maxY, maxZ]},
        {'bufferView': 1, 'componentType': 5126, 'count': vc, 'type': 'VEC3'},
        {'bufferView': 2, 'componentType': 5125, 'count': indices.length, 'type': 'SCALAR'},
      ],
    };

    final jRaw = utf8.encode(jsonEncode(gltf));
    final jPad = (4 - (jRaw.length % 4)) % 4;
    final jLen = jRaw.length + jPad;
    final total = 12 + 8 + jLen + 8 + binLen;
    final out = Uint8List(total);
    final h = ByteData.sublistView(out);
    h.setUint32(0, 0x46546C67, Endian.little);
    h.setUint32(4, 2, Endian.little);
    h.setUint32(8, total, Endian.little);
    h.setUint32(12, jLen,
