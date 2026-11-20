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
      final localPath = await _downloadFirstValidGlb(candidates);
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
            r'''(https?:\/\/[^\s"'<>]+\.glb[^\s"'<>]*|\/?(?:gradio_api\/)?file=[^\s"'<>]+\.glb[^\s"'<>]*)''',
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
    } else {
      collectFromItem(decoded);
    }

    final List<String> glbFirst = [];
    final List<String> others = [];
    for (final u in urls) {
      final lower = u.toLowerCase();
      if (lower.contains('.glb') || lower.startsWith('data:')) {
        glbFirst.add(u);
      } else {
        others.add(u);
      }
    }
    return [...glbFirst, ...others];
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

  static Future<String> _downloadFirstValidGlb(
    List<String> candidates,
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
            attemptLogs.add(
              'dataURI (${bytes.length}B): ${_bytesPreview(bytes)}',
            );
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
          attemptLogs.add(
            'Not GLB (${response.bodyBytes.length}B) ${_shortUrl(url)} -> ${_bytesPreview(response.bodyBytes)}',
          );
        } else {
          attemptLogs.add('HTTP ${response.statusCode} ${_shortUrl(url)}');
        }
      } catch (e) {
        attemptLogs.add('ERR ${_shortUrl(url)}: $e');
      }
    }

    final details = attemptLogs.isEmpty
        ? 'No candidate URLs'
        : attemptLogs.take(4).join('\n');
    throw Exception('Valid GLB not found.\n$details');
  }

  static String _bytesPreview(List<int> bytes) {
    final sample = bytes.take(16).toList();
    final ascii = sample
        .map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.')
        .join();
    final hex = sample
        .take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    return '"$ascii" [$hex]';
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
