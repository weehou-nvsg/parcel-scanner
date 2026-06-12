/// Builds ZPL (Zebra Programming Language) for the HPRT HM-T3 Pro.
///
/// The HM-T3 Pro prints from **ZPL only**. ESC/POS and CPCL are accepted over
/// the link and then silently dropped — nothing comes out. Coordinates are in
/// dots: at 203 dpi, 1 mm ≈ 8 dots, origin top-left.
///
/// Format details (CRLF line endings, `^PW576`, `^MNY` gapped media) match
/// the proven test app at `~/work/ninjavan/hprt`.
class ZplBuilder {
  /// Hardware maximum print width — the 72 mm head at 203 dpi.
  static const int maxPrintWidth = 576;

  /// This app prints onto 75 mm × 50 mm label stock (landscape);
  /// printable width is the full 576-dot head.
  static const int labelWidth  = 576;
  static const int labelLength = 400; // 50 mm × 8 dots/mm

  // QR column: x=8, QR occupies ~270 dots wide (magnification 9, version 3–4).
  // Text column starts at x=_textX with _textW dots of usable width.
  static const int _textX  = 285;
  static const int _textW  = labelWidth - _textX - 8; // ≈ 283 dots

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

    return '^XA\r\n'
        '^CI28\r\n'
        '^PW$labelWidth\r\n'
        '^LL$labelLength\r\n'
        '^LH0,0\r\n'
        '^MNY\r\n' // gapped label stock (use ^MNN for continuous)
        // ── QR code — dominant left side, magnification 9 ≈ 33–37 mm square ──
        '^FO8,8^BQN,2,9^FDMA,$tracking^FS\r\n'
        // ── Right column: tracking number ──
        '^FO$_textX,8^A0N,15,15^FDNEW TRACKING:^FS\r\n'
        '^FO$_textX,27^A0N,19,19^FB$_textW,3,2,L^FD$tracking^FS\r\n'
        // ── Delivery address ──
        '^FO$_textX,115^A0N,15,15^FDDELIVER TO:^FS\r\n'
        '^FO$_textX,134^A0N,17,17^FB$_textW,4,2,L^FD$address^FS\r\n'
        // ── Divider + carton count ──
        '^FO$_textX,300^GB$_textW,2,2^FS\r\n'
        '^FO$_textX,308^A0N,14,14^FDCARTON:^FS\r\n'
        '^FO$_textX,326^A0N,60,60^FD$carton^FS\r\n'
        '^XZ\r\n';
  }

  /// Minimal text-only label — send this first to confirm ZPL works at all.
  static String minimalTest() => '^XA\r\n'
      '^CI28\r\n'
      '^PW$labelWidth\r\n'
      '^LL$labelLength\r\n'
      '^MNY\r\n'
      '^FO40,60^A0N,50,50^FDZPL TEST^FS\r\n'
      '^FO40,130^A0N,28,28^FDHPRT HM-T3 Pro^FS\r\n'
      '^XZ\r\n';

  /// `^` and `~` start ZPL commands — strip them (and newlines) from any
  /// user-supplied data so it cannot inject commands.
  static String _sanitize(String s) => s
      .replaceAll('^', ' ')
      .replaceAll('~', ' ')
      .replaceAll('\r', '')
      .replaceAll('\n', ' ');
}
