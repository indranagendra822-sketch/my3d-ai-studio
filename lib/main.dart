import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const My3DApp());
}

class My3DApp extends StatelessWidget {
  const My3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My3D AI Studio',
      theme: ThemeData.dark(),
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
  File? selectedImage;

  Future<void> pickImage() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (image != null) {
      setState(() {
        selectedImage = File(image.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        title: const Text(
          'My3D AI Studio',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create 3D Models with AI',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Turn your images into 3D models',
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 30),

            GestureDetector(
              onTap: pickImage,
              child: Container(
                width: double.infinity,
                height: 250,
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
                            Icons.add_photo_alternate,
                            size: 75,
                            color: Colors.blueAccent,
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Upload Your Image',
                            style: TextStyle(fontSize: 20),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap here to select an image',
                            style: TextStyle(color: Colors.white60),
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

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: pickImage,
                icon: const Icon(Icons.upload),
                label: const Text('Choose Image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF252B40),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: selectedImage == null
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Image selected! AI generation is our next step.',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate 3D Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const Spacer(),

            const Center(
              child: Text(
                'Powered by My3D AI Studio',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}