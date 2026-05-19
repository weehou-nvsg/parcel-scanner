import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiResult {
  final String trackingNumber;
  final String cartonCurrent;
  final String cartonTotal;
  final List<String> addressLines;
  final String rawResponse;

  GeminiResult({
    required this.trackingNumber,
    required this.cartonCurrent,
    required this.cartonTotal,
    required this.addressLines,
    required this.rawResponse,
  });
}

class GeminiService {
  final String apiKey;

  GeminiService(this.apiKey);

  Future<GeminiResult> analyzeLabel(String imagePath) async {
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    final imageBytes = await File(imagePath).readAsBytes();
    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png'
        : ext == 'webp' ? 'image/webp'
        : ext == 'heic' || ext == 'heif' ? 'image/heic'
        : 'image/jpeg';
    final imagePart = DataPart(mimeType, imageBytes);

    const prompt = '''
You are a parcel label reader. Analyze this shipping/parcel label image and extract the following fields.

Return your answer in EXACTLY this format (one field per line, no extra text):
TID: <the tracking ID or tracking number — usually the longest barcode number or the number labelled as tracking, consignment, TID, or similar>
CARTON_CURRENT: <the current carton number, e.g. if label says "3 of 10" or "3/10" return 3>
CARTON_TOTAL: <the total carton count, e.g. if label says "3 of 10" or "3/10" return 10>
ADDRESS_1: <first line of delivery address>
ADDRESS_2: <second line of delivery address, or blank>
ADDRESS_3: <city/state/postcode line, or blank>

Rules:
- TID is usually the longest numeric sequence on the label, often under a barcode
- If you cannot find a field, leave it blank after the colon
- Do not add any explanation, just the 6 lines above
''';

    final response = await model.generateContent([
      Content.multi([TextPart(prompt), imagePart])
    ]);

    final text = response.text ?? '';
    return _parseResponse(text);
  }

  GeminiResult _parseResponse(String text) {
    String tid = '';
    String cartonCurrent = '';
    String cartonTotal = '';
    final addressLines = <String>[];

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('TID:')) {
        tid = trimmed.substring(4).trim();
      } else if (trimmed.startsWith('CARTON_CURRENT:')) {
        cartonCurrent = trimmed.substring(15).trim();
      } else if (trimmed.startsWith('CARTON_TOTAL:')) {
        cartonTotal = trimmed.substring(13).trim();
      } else if (trimmed.startsWith('ADDRESS_1:')) {
        final v = trimmed.substring(10).trim();
        if (v.isNotEmpty) addressLines.add(v);
      } else if (trimmed.startsWith('ADDRESS_2:')) {
        final v = trimmed.substring(10).trim();
        if (v.isNotEmpty) addressLines.add(v);
      } else if (trimmed.startsWith('ADDRESS_3:')) {
        final v = trimmed.substring(10).trim();
        if (v.isNotEmpty) addressLines.add(v);
      }
    }

    return GeminiResult(
      trackingNumber: tid,
      cartonCurrent: cartonCurrent,
      cartonTotal: cartonTotal,
      addressLines: addressLines.isEmpty ? ['Address not detected'] : addressLines,
      rawResponse: text,
    );
  }
}
