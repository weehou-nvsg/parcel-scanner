import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

/// Renders the parcel label as a 1-bit raster image for dot-line printers
/// (Paperang P1: 384 dots per line, MSB = leftmost pixel, bit 1 = black).
///
/// This is the raster equivalent of `ZplBuilder.parcelLabel` /
/// `CpclBuilder.parcelLabel` — same content, drawn with a Canvas instead of a
/// printer language: large QR on top, tracking number, address, carton count.
class LabelRasterizer {
  static const int width = 384;
  static const int bytesPerLine = width ~/ 8; // 48

  static const double _margin = 8;
  static const double _gap = 10;

  /// Renders the full parcel label. Returns one 48-byte packed line per
  /// printed dot row, top to bottom.
  static Future<List<Uint8List>> renderParcelLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) async {
    final image = await _drawLabel(
      trackingNumber: trackingNumber,
      addressLines: addressLines,
      cartonDisplay: cartonDisplay,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return rgbaToLines(data!.buffer.asUint8List(), image.width, image.height);
  }

  static Future<ui.Image> _drawLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) async {
    const maxTextWidth = width - 2 * _margin;

    TextPainter text(String s,
        {double size = 20,
        FontWeight weight = FontWeight.normal,
        String? family}) {
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: const Color(0xFF000000),
            fontSize: size,
            fontWeight: weight,
            fontFamily: family,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: maxTextWidth);
    }

    // Only the new tracking number is printed — big and bold under the QR.
    // The address/carton arguments are accepted for a uniform interface but
    // intentionally not drawn.
    final tracking = text(trackingNumber,
        size: 30, weight: FontWeight.bold, family: 'monospace');

    // QR with an integer dots-per-module size so modules stay crisp.
    final qrCode = QrCode.fromData(
      data: trackingNumber,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    final modules = qrImage.moduleCount;
    final moduleSize = ((width - 48) ~/ modules).clamp(1, 16);
    final qrSize = (modules * moduleSize).toDouble();
    final qrX = ((width - qrSize) / 2).floorToDouble();

    var height = _margin + qrSize + _gap;
    height += tracking.height + _margin;
    final heightPx = height.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), heightPx.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final black = Paint()..color = const Color(0xFF000000);

    var y = _margin;
    for (var r = 0; r < modules; r++) {
      for (var c = 0; c < modules; c++) {
        if (qrImage.isDark(r, c)) {
          canvas.drawRect(
            Rect.fromLTWH(qrX + c * moduleSize, y + r * moduleSize,
                moduleSize.toDouble(), moduleSize.toDouble()),
            black,
          );
        }
      }
    }
    y += qrSize + _gap;

    void drawCentered(TextPainter t) {
      t.paint(canvas, Offset(_margin + (maxTextWidth - t.width) / 2, y));
      y += t.height;
    }

    drawCentered(tracking);

    return recorder.endRecording().toImage(width, heightPx);
  }

  /// Thresholds raw RGBA pixels into packed 1-bit lines.
  /// Dark + opaque pixels (luma < 160) become ink.
  static List<Uint8List> rgbaToLines(Uint8List rgba, int w, int h) {
    final lines = <Uint8List>[];
    for (var y = 0; y < h; y++) {
      final line = Uint8List(bytesPerLine);
      final limit = w < width ? w : width;
      for (var x = 0; x < limit; x++) {
        final i = (y * w + x) * 4;
        final luma =
            (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (rgba[i + 3] > 128 && luma < 160) {
          line[x >> 3] |= 0x80 >> (x & 7);
        }
      }
      lines.add(line);
    }
    return lines;
  }
}
