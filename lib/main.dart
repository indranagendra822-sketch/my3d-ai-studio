import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kBgDark = Color(0xFF222022);
const Color kCardDark = Color(0xFF2D2A2D);
const Color kLime = Color(0xFFC3D809);

void main() => runApp(const My3DApp());

class My3DApp extends StatelessWidget {
  const My3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My3D AI Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBgDark,
        colorScheme: const ColorScheme.dark(
          primary: kLime,
          onPrimary: Colors.black,
          secondary: kLime,
          surface: kCardDark,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. SPLASH SCREEN
// ---------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kCardDark,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kLime.withOpacity(0.5), width: 2),
              ),
              child: const Icon(Icons.view_in_ar, size: 72, color: kLime),
            ),
            const SizedBox(height: 24),
            const Text(
              'My3D AI Studio',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Photos into 3D models',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(
                  color: kLime,
                  backgroundColor: kCardDark,
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MAIN NAVIGATION (HOME + HISTORY)
// ---------------------------------------------------------------------------
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _index == 0 ? const HomeScreen() : const HistoryScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: kBgDark,
        indicatorColor: kLime,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: Colors.white),
            selectedIcon: Icon(Icons.home, color: Colors.black),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined, color: Colors.white),
            selectedIcon: Icon(Icons.grid_view, color: Colors.black),
            label: 'History',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. HOME SCREEN
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _recentModels = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${dir.path}/saved_models');
    if (await modelsDir.exists()) {
      final files = modelsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.glb'))
          .toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => _recentModels = files.take(4).toList());
    }
  }

  Future<void> _showApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(text: prefs.getString('saved_api_url') ?? '');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCardDark,
        title: const Text('Backend API URL', style: TextStyle(color: kLime)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://....trycloudflare.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kLime, foregroundColor: Colors.black),
            onPressed: () async {
              await prefs.setString('saved_api_url', controller.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _openUpload() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UploadScreen()),
    );
    _loadRecent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.view_in_ar, color: kLime),
            SizedBox(width: 8),
            Text('My3D AI Studio', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showApiSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _featureCard(
                  icon: Icons.image_outlined,
                  title: 'Image to 3D',
                  subtitle: 'Photo to GLB',
                  active: true,
                  onTap: _openUpload,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _featureCard(
                  icon: Icons.text_fields,
                  title: 'Text to 3D',
                  subtitle: 'Coming soon',
                  active: false,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Text to 3D ಶೀಘ್ರದಲ್ಲೇ ಬರಲಿದೆ!')),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openUpload,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text(
                'Create new model',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kLime,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Recent projects',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_recentModels.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: kCardDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.view_in_ar_outlined, size: 42, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('ಇನ್ನೂ ಯಾವುದೇ 3D ಮಾಡೆಲ್ ಇಲ್ಲ', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            ..._recentModels.map((file) {
              final name = file.path.split('/').last;
              final sizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
              return Card(
                color: kCardDark,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBgDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.view_in_ar, color: kLime),
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('$sizeMb MB • GLB', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => Preview3DScreen(glbPath: file.path)),
                    );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCardDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? kLime.withOpacity(0.6) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: active ? kLime : Colors.grey, size: 30),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: active ? kLime : Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. IMAGE UPLOAD SCREEN (+ CUTOUT OPTION)
// ---------------------------------------------------------------------------
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _imageFile;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _openCutout() async {
    if (_imageFile == null) return;
    final edited = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => CutoutEditorScreen(imageFile: _imageFile!)),
    );
    if (edited != null) {
      setState(() => _imageFile = edited);
    }
  }

  Future<void> _startGeneration() async {
    if (_imageFile == null) return;
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('saved_api_url') ?? '';
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ಮೊದಲು Home ಸ್ಕ್ರೀನ್‌ನ ⚙️ Settings ನಲ್ಲಿ API URL ಸೇವ್ ಮಾಡಿ!')),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GenerationProgressScreen(imageFile: _imageFile!, apiUrl: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Photo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: kCardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: _imageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(_imageFile!, fit: BoxFit.contain),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 64, color: kLime),
                          SizedBox(height: 12),
                          Text('3D ಮಾಡಲು ಫೋಟೋ ಆಯ್ಕೆ ಮಾಡಿ', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    label: const Text('Gallery', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    label: const Text('Camera', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                if (_imageFile != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openCutout,
                      icon: const Icon(Icons.brush, color: kLime),
                      label: const Text('Cutout', style: TextStyle(color: kLime)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kLime),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _imageFile == null ? null : _startGeneration,
                icon: const Icon(Icons.bolt, color: Colors.black),
                label: const Text(
                  'Generate 3D Model',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kLime,
                  disabledBackgroundColor: Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3B. CUTOUT EDITOR SCREEN (ERASE / RESTORE BRUSH)
// ---------------------------------------------------------------------------
class _Stroke {
  final List<Offset> points;
  final double width;
  final bool isErase;
  _Stroke(this.points, this.width, this.isErase);
}

class CutoutEditorScreen extends StatefulWidget {
  final File imageFile;
  const CutoutEditorScreen({super.key, required this.imageFile});

  @override
  State<CutoutEditorScreen> createState() => _CutoutEditorScreenState();
}

class _CutoutEditorScreenState extends State<CutoutEditorScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  bool _isErase = true;
  double _brushSize = 26.0;
  bool _saving = false;

  Future<void> _saveCutout() async {
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final outFile = File('${dir.path}/cutout_${DateTime.now().millisecondsSinceEpoch}.png');
      await outFile.writeAsBytes(bytes);

      if (mounted) Navigator.pop(context, outFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(conte