import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ai_3d_service.dart';
import 'model_viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? selectedImage;
  bool isGenerating = false;
  bool withTexture = true;
  String statusMessage = '';
  final ImagePicker picker = ImagePicker();

  Future<void> pickImage() async {
    if (isGenerating) return;
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (image != null) {
      setState(() {
        selectedImage = File(image.path);
      });
    }
  }

  Future<void> generateModel() async {
    if (selectedImage == null || isGenerating) return;

    setState(() {
      isGenerating = true;
      statusMessage = 'Connecting to AI server...';
    });

    try {
      final glbPath = await Ai3dService.generate3DModel(
        imageFile: selectedImage!,
        withTexture: withTexture,
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            statusMessage = status;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        isGenerating = false;
        statusMessage = '';
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ModelViewerScreen(
            modelSource: glbPath,
            isLocalFile: true,
            modelName: withTexture
                ? 'my3d_textured_model.glb'
                : 'my3d_white_model.glb',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isGenerating = false;
        statusMessage = '';
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF171B26),
          title: const Text(
            '3D Generation Failed',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildModeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: isGenerating ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.blueAccent.withValues(alpha: 0.2)
                : const Color(0xFF171B26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.blueAccent : Colors.white24,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? Colors.blueAccent : Colors.white60,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        title: const Text(
          'My3D AI Studio',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create 3D Models with AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Turn your images into 3D models',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: pickImage,
                child: Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFF171B26),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: selectedImage == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 64,
                              color: Colors.blueAccent,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Upload Your Image',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Tap here to select an image',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.file(
                            selectedImage!,
                            fit: BoxFit.contain,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildModeOption(
                    title: 'Color & Texture',
                    subtitle: '1-3 min • Full Color',
                    icon: Icons.palette_rounded,
                    selected: withTexture,
                    onTap: () => setState(() => withTexture = true),
                  ),
                  const SizedBox(width: 12),
                  _buildModeOption(
                    title: 'Fast White',
                    subtitle: '30-90 sec • Shape',
                    icon: Icons.bolt_rounded,
                    selected: !withTexture,
                    onTap: () => setState(() => withTexture = false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: isGenerating ? null : pickImage,
                  icon: const Icon(Icons.upload),
                  label: const Text(
                    'Choose Image',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF23293A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: (selectedImage == null || isGenerating)
                      ? null
                      : generateModel,
                  icon: isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    isGenerating
                        ? 'Generating 3D...'
                        : (withTexture
                            ? 'Generate Textured 3D'
                            : 'Generate Fast 3D'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF23262F),
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              if (isGenerating && statusMessage.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171B26),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blueAccent),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 30),
              const Center(
                child: Text(
                  'Powered by My3D AI Studio',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
