import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/parcel_data.dart';
import 'zpl_builder.dart';

/// A bonded (already-paired) Bluetooth device.
class PrinterDevice {
  final String name;
  final String address;
  const PrinterDevice({required this.name, required this.address});
}

/// Drives the HPRT HM-T3 Pro over Bluetooth-Classic SPP (RFCOMM) via the
/// native `hprt_printer` MethodChannel.
///
/// The native side holds a single, process-wide RFCOMM socket, so a printer
/// connected from any screen is shared by every [PrinterService] instance —
/// use [isConnected] (not the cached [connectedName]) as the source of truth.
class PrinterService {
  static const _channel = MethodChannel('hprt_printer');

  String? _connectedName;

  /// Name of the printer this instance connected to, if any. May be empty
  /// even while [isConnected] is true (e.g. connected from another screen).
  String get connectedName => _connectedName ?? '';

  /// Requests the Android 12+ runtime Bluetooth permissions. Returns true
  /// when all are granted (on Android ≤ 11 these are granted at install).
  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// Bonded Bluetooth devices. The HM-T3 Pro must already be paired in
  /// Android Settings → Bluetooth — this app connects, it does not pair.
  Future<List<PrinterDevice>> pairedPrinters() async {
    final raw =
        await _channel.invokeListMethod<Map<dynamic, dynamic>>('getPairedPrinters') ??
            const [];
    return raw
        .map((m) => PrinterDevice(
              name: (m['name'] as String?) ?? 'Unknown device',
              address: m['address'] as String,
            ))
        .toList();
  }

  /// True when the native RFCOMM socket is currently open.
  Future<bool> isConnected() async =>
      (await _channel.invokeMethod<bool>('isConnected')) ?? false;

  /// Opens an RFCOMM/SPP connection to [printer]. Throws [PlatformException]
  /// on failure (printer off, out of range, not paired).
  Future<void> connect(PrinterDevice printer) async {
    await _channel.invokeMethod<void>('connect', {'address': printer.address});
    _connectedName = printer.name;
  }

  Future<void> disconnect() async {
    await _channel.invokeMethod<void>('disconnect');
    _connectedName = null;
  }

  /// Prints [copies] of the parcel label as ZPL.
  Future<void> printParcelLabel(ParcelData parcel, {int copies = 1}) {
    final label = ZplBuilder.parcelLabel(
      trackingNumber: parcel.newTrackingNumber,
      addressLines: parcel.addressLines,
      cartonDisplay: parcel.cartonDisplay,
    );
    // Each ^XA…^XZ is one physical label — concatenate for multiple copies.
    final job = List.filled(copies.clamp(1, 99), label).join();
    return _printRaw(job);
  }

  /// Sends the minimal ZPL test label — use to verify the link and language.
  Future<void> printTest() => _printRaw(ZplBuilder.minimalTest());

  /// ZPL is sent as UTF-8 bytes (`^CI28` selects UTF-8 on the printer).
  Future<void> _printRaw(String zpl) => _channel.invokeMethod<void>(
        'printBytes',
        {'bytes': Uint8List.fromList(utf8.encode(zpl))},
      );
}
