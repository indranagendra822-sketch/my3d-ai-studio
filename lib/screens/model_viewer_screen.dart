import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ModelViewerScreen extends StatefulWidget {
  final String modelSource;
  final bool isLocalFile;
  final String modelName;

  const ModelViewerScreen({
    super.key,
    required this.modelSource,
    this.isLocalFile = false,
    this.modelName = 'my3d_model.glb',
  });

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen> {
  bool isExporting = false;

  Future<void> exportModel() async {
    setState(() {
      isExporting = true;
    });

    try {
      String filePath;

      if (widget.isLocalFile) {
        filePath = widget.modelSource;
      } else {
        final response = await http.get(Uri.parse(widget.modelSource));
        if (response.statusCode != 200) {
          throw Exception('Failed to download 3D model');
        }
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.modelName}');
        await file.writeAsBytes(response.bodyBytes);
        filePath = file.path;
      }

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Created with My3D AI Studio',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewerSrc =
        widget.isLocalFile && !widget.modelSource.startsWith('file://')
            ? 'file://${widget.modelSource}'
            : widget.modelSource;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        title: const Text(
          '3D Model Preview',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF171B26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ModelViewer(
                  backgroundColor: const Color(0xFF171B26),
                  src: viewerSrc,
                  alt: 'Generated 3D Model',
                  ar: false,
                  autoRotate: true,
                  cameraControls: true,
                  disableZoom: false,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Drag to rotate 360° • Pinch to zoom in/out',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: isExporting ? null : exportModel,
                icon: isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  isExporting ? 'Preparing GLB...' : 'Export 3D Model (.GLB)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
