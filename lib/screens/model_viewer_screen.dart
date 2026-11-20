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
  HttpServer? _localServer;
  String? viewerUrl;
  String? fileInfo;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _prepareViewer();
  }

  Future<void> _prepareViewer() async {
    if (!widget.isLocalFile) {
      setState(() {
        viewerUrl = widget.modelSource;
      });
      return;
    }

    try {
      final file = File(widget.modelSource);
      if (!await file.exists()) {
        setState(() {
          errorMessage = '3D model file not found on device.';
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final isValidGlb = bytes.length >= 4 &&
          bytes[0] == 0x67 &&
          bytes[1] == 0x6C &&
          bytes[2] == 0x54 &&
          bytes[3] == 0x46;

      if (!isValidGlb) {
        setState(() {
          errorMessage =
              'Downloaded file is not a valid GLB (${bytes.length} bytes).';
        });
        return;
      }

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _localServer = server;

      server.listen((HttpRequest request) async {
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.headers
            .set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
        request.response.headers.set('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('Content-Type', 'model/gltf-binary');
        request.response.headers.contentLength = bytes.length;
        if (request.method != 'HEAD') {
          request.response.add(bytes);
        }
        await request.response.close();
      });

      final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(2);
      if (!mounted) return;
      setState(() {
        viewerUrl = 'http://127.0.0.1:${server.port}/model.glb';
        fileInfo = 'GLB Ready • $sizeMb MB';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Could not load 3D preview: $e';
      });
    }
  }

  @override
  void dispose() {
    _localServer?.close(force: true);
    super.dispose();
  }

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
          if (fileInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                fileInfo!,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3040),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : viewerUrl == null
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                            ),
                          )
                        : ModelViewer(
                            backgroundColor: const Color(0xFF2A3040),
                            src: viewerUrl!,
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
