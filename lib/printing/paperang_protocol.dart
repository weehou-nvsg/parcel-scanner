import 'dart:typed_data';

/// Frame/packet builder for the Paperang P1 thermal printer.
///
/// Dart port of the proven Kotlin `PaperangClient` (paperang test app). The
/// P1 speaks a proprietary protocol over Bluetooth Classic SPP (RFCOMM).
/// Frame layout (everything little-endian):
///
///   0x02 | command (1B) | packet index (1B) | payload length (2B) | payload
///        | CRC32 of payload (4B) | 0x03
///
/// The CRC32 is a standard zlib CRC32 seeded with a session key. The default
/// ("standard") key is 0x35769521. On connect the driver registers a session
/// key with SET_CRC_KEY (payload = sessionKey XOR standardKey, packet CRC'd
/// with the standard key); all subsequent packets are CRC'd with the session
/// key.
///
/// Print data is a 1-bit image, 384 dots per line (48 bytes), MSB = leftmost
/// pixel, bit 1 = black.
class PaperangProtocol {
  // ── Commands ─────────────────────────────────────────────────────────────
  static const int cmdPrintData = 0;
  static const int cmdGetStatus = 12;
  static const int cmdSetCrcKey = 24;
  static const int cmdSetHeatDensity = 25;
  static const int cmdFeedLine = 26;
  static const int cmdPrintTestPage = 27;

  // ── Geometry / limits ────────────────────────────────────────────────────
  static const int lineWidthDots = 384;
  static const int bytesPerLine = lineWidthDots ~/ 8; // 48

  /// Bytes of image data per PRINT_DATA packet (32 lines).
  static const int maxDataChunk = 1536;

  // ── CRC keys ─────────────────────────────────────────────────────────────
  static const int standardCrcKey = 0x35769521;

  /// 0x6968634 + 5, same as known-working implementations.
  static const int sessionCrcKey = 0x06968639;

  // zlib-compatible CRC32 table, polynomial 0xEDB88320.
  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
    return c;
  });

  /// Equivalent of zlib.crc32(data, seed): seed is a previous CRC value.
  static int crc32(List<int> data, int seed) {
    var c = (~seed) & 0xFFFFFFFF;
    for (final b in data) {
      c = (c >> 8) ^ _crcTable[(c ^ (b & 0xFF)) & 0xFF];
    }
    return (~c) & 0xFFFFFFFF;
  }

  /// Assembles one framed packet, CRC'd with [crcKey].
  static Uint8List packet({
    required int command,
    required List<int> payload,
    int index = 0,
    required int crcKey,
  }) {
    final crc = crc32(payload, crcKey);
    return Uint8List.fromList([
      0x02,
      command,
      index & 0xFF,
      payload.length & 0xFF,
      (payload.length >> 8) & 0xFF,
      ...payload,
      crc & 0xFF,
      (crc >> 8) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 24) & 0xFF,
      0x03,
    ]);
  }

  /// SET_CRC_KEY handshake packet — must be the first packet after connect.
  /// It is CRC'd with the standard key; everything after uses the session key.
  static Uint8List setCrcKeyPacket() {
    final xored = sessionCrcKey ^ standardCrcKey;
    return packet(
      command: cmdSetCrcKey,
      payload: [
        xored & 0xFF,
        (xored >> 8) & 0xFF,
        (xored >> 16) & 0xFF,
        (xored >> 24) & 0xFF,
      ],
      crcKey: standardCrcKey,
    );
  }

  static Uint8List setHeatDensityPacket(int density) => packet(
        command: cmdSetHeatDensity,
        payload: [density.clamp(0, 100)],
        crcKey: sessionCrcKey,
      );

  static Uint8List feedPacket(int lines) => packet(
        command: cmdFeedLine,
        payload: [lines & 0xFF, (lines >> 8) & 0xFF],
        crcKey: sessionCrcKey,
      );

  static Uint8List printTestPagePacket() => packet(
        command: cmdPrintTestPage,
        payload: const [0],
        crcKey: sessionCrcKey,
      );

  static Uint8List printDataPacket(List<int> chunk, int index) => packet(
        command: cmdPrintData,
        payload: chunk,
        index: index,
        crcKey: sessionCrcKey,
      );
}
