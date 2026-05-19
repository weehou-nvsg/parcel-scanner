import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ocr_service.dart';
import '../models/parcel_data.dart';
import 'review_screen.dart';

class ScanScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const ScanScreen({super.key, required this.prefs});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isProcessing = false;
  String _status = 'Point camera at the parcel label';
  final _ocr = OcrService();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _status = 'Camera permission denied');
      return;
    }
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      setState(() => _status = 'No camera found');
      return;
    }
    _controller = CameraController(_cameras[0], ResolutionPreset.high);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Processing label...';
    });

    try {
      final file = await _controller!.takePicture();
      final result = await _ocr.processImage(file.path);

      if (!mounted) return;

      final prefix = widget.prefs.getString('prefix') ?? '';
      final parcel = ParcelData(
        trackingNumber: result.trackingNumber,
        cartonCurrent: result.cartonCurrent,
        cartonTotal: result.cartonTotal,
        addressLines: result.addressLines,
        prefix: prefix,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            parcel: parcel,
            rawText: result.rawText,
            imagePath: file.path,
            prefs: widget.prefs,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _status = 'Error: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Label')),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(child: CameraPreview(_controller!))
          else
            Center(
              child: Text(_status, style: const TextStyle(color: Colors.white)),
            ),
          // Overlay frame guide
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: CustomPaint(painter: _FramePainter()),
            ),
          // Status + button at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isProcessing ? 'Processing...' : _status,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (!_isProcessing)
                    GestureDetector(
                      onTap: _captureAndProcess,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: Colors.white24,
                        ),
                        child: const Icon(Icons.camera, color: Colors.white, size: 36),
                      ),
                    )
                  else
                    const CircularProgressIndicator(color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final margin = size.width * 0.08;
    final rect = Rect.fromLTWH(
      margin,
      size.height * 0.2,
      size.width - margin * 2,
      size.height * 0.45,
    );

    const cornerLen = 28.0;
    // Draw corner brackets
    for (final corner in [
      [rect.left, rect.top, 1.0, 1.0],
      [rect.right, rect.top, -1.0, 1.0],
      [rect.left, rect.bottom, 1.0, -1.0],
      [rect.right, rect.bottom, -1.0, -1.0],
    ]) {
      final x = corner[0];
      final y = corner[1];
      final dx = corner[2];
      final dy = corner[3];
      canvas.drawLine(Offset(x, y), Offset(x + dx * cornerLen, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * cornerLen), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
