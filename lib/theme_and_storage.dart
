import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

const kBg = Color(0xFF1A181A);
const kCard = Color(0xFF252326);
const kCardLight = Color(0xFF302D31);
const kLime = Color(0xFFC3D809);
const kBorder = Color(0xFF38343A);

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: kCardLight,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kLime, width: 1),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}

class SavedModel {
  final File glbFile;
  final File? thumbFile;
  final String name;
  final String sizeMb;
  final DateTime date;

  SavedModel({
    required this.glbFile,
    this.thumbFile,
    required this.name,
    required this.sizeMb,
    required this.date,
  });
}

Future<Directory> _modelsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final d = Directory('${dir.path}/saved_models');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<String> saveModelWithThumb(List<int> glbBytes, File sourceImage) async {
  final d = await _modelsDir();
  final id = DateTime.now().millisecondsSinceEpoch;
  final glbPath = '${d.path}/model_$id.glb';
  final thumbPath = '${d.path}/model_$id.png';

  await File(glbPath).writeAsBytes(glbBytes);
  await sourceImage.copy(thumbPath);
  return glbPath;
}

Future<List<SavedModel>> loadSavedModels() async {
  final d = await _modelsDir();
  final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList();
  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

  return files.map((f) {
    final thumbPath = f.path.replaceAll('.glb', '.png');
    final thumb = File(thumbPath);
    return SavedModel(
      glbFile: f,
      thumbFile: thumb.existsSync() ? thumb : null,
      name: f.path.split('/').last.replaceAll('.glb', ''),
      sizeMb: (f.lengthSync() / 1048576).toStringAsFixed(1),
      date: f.lastModifiedSync(),
    );
  }).toList();
}

Future<void> deleteSavedModel(SavedModel m) async {
  if (await m.glbFile.exists()) await m.glbFile.delete();
  if (m.thumbFile != null && await m.thumbFile!.exists()) {
    await m.thumbFile!.delete();
  }
}
