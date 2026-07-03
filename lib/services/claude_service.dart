import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ClaudeResult {
  final String trackingNumber;
  final String cartonCurrent;
  final String cartonTotal;
  final List<String> addressLines;
  final String rawResponse;

  ClaudeResult({
    required this.trackingNumber,
    required this.cartonCurrent,
    required this.cartonTotal,
    required this.addressLines,
    required this.rawResponse,
  });
}

class ClaudeService {
  final String apiKey;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001';

  ClaudeService(this.apiKey);

  Future<ClaudeResult> analyzeLabel(String imagePath) async {
    final imageBytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png'
        : ext == 'webp' ? 'image/webp'
        : ext == 'heic' || ext == 'heif' ? 'image/heic'
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
      Uri.parse(_endpoint),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 512,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': mimeType,
                  'data': base64Image,
                },
              },
              {
                'type': 'text',
                'text': prompt,
              },
            ],
          }
        ],
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Claude API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body);
    final contentList = json['content'] as List?;
    if (contentList == null || contentList.isEmpty) {
      throw Exception('Claude returned an empty response. Body: ${response.body}');
    }
    final text = contentList.first['text'] as String? ?? '';
    return _parseResponse(text);
  }

  ClaudeResult _parseResponse(String text) {
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

    return ClaudeResult(
      trackingNumber: tid,
      cartonCurrent: cartonCurrent,
      cartonTotal: cartonTotal,
      addressLines: addressLines.isEmpty ? ['Address not detected'] : addressLines,
      rawResponse: text,
    );
  }
}
