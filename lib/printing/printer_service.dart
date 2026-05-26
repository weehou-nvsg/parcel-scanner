import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'paperang_builder.dart';

/// A discovered Paperang BLE device.
class PrinterDevice {
  final String name;
  final String address; // BLE remote ID string
  final int rssi;
  final BluetoothDevice bleDevice;

  const PrinterDevice({
    required this.name,
    required this.address,
    required this.rssi,
    required this.bleDevice,
  });
}

/// Drives a Paperang P1/P2 thermal printer over Bluetooth LE.
///
/// No Android pairing needed — Paperang uses BLE GATT, not Classic SPP.
/// Connect flow: scanDevices() → connect(device) → printFromImage(pngBytes).
class PrinterService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChr;
  String? _connectedName;

  String get connectedName => _connectedName ?? '';

  // ── Permissions ──────────────────────────────────────────────────────────

  /// Requests the BLE + location runtime permissions Android needs for scanning.
  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ── Scan ─────────────────────────────────────────────────────────────────

  /// Scans for BLE devices and returns all found, sorted by RSSI (strongest first).
  /// Shows all devices — the user picks their Paperang by name.
  Future<List<PrinterDevice>> scanDevices({int seconds = 6}) async {
    final found = <String, PrinterDevice>{};

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final advName = r.advertisementData.advName;
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : advName.isNotEmpty
                ? advName
                : 'BLE ${r.device.remoteId.str.substring(0, 8)}';
        found[r.device.remoteId.str] = PrinterDevice(
          name: name,
          address: r.device.remoteId.str,
          rssi: r.rssi,
          bleDevice: r.device,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: seconds),
      );
      // Wait until scan finishes
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    } finally {
      await sub.cancel();
    }

    return found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  /// Alias kept for compatibility with existing screen code.
  Future<List<PrinterDevice>> pairedPrinters() => scanDevices();

  // ── Connection ───────────────────────────────────────────────────────────

  Future<bool> isConnected() async {
    if (_device == null) return false;
    return _device!.isConnected;
  }

  /// Connects to [printer] and discovers the Paperang write characteristic.
  Future<void> connect(PrinterDevice printer) async {
    // Disconnect any existing connection first
    await disconnect();

    await printer.bleDevice.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 12),
    );
    _device = printer.bleDevice;
    _connectedName = printer.name;

    // Discover services and find the Paperang write characteristic
    final services = await _device!.discoverServices();
    for (final svc in services) {
      if (svc.uuid == Guid(PaperangBuilder.serviceUuid)) {
        for (final chr in svc.characteristics) {
          if (chr.uuid == Guid(PaperangBuilder.writeUuid)) {
            _writeChr = chr;
            return;
          }
        }
      }
    }

    // If Paperang service UUID not found, try to find any writable characteristic
    // (some firmware versions don't advertise the UUID correctly)
    for (final svc in services) {
      for (final chr in svc.characteristics) {
        if (chr.properties.write || chr.properties.writeWithoutResponse) {
          _writeChr = chr;
          return;
        }
      }
    }

    throw Exception(
        'Could not find a writable characteristic on ${printer.name}. '
        'Is this a Paperang printer?');
  }

  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _writeChr = null;
    _connectedName = null;
  }

  // ── Printing ─────────────────────────────────────────────────────────────

  /// Prints a label from PNG bytes (e.g. from ScreenshotController.capture()).
  ///
  /// The PNG is decoded and scaled to [PaperangBuilder.printWidth] pixels wide,
  /// then converted to the 1-bit raster format the Paperang expects.
  Future<void> printFromImage(Uint8List pngBytes, {int copies = 1}) async {
    if (_writeChr == null) throw Exception('Not connected to a printer.');

    // Decode PNG → RGBA, scaling to the printer's native print width
    final codec = await ui.instantiateImageCodec(
      pngBytes,
      targetWidth: PaperangBuilder.printWidth,
    );
    final frame = await codec.getNextFrame();
    final byteData =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('Failed to decode label image.');

    final rgba   = byteData.buffer.asUint8List();
    final width  = frame.image.width;
    final height = frame.image.height;

    final lines   = PaperangBuilder.rgbaToRasterLines(rgba, width, height);
    final packets = PaperangBuilder.buildPrintJob(lines);

    final useWithoutResponse = _writeChr!.properties.writeWithoutResponse;

    for (int copy = 0; copy < copies.clamp(1, 99); copy++) {
      for (final pkt in packets) {
        await _writeChr!.write(pkt, withoutResponse: useWithoutResponse);
        await Future.delayed(const Duration(milliseconds: 30));
      }
      if (copies > 1 && copy < copies - 1) {
        // Small pause between copies so the printer keeps up
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Sends a test stripe pattern to verify the connection.
  Future<void> printTest() async {
    if (_writeChr == null) throw Exception('Not connected to a printer.');
    final packets = PaperangBuilder.buildTestJob();
    final useWithoutResponse = _writeChr!.properties.writeWithoutResponse;
    for (final pkt in packets) {
      await _writeChr!.write(pkt, withoutResponse: useWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }
}
