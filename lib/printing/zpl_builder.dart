/// Builds ZPL (Zebra Programming Language) for the HPRT HM-T3 Pro.
///
/// The HM-T3 Pro prints from **ZPL only**. ESC/POS and CPCL are accepted over
/// the link and then silently dropped — nothing comes out. Coordinates are in
/// dots: at 203 dpi, 1 mm ≈ 8 dots, origin top-left.
class ZplBuilder {
  /// Hardware maximum print width — the 72 mm head at 203 dpi.
  static const int maxPrintWidth = 576;

  /// This app prints onto 70 mm × 50 mm label stock (landscape).
  static const int labelWidth  = 560; // 70 mm × 8 dots/mm
  static const int labelLength = 400; // 50 mm × 8 dots/mm

  // QR column: x=8, QR occupies ~270 dots wide (magnification 9, version 3–4).
  // Text column starts at x=_textX with _textW dots of usable width.
  static const int _textX  = 285;
  static const int _textW  = labelWidth - _textX - 8; // ≈ 267 dots

  /// The parcel label: large QR code on the left, tracking number, delivery
  /// address, and carton count stacked in the right column.
  /// Mirrors the on-screen preview and the PDF output.
  static String parcelLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) {
    final tracking = _sanitize(trackingNumber);
    final address  = addressLines.take(3).map(_sanitize).join(r'\&');
    final carton   = _sanitize(cartonDisplay);

    return '^XA\n'
        '^CI28\n'
        '^PW$labelWidth\n'
        '^LL$labelLength\n'
        '^LH0,0\n'
        // ── QR code — dominant left side, magnification 9 ≈ 33–37 mm square ──
        '^FO8,8^BQN,2,9^FDMA,$tracking^FS\n'
        // ── Right column: tracking number ──
        '^FO${_textX},8^A0N,15,15^FDNEW TRACKING:^FS\n'
        '^FO${_textX},27^A0N,19,19^FB${_textW},3,2,L^FD$tracking^FS\n'
        // ── Delivery address ──
        '^FO${_textX},115^A0N,15,15^FDDELIVER TO:^FS\n'
        '^FO${_textX},134^A0N,17,17^FB${_textW},4,2,L^FD$address^FS\n'
        // ── Divider + carton count ──
        '^FO${_textX},300^GB${_textW},2,2^FS\n'
        '^FO${_textX},308^A0N,14,14^FDCARTON:^FS\n'
        '^FO${_textX},326^A0N,60,60^FD$carton^FS\n'
        '^XZ\n';
  }

  /// Minimal text-only label — send this first to confirm ZPL works at all.
  static String minimalTest() => '^XA\n'
      '^CI28\n'
      '^PW$labelWidth\n'
      '^FO40,60^A0N,50,50^FDZPL TEST^FS\n'
      '^XZ\n';

  /// `^` and `~` start ZPL commands — strip them (and newlines) from any
  /// user-supplied data so it cannot inject commands.
  static String _sanitize(String s) => s
      .replaceAll('^', ' ')
      .replaceAll('~', ' ')
      .replaceAll('\r', '')
      .replaceAll('\n', ' ');
}
