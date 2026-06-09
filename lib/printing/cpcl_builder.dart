/// Builds CPCL (Comtec Printer Control Language) for the Honeywell RP4B.
///
/// Label size: 100 mm wide × 150 mm tall (portrait).
/// Resolution: 200 DPI (CPCL standard unit).
/// Layout: large QR code at top, tracking + address + carton below.
class CpclBuilder {
  static const int _dpi         = 200;
  static const int _widthDots   = 800;   // 100 mm × 8 dots/mm
  static const int _heightDots  = 1200;  // 150 mm × 8 dots/mm

  /// Full parcel label — QR dominant at top, text info below.
  static String parcelLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
  }) {
    final t  = _sanitize(trackingNumber);
    final a1 = addressLines.isNotEmpty     ? _sanitize(addressLines[0]) : '';
    final a2 = addressLines.length > 1     ? _sanitize(addressLines[1]) : '';
    final a3 = addressLines.length > 2     ? _sanitize(addressLines[2]) : '';
    final c  = _sanitize(cartonDisplay);

    // QR module width 18 → ~65–74 mm square, centred on 800-dot wide label.
    // Printer auto-selects version; M = medium error correction.
    const qrMod = 18;
    const qrX   = 103;  // (800 − 594) / 2  ≈ centred for version-4 QR
    const qrY   = 30;

    final sb = StringBuffer();
    sb.writeln('! 0 $_dpi $_dpi $_heightDots 1');
    // Large QR code
    sb.writeln('BARCODE QR $qrX $qrY M $qrMod');
    sb.writeln('MA,M');
    sb.writeln(t);
    sb.writeln('ENDQR');
    // Tracking number
    sb.writeln('TEXT 4 0 20 660 NEW TRACKING:');
    sb.writeln('TEXT 7 0 20 690 $t');
    // Delivery address
    sb.writeln('TEXT 4 0 20 770 DELIVER TO:');
    if (a1.isNotEmpty) sb.writeln('TEXT 4 0 20 800 $a1');
    if (a2.isNotEmpty) sb.writeln('TEXT 4 0 20 830 $a2');
    if (a3.isNotEmpty) sb.writeln('TEXT 4 0 20 860 $a3');
    // Carton count — large text
    sb.writeln('LINE 20 920 780 920 2');
    sb.writeln('TEXT 4 0 20 930 CARTON:');
    sb.writeln('SETMAG 3 3');
    sb.writeln('TEXT 7 0 20 960 $c');
    sb.writeln('SETMAG 1 1');
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
