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

enum ViewAngle { front, left, back, right, extra }

extension ViewAngleLabel on ViewAngle {
  String get label {
    switch (this) {
      case ViewAngle.front: return 'Front';
      case ViewAngle.left: return 'Left';
      case ViewAngle.back: return 'Back';
      case ViewAngle.right: return 'Right';
      case ViewAngle.extra: return 'Extra';
    }
  }
}

class MultiViewSlot {
  final String id;
  ViewAngle angle;
  File? file;
  MultiViewSlot({required this.id, required this.angle, this.file});
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final List<MultiViewSlot> _slots = [
    MultiViewSlot(id: 'front', angle: ViewAngle.front),
    MultiViewSlot(id: 'left', angle: ViewAngle.left),
    MultiViewSlot(id: 'back', angle: ViewAngle.back),
    MultiViewSlot(id: 'right', angle: ViewAngle.right),
  ];
  int _selectedIndex = 0;
  int _extraCount = 1;
  MultiViewSlot get _activeSlot => _slots[_selectedIndex];

  bool get _hasRequiredFront {
    final frontSlot = _slots.firstWhere((s) => s.angle == ViewAngle.front, orElse: () => _slots.first);
    return frontSlot.file != null;
  }

  Future<void> _pickForSlot(int index, ImageSource src) async {
    final p = await ImagePicker().pickImage(source: src);
    if (p == null) return;
    setState(() { _slots[index].file = File(p.path); _selectedIndex = index; });
  }

  void _showSourceSheet(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_library_rounded, color: kLime), title: const Text('Choose from Gallery'), onTap: () { Navigator.pop(context); _pickForSlot(index, ImageSource.gallery); }),
            ListTile(leading: const Icon(Icons.camera_alt_rounded, color: kLime), title: const Text('Take Photo with Camera'), onTap: () { Navigator.pop(context); _pickForSlot(index, ImageSource.camera); }),
          ]),
        ),
      ),
    );
  }

  void _removeSlotImage(int index) {
    setState(() => _slots[index].file = null);
    showToast(context, '${_slots[index].angle.label} photo removed');
  }

  void _addExtraSlot() {
    setState(() {
      _slots.add(MultiViewSlot(id: 'extra_${_extraCount++}_${DateTime.now().millisecondsSinceEpoch}', angle: ViewAngle.extra));
      _selectedIndex = _slots.length - 1;
    });
    _showSourceSheet(_selectedIndex);
  }

  Future<void> _openCutout() async {
    final currentFile = _activeSlot.file;
    if (currentFile == null) return;
    final res = await Navigator.push<File>(context, MaterialPageRoute(builder: (_) => CutoutScreen(imageFile: currentFile)));
    if (res != null) setState(() => _activeSlot.file = res);
  }

  Future<void> _generate() async {
    if (!_hasRequiredFront) { showToast(context, 'Front view photo ಕಡ್ಡಾಯವಾಗಿದೆ!'); return; }
    final frontFile = _slots.firstWhere((s) => s.angle == ViewAngle.front && s.file != null, orElse: () => _slots.first).file!;
    final url = (await SharedPreferences.getInstance()).getString('saved_api_url') ?? '';
    if (url.isEmpty) { if (mounted) showToast(context, 'ಮೊದಲು Home Settings (⚙️) ನಲ್ಲಿ API URL ಸೇವ್ ಮಾಡಿ!'); return; }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressScreen(imageFile: frontFile, apiUrl: url)));
  }

  @override
  Widget build(BuildContext context) {
    final previewFile = _activeSlot.file;
    return Scaffold(
      appBar: AppBar(title: const Text('New 3D Model', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Multi-View Angles (Front required)', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _slots.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                if (idx == _slots.length) return _buildAddMoreCard();
                final slot = _slots[idx];
                final isSelected = idx == _selectedIndex;
                final isFront = slot.angle == ViewAngle.front;
                return GestureDetector(
                  onTap: () { setState(() => _selectedIndex = idx); if (slot.file == null) _showSourceSheet(idx); },
                  child: Container(
                    width: 86,
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? kLime : kBorder, width: isSelected ? 2 : 1)),
                    child: Stack(children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 4), child: ClipRRect(borderRadius: BorderRadius.circular(11), child: Container(width: double.infinity, color: kBg, child: slot.file != null ? Image.file(slot.file!, fit: BoxFit.cover) : const Icon(Icons.add_a_photo_rounded, color: Colors.grey, size: 24))))),
                        Padding(padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4), child: Text(isFront ? 'Front *' : slot.angle.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? kLime : Colors.white70))),
                      ]),
                      if (slot.file != null)
                        Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => _removeSlotImage(idx), child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 14, color: Colors.white)))),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text('Angle:', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            const SizedBox(width: 8),
            DropdownButton<ViewAngle>(
              value: _activeSlot.angle,
              dropdownColor: kCardLight,
              underline: const SizedBox(),
              style: const TextStyle(color: kLime, fontWeight: FontWeight.bold, fontSize: 13),
              items: ViewAngle.values.map((a) => DropdownMenuItem(value: a, child: Text(a.label))).toList(),
              onChanged: (val) { if (val != null) setState(() => _activeSlot.angle = val); },
            ),
            const Spacer(),
            if (previewFile != null)
              TextButton.icon(onPressed: () => _showSourceSheet(_selectedIndex), icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: kLime), label: const Text('Replace', style: TextStyle(color: kLime, fontSize: 12))),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: previewFile != null ? kLime.withOpacity(0.5) : kBorder, width: 1.5)),
              child: previewFile != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.file(previewFile, fit: BoxFit.contain))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: kLime.withOpacity(0.12), shape: BoxShape.circle), child: const Icon(Icons.add_photo_alternate_rounded, size: 46, color: kLime)),
                      const SizedBox(height: 14),
                      Text('${_activeSlot.angle.label} view photo ಆಯ್ಕೆ ಮಾಡಿ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Front view ಕಡ್ಡಾಯ; Left, Back, Right optional', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _toolBtn(Icons.photo_library_rounded, 'Gallery', () => _pickForSlot(_selectedIndex, ImageSource.gallery))),
            const SizedBox(width: 10),
            Expanded(child: _toolBtn(Icons.camera_alt_rounded, 'Camera', () => _pickForSlot(_selectedIndex, ImageSource.camera))),
            if (previewFile != null) ...[
              const SizedBox(width: 10),
              Expanded(child: _toolBtn(Icons.auto_fix_high_rounded, 'Cutout', _openCutout, highlight: true)),
            ],
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _hasRequiredFront ? _generate : null,
              icon: const Icon(Icons.bolt_rounded, color: Colors.black, size: 22),
              label: const Text('Generate 3D Model', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
              style: ElevatedButton.styleFrom(backgroundColor: kLime, disabledBackgroundColor: kCardLight, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAddMoreCard() {
    return GestureDetector(
      onTap: _addExtraSlot,
      child: Container(
        width: 82,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLime.withOpacity(0.5), width: 1.2)),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_rounded, color: kLime, size: 28),
          SizedBox(height: 6),
          Text('Add More', style: TextStyle(fontSize: 11, color: kLime, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, VoidCallback onTap, {bool highlight = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: highlight ? kLime : Colors.white),
      label: Text(label, style: TextStyle(color: highlight ? kLime : Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      style: OutlinedButton.styleFrom(backgroundColor: highlight ? kLime.withOpacity(0.1) : kCard, side: BorderSide(color: highlight ? kLime : kBorder), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
  static const String _defaultOrbit = '0deg 75deg 2.5m';
  static const String _defaultFov = '45deg';

  bool _rot = true;
  double _zoomRadius = 2.5;
  int _viewResetTick = 0;

  void _zoomIn() => setState(() => _zoomRadius = (_zoomRadius - 0.35).clamp(1.4, 4.2));
  void _zoomOut() => setState(() => _zoomRadius = (_zoomRadius + 0.35).clamp(1.4, 4.2));
  void _resetView() {
    setState(() {
      _zoomRadius = 2.5;
      _rot = true;
      _viewResetTick++;
    });
    showToast(context, 'View reset to default');
  }

  @override
  Widget build(BuildContext context) {
    final orbit = '0deg 75deg ${_zoomRadius.toStringAsFixed(2)}m';

    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Preview', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(tooltip: 'Reset View', icon: const Icon(Icons.refresh_rounded, color: kLime, size: 26), onPressed: _resetView),
          IconButton(tooltip: '360° Auto-Rotate', icon: Icon(_rot ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: kLime, size: 28), onPressed: () => setState(() => _rot = !_rot)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            ModelViewer(
              key: ValueKey('$_rot-$_zoomRadius-$_viewResetTick'),
              src: 'file://${widget.glbPath}',
              alt: '3D Model',
              autoRotate: _rot,
              rotationPerSecond: '30deg',
              cameraControls: true,
              cameraOrbit: _viewResetTick == 0 && _zoomRadius == 2.5 ? _defaultOrbit : orbit,
              fieldOfView: _defaultFov,
              minCameraOrbit: 'auto auto 1.2m',
              maxCameraOrbit: 'auto auto 5.0m',
              backgroundColor: kBg,
            ),
            Positioned(
              right: 14,
              top: 16,
              child: Column(children: [
                _viewerActionBtn(Icons.add_rounded, 'Zoom In', _zoomIn),
                const SizedBox(height: 10),
                _viewerActionBtn(Icons.remove_rounded, 'Zoom Out', _zoomOut),
                const SizedBox(height: 10),
                _viewerActionBtn(Icons.center_focus_strong_rounded, 'Reset View', _resetView),
              ]),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: kCard.withOpacity(0.92), borderRadius: BorderRadius.circular(20), border: Border.all(color: _rot ? kLime : kBorder)),
                child: InkWell(
                  onTap: () => setState(() => _rot = !_rot),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.autorenew_rounded, size: 16, color: _rot ? kLime : Colors.grey),
                    const SizedBox(width: 6),
                    Text(_rot ? '360° Rotate: ON' : '360° Rotate: OFF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _rot ? kLime : Colors.grey)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
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

  Widget _viewerActionBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: kCard.withOpacity(0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kBorder)),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: kLime, size: 22))),
    );
  }

  Widget _chip(String label, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: active ? kLime : kBg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
  );
}

