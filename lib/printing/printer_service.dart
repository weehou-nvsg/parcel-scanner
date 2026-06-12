import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_driver.dart';
import 'printer_models.dart';

export 'printer_driver.dart' show PrinterDevice;
export 'printer_models.dart';

/// Facade over the per-model printer drivers (see `printer_models.dart`).
///
/// A singleton: every screen that constructs `PrinterService()` gets the same
/// instance, so a printer connected in Settings is the same connection
/// LabelScreen prints with. The active driver follows the `printer_model`
/// preference; switching models disconnects the old driver.
class PrinterService {
  PrinterService._();
  static final PrinterService _instance = PrinterService._();
  factory PrinterService() => _instance;

  PrinterDriver? _driver;
  String _modelId = '';

  String get connectedName => _driver?.connectedName ?? '';

  // ── Permissions ──────────────────────────────────────────────────────────

  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ── Model selection ──────────────────────────────────────────────────────

  /// Driver for the currently selected `printer_model` pref, swapping (and
  /// disconnecting) if the selection changed since last use.
  Future<PrinterDriver> _activeDriver() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(PrinterModels.prefKey) ?? PrinterModels.defaultId;
    if (_driver == null || id != _modelId) {
      await _driver?.disconnect();
      _modelId = id;
      _driver = PrinterModels.byId(id).createDriver();
    }
    return _driver!;
  }

  /// Persists the model choice and swaps the active driver.
  Future<void> selectModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrinterModels.prefKey, id);
    await _activeDriver();
  }

  // ── Device list ──────────────────────────────────────────────────────────

  /// Returns devices already paired in Android Bluetooth Settings.
  Future<List<PrinterDevice>> scanDevices() async =>
      (await _activeDriver()).scanDevices();

  /// Alias kept for compatibility with existing screen code.
  Future<List<PrinterDevice>> pairedPrinters() => scanDevices();

  // ── Connection ───────────────────────────────────────────────────────────

  Future<bool> isConnected() async => (await _activeDriver()).isConnected();

  Future<void> connect(PrinterDevice printer) async =>
      (await _activeDriver()).connect(printer);

  Future<void> disconnect() async => _driver?.disconnect();

  // ── Printing ─────────────────────────────────────────────────────────────

  /// Prints the parcel label in the selected printer's native format.
  Future<void> printLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  }) async =>
      (await _activeDriver()).printLabel(
        trackingNumber: trackingNumber,
        addressLines: addressLines,
        cartonDisplay: cartonDisplay,
        copies: copies,
      );

  /// Prints a minimal test label to verify the link.
  Future<void> printTest() async => (await _activeDriver()).printTest();

  /// Sends raw bytes — used by print-language test buttons.
  Future<void> printRaw(Uint8List bytes) async =>
      (await _activeDriver()).printRaw(bytes);
}
