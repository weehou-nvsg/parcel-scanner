import 'dart:typed_data';

/// Generates a simple test payload for each supported print language.
/// Send via PrinterService.printRaw() — raw bytes, no Paperang framing.
class PrintLanguageTester {
  /// ESC/POS — Epson standard, used by most generic thermal printers.
  static Uint8List escPos() {
    final b = <int>[];
    b.addAll([0x1B, 0x40]);           // Initialize printer
    b.addAll([0x1B, 0x21, 0x08]);     // Double-height text
    b.addAll('ESC/POS TEST\n'.codeUnits);
    b.addAll([0x1B, 0x21, 0x00]);     // Normal text
    b.addAll('Print language: ESC/POS\n'.codeUnits);
    b.addAll([0x1B, 0x64, 0x04]);     // Feed 4 lines
    return Uint8List.fromList(b);
  }

  /// ZPL — Zebra Programming Language, used by Zebra label printers.
  static Uint8List zpl() {
    const s = '^XA\n'
        '^FO30,30^A0N,40,40^FDZPL TEST^FS\n'
        '^FO30,80^A0N,25,25^FDPrint language: ZPL^FS\n'
        '^XZ\n';
    return Uint8List.fromList(s.codeUnits);
  }

  /// TSPL — TSC Printer Language, used by TSC label printers.
  static Uint8List tspl() {
    const s = 'SIZE 50 mm,30 mm\r\n'
        'GAP 2 mm,0 mm\r\n'
        'CLS\r\n'
        'TEXT 10,10,"3",0,1,1,"TSPL TEST"\r\n'
        'TEXT 10,60,"2",0,1,1,"Print language: TSPL"\r\n'
        'PRINT 1\r\n';
    return Uint8List.fromList(s.codeUnits);
  }

  /// CPCL — Comtec Printer Control Language, used by Zebra/Honeywell mobile printers.
  static Uint8List cpcl() {
    const s = '! 0 200 200 200 1\r\n'
        'TEXT 4 0 20 40 CPCL TEST\r\n'
        'TEXT 4 0 20 90 Print language: CPCL\r\n'
        'FORM\r\n'
        'PRINT\r\n';
    return Uint8List.fromList(s.codeUnits);
  }
}
