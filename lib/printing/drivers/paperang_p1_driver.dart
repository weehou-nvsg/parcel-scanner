import 'dart:typed_data';

import '../label_rasterizer.dart';
import '../paperang_protocol.dart';
import 'spp_printer_driver.dart';

/// Paperang P1 — proprietary framed raster protocol over Bluetooth Classic
/// SPP. No printer language: the label is rasterized to a 384-dot-wide 1-bit
/// image and streamed in PRINT_DATA packets.
///
/// Connect sequence mirrors the proven Kotlin client: register the session
/// CRC key first, then set heat density (printers fresh out of the box can
/// sit at 0 → blank prints).
class PaperangP1Driver extends SppPrinterDriver {
  static const int _heatDensity = 95;
  static const int _feedAfterPixels = 120;

  @override
  Future<void> onConnected() async {
    await sendBytes(PaperangProtocol.setCrcKeyPacket());
    await Future.delayed(const Duration(milliseconds: 100));
    await sendBytes(PaperangProtocol.setHeatDensityPacket(_heatDensity));
  }

  @override
  Future<void> printLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async {
    final lines = await LabelRasterizer.renderParcelLabel(
      trackingNumber: trackingNumber,
      addressLines: addressLines,
      cartonDisplay: cartonDisplay,
    );
    final data = Uint8List.fromList([for (final l in lines) ...l]);
    for (int i = 0; i < copies.clamp(1, 99); i++) {
      await _printImageData(data);
      if (i < copies - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Streams raw 1-bit image data (48 bytes per 384-dot line) in chunks with
  /// an incrementing packet index, pacing writes so the printer's buffer is
  /// not overrun.
  Future<void> _printImageData(Uint8List data) async {
    var index = 0;
    var offset = 0;
    while (offset < data.length) {
      final end = (offset + PaperangProtocol.maxDataChunk).clamp(0, data.length);
      await sendBytes(
        PaperangProtocol.printDataPacket(data.sublist(offset, end), index),
      );
      index++;
      offset = end;
      await Future.delayed(const Duration(milliseconds: 15));
    }
    await sendBytes(PaperangProtocol.feedPacket(_feedAfterPixels));
  }

  /// Triggers the printer's built-in self-test page.
  @override
  Future<void> printTest() =>
      sendBytes(PaperangProtocol.printTestPagePacket());
}
