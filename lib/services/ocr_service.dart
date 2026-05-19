import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String trackingNumber;
  final String cartonCurrent;
  final String cartonTotal;
  final List<String> addressLines;
  final String rawText;

  OcrResult({
    required this.trackingNumber,
    required this.cartonCurrent,
    required this.cartonTotal,
    required this.addressLines,
    required this.rawText,
  });
}

class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> processImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(inputImage);
    final rawText = recognized.text;

    final tracking = _extractTracking(rawText);
    final carton = _extractCarton(rawText);
    final address = _extractAddress(rawText, tracking, carton.$1, carton.$2);

    return OcrResult(
      trackingNumber: tracking,
      cartonCurrent: carton.$1,
      cartonTotal: carton.$2,
      addressLines: address,
      rawText: rawText,
    );
  }

  // Finds the longest digit sequence — usually the tracking barcode number
  String _extractTracking(String text) {
    final numPattern = RegExp(r'\b\d{8,}\b');
    final matches = numPattern.allMatches(text).toList();
    if (matches.isEmpty) return '';
    matches.sort((a, b) => b.group(0)!.length.compareTo(a.group(0)!.length));
    return matches.first.group(0)!;
  }

  // Finds X/Y or "X of Y" carton pattern
  (String, String) _extractCarton(String text) {
    // Try X/Y format
    final slashPattern = RegExp(r'\b(\d{1,4})\s*/\s*(\d{1,4})\b');
    var m = slashPattern.firstMatch(text);
    if (m != null) return (m.group(1)!, m.group(2)!);

    // Try "X of Y" format
    final ofPattern = RegExp(r'\b(\d{1,4})\s+of\s+(\d{1,4})\b', caseSensitive: false);
    m = ofPattern.firstMatch(text);
    if (m != null) return (m.group(1)!, m.group(2)!);

    return ('', '');
  }

  // Heuristic: address lines typically contain street keywords or postcode patterns
  List<String> _extractAddress(
      String text, String tracking, String cartonA, String cartonB) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Remove lines that are clearly tracking or carton-count lines
    final skipPatterns = [
      if (tracking.isNotEmpty) RegExp(RegExp.escape(tracking)),
      RegExp(r'^\d{1,4}[/\s]of[\s/]\d{1,4}$', caseSensitive: false),
      RegExp(r'^tracking', caseSensitive: false),
      RegExp(r'^barcode', caseSensitive: false),
      RegExp(r'^scan', caseSensitive: false),
    ];

    bool shouldSkip(String line) {
      for (final p in skipPatterns) {
        if (p.hasMatch(line)) return true;
      }
      return false;
    }

    // Score lines: address lines tend to have letters + numbers, or AU postcode pattern
    final postcodeRe = RegExp(r'\b\d{4}\b');  // AU postcodes
    final streetRe = RegExp(
        r'\b(st|street|rd|road|ave|avenue|dr|drive|ln|lane|ct|court|blvd|way|pl|place|crescent|cres|parade|pde)\b',
        caseSensitive: false);

    final scored = <MapEntry<String, int>>[];
    for (final line in lines) {
      if (shouldSkip(line)) continue;
      int score = 0;
      if (streetRe.hasMatch(line)) score += 3;
      if (postcodeRe.hasMatch(line)) score += 2;
      if (RegExp(r'[A-Za-z]').hasMatch(line) && RegExp(r'\d').hasMatch(line)) score += 1;
      if (line.length > 5 && line.length < 60) score += 1;
      scored.add(MapEntry(line, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    // Take top 3 address lines (min score 1)
    final result = scored.where((e) => e.value >= 1).take(3).map((e) => e.key).toList();
    return result.isEmpty ? ['Address not detected'] : result;
  }

  void dispose() {
    _recognizer.close();
  }
}
