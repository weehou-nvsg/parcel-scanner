import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

// HPRT HM-T3 Pro uses TSPL (Eltron/TSC label command language)
// Label size: 30mm wide x 75mm tall
// At 203 DPI (8 dots/mm): 240 dots wide, 600 dots tall

class PrinterService {
  BluetoothConnection? _connection;
  String? _connectedAddress;

  bool get isConnected => _connection?.isConnected ?? false;
  String? get connectedAddress => _connectedAddress;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices;
  }

  Future<void> connect(String address) async {
    await _connection?.close();
    _connection = await BluetoothConnection.toAddress(address);
    _connectedAddress = address;
  }

  Future<void> disconnect() async {
    await _connection?.close();
    _connection = null;
    _connectedAddress = null;
  }

  Future<void> printLabel({
    required String newTrackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async {
    if (_connection == null || !_connection!.isConnected) {
      throw Exception('Printer not connected');
    }

    final tspl = _buildTspl(
      newTrackingNumber: newTrackingNumber,
      addressLines: addressLines,
      cartonDisplay: cartonDisplay,
      copies: copies,
    );

    _connection!.output.add(Uint8List.fromList(latin1.encode(tspl)));
    await _connection!.output.allSent;
  }

  // Builds TSPL commands for 30mm x 75mm label (portrait)
  // Coordinate origin: top-left
  // Units: dots (1 dot = 0.125mm at 203dpi)
  String _buildTspl({
    required String newTrackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    required int copies,
  }) {
    final buf = StringBuffer();

    // Label setup
    buf.writeln('SIZE 30 mm,75 mm');
    buf.writeln('GAP 2 mm,0 mm');
    buf.writeln('DIRECTION 0,0');
    buf.writeln('REFERENCE 0,0');
    buf.writeln('OFFSET 0 mm');
    buf.writeln('SET PEEL OFF');
    buf.writeln('SET CUTTER OFF');
    buf.writeln('CLS');

    // --- "NEW TRACKING" header label (font 1 = 8x12 dots) ---
    buf.writeln('TEXT 5,5,"1",0,1,1,"NEW TRACKING:"');

    // Tracking number — may be long; use font 1 (8 dots/char)
    // 240 dots wide / 8 = 30 chars max per line
    final trackParts = _splitIntoLines(newTrackingNumber, 28);
    int y = 20;
    for (final part in trackParts) {
      buf.writeln('TEXT 5,$y,"1",0,1,1,"$part"');
      y += 14;
    }

    // --- QR Code ---
    // QRCODE x,y,ECC,cellWidth,mode,rotation,"data"
    // Cell width 4 → QR is roughly 4*modules dots; for version 3 ~29 modules → ~116 dots ≈ 14.5mm
    // Center horizontally: (240 - estimated_size) / 2
    final qrY = y + 5;
    final safeTracking = newTrackingNumber.replaceAll('"', '\'');
    buf.writeln('QRCODE 55,$qrY,L,4,A,0,"$safeTracking"');
    final qrEndY = qrY + 130; // approximate QR height in dots

    // --- Delivery address ---
    int addrY = qrEndY + 8;
    buf.writeln('TEXT 5,$addrY,"1",0,1,1,"DELIVER TO:"');
    addrY += 14;
    for (final line in addressLines.take(3)) {
      final safe = line.replaceAll('"', '\'').replaceAll(r'\', '/');
      final parts = _splitIntoLines(safe, 28);
      for (final p in parts) {
        buf.writeln('TEXT 5,$addrY,"1",0,1,1,"$p"');
        addrY += 13;
      }
    }

    // --- Divider line ---
    final barY = addrY + 4;
    buf.writeln('BAR 5,$barY,230,2');

    // --- Carton count (large) ---
    final cartonY = barY + 8;
    buf.writeln('TEXT 5,$cartonY,"3",0,1,1,"$cartonDisplay"');
    buf.writeln('TEXT 5,${cartonY + 30},"1",0,1,1,"CARTON COUNT"');

    // --- Print ---
    buf.writeln('PRINT $copies,1');
    buf.writeln('');

    return buf.toString();
  }

  List<String> _splitIntoLines(String text, int maxChars) {
    final parts = <String>[];
    var remaining = text;
    while (remaining.length > maxChars) {
      parts.add(remaining.substring(0, maxChars));
      remaining = remaining.substring(maxChars);
    }
    if (remaining.isNotEmpty) parts.add(remaining);
    return parts;
  }
}
