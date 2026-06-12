import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import '../printer_driver.dart';

/// Base driver for printers that speak over Bluetooth Classic SPP (RFCOMM).
///
/// Owns the connection lifecycle; subclasses implement the print methods and
/// may override [onConnected] for a post-connect handshake.
abstract class SppPrinterDriver implements PrinterDriver {
  BluetoothConnection? _connection;
  String? _connectedName;

  @override
  String get connectedName => _connectedName ?? '';

  @override
  Future<List<PrinterDevice>> scanDevices() async {
    final paired = await FlutterBluetoothSerial.instance.getBondedDevices();
    return paired
        .map((d) => PrinterDevice(
              name: d.name?.isNotEmpty == true ? d.name! : d.address,
              address: d.address,
            ))
        .toList();
  }

  @override
  Future<bool> isConnected() async => _connection?.isConnected ?? false;

  @override
  Future<void> connect(PrinterDevice device) async {
    await disconnect();
    _connection = await BluetoothConnection.toAddress(device.address);
    _connectedName = device.name;
    await onConnected();
  }

  /// Post-connect handshake hook (e.g. Paperang CRC-key registration).
  @protected
  Future<void> onConnected() async {}

  @override
  Future<void> disconnect() async {
    try {
      await _connection?.finish();
    } catch (_) {}
    _connection = null;
    _connectedName = null;
  }

  @protected
  Future<void> sendBytes(Uint8List bytes) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw Exception('Not connected to a printer.');
    }
    conn.output.add(bytes);
    await conn.output.allSent;
  }

  @protected
  Future<void> sendText(String text) =>
      sendBytes(Uint8List.fromList(utf8.encode(text)));

  @override
  Future<void> printRaw(Uint8List bytes) => sendBytes(bytes);
}
