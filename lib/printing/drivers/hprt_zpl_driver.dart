import '../zpl_builder.dart';
import 'spp_printer_driver.dart';

/// HPRT HM-T3 Pro — prints from ZPL only (ESC/POS and CPCL are silently
/// dropped). 70 × 50 mm label stock, 203 dpi.
class HprtZplDriver extends SppPrinterDriver {
  @override
  Future<void> printLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async {
    final zpl = ZplBuilder.parcelLabel(
      trackingNumber: trackingNumber,
      addressLines: addressLines,
      cartonDisplay: cartonDisplay,
    );
    for (int i = 0; i < copies.clamp(1, 99); i++) {
      await sendText(zpl);
      if (i < copies - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  Future<void> printTest() => sendText(ZplBuilder.minimalTest());
}
