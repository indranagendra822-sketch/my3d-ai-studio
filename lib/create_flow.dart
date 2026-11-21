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
import 'theme_and_storage.dart';

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

  Future<void> _openCutout() async {
    if (_img == null) return;
    final res = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => CutoutScreen(imageFile: _img!)),
    );
    if (res != null) setState(() => _img = res);
  }

  Future<void> _generate() async {
    if (_img == null) return;
    final url = (await SharedPreferences.getInstance()).getString('saved_api_url') ?? '';
    if (url.isEmpty) {
      if (mounted) showToast(context, 'ಮೊದಲು Home Settings (⚙️) ನಲ್ಲಿ API URL ಸೇವ್ ಮಾಡಿ!');
      return;
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProgressScreen(imageFile: _img!, apiUrl: url)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New 3D Model', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _img != null ? kLime.withOpacity(0.5) : kBorder, width: 1.5),
                ),
                child: _img != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.file(_img!, fit: BoxFit.contain))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: kLime.withOpacity(0.12), shape: BoxShape.circle),
                            child: const Icon(Icons.add_photo_alternate_rounded, size: 48, color: kLime),
                          ),
                          const SizedBox(height: 16),
                          const Text('Select a photo to begin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('Clear background gives the best 3D result', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _toolBtn(Icons.photo_library_rounded, 'Gallery', () => _pick(ImageSource.gallery))),
                const SizedBox(width: 10),
                Expanded(child: _toolBtn(Icons.camera_alt_rounded, 'Camera', () => _pick(ImageSource.camera))),
                if (_img != null) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _toolBtn(Icons.auto_fix_high_rounded, 'Cutout', _openCutout, highlight: true)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _img == null ? null : _generate,
                icon: const Icon(Icons.bolt_rounded, color: Colors.black, size: 22),
                label: const Text('Generate 3D Model', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kLime,
                  disabledBackgroundColor: kCardLight,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, VoidCallback onTap, {bool highlight = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: highlight ? kLime : Colors.white),
      label: Text(label, style: TextStyle(color: highlight ? kLime : Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        backgroundColor: highlight ? kLime.withOpacity(0.1) : kCard,
        side: BorderSide(color: highlight ? kLime : kBorder),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          IconButton(icon: const Icon(Icons.undo_rounded), onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.removeLast())),
          TextButton(onPressed: _save, child: const Text('DONE', style: TextStyle(color: kLime, fontWeight: FontWeight.bold))),
        ],
      ),
      body: Column(
        children: [
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            color: kCard,
            child: Column(children: [
              Slider(value: _size, min: 8, max: 60, activeColor: kLime, onChanged: (v) => setState(() => _size = v)),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => setState(() => _erase = true), icon: const Icon(Icons.cleaning_services_rounded), label: const Text('Erase'), style: ElevatedButton.styleFrom(backgroundColor: _erase ? kLime : kBg, foregroundColor: _erase ? Colors.black : Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(onPressed: () => setState(() => _erase = false), icon: const Icon(Icons.restore_rounded), label: const Text('Restore'), style: ElevatedButton.styleFrom(backgroundColor: !_erase ? kLime : kBg, foregroundColor: !_erase ? Colors.black : Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
              ]),
            ]),
          ),
        ],
      ),
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

class _ProgressScreenState extends State<ProgressScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  double _p = 0.12;
  Timer? _t;
  bool _cancel = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _t = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _p < 0.92) setState(() => _p += 0.04);
    });
    _run();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _t?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final base = widget.apiUrl.replaceAll(RegExp(r'/$'), '');
      final req = http.MultipartRequest('POST', Uri.parse('$base/generate'))
        ..headers['x-api-key'] = 'my3d-secret-2026'
        ..files.add(await http.MultipartFile.fromPath('file', widget.imageFile.path));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 5)));
      if (_cancel || !mounted) return;
      if (res.statusCode == 200) {
        final path = await saveModelWithThumb(res.bodyBytes, widget.imageFile);
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PreviewScreen(glbPath: path)));
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
                  const Icon(Icons.error_outline_rounded, size: 60, color: Colors.redAccent),
                  const SizedBox(height: 14),
                  Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: kLime, foregroundColor: Colors.black), child: const Text('Go Back')),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: kLime.withOpacity(0.15 + _pulse.value * 0.2), blurRadius: 28, spreadRadius: 4)],
                      ),
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox(width: 146, height: 146, child: CircularProgressIndicator(value: _p, strokeWidth: 8, color: kLime, backgroundColor: kCardLight)),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Transform.scale(scale: 0.92 + _pulse.value * 0.14, child: const Icon(Icons.view_in_ar_rounded, size: 38, color: kLime)),
                          const SizedBox(height: 4),
                          Text('${(_p * 100).toInt()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _step('Preparing image & depth', _p >= 0.12),
                  _step('Sculpting 3D geometry', _p >= 0.36),
                  _step('Refining mesh surface', _p >= 0.65),
                  _step('Packaging .GLB file', _p >= 0.88),
                  const SizedBox(height: 32),
                  OutlinedButton(
                    onPressed: () { _cancel = true; Navigator.pop(context); },
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _step(String t, bool done) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: done ? kLime : Colors.grey, size: 18),
      const SizedBox(width: 10),
      Text(t, style: TextStyle(color: done ? Colors.white : Colors.grey, fontWeight: done ? FontWeight.w600 : FontWeight.normal)),
    ]),
  );
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
        title: const Text('3D Preview', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        actions: [IconButton(icon: Icon(_rot ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: kLime, size: 28), onPressed: () => setState(() => _rot = !_rot))],
      ),
      body: Column(children: [
        Expanded(child: ModelViewer(key: ValueKey(_rot), src: 'file://${widget.glbPath}', alt: '3D Model', autoRotate: _rot, cameraControls: true, backgroundColor: kBg)),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(color: kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [_chip('GLB', true), const SizedBox(width: 10), _chip('OBJ • Soon', false), const SizedBox(width: 10), _chip('FBX • Soon', false)]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Share.shareXFiles([XFile(widget.glbPath)], text: 'My3D AI Studio (.glb)'),
                icon: const Icon(Icons.download_rounded, color: Colors.black),
                label: const Text('Download / Share .GLB', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                style: ElevatedButton.styleFrom(backgroundColor: kLime, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: active ? kLime : kBg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
  );
}
