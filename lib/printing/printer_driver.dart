import 'dart:typed_data';

/// A paired Bluetooth device.
class PrinterDevice {
  final String name;
  final String address;

  const PrinterDevice({required this.name, required this.address});
}

/// One supported printer model.
///
/// Each model speaks its own language (ZPL, CPCL, proprietary raster, ...) so
/// each gets its own driver. A driver owns its connection and knows how to
/// turn the parcel fields into bytes the printer understands.
///
/// Drivers are created by the registry in `printer_models.dart` and used
/// through the `PrinterService` facade — screens never touch a driver
/// directly.
abstract class PrinterDriver {
  /// Name of the connected device, or '' when disconnected.
  String get connectedName;

  /// Devices already paired in Android Bluetooth Settings.
  Future<List<PrinterDevice>> scanDevices();

  Future<void> connect(PrinterDevice device);

  Future<void> disconnect();

  Future<bool> isConnected();

  /// Prints the parcel label in this printer's native format.
  Future<void> printLabel({
    required String trackingNumber,
    required List<String> addressLines,
    required String cartonDisplay,
    int copies = 1,
  });

  /// Prints a minimal test label to verify the link.
  Future<void> printTest();

  /// Sends raw bytes — used by print-language diagnostics.
  Future<void> printRaw(Uint8List bytes);
}
