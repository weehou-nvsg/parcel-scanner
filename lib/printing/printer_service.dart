import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'cpcl_builder.dart';

/// A paired Bluetooth device.
class PrinterDevice {
  final String name;
  final String address;

  const PrinterDevice({required this.name, required this.address});
}

/// Drives a Honeywell RP4B thermal printer over Bluetooth Classic (SPP).
///
/// The device must be paired in Android Bluetooth Settings before use.
/// Connect flow: scanDevices() → connect(device) → printLabel(...).
class PrinterService {
  BluetoothConnection? _connection;
  String? _connectedName;

  String get connectedName => _connectedName ?? '';

  // ── Permissions ──────────────────────────────────────────────────────────

  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ── Device list ──────────────────────────────────────────────────────────

  /// Returns devices already paired in Android Bluetooth Settings.
  Future<List<PrinterDevice>> scanDevices() async {
    final paired = await FlutterBluetoothSerial.instance.getBondedDevices();
    return paired
        .map((d) => PrinterDevice(
              name: d.name?.isNotEmpty == true ? d.name! : d.address,
              address: d.address,
            ))
        .toList();
  }

  /// Alias kept for compatibility with existing screen code.
  Future<List<PrinterDevice>> pairedPrinters() => scanDevices();

  // ── Connection ───────────────────────────────────────────────────────────

  Future<bool> isConnected() async => _connection?.isConnected ?? false;

  /// Connects to [printer] via Bluetooth Classic SPP.
  Future<void> connect(PrinterDevice printer) async {
    await disconnect();
    _connection = await BluetoothConnection.toAddress(printer.address);
    _connectedName = printer.name;
  }

  Future<void> disconnect() async {
    try {
      await _connection?.finish();
    } catch (_) {}
    _connection = null;
    _connectedName = null;
  }

  // ── Printing ─────────────────────────────────────────────────────────────

  Future<void> _send(String cpcl) async {
    if (_connection == null || !(_connection!.isConnected)) {
      throw Exception('Not connected to a printer.');
    }
    _connection!.output.add(Uint8List.fromList(cpcl.codeUnits));
    await _connection!.output.allSent;
  }

  /// Prints a parcel label via CPCL.
  Future<void> printLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async {
    final cpcl = CpclBuilder.parcelLabel(
      trackingNumber: trackingNumber,
      addressLines: addressLines,
      cartonDisplay: cartonDisplay,
    );
    for (int i = 0; i < copies.clamp(1, 99); i++) {
      await _send(cpcl);
      if (copies > 1 && i < copies - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Sends a minimal CPCL test label to verify the connection.
  Future<void> printTest() async => _send(CpclBuilder.testLabel());

  /// Sends raw bytes — used by print-language test buttons.
  Future<void> printRaw(Uint8List bytes) async {
    if (_connection == null || !(_connection!.isConnected)) {
      throw Exception('Not connected to a printer.');
    }
    _connection!.output.add(bytes);
    await _connection!.output.allSent;
  }
}
