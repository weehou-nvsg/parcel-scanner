import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String trackingNumber;
  final String cartonCurrent;
  final String cartonTotal;
  final List<String> addressLines;
  final String rawText;
  // All distinct text tokens found — shown to user for manual TID selection
  final List<String> allTokens;

  OcrResult({
    required this.trackingNumber,
    required this.cartonCurrent,
    required this.cartonTotal,
    required this.addressLines,
    required this.rawText,
    required this.allTokens,
  });
}

class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> processImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(inputImage);
    final rawText = recognized.text;

    final allTokens = _extractAllTokens(rawText);
    final tracking = _extractTracking(rawText);
    final carton = _extractCarton(rawText);
    final address = _extractAddress(rawText, tracking, carton.$1, carton.$2);

    return OcrResult(
      trackingNumber: tracking,
      cartonCurrent: carton.$1,
      cartonTotal: carton.$2,
      addressLines: address,
      rawText: rawText,
      allTokens: allTokens,
    );
  }

  // Returns every non-trivial text token for the user to pick from
  List<String> _extractAllTokens(String text) {
    final seen = <String>{};
    final tokens = <String>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue;
      // Split on whitespace and keep each word/number chunk
      for (final word in trimmed.split(RegExp(r'\s+'))) {
        final w = word.trim();
        if (w.length >= 3 && seen.add(w)) tokens.add(w);
      }
      // Also keep the full line if it's a reasonable length
      if (trimmed.length >= 4 && trimmed.length <= 80 && seen.add(trimmed)) {
        tokens.add(trimmed);
      }
    }
    // Sort: numbers first (likely barcodes/TIDs), then by length descending
    tokens.sort((a, b) {
      final aNum = RegExp(r'^\d+$').hasMatch(a);
      final bNum = RegExp(r'^\d+$').hasMatch(b);
      if (aNum && !bNum) return -1;
      if (!aNum && bNum) return 1;
      return b.length.compareTo(a.length);
    });
    return tokens;
  }

  String _extractTracking(String text) {
    final numPattern = RegExp(r'\b\d{8,}\b');
    final matches = numPattern.allMatches(text).toList();
    if (matches.isEmpty) return '';
    matches.sort((a, b) => b.group(0)!.length.compareTo(a.group(0)!.length));
    return matches.first.group(0)!;
  }

  (String, String) _extractCarton(String text) {
    final slashPattern = RegExp(r'\b(\d{1,4})\s*/\s*(\d{1,4})\b');
    var m = slashPattern.firstMatch(text);
    if (m != null) return (m.group(1)!, m.group(2)!);
    final ofPattern = RegExp(r'\b(\d{1,4})\s+of\s+(\d{1,4})\b', caseSensitive: false);
    m = ofPattern.firstMatch(text);
    if (m != null) return (m.group(1)!, m.group(2)!);
    return ('', '');
  }

  List<String> _extractAddress(
      String text, String tracking, String cartonA, String cartonB) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

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

    final postcodeRe = RegExp(r'\b\d{4}\b');
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
    final result = scored.where((e) => e.value >= 1).take(3).map((e) => e.key).toList();
    return result.isEmpty ? ['Address not detected'] : result;
  }

  void dispose() {
    _recognizer.close();
  }
}
