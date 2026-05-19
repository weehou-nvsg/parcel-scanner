/// Builds ZPL (Zebra Programming Language) for the HPRT HM-T3 Pro.
///
/// The HM-T3 Pro prints from **ZPL only**. ESC/POS and CPCL are accepted over
/// the link and then silently dropped — nothing comes out. Coordinates are in
/// dots: at 203 dpi, 1 mm ≈ 8 dots, origin top-left.
class ZplBuilder {
  /// Hardware maximum print width — the 72 mm head at 203 dpi.
  static const int maxPrintWidth = 576;

  /// This app prints onto 30 mm × 75 mm label stock.
  static const int labelWidth = 240; // 30 mm
  static const int labelLength = 600; // 75 mm

  /// Usable text width — [labelWidth] minus an 8-dot margin on each side.
  static const int _textWidth = labelWidth - 16;

  /// The parcel label: re-formatted tracking number as text + QR code, the
  /// delivery address, and a large carton count. Mirrors the on-screen
  /// preview and the PDF output.
  ///
  /// Geometry is tuned for 30 mm × 75 mm stock; the dot coordinates may need
  /// adjustment if a different label size is loaded.
  static String parcelLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) {
    final tracking = _sanitize(trackingNumber);
    // `\&` is the line break inside a ^FB field block.
    final address =
        addressLines.take(3).map(_sanitize).join(r'\&');
    final carton = _sanitize(cartonDisplay);

    return '^XA\n'
        '^CI28\n' //                          interpret field data as UTF-8
        '^PW$labelWidth\n' //                 print width (dots)
        '^LL$labelLength\n' //                label length (dots)
        '^LH0,0\n' //                         label home = top-left
        // ── New tracking number ──
        '^FO8,12^A0N,18,18^FDNEW TRACKING:^FS\n'
        '^FO8,34^A0N,26,26^FB$_textWidth,3,2,L^FD$tracking^FS\n'
        // ── QR code — encodes the same tracking number ──
        '^FO64,112^BQN,2,4^FDMA,$tracking^FS\n'
        // ── Delivery address ──
        '^FO8,300^A0N,18,18^FDDELIVER TO:^FS\n'
        '^FO8,322^A0N,22,22^FB$_textWidth,4,2,L^FD$address^FS\n'
        // ── Divider + carton count ──
        '^FO8,440^GB$_textWidth,2,2^FS\n'
        '^FO8,452^A0N,18,18^FDCARTON COUNT^FS\n'
        '^FO8,476^A0N,90,90^FD$carton^FS\n'
        '^XZ\n';
  }

  /// Minimal text-only label — send this first to confirm ZPL works at all.
  /// If this prints, the link and language are good; if not, the problem is
  /// the connection/transport.
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
