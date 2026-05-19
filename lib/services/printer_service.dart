import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ─── HPRT HM-T3 Pro BLE UUIDs ────────────────────────────────────────────────
// HPRT uses the Nordic UART Service (NUS) profile for BLE printing
const _kNusServiceUuid    = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _kNusTxCharUuid     = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // phone → printer
const _kNusRxCharUuid     = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // printer → phone

// Fallback: HPRT proprietary service seen on some models
const _kHprtServiceUuid   = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
const _kHprtWriteCharUuid = '49535343-8841-43f4-a8d4-ecbe34729bb3';

// ─── Data classes ─────────────────────────────────────────────────────────────
class PrinterDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;

  PrinterDevice({required this.device, required this.name, required this.rssi});

  String get id => device.remoteId.str;
}

enum PrintProtocol { cpcl, tspl }

// ─── Service ──────────────────────────────────────────────────────────────────
class PrinterService {
  BluetoothDevice?         _bleDevice;
  BluetoothCharacteristic? _writeChr;
  StreamSubscription?      _stateSub;
  bool                     _connected = false;
  String?                  _connectedName;
  PrintProtocol            protocol = PrintProtocol.cpcl;

  bool   get isConnected   => _connected;
  String get connectedName => _connectedName ?? '';

  // ── Scan nearby BLE devices ───────────────────────────────────────────────
  Future<List<PrinterDevice>> scanBleDevices({int seconds = 6}) async {
    final found = <String, PrinterDevice>{};

    await FlutterBluePlus.startScan(timeout: Duration(seconds: seconds));

    await for (final results in FlutterBluePlus.scanResults) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        if (found.containsKey(id)) continue;
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : id;
        found[id] = PrinterDevice(
          device: r.device,
          name: name,
          rssi: r.rssi,
        );
      }
    }

    await FlutterBluePlus.stopScan();

    final list = found.values.toList();
    // Sort: likely printers first, then by signal strength
    list.sort((a, b) {
      final ap = _isPrinterName(a.name);
      final bp = _isPrinterName(b.name);
      if (ap && !bp) return -1;
      if (!ap && bp) return 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }

  bool _isPrinterName(String name) {
    final l = name.toLowerCase();
    return l.contains('hprt') || l.contains('t3') || l.contains('gm-t') ||
        l.contains('hm-t') || l.contains('printer') || l.contains('label') ||
        l.contains('thermal');
  }

  // ── Connect ───────────────────────────────────────────────────────────────
  Future<String> connect(PrinterDevice printer) async {
    await disconnect();

    await printer.device.connect(timeout: const Duration(seconds: 12));
    _bleDevice = printer.device;

    _stateSub = printer.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connected = false;
        _writeChr = null;
      }
    });

    final services = await printer.device.discoverServices();
    _writeChr = _findWriteChar(services);

    if (_writeChr == null) {
      await printer.device.disconnect();
      throw Exception(
        'Connected to "${printer.name}" but could not find a print characteristic.\n'
        'This printer may not be compatible or may not be in BLE mode.',
      );
    }

    _connected = true;
    _connectedName = printer.name;

    // Describe what we found for diagnostics
    final svcUuid = _writeChr!.serviceUuid.toString().toLowerCase();
    if (svcUuid == _kNusServiceUuid) return 'Connected via Nordic UART (NUS)';
    if (svcUuid == _kHprtServiceUuid) return 'Connected via HPRT proprietary service';
    return 'Connected (generic write characteristic)';
  }

  BluetoothCharacteristic? _findWriteChar(List<BluetoothService> services) {
    // 1. Nordic UART Service
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == _kNusServiceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == _kNusTxCharUuid) return c;
        }
      }
    }
    // 2. HPRT proprietary
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == _kHprtServiceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == _kHprtWriteCharUuid) return c;
        }
      }
    }
    // 3. Any writable characteristic
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) return c;
      }
    }
    return null;
  }

  // ── Print label ───────────────────────────────────────────────────────────
  Future<void> printLabel({
    required String newTrackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async {
    if (!_connected || _writeChr == null) {
      throw Exception('Printer not connected');
    }

    final bytes = protocol == PrintProtocol.cpcl
        ? _buildCpcl(
            tracking: newTrackingNumber,
            addressLines: addressLines,
            carton: cartonDisplay,
            copies: copies,
          )
        : _buildTspl(
            tracking: newTrackingNumber,
            addressLines: addressLines,
            carton: cartonDisplay,
            copies: copies,
          );

    await _sendBytes(bytes);
  }

  Future<void> _sendBytes(Uint8List bytes) async {
    // BLE MTU is commonly 20–512 bytes; use 200 to be safe
    const chunkSize = 200;
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      final chunk = bytes.sublist(i, end);
      if (_writeChr!.properties.writeWithoutResponse) {
        await _writeChr!.write(chunk, withoutResponse: true);
      } else {
        await _writeChr!.write(chunk);
      }
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  // ── CPCL commands — HPRT HM-T3 Pro (30mm × 75mm, 203 dpi) ───────────────
  // Coordinate system: dots. Width = 240, Height = 600
  Uint8List _buildCpcl({
    required String tracking,
    required List<String> addressLines,
    required String carton,
    required int copies,
  }) {
    final b = StringBuffer();

    // ! [offset] [hDpi] [vDpi] [height dots] [copies]
    b.writeln('! 0 203 203 600 $copies');
    b.writeln('PAGE-WIDTH 240');

    // ── Tracking number ──
    b.writeln('TEXT 4 0 5 5 NEW TRACKING:');
    int y = 25;
    for (final part in _wrap(tracking, 26)) {
      b.writeln('TEXT 4 0 5 $y $part');
      y += 20;
    }

    // ── QR code (centred) ──
    // BARCODE QR x y Model Multiplier ErrorLevel CellWidth
    final qrX = (240 - 160) ~/ 2;
    b.writeln('BARCODE QR $qrX ${y + 5} M 2 U 6');
    b.writeln(_safe(tracking));
    b.writeln('ENDQR');
    y = y + 5 + 170; // QR approx height

    // ── Address ──
    b.writeln('TEXT 4 0 5 $y DELIVER TO:');
    y += 20;
    for (final line in addressLines.take(3)) {
      for (final part in _wrap(_safe(line), 26)) {
        b.writeln('TEXT 4 0 5 $y $part');
        y += 18;
      }
    }

    // ── Divider + carton count ──
    y += 6;
    b.writeln('LINE 5 $y 235 $y 2');
    y += 8;
    b.writeln('TEXT 55 0 5 $y $carton');      // large font
    b.writeln('TEXT 4 0 5 ${y + 45} CARTON COUNT');

    b.writeln('FORM');
    b.writeln('PRINT');

    return Uint8List.fromList(latin1.encode(b.toString()));
  }

  // ── TSPL commands — fallback for other HPRT / TSC models ─────────────────
  Uint8List _buildTspl({
    required String tracking,
    required List<String> addressLines,
    required String carton,
    required int copies,
  }) {
    final b = StringBuffer();
    b.writeln('SIZE 30 mm,75 mm');
    b.writeln('GAP 2 mm,0 mm');
    b.writeln('DIRECTION 0,0');
    b.writeln('CLS');
    b.writeln('TEXT 5,5,"1",0,1,1,"NEW TRACKING:"');
    int y = 20;
    for (final p in _wrap(tracking, 28)) {
      b.writeln('TEXT 5,$y,"1",0,1,1,"$p"');
      y += 14;
    }
    b.writeln('QRCODE 55,${y + 5},L,4,A,0,"${_safe(tracking)}"');
    y = y + 140;
    b.writeln('TEXT 5,$y,"1",0,1,1,"DELIVER TO:"');
    y += 14;
    for (final line in addressLines.take(3)) {
      b.writeln('TEXT 5,$y,"1",0,1,1,"${_safe(line)}"');
      y += 13;
    }
    b.writeln('BAR 5,${y + 4},230,2');
    b.writeln('TEXT 5,${y + 12},"3",0,1,1,"$carton"');
    b.writeln('TEXT 5,${y + 42},"1",0,1,1,"CARTON COUNT"');
    b.writeln('PRINT $copies,1');
    return Uint8List.fromList(latin1.encode(b.toString()));
  }

  List<String> _wrap(String s, int max) {
    final out = <String>[];
    while (s.length > max) { out.add(s.substring(0, max)); s = s.substring(max); }
    if (s.isNotEmpty) out.add(s);
    return out;
  }

  String _safe(String s) =>
      s.replaceAll('"', "'").replaceAll('\r', '').replaceAll('\n', ' ');

  // ── Disconnect ────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _stateSub?.cancel();
    _stateSub = null;
    try { await _bleDevice?.disconnect(); } catch (_) {}
    _bleDevice = null;
    _writeChr = null;
    _connected = false;
    _connectedName = null;
  }
}
