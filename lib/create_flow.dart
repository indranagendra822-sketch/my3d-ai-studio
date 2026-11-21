import 'dart:async';
import 'dart:convert';
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
      case ViewAngle.front:
        return 'Front';
      case ViewAngle.left:
        return 'Left';
      case ViewAngle.back:
        return 'Back';
      case ViewAngle.right:
        return 'Right';
      case ViewAngle.extra:
        return 'Extra';
    }
  }
}

class MultiViewSlot {
  final String id;
  ViewAngle angle;
  File? file;
  MultiViewSlot({required this.id, required this.angle, this.file});
}

class MultiViewPayload {
  final File frontFile;
  final List<MapEntry<String, File>> views;
  MultiViewPayload({required this.frontFile, required this.views});
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

  MultiViewPayload? _buildPayload() {
    if (!_hasRequiredFront) return null;
    final frontSlot = _slots.firstWhere(
      (s) => s.angle == ViewAngle.front && s.file != null,
      orElse: () => _slots.firstWhere((s) => s.file != null),
    );
    final List<MapEntry<String, File>> entries = [];
    int extraIdx = 1;
    for (final slot in _slots) {
      final f = slot.file;
      if (f == null) continue;
      if (slot == frontSlot) {
        entries.add(MapEntry('front', f));
      } else if (slot.angle == ViewAngle.extra) {
        entries.add(MapEntry('extra_${extraIdx++}', f));
      } else {
        entries.add(MapEntry(slot.angle.name, f));
      }
    }
    return MultiViewPayload(frontFile: frontSlot.file!, views: entries);
  }

  Future<void> _pickForSlot(int index, ImageSource src) async {
    final p = await ImagePicker().pickImage(source: src);
    if (p == null) return;
    setState(() {
      _slots[index].file = File(p.path);
      _selectedIndex = index;
    });
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
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: kLime),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickForSlot(index, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: kLime),
              title: const Text('Take Photo with Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickForSlot(index, ImageSource.camera);
              },
            ),
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
    final payload = _buildPayload();
    if (payload == null) {
      showToast(context, 'Front view photo ಕಡ್ಡಾಯವಾಗಿದೆ!');
      return;
    }
    final url = (await SharedPreferences.getInstance()).getString('saved_api_url') ?? '';
    if (url.trim().isEmpty) {
      if (mounted) showToast(context, 'ಮೊದಲು Home Settings (⚙️) ನಲ್ಲಿ API URL ಸೇವ್ ಮಾಡಿ!');
      return;
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProgressScreen(payload: payload, apiUrl: url.trim())),
      );
    }
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
                  onTap: () {
                    setState(() => _selectedIndex = idx);
                    if (slot.file == null) _showSourceSheet(idx);
                  },
                  child: Container(
                    width: 86,
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? kLime : kBorder, width: isSelected ? 2 : 1),
                    ),
                    child: Stack(children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Container(
                                width: double.infinity,
                                color: kBg,
                                child: slot.file != null
                                    ? Image.file(slot.file!, fit: BoxFit.cover)
                                    : const Icon(Icons.add_a_photo_rounded, color: Colors.grey, size: 24),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                          child: Text(
                            isFront ? 'Front *' : slot.angle.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? kLime : Colors.white70),
                          ),
                        ),
                      ]),
                      if (slot.file != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeSlotImage(idx),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
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
              onChanged: (val) {
                if (val != null) setState(() => _activeSlot.angle = val);
              },
            ),
            const Spacer(),
            if (previewFile != null)
              TextButton.icon(
                onPressed: () => _showSourceSheet(_selectedIndex),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: kLime),
                label: const Text('Replace', style: TextStyle(color: kLime, fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: previewFile != null ? kLime.withOpacity(0.5) : kBorder, width: 1.5),
              ),
              child: previewFile != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.file(previewFile, fit: BoxFit.contain))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: kLime.withOpacity(0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.add_photo_alternate_rounded, size: 46, color: kLime),
                      ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: kLime,
                disabledBackgroundColor: kCardLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
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
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLime.withOpacity(0.5), width: 1.2),
        ),
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
      final p = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s.w
        ..style = PaintingStyle.stroke;
      if (s.erase) {
        p.color = Colors.white;
      } else {
        p.blendMode = BlendMode.clear;
      }
      for (int i = 0; i < s.pts.length - 1; i++) {
        canvas.drawLine(s.pts[i], s.pts[i + 1], p);
      }
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
