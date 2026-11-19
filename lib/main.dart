
import 'package:flutter/material.dart';

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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D17),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Header
              Row(
                children: [
                  const Icon(
                    Icons.view_in_ar_rounded,
                    color: Color(0xFF8B5CF6),
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'My3D AI Studio',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.settings_outlined,
                      color: Colors.white70),
                ],
              ),

              const SizedBox(height: 35),

              // Welcome Text
              const Text(
                'Create Anything',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Turn your ideas into 3D models with AI.',
                style: TextStyle(color: Colors.white60),
              ),

              const SizedBox(height: 28),

              // Image to 3D Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF6D28D9),
                      Color(0xFF2563EB),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 35,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Image to 3D',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Transform your image into a 3D model.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Image to 3D will be added soon!',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(
                            vertical: 15,
                          ),
                        ),
                        child: const Text('Create 3D Model'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // Tools Title
              const Text(
                'Creative Tools',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              // Text to 3D
              _toolCard(
                icon: Icons.text_fields,
                title: 'Text to 3D',
                subtitle: 'Create a model from your imagination',
                color: const Color(0xFF06B6D4),
              ),

              const SizedBox(height: 12),

              // AI Textures
              _toolCard(
                icon: Icons.texture,
                title: 'AI Textures',
                subtitle: 'Give your 3D models new textures',
                color: const Color(0xFFEC4899),
              ),

              const SizedBox(height: 28),

              // Recent Projects
              const Text(
                'Recent Projects',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF171A29),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white10,
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.view_in_ar,
                      size: 45,
                      color: Colors.white30,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No projects yet',
                      style: TextStyle(color: Colors.white70),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Your creations will appear here.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              const Center(
                child: Text(
                  'MY3D AI STUDIO • VERSION 1.0',
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _toolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF171A29),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios,
              size: 15, color: Colors.white38),
        ],
      ),
    );
  }
}
