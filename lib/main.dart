import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const My3DApp());

class My3DApp extends StatelessWidget {
  const My3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My3D AI Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  File? _selectedImage;
  String? _glbFilePath;
  bool _isLoading = false;
  String _status = "Colab API URL ಪೇಸ್ಟ್ ಮಾಡಿ ಮತ್ತು ಫೋಟೋ ಆಯ್ಕೆ ಮಾಡಿ";

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
        _glbFilePath = null;
        _status = "ಫೋಟೋ ಆಯ್ಕೆಯಾಗಿದೆ. ಈಗ Generate ಒತ್ತಿ!";
      });
    }
  }

  Future<void> _generate3D() async {
    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/$'), '');
    if (baseUrl.isEmpty || _selectedImage == null) {
      setState(() => _status = "ದಯವಿಟ್ಟು API URL ಮತ್ತು ಫೋಟೋ ಎರಡನ್ನೂ ಕೊಡಿ!");
      return;
    }

    setState(() {
      _isLoading = true;
      _status = "3D ಮಾಡೆಲ್ ತಯಾರಾಗುತ್ತಿದೆ... (1–2 ನಿಮಿಷ ಕಾಯಿರಿ)";
    });

    try {
      final uri = Uri.parse('$baseUrl/generate');
      final request = http.MultipartRequest('POST', uri)
        ..headers['x-api-key'] = 'my3d-secret-2026'
        ..files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));

      final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/model_${DateTime.now().millisecondsSinceEpoch}.glb';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          _glbFilePath = filePath;
          _status = "3D ಮಾಡೆಲ್ ರೆಡಿ! ತಿರುಗಿಸಿ ನೋಡಿ 🎉";
        });
      } else {
        setState(() => _status = "Error ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      setState(() => _status = "Connection Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadOrShareModel() async {
    if (_glbFilePath == null) return;
    await Share.shareXFiles(
      [XFile(_glbFilePath!)],
      text: 'My3D AI Studio - Generated 3D Model (.glb)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My3D AI Studio')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Colab API URL (https://....trycloudflare.com)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickImage,
                    icon: const Icon(Icons.photo),
                    label: const Text('Pick Photo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _generate3D,
                    icon: const Icon(Icons.view_in_ar),
                    label: const Text('Generate 3D'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_status, textAlign: TextAlign.center),
            if (_isLoading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _glbFilePath != null
                  ? ModelViewer(
                      src: 'file://$_glbFilePath',
                      alt: 'Generated 3D Model',
                      autoRotate: true,
                      cameraControls: true,
                      backgroundColor: const Color(0xFF1A1A1A),
                    )
                  : _selectedImage != null
                      ? Image.file(_selectedImage!, fit: BoxFit.contain)
                      : const Center(child: Text('ಇಲ್ಲಿ ನಿಮ್ಮ 3D ಮಾಡೆಲ್ ಕಾಣಿಸುತ್ತದೆ')),
            ),
            if (_glbFilePath != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _downloadOrShareModel,
                  icon: const Icon(Icons.download),
                  label: const Text('Download / Share .GLB'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
