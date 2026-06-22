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

  /// The parcel label — only the new tracking number: a large, centred QR with
  /// the tracking number in big text underneath. The address/carton arguments
  /// are accepted for a uniform driver interface but intentionally not printed.
  /// Mirrors the on-screen preview and the PDF output.
  static String parcelLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) {
    final tracking = _sanitize(trackingNumber);

    // Magnification 9 ≈ 33–37 mm square; qrX centres the typical (version 2–3)
    // code on the 576-dot head so it can't clip at the paper edge.
    const qrX = 165;

    return '^XA\r\n'
        '^CI28\r\n'
        '^PW$labelWidth\r\n'
        '^LL$labelLength\r\n'
        '^LH0,0\r\n'
        '^MNY\r\n' // gapped label stock (use ^MNN for continuous)
        // ── Large, centred QR code ──
        '^FO$qrX,10^BQN,2,9^FDMA,$tracking^FS\r\n'
        // ── Tracking number — big, centred across the full width ──
        '^FO0,300^A0N,40,40^FB$labelWidth,2,0,C^FD$tracking^FS\r\n'
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
