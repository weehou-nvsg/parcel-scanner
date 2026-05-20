import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

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

  // Uses the stable v1 REST endpoint — avoids the v1beta package limitation
  // where gemini-1.5-flash is not resolvable.
  static const _model = 'gemini-3.1-flash-lite-preview';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1/models/$_model:generateContent';

  GeminiService(this.apiKey);

  Future<GeminiResult> analyzeLabel(String imagePath) async {
    final imageBytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);

    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : (ext == 'heic' || ext == 'heif')
                ? 'image/heic'
                : 'image/jpeg';

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

    final response = await http.post(
      Uri.parse('$_endpoint?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Image,
                }
              },
              {'text': prompt},
            ]
          }
        ]
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body);
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no candidates. Body: ${response.body}');
    }
    final parts = candidates.first['content']['parts'] as List?;
    final text = (parts?.isNotEmpty == true ? parts!.first['text'] as String? : null) ?? '';
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
