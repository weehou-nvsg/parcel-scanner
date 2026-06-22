/// Builds CPCL (Comtec Printer Control Language) for the Honeywell RP4B.
///
/// Label size: 100 mm wide × 150 mm tall (portrait).
/// Resolution: 200 DPI (CPCL standard unit).
/// Layout: large centred QR code with the tracking number in big text below.
class CpclBuilder {
  static const int _dpi         = 200;
  static const int _heightDots  = 1200;  // 150 mm × 8 dots/mm

  /// Parcel label — only the new tracking number: a large, centred QR with the
  /// tracking number in big text underneath. The address/carton arguments are
  /// accepted for a uniform driver interface but intentionally not printed.
  static String parcelLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) {
    final t = _sanitize(trackingNumber);

    // QR module width 18 → large square. CENTER makes the QR (and the text)
    // auto-centre on the 800-dot label regardless of QR version, so a short
    // code can't drift to the edge and clip.
    const qrMod = 18;
    const qrY   = 100;

    final sb = StringBuffer();
    sb.writeln('! 0 $_dpi $_dpi $_heightDots 1');
    sb.writeln('CENTER');
    // Large, centred QR code
    sb.writeln('BARCODE QR 0 $qrY M $qrMod');
    sb.writeln('MA,M');
    sb.writeln(t);
    sb.writeln('ENDQR');
    // Tracking number — large and centred, below the QR
    sb.writeln('SETMAG 2 2');
    sb.writeln('TEXT 7 0 0 760 $t');
    sb.writeln('SETMAG 1 1');
    sb.writeln('LEFT');
    sb.writeln('FORM');
    sb.writeln('PRINT');
    return sb.toString();
  }

  /// Minimal test label — confirms CPCL is the correct print language.
  static String testLabel() {
    final sb = StringBuffer();
    sb.writeln('! 0 $_dpi $_dpi 400 1');
    sb.writeln('TEXT 7 0 50 50 CPCL TEST OK');
    sb.writeln('TEXT 4 0 50 140 Honeywell RP4B');
    sb.writeln('TEXT 4 0 50 190 Print language: CPCL');
    sb.writeln('FORM');
    sb.writeln('PRINT');
    return sb.toString();
  }

  static String _sanitize(String s) =>
      s.replaceAll('\r', '').replaceAll('\n', ' ').trim();
}
