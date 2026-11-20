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

class _CandidateList {
  final List<String> urls;

  const _CandidateList(this.urls);
}

class Ai3dService {
  static const String _fastBaseUrl = 'https://frogleo-image-to-3d.hf.space';
  static const String _texturedBaseUrl =
      'https://imagine-io-webinar-image-to-3d.hf.space';

  static Map<String, String> _headersFor(String baseUrl) {
    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      'Referer': '$baseUrl/',
      'Origin': baseUrl,
      'Accept': '*/*',
    };
  }

  static Future<String> generate3DModel({
    required File imageFile,
    bool withTexture = false,
    void Function(String status)? onStatus,
  }) async {
    final baseUrl = withTexture ? _texturedBaseUrl : _fastBaseUrl;
    final endpoint = withTexture ? '/generation_all' : '/gen_shape';
    final client = http.Client();

    try {
      onStatus?.call(
        withTexture
            ? 'Uploading image to Color & Texture AI...'
            : 'Uploading image to Fast AI server...',
      );
      final uploadResult = await _uploadImage(baseUrl, imageFile);

      int turboSteps = 5;
      if (withTexture) {
        turboSteps = await _fetchTurboSteps(baseUrl, uploadResult.prefix);
      }

      onStatus?.call(
        withTexture
            ? 'Starting Textured 3D generation...'
            : 'Starting Fast 3D generation...',
      );

      final Map<String, dynamic> payload = withTexture
          ? {
              'data': [
                {
                  'path': uploadResult.path,
                  'meta': {'_type': 'gradio.FileData'},
                },
                null,
                null,
                null,
                null,
                turboSteps,
                5.5,
                1234,
                256,
                true,
                8000,
                true,
              ],
            }
          : {
              'data': [
                {
                  'path': uploadResult.path,
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

      final startResult = await _startGeneration(
        baseUrl: baseUrl,
        apiPrefix: uploadResult.prefix,
        endpoint: endpoint,
        payload: payload,
      );

      onStatus?.call(
        withTexture
            ? 'AI is building 3D shape & painting color texture (1-3 min)...'
            : 'AI is building your 3D model (30-90 sec)...',
      );

      final candidateList = await _waitForCandidates(
        client: client,
        baseUrl: baseUrl,
        apiPrefix: startResult.prefix,
        endpoint: endpoint,
        eventId: startResult.eventId,
        withTexture: withTexture,
      );

      onStatus?.call('Downloading 3D model (.glb)...');
      final localPath = await _downloadFirstValid3dModel(
        baseUrl,
        candidateList.urls,
        onStatus,
      );
      return localPath;
    } finally {
      client.close();
    }
  }

  static Future<_UploadResult> _uploadImage(
    String baseUrl,
    File imageFile,
  ) async {
    for (final prefix in ['', '/gradio_api']) {
      final uri = Uri.parse('$baseUrl$prefix/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headersFor(baseUrl));
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

  static Future<int> _fetchTurboSteps(
    String baseUrl,
    String apiPrefix,
  ) async {
    try {
      final headers = _headersFor(baseUrl);
      headers['Content-Type'] = 'application/json';

      for (final prefix in [
        apiPrefix,
        apiPrefix.isEmpty ? '/gradio_api' : '',
      ]) {
        final postUri = Uri.parse('$baseUrl$prefix/call/on_gen_mode_change');
        final postResp = await http
            .post(
              postUri,
              headers: headers,
              body: jsonEncode({
                'data': ['Turbo']
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (postResp.statusCode != 200) continue;
        final decoded = jsonDecode(postResp.body);
        final eventId =
            (decoded is Map) ? decoded['event_id']?.toString() : null;
        if (eventId == null || eventId.isEmpty) continue;

        final getUri =
            Uri.parse('$baseUrl$prefix/call/on_gen_mode_change/$eventId');
        final getResp = await http
            .get(getUri, headers: _headersFor(baseUrl))
            .timeout(const Duration(seconds: 10));

        if (getResp.statusCode != 200) continue;
        for (final line in const LineSplitter().convert(getResp.body)) {
          if (line.startsWith('data:')) {
            final raw = line.substring(5).trim();
            if (raw.isEmpty || raw == 'null') continue;
            final data = jsonDecode(raw);
            if (data is List && data.isNotEmpty) {
              final first = data.first;
              int? parsed;
              if (first is num) {
                parsed = first.round();
              } else if (first is Map && first['value'] is num) {
                parsed = (first['value'] as num).round();
              }
              if (parsed != null && parsed >= 1 && parsed <= 50) {
                return parsed;
              }
            }
          }
        }
      }
    } catch (_) {}
    return 5;
  }

  static Future<_StartResult> _startGeneration({
    required String baseUrl,
    required String apiPrefix,
    required String endpoint,
    required Map<String, dynamic> payload,
  }) async {
    final headers = _headersFor(baseUrl);
    headers['Content-Type'] = 'application/json';

    final prefixesToTry = [
      apiPrefix,
      apiPrefix.isEmpty ? '/gradio_api' : '',
    ];

    String lastError = 'AI server did not respond.';

    for (final prefix in prefixesToTry) {
      final uri = Uri.parse('$baseUrl$prefix/call$endpoint');
      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['event_id'] != null) {
          return _StartResult(decoded['event_id'].toString(), prefix);
        }
      }

      lastError =
          'AI server error (${response.statusCode}): ${_truncate(response.body, 150)}';
      if (response.statusCode != 404 && response.statusCode != 405) {
        throw Exception(lastError);
      }
    }

    throw Exception(lastError);
  }

  static Future<_CandidateList> _waitForCandidates({
    required http.Client client,
    required String baseUrl,
    required String apiPrefix,
    required String endpoint,
    required String eventId,
    required bool withTexture,
  }) async {
    final uri = Uri.parse('$baseUrl$apiPrefix/call$endpoint/$eventId');
    final request = http.Request('GET', uri);
    request.headers.addAll(_headersFor(baseUrl));
    request.headers['Accept'] = 'text/event-stream';

    final timeout =
        withTexture ? const Duration(minutes: 6) : const Duration(minutes: 4);

    final response = await client.send(request).timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to read AI result (${response.statusCode})');
    }

    String currentEvent = '';
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines.timeout(timeout)) {
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final dataStr = line.substring(5).trim();

        if (currentEvent == 'error') {
          if (dataStr.toLowerCase().contains('quota')) {
            throw Exception(
              'Free GPU quota limit reached. Try Fast mode or try again later.',
            );
          }
          throw Exception(
            'AI generation failed: ${dataStr.isEmpty ? "Server busy" : _truncate(dataStr, 180)}',
          );
        }

        if (currentEvent == 'complete') {
          final decoded = jsonDecode(dataStr);
          final candidates = _extractCandidates(
            decoded,
            baseUrl,
            apiPrefix,
            withTexture,
          );
          if (candidates.isNotEmpty) {
            return _CandidateList(candidates);
          }
          throw Exception(
            '3D model link not found. Response: ${_truncate(dataStr, 200)}',
          );
        }
      }
    }

    throw Exception('Connection closed before 3D model finished.');
  }

  static List<String> _extractCandidates(
    dynamic decoded,
    String baseUrl,
    String apiPrefix,
    bool withTexture,
  ) {
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
        addUnique('$baseUrl${Uri.encodeFull(value)}');
      } else if (value.startsWith('static/')) {
        addUnique('$baseUrl/${Uri.encodeFull(value)}');
      }

      if (value.startsWith('http://') || value.startsWith('https://')) {
        final httpBase = baseUrl.replaceFirst('https://', 'http://');
        final fixed = value.replaceFirst(httpBase, baseUrl);
        if (fixed.contains('/file=/static/')) {
          addUnique(fixed.replaceFirst('/file=/static/', '/static/'));
        }
        addUnique(fixed);
        if (fixed.contains('$baseUrl/file=') &&
            !fixed.contains('/gradio_api/file=')) {
          addUnique(
            fixed.replaceFirst('$baseUrl/file=', '$baseUrl/gradio_api/file='),
          );
        } else if (fixed.contains('$baseUrl/gradio_api/file=')) {
          addUnique(
            fixed.replaceFirst('$baseUrl/gradio_api/file=', '$baseUrl/file='),
          );
        }
        return;
      }

      if (value.startsWith('/gradio_api/file=') || value.startsWith('/file=')) {
        addCandidate('$baseUrl$value');
        return;
      }

      if (value.startsWith('gradio_api/file=') || value.startsWith('file=')) {
        addCandidate('$baseUrl/$value');
        return;
      }

      final cleaned = value.startsWith('./') ? value.substring(2) : value;
      final encoded = Uri.encodeFull(cleaned);
      addUnique('$baseUrl$apiPrefix/file=$encoded');
      addUnique('$baseUrl/gradio_api/file=$encoded');
      addUnique('$baseUrl/file=$encoded');
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
      if (withTexture) {
        // /generation_all returns [0]=white, [1]=textured, [2]=html
        if (decoded.length > 1) collectFromItem(decoded[1]);
        if (decoded.length > 2) collectFromItem(decoded[2]);
        if (decoded.isNotEmpty) collectFromItem(decoded[0]);
      } else {
        // /gen_shape returns [0]=html, [1]=download, [2]=glbPath, [3]=objPath
        if (decoded.length > 2) collectFromItem(decoded[2]);
        if (decoded.isNotEmpty) collectFromItem(decoded[0]);
        if (decoded.length > 1) collectFromItem(decoded[1]);
        if (decoded.length > 3) collectFromItem(decoded[3]);
      }
    } else {
      collectFromItem(decoded);
    }

    final List<String> glbUrls = [];
    final List<String> objUrls = [];
    final List<String> others = [];

    for (final u in urls) {
      final lower = u.toLowerCase();
      if (lower.contains('.glb') || lower.startsWith('data:')) {
        glbUrls.add(u);
      } else if (lower.contains('.obj')) {
        objUrls.add(u);
      } else {
        others.add(u);
      }
    }

    return [...glbUrls, ...objUrls, ...others];
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
    String baseUrl,
    List<String> candidates,
    void Function(String status)? onStatus,
  ) async {
    final List<String> attemptLogs = [];
    final headers = _headersFor(baseUrl);

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
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(minutes: 3));

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
            'Unsupported (${response.bodyBytes.length}B) ${_shortUrl(baseUrl, url)}',
          );
        } else {
          attemptLogs.add(
            'HTTP ${response.statusCode} ${_shortUrl(baseUrl, url)}',
          );
        }
      } catch (e) {
        attemptLogs.add('ERR ${_shortUrl(baseUrl, url)}: $e');
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