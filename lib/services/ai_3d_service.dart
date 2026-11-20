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
      final glbUrl = await _waitForResult(
        client: client,
        eventId: eventId,
        apiPrefix: uploadResult.prefix,
      );

      onStatus?.call('Downloading 3D model (.glb)...');
      final localPath = await _downloadGlb(glbUrl);
      return localPath;
    } finally {
      client.close();
    }
  }

  static Future<_UploadResult> _uploadImage(File imageFile) async {
    for (final prefix in ['', '/gradio_api']) {
      final uri = Uri.parse('$_baseUrl$prefix/upload');
      final request = http.MultipartRequest('POST', uri);
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

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
        'AI server error (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['event_id'] != null) {
      return decoded['event_id'].toString();
    }
    throw Exception('Invalid response from AI server.');
  }

  static Future<String> _waitForResult({
    required http.Client client,
    required String eventId,
    required String apiPrefix,
  }) async {
    final uri = Uri.parse('$_baseUrl$apiPrefix/call/gen_shape/$eventId');
    final request = http.Request('GET', uri);
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
            'AI generation failed: ${dataStr.isEmpty ? "Server busy" : dataStr}',
          );
        }

        if (currentEvent == 'complete') {
          final decoded = jsonDecode(dataStr);
          final glbUrl = _extractGlbUrl(decoded, apiPrefix);
          if (glbUrl != null) {
            return glbUrl;
          }
          throw Exception('3D model file not found in AI response.');
        }
      }
    }

    throw Exception('Connection closed before 3D model finished.');
  }

  static String? _extractGlbUrl(dynamic decoded, String apiPrefix) {
    if (decoded is! List) return null;

    if (decoded.length > 1) {
      final downloadItem = decoded[1];
      if (downloadItem is Map) {
        final url = downloadItem['url']?.toString();
        if (url != null && url.startsWith('http')) {
          return url;
        }
        final path = downloadItem['path']?.toString();
        if (path != null && path.isNotEmpty) {
          return _buildFileUrl(path, apiPrefix);
        }
      } else if (downloadItem is String && downloadItem.isNotEmpty) {
        return _buildFileUrl(downloadItem, apiPrefix);
      }
    }

    if (decoded.length > 2) {
      final glbPath = decoded[2]?.toString();
      if (glbPath != null && glbPath.isNotEmpty) {
        return _buildFileUrl(glbPath, apiPrefix);
      }
    }

    return null;
  }

  static String _buildFileUrl(String pathOrUrl, String apiPrefix) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    final encoded = Uri.encodeFull(pathOrUrl);
    return '$_baseUrl$apiPrefix/file=$encoded';
  }

  static Future<String> _downloadGlb(String url) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception(
        'Failed to download 3D file (${response.statusCode})',
      );
    }

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/my3d_$timestamp.glb');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }
}
