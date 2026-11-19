
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10101A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10101A),
        title: const Text(
          'My3D AI Studio',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.view_in_ar,
              size: 100,
              color: Colors.deepPurpleAccent,
            ),
            const SizedBox(height: 20),
            const Text(
              'Create 3D Models with AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Turn your images into 3D models',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.image),
              label: const Text('Select Image'),
            ),
          ],
        ),
      ),
    );
  }
}
