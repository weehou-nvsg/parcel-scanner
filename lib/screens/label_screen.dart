import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/parcel_data.dart';
import '../services/printer_service.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class LabelScreen extends StatefulWidget {
  final ParcelData parcel;
  final SharedPreferences prefs;

  const LabelScreen({super.key, required this.parcel, required this.prefs});

  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  final _printer = PrinterService();
  final _screenshotCtrl = ScreenshotController();
  List<BluetoothDevice> _devices = [];
  bool _loadingDevices = false;
  bool _printing = false;
  String _printerStatus = 'Not connected';
  int _copies = 1;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final saved = widget.prefs.getString('printer_address');
    if (saved != null) {
      setState(() => _printerStatus = 'Connecting...');
      try {
        await _printer.connect(saved);
        setState(() => _printerStatus = 'Connected');
      } catch (_) {
        setState(() => _printerStatus = 'Saved printer unavailable — tap to connect');
      }
    }
  }

  Future<void> _showPrinterPicker() async {
    setState(() => _loadingDevices = true);
    try {
      _devices = await _printer.getPairedDevices();
    } catch (e) {
      _devices = [];
    }
    setState(() => _loadingDevices = false);

    if (!mounted) return;

    if (_devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No paired Bluetooth devices found. Pair your HPRT HM-T3 Pro in Android Bluetooth settings first.'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Select Printer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ..._devices.map((d) => ListTile(
                leading: const Icon(Icons.print),
                title: Text(d.name ?? d.address),
                subtitle: Text(d.address),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _printerStatus = 'Connecting...');
                  try {
                    await _printer.connect(d.address);
                    await widget.prefs.setString('printer_address', d.address);
                    setState(() => _printerStatus = 'Connected: ${d.name ?? d.address}');
                  } catch (e) {
                    setState(() => _printerStatus = 'Connection failed: $e');
                  }
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _print() async {
    if (!_printer.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to printer first')),
      );
      return;
    }
    setState(() {
      _printing = true;
      _printerStatus = 'Printing...';
    });
    try {
      await _printer.printLabel(
        newTrackingNumber: widget.parcel.newTrackingNumber,
        addressLines: widget.parcel.addressLines,
        cartonDisplay: widget.parcel.cartonDisplay,
        copies: _copies,
      );
      setState(() => _printerStatus = 'Printed $_copies label(s) successfully');
    } catch (e) {
      setState(() => _printerStatus = 'Print error: $e');
    } finally {
      setState(() => _printing = false);
    }
  }

  @override
  void dispose() {
    _printer.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parcel = widget.parcel;
    return Scaffold(
      appBar: AppBar(title: const Text('Generated Label')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Label preview card (matches 3cm x 7.5cm ratio ≈ 1:2.5)
            Screenshot(
              controller: _screenshotCtrl,
              child: _buildLabelPreview(parcel),
            ),

            const SizedBox(height: 24),

            // Printer connection card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _printer.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                          color: _printer.isConnected ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_printerStatus,
                              style: TextStyle(
                                color: _printer.isConnected ? Colors.green : Colors.grey[700],
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _loadingDevices
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.bluetooth_searching),
                        label: const Text('Select HPRT Printer'),
                        onPressed: _loadingDevices ? null : _showPrinterPicker,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Copies row
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('Copies:', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                    ),
                    Text('$_copies', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _copies++),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _printing
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.print),
                label: Text(_printing ? 'Printing...' : 'Print Label',
                    style: const TextStyle(fontSize: 18)),
                onPressed: _printing ? null : _print,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelPreview(ParcelData parcel) {
    // Preview proportional to 30mm x 75mm (ratio 1:2.5)
    final w = MediaQuery.of(context).size.width - 32;
    final h = w * 2.5;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(2, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('NEW TRACKING:',
                style: TextStyle(fontSize: 8, color: Colors.grey, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text(
              parcel.newTrackingNumber,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
            const SizedBox(height: 8),

            // QR code centered
            Center(
              child: QrImageView(
                data: parcel.newTrackingNumber,
                version: QrVersions.auto,
                size: w * 0.65,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            const Text('DELIVER TO:',
                style: TextStyle(fontSize: 8, color: Colors.grey, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            ...parcel.addressLines.map((line) => Text(
                  line,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                )),

            const Spacer(),
            const Divider(height: 8, thickness: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('CARTON COUNT:',
                    style: TextStyle(fontSize: 8, color: Colors.grey)),
                Text(
                  parcel.cartonDisplay,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
