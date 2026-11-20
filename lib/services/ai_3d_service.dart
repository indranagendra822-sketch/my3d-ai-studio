import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

      onStatus?.call('Downloading 3D model (.glb)...');
      final localPath = await _downloadFirstWorkingGlb(candidates);
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

      if (value.startsWith('http://') || value.startsWith('https://')) {
        final fixed = value.replaceFirst(
          'http://frogleo-image-to-3d.hf.space',
          _baseUrl,
        );
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
          final regex = RegExp(
            r'''(https?:\/\/[^\s"'<>]+\.glb[^\s"'<>]*|\/(?:gradio_api\/)?file=[^\s"'<>]+\.glb[^\s"'<>]*)''',
            caseSensitive: false,
          );
          for (final match in regex.allMatches(item)) {
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
      if (decoded.length > 1) collectFromItem(decoded[1]);
      if (decoded.isNotEmpty) collectFromItem(decoded[0]);
      if (decoded.length > 2) collectFromItem(decoded[2]);
    } else {
      collectFromItem(decoded);
    }

    return urls;
  }

  static Future<String> _downloadFirstWorkingGlb(
    List<String> candidates,
  ) async {
    String lastError = 'No download URL available';

    for (final url in candidates) {
      try {
        if (url.startsWith('data:')) {
          final commaIndex = url.indexOf(',');
          if (commaIndex != -1) {
            final bytes = base64Decode(url.substring(commaIndex + 1));
            if (bytes.isNotEmpty) {
              return _saveGlbBytes(bytes);
            }
          }
          continue;
        }

        final response = await http
            .get(Uri.parse(url), headers: _browserHeaders)
            .timeout(const Duration(minutes: 2));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final headerText = utf8
              .decode(
                response.bodyBytes.take(24).toList(),
                allowMalformed: true,
              )
              .trimLeft();

          if (!headerText.startsWith('<')) {
            return _saveGlbBytes(response.bodyBytes);
          }
          lastError = 'Server returned HTML instead of GLB for $url';
        } else {
          lastError =
              'HTTP ${response.statusCode} for $url (${_truncate(response.body, 100)})';
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    throw Exception('Failed to download 3D file: $lastError');
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
