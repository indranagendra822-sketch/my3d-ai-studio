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

const kBg = Color(0xFF222022);
const kCard = Color(0xFF2D2A2D);
const kLime = Color(0xFFC3D809);

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
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kLime, onPrimary: Colors.black, surface: kCard),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

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
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNav()));
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: kLime, width: 2)),
              child: const Icon(Icons.view_in_ar, size: 68, color: kLime),
            ),
            const SizedBox(height: 20),
            const Text('My3D AI Studio', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const Text('Photos into 3D models', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            const SizedBox(width: 160, child: LinearProgressIndicator(color: kLime, backgroundColor: kCard)),
          ],
        ),
      ),
    );
  }
}

class MainNav extends StatefulWidget {
  const MainNav({super.key});
  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  int _idx = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _idx == 0 ? const HomeScreen() : const HistoryScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: kBg,
        indicatorColor: kLime,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: Colors.black), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view, color: Colors.black), label: 'History'),
        ],
      ),
    );
  }
}

Future<List<File>> loadSavedModels() async {
  final dir = await getApplicationDocumentsDirectory();
  final d = Directory('${dir.path}/saved_models');
  if (!await d.exists()) return [];
  final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList();
  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return files;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _recent = [];
  @override
  void initState() {
    super.initState();
    _refresh();
  }
  Future<void> _refresh() async {
    final files = await loadSavedModels();
    if (mounted) setState(() => _recent = files.take(4).toList());
  }
  Future<void> _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(text: prefs.getString('saved_api_url') ?? '');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Backend API URL', style: TextStyle(color: kLime)),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://....trycloudflare.com', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kLime, foregroundColor: Colors.black),
            onPressed: () async {
              await prefs.setString('saved_api_url', ctrl.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  void _goUpload() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadScreen()));
    _refresh();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(children: [Icon(Icons.view_in_ar, color: kLime), SizedBox(width: 8), Text('My3D AI Studio', style: TextStyle(fontWeight: FontWeight.w900))]),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _card(Icons.image_outlined, 'Image to 3D', 'Photo to GLB', true, _goUpload)),
            const SizedBox(width: 12),
            Expanded(child: _card(Icons.text_fields, 'Text to 3D', 'Coming soon', false, () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming soon!'))))),
          ]),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _goUpload,
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('Create new model', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
            style: ElevatedButton.styleFrom(backgroundColor: kLime, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
          const SizedBox(height: 24),
          const Text('Recent projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_recent.isEmpty)
            Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)), child: const Center(child: Text('No 3D models yet', style: TextStyle(color: Colors.grey))))
          else
            ..._recent.map((f) => Card(
              color: kCard,
              child: ListTile(
                leading: const Icon(Icons.view_in_ar, color: kLime),
                title: Text(f.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${(f.lengthSync() / 1048576).toStringAsFixed(1)} MB • GLB'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(glbPath: f.path))),
              ),
            )),
        ],
      ),
    );
  }
  Widget _card(IconData ic, String t, String sub, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? kLime : Colors.white12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, color: active ? kLime : Colors.grey, size: 28),
          const SizedBox(height: 10),
          Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(sub, style: TextStyle(color: active ? kLime : Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _img;
  Future<void> _pick(ImageSource src) async {
    final p = await ImagePicker().pickImage(source: src);
    if (p != null) setState(() => _img = File(p.path));
  }
  Future<void> _cutout() async {
    if (_img == null) return;
    final res = await Navigator.push<File>(context, MaterialPageRoute(builder: (_) => CutoutScreen(imageFile: _img!)));
    if (res != null) setState(() => _img = res);
  }
  Future<void> _generate() async {
    if (_img == null) return;
    final url = (await SharedPreferences.getInstance()).getString('saved_api_url') ?? '';
    if (url.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save API URL in Home Settings first!')));
      return;
    }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressScreen(imageFile: _img!, apiUrl: url)));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Photo'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20)),
              child: _img != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_img!, fit: BoxFit.contain))
                  : const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 64, color: kLime)),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo), label: const Text('Gallery'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Camera'))),
            if (_img != null) ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _cutout, icon: const Icon(Icons.brush, color: kLime), label: const Text('Cutout', style: TextStyle(color: kLime)), style: OutlinedButton.styleFrom(side: const BorderSide(color: kLime)))),
            ],
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _img == null ? null : _generate,
              icon: const Icon(Icons.bolt, color: Colors.black),
              label: const Text('Generate 3D Model', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              style: ElevatedButton.styleFrom(backgroundColor: kLime, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stroke {
  final List<Offset> pts;
  final double w;
  final bool erase;
  _Stroke(this.pts, this.w, this.erase);
}

class CutoutScreen extends StatefulWidget {
  final File imageFile;
  const CutoutScreen({super.key, required this.imageFile});
  @override
  State<CutoutScreen> createState() => _CutoutScreenState();
}

class _CutoutScreenState extends State<CutoutScreen> {
  final _key = GlobalKey();
  final List<_Stroke> _strokes = [];
  bool _erase = true;
  double _size = 26;
  Future<void> _save() async {
    final b = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2.0);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final f = File('${(await getTemporaryDirectory()).path}/cut_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes);
    if (mounted) Navigator.pop(context, f);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cutout Editor'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.removeLast())),
          TextButton(onPressed: _save, child: const Text('DONE', style: TextStyle(color: kLime, fontWeight: FontWeight.bold))),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: RepaintBoundary(
              key: _key,
              child: Container(
                color: Colors.white,
                child: GestureDetector(
                  onPanStart: (d) => setState(() => _strokes.add(_Stroke([d.localPosition], _size, _erase))),
                  onPanUpdate: (d) => setState(() => _strokes.last.pts.add(d.localPosition)),
                  child: Stack(fit: StackFit.passthrough, children: [
                    Image.file(widget.imageFile, fit: BoxFit.contain),
                    Positioned.fill(child: CustomPaint(painter: _CutoutPainter(_strokes))),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          color: kCard,
          child: Column(children: [
            Slider(value: _size, min: 8, max: 60, activeColor: kLime, onChanged: (v) => setState(() => _size = v)),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: () => setState(() => _erase = true), icon: const Icon(Icons.cleaning_services), label: const Text('Erase'), style: ElevatedButton.styleFrom(backgroundColor: _erase ? kLime : kBg, foregroundColor: _erase ? Colors.black : Colors.white))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: () => setState(() => _erase = false), icon: const Icon(Icons.restore), label: const Text('Restore'), style: ElevatedButton.styleFrom(backgroundColor: !_erase ? kLime : kBg, foregroundColor: !_erase ? Colors.black : Colors.white))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _CutoutPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _CutoutPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in strokes) {
      final p = Paint()..strokeCap = StrokeCap.round..strokeWidth = s.w..style = PaintingStyle.stroke;
      if (s.erase) { p.color = Colors.white; } else { p.blendMode = BlendMode.clear; }
      for (int i = 0; i < s.pts.length - 1; i++) {
        canvas.drawLine(s.pts[i], s.pts[i + 1], p);
      }
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class ProgressScreen extends StatefulWidget {
  final File imageFile;
  final String apiUrl;
  const ProgressScreen({super.key, required this.imageFile, required this.apiUrl});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  double _p = 0.15;
  Timer? _t;
  bool _cancel = false;
  String? _err;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _p < 0.9) setState(() => _p += 0.04);
    });
    _run();
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  Future<void> _run() async {
    try {
      final base = widget.apiUrl.replaceAll(RegExp(r'/$'), '');
      final req = http.MultipartRequest('POST', Uri.parse('$base/generate'))
        ..headers['x-api-key'] = 'my3d-secret-2026'
        ..files.add(await http.MultipartFile.fromPath('file', widget.imageFile.path));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 5)));
      if (_cancel || !mounted) return;
      if (res.statusCode == 200) {
        final d = Directory('${(await getApplicationDocumentsDirectory()).path}/saved_models');
        if (!await d.exists()) await d.create(recursive: true);
        final path = '${d.path}/model_${DateTime.now().millisecondsSinceEpoch}.glb';
        await File(path).writeAsBytes(res.bodyBytes);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PreviewScreen(glbPath: path)));
      } else {
        setState(() => _err = 'Error ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      if (!_cancel && mounted) setState(() => _err = 'Connection Error: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generating 3D'), backgroundColor: Colors.transparent),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _err != null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: kLime, foregroundColor: Colors.black), child: const Text('Go Back')),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Stack(alignment: Alignment.center, children: [
                    SizedBox(width: 130, height: 130, child: CircularProgressIndicator(value: _p, strokeWidth: 9, color: kLime, backgroundColor: kCard)),
                    Text('${(_p * 100).toInt()}%', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 28),
                  const Text('Creating your 3D model...', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  OutlinedButton(onPressed: () { _cancel = true; Navigator.pop(context); }, child: const Text('Cancel')),
                ]),
        ),
      ),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  final String glbPath;
  const PreviewScreen({super.key, required this.glbPath});
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  bool _rot = true;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Preview'),
        actions: [IconButton(icon: Icon(_rot ? Icons.pause_circle : Icons.play_circle, color: kLime), onPressed: () => setState(() => _rot = !_rot))],
      ),
      body: Column(children: [
        Expanded(child: ModelViewer(key: ValueKey(_rot), src: 'file://${widget.glbPath}', alt: '3D Model', autoRotate: _rot, cameraControls: true, backgroundColor: kBg)),
        Container(
          padding: const EdgeInsets.all(16),
          color: kCard,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Share.shareXFiles([XFile(widget.glbPath)], text: 'My3D AI Studio (.glb)'),
              icon: const Icon(Icons.download, color: Colors.black),
              label: const Text('Download / Share .GLB', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              style: ElevatedButton.styleFrom(backgroundColor: kLime, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
        ),
      ]),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<File> _models = [];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final f = await loadSavedModels();
    if (mounted) setState(() => _models = f);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Models', style: TextStyle(fontWeight: FontWeight.w900)), backgroundColor: Colors.transparent),
      body: _models.isEmpty
          ? const Center(child: Text('No saved models yet', style: TextStyle(color: Colors.grey)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
              itemCount: _models.length,
              itemBuilder: (_, i) {
                final f = _models[i];
                return Card(
                  color: kCard,
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(glbPath: f.path))),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Container(decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)), child: const Center(child: Icon(Icons.view_in_ar, size: 44, color: kLime)))),
                        const SizedBox(height: 8),
                        Text(f.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('${(f.lengthSync() / 1048576).toStringAsFixed(1)} MB', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () async { await f.delete(); _load(); }),
                        ]),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
