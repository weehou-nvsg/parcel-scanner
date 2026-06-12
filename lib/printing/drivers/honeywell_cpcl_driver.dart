import '../cpcl_builder.dart';
import 'spp_printer_driver.dart';

/// Honeywell RP4B — CPCL over Bluetooth Classic.
/// 100 × 150 mm portrait label stock, 200 dpi.
class HoneywellCpclDriver extends SppPrinterDriver {
  @override
  Future<void> printLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async {
    final cpcl = CpclBuilder.parcelLabel(
      trackingNumber: trackingNumber,
      addressLines: addressLines,
      cartonDisplay: cartonDisplay,
    );
    for (int i = 0; i < copies.clamp(1, 99); i++) {
      await sendText(cpcl);
      if (i < copies - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  Future<void> printTest() => sendText(CpclBuilder.testLabel());
}
