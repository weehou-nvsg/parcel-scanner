import 'dart:typed_data';

/// Builds binary BLE packets for the Paperang thermal printer.
///
/// Protocol reverse-engineered from open-source projects:
///   python-paperang, sharperang (C#), paperang-web (WebBLE).
///
/// Packet structure:
///   0x02 | cmd(1B) | packetRemain(1B) | dataLen(2B LE) | data | CRC32(4B LE) | 0x03
///
/// CRC32 uses the non-standard initial value 0x35769521.
class PaperangBuilder {
  // ── BLE UUIDs (all Paperang models) ──────────────────────────────────────
  static const String serviceUuid = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  static const String writeUuid   = '49535343-6daa-4d02-abf6-19569aca69fe';
  static const String notifyUuid  = '49535343-1e4d-4bd9-ba61-23c647249616';

  // ── Print geometry ────────────────────────────────────────────────────────
  /// P1 / P2 standard print width: 384 pixels = 48 bytes per line (~200 DPI).
  static const int printWidth  = 384;
  static const int bytesPerLine = printWidth ~/ 8; // 48

  // ── Commands ──────────────────────────────────────────────────────────────
  static const int _cmdPrint = 0x00; // raster data (one line per packet)
  static const int _cmdHeat  = 0x19; // print density 0–100
  static const int _cmdFeed  = 0x1a; // paper feed, 2-byte LE pixel count

  // ── Framing ───────────────────────────────────────────────────────────────
  static const int _start = 0x02;
  static const int _end   = 0x03;

  // ── CRC32 — non-standard initial value ───────────────────────────────────
  static const int _crcInit = 0x35769521;

  static int _crc32(List<int> data) {
    int crc = _crcInit;
    for (int byte in data) {
      for (int i = 0; i < 8; i++) {
        final xorFlag = (crc ^ byte) & 1;
        crc = (crc >> 1) & 0x7FFFFFFF;
        if (xorFlag != 0) crc ^= 0xEDB88320;
        byte >>= 1;
      }
    }
    return crc & 0xFFFFFFFF;
  }

  /// Assembles a single framed packet.
  static Uint8List buildPacket(int cmd, List<int> data) {
    final len = data.length;
    // CRC covers cmd + packetRemain + dataLen(2B) + data (NOT the 0x02 start byte)
    final crcInput = [cmd, 0x00, len & 0xFF, (len >> 8) & 0xFF, ...data];
    final crc = _crc32(crcInput);
    return Uint8List.fromList([
      _start,
      cmd,
      0x00,            // packetRemain — 0 means this is the last (only) packet
      len & 0xFF,
      (len >> 8) & 0xFF,
      ...data,
      crc & 0xFF,
      (crc >> 8) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 24) & 0xFF,
      _end,
    ]);
  }

  // ── Image conversion ──────────────────────────────────────────────────────

  /// Converts raw RGBA pixel data to 1-bit raster lines for the Paperang.
  ///
  /// [rgba] must already be scaled to exactly [printWidth] pixels wide (the
  /// caller should use ui.instantiateImageCodec with targetWidth).
  /// Dark pixels (luminance < 180) → 1 (ink); light → 0 (no ink).
  static List<Uint8List> rgbaToRasterLines(
      Uint8List rgba, int width, int height) {
    final lines = <Uint8List>[];
    final scaleX = width / printWidth;

    for (int y = 0; y < height; y++) {
      final line = Uint8List(bytesPerLine);
      for (int byteIdx = 0; byteIdx < bytesPerLine; byteIdx++) {
        int byteVal = 0;
        for (int bit = 0; bit < 8; bit++) {
          final px   = byteIdx * 8 + bit;
          final srcX = (px * scaleX).round().clamp(0, width - 1);
          final idx  = (y * width + srcX) * 4;
          final r = rgba[idx];
          final g = rgba[idx + 1];
          final b = rgba[idx + 2];
          final a = rgba[idx + 3];
          final luma = (0.299 * r + 0.587 * g + 0.114 * b).round();
          // Dark + opaque pixel → print dot
          if (a > 128 && luma < 180) byteVal |= (0x80 >> bit);
        }
        line[byteIdx] = byteVal;
      }
      lines.add(line);
    }
    return lines;
  }

  // ── Print job builders ────────────────────────────────────────────────────

  /// Full print job from raster lines.
  /// Returns packets in send order: heat setting → raster lines → paper feed.
  static List<Uint8List> buildPrintJob(
    List<Uint8List> rasterLines, {
    int heatDensity = 50,   // 0–100; higher = darker
    int feedPixels  = 120,  // blank feed after print
  }) {
    final packets = <Uint8List>[];
    packets.add(buildPacket(_cmdHeat, [heatDensity.clamp(0, 100)]));
    for (final line in rasterLines) {
      packets.add(buildPacket(_cmdPrint, line));
    }
    packets.add(buildPacket(
      _cmdFeed,
      [feedPixels & 0xFF, (feedPixels >> 8) & 0xFF],
    ));
    return packets;
  }

  /// Test 1 — horizontal stripes (alternating 5px black/white bands).
  static List<Uint8List> buildTestStripes() {
    final lines = <Uint8List>[];
    for (int y = 0; y < 100; y++) {
      final line = Uint8List(bytesPerLine);
      final fill = (y ~/ 5).isEven ? 0xFF : 0x00;
      for (int i = 0; i < bytesPerLine; i++) line[i] = fill;
      lines.add(line);
    }
    return buildPrintJob(lines, feedPixels: 60);
  }

  /// Test 2 — solid black block (full ink coverage).
  static List<Uint8List> buildTestSolid() {
    final lines = <Uint8List>[];
    for (int y = 0; y < 100; y++) {
      final line = Uint8List(bytesPerLine)..fillRange(0, bytesPerLine, 0xFF);
      lines.add(line);
    }
    return buildPrintJob(lines, feedPixels: 60);
  }

  /// Test 3 — checkerboard (8×8 pixel squares alternating black/white).
  static List<Uint8List> buildTestCheckerboard() {
    final lines = <Uint8List>[];
    for (int y = 0; y < 100; y++) {
      final line = Uint8List(bytesPerLine);
      for (int b = 0; b < bytesPerLine; b++) {
        // Each byte = 8 pixels; alternate 0xAA / 0x55 per row, shift per col
        final rowShift = (y ~/ 8).isEven;
        line[b] = rowShift ? 0xAA : 0x55;
      }
      lines.add(line);
    }
    return buildPrintJob(lines, feedPixels: 60);
  }

  /// Test 4 — border only (outline rectangle, blank inside).
  static List<Uint8List> buildTestBorder() {
    final lines = <Uint8List>[];
    for (int y = 0; y < 100; y++) {
      final line = Uint8List(bytesPerLine);
      if (y == 0 || y == 99) {
        // Top and bottom edge — full line
        line.fillRange(0, bytesPerLine, 0xFF);
      } else {
        // Left 3 pixels and right 3 pixels only
        line[0] = 0xE0;                     // 3 left pixels
        line[bytesPerLine - 1] = 0x07;      // 3 right pixels
      }
      lines.add(line);
    }
    return buildPrintJob(lines, feedPixels: 60);
  }

  /// Kept for backward compatibility.
  static List<Uint8List> buildTestJob() => buildTestStripes();
}
