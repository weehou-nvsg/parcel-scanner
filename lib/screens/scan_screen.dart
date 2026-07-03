import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ocr_service.dart';
import '../services/gemini_service.dart';
import '../services/claude_service.dart';
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
  final _picker = ImagePicker();

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

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      // Labels read fine at this size; full-resolution photos make the
      // base64 upload to Claude/Gemini several times slower.
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;
    await _processFile(picked.path);
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;
    setState(() { _isProcessing = true; _status = 'Capturing...'; });
    try {
      final file = await _controller!.takePicture();
      await _processFile(file.path);
    } catch (e) {
      setState(() { _isProcessing = false; _status = 'Error: $e'; });
    }
  }

  Future<void> _processFile(String filePath) async {
    setState(() { _isProcessing = true; _status = 'Processing...'; });
    try {
      final selectedAi = widget.prefs.getString('selected_ai') ?? 'ocr';
      final geminiKey = widget.prefs.getString('gemini_api_key') ?? '';
      final claudeKey = widget.prefs.getString('claude_api_key') ?? '';
      final prefix = widget.prefs.getString('prefix') ?? '';

      String trackingNumber = '';
      String cartonCurrent = '';
      String cartonTotal = '';
      List<String> addressLines = [];
      String rawText = '';
      List<String> ocrTokens = [];

      // Start on-device OCR immediately so it runs while any AI request is in
      // flight: AI failure falls back instantly, and the review-screen pickers
      // get tokens even when AI succeeds.
      final ocrFuture = _ocr.processImage(filePath);

      Future<void> useOcrResult() async {
        final result = await ocrFuture;
        trackingNumber = result.trackingNumber;
        cartonCurrent = result.cartonCurrent;
        cartonTotal = result.cartonTotal;
        addressLines = result.addressLines;
        rawText = result.rawText;
        ocrTokens = result.allTokens;
      }

      if (selectedAi == 'gemini' && geminiKey.isNotEmpty) {
        setState(() => _status = 'Analysing with Gemini AI...');
        try {
          final result = await GeminiService(geminiKey).analyzeLabel(filePath);
          trackingNumber = result.trackingNumber;
          cartonCurrent = result.cartonCurrent;
          cartonTotal = result.cartonTotal;
          addressLines = result.addressLines;
          rawText = result.rawResponse;
          try { ocrTokens = (await ocrFuture).allTokens; } catch (_) {}
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Gemini error: $e'),
              duration: const Duration(seconds: 6),
              backgroundColor: Colors.red.shade700,
            ));
          }
          setState(() => _status = 'Gemini failed — using on-device OCR...');
          await useOcrResult();
        }
      } else if (selectedAi == 'claude' && claudeKey.isNotEmpty) {
        setState(() => _status = 'Analysing with Claude AI...');
        try {
          final result = await ClaudeService(claudeKey).analyzeLabel(filePath);
          trackingNumber = result.trackingNumber;
          cartonCurrent = result.cartonCurrent;
          cartonTotal = result.cartonTotal;
          addressLines = result.addressLines;
          rawText = result.rawResponse;
          try { ocrTokens = (await ocrFuture).allTokens; } catch (_) {}
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Claude error: $e'),
              duration: const Duration(seconds: 6),
              backgroundColor: Colors.red.shade700,
            ));
          }
          setState(() => _status = 'Claude failed — using on-device OCR...');
          await useOcrResult();
        }
      } else {
        setState(() => _status = 'Reading label...');
        await useOcrResult();
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            parcel: ParcelData(
              trackingNumber: trackingNumber,
              cartonCurrent: cartonCurrent,
              cartonTotal: cartonTotal,
              addressLines: addressLines,
              prefix: prefix,
            ),
            rawText: rawText,
            imagePath: filePath,
            prefs: widget.prefs,
            ocrTokens: ocrTokens,
          ),
        ),
      );
    } catch (e) {
      setState(() { _isProcessing = false; _status = 'Error: $e'; });
    }
  }

  String get _aiBadgeLabel {
    final selected = widget.prefs.getString('selected_ai') ?? 'ocr';
    switch (selected) {
      case 'gemini': return 'Gemini AI';
      case 'claude': return 'Claude AI';
      default: return 'OCR only';
    }
  }

  IconData get _aiBadgeIcon {
    final selected = widget.prefs.getString('selected_ai') ?? 'ocr';
    switch (selected) {
      case 'gemini': return Icons.auto_awesome;
      case 'claude': return Icons.psychology;
      default: return Icons.text_fields;
    }
  }

  bool get _aiActive {
    final selected = widget.prefs.getString('selected_ai') ?? 'ocr';
    return selected != 'ocr';
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
            Center(child: Text(_status, style: const TextStyle(color: Colors.white))),
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(child: CustomPaint(painter: _FramePainter())),
          // AI badge
          Positioned(
            top: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _aiActive
                    ? Colors.blue.withOpacity(0.85)
                    : Colors.grey.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_aiBadgeIcon, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(_aiBadgeLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
          // Status + shutter button
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isProcessing ? _status : 'Take a photo or upload from gallery',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (!_isProcessing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Gallery button
                        GestureDetector(
                          onTap: _pickFromGallery,
                          child: Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white70, width: 2),
                              color: Colors.white12,
                            ),
                            child: const Icon(Icons.photo_library,
                                color: Colors.white70, size: 26),
                          ),
                        ),
                        // Camera shutter button
                        GestureDetector(
                          onTap: _captureAndProcess,
                          child: Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.white24,
                            ),
                            child: const Icon(Icons.camera,
                                color: Colors.white, size: 36),
                          ),
                        ),
                        // Spacer to balance layout
                        const SizedBox(width: 56, height: 56),
                      ],
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
      margin, size.height * 0.2,
      size.width - margin * 2, size.height * 0.45,
    );
    const cornerLen = 28.0;
    for (final corner in [
      [rect.left, rect.top, 1.0, 1.0],
      [rect.right, rect.top, -1.0, 1.0],
      [rect.left, rect.bottom, 1.0, -1.0],
      [rect.right, rect.bottom, -1.0, -1.0],
    ]) {
      final x = corner[0]; final y = corner[1];
      final dx = corner[2]; final dy = corner[3];
      canvas.drawLine(Offset(x, y), Offset(x + dx * cornerLen, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * cornerLen), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
