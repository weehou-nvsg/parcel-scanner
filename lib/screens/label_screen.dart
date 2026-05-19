import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';  // used by label preview widget
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/parcel_data.dart';
import '../services/printer_service.dart';

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
  List<PrinterDevice> _bleDevices = [];
  bool _scanning = false;
  bool _printing = false;
  String _printerStatus = 'Not connected';
  int _copies = 1;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    // Restore saved protocol preference
    final proto = widget.prefs.getString('print_protocol') ?? 'cpcl';
    _printer.protocol = proto == 'tspl' ? PrintProtocol.tspl : PrintProtocol.cpcl;
  }

  // Shows the print options bottom sheet
  void _showPrintOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Print Options',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bluetooth, color: Colors.blue),
                ),
                title: const Text('Bluetooth Printer'),
                subtitle: Text(_printer.isConnected ? _printer.connectedName : 'Tap to scan for BLE printers'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _showPrinterPicker();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: Colors.red),
                ),
                title: const Text('Save / Print as PDF'),
                subtitle: const Text('Opens system print dialog — save to PDF or print'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _printToPdf();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPrinterPicker() async {
    // Request runtime BLE + location permissions (required on Android 12+)
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth & Location permissions are required to scan for printers.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Check BLE is on
    final bleState = await FlutterBluePlus.adapterState.first;
    if (bleState != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please turn on Bluetooth and try again.')),
      );
      return;
    }

    setState(() { _scanning = true; _printerStatus = 'Scanning for BLE printers...'; });
    try {
      _bleDevices = await _printer.scanBleDevices(seconds: 6);
    } catch (e) {
      _bleDevices = [];
    }
    setState(() => _scanning = false);

    if (!mounted) return;

    if (_bleDevices.isEmpty) {
      setState(() => _printerStatus = 'No BLE devices found');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No BLE printers found nearby. Make sure your HPRT printer is on and in BLE mode.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      const Text('Select BLE Printer',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      // Protocol toggle
                      Row(
                        children: [
                          const Text('CPCL', style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _printer.protocol == PrintProtocol.tspl,
                            onChanged: (v) async {
                              _printer.protocol = v ? PrintProtocol.tspl : PrintProtocol.cpcl;
                              await widget.prefs.setString('print_protocol', v ? 'tspl' : 'cpcl');
                              setBS(() {});
                              setState(() {});
                            },
                          ),
                          const Text('TSPL', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'CPCL = HPRT HM-T3 Pro  |  TSPL = other HPRT/TSC models',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                const Divider(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView(
                    shrinkWrap: true,
                    children: _bleDevices.map((d) {
                      final isConnected = _printer.isConnected && _printer.connectedName == d.name;
                      return ListTile(
                        leading: Icon(
                          isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                          color: isConnected ? Colors.green : Colors.blue,
                        ),
                        title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text('${d.id}  •  ${d.rssi} dBm'),
                        trailing: isConnected
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () async {
                          Navigator.pop(ctx);
                          setState(() => _printerStatus = 'Connecting to ${d.name}...');
                          try {
                            final info = await _printer.connect(d);
                            await widget.prefs.setString('printer_address', d.id);
                            setState(() => _printerStatus = '$info — ${d.name}');
                            if (mounted) _confirmBluetoothPrint();
                          } catch (e) {
                            setState(() => _printerStatus = 'Failed: $e');
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmBluetoothPrint() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Printer connected'),
        content: Text('Print $_copies label(s) now?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not yet')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _printBluetooth();
            },
            child: const Text('Print'),
          ),
        ],
      ),
    );
  }

  Future<void> _printBluetooth() async {
    if (!_printer.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a Bluetooth printer first')),
      );
      return;
    }
    setState(() { _printing = true; _printerStatus = 'Printing...'; });
    try {
      await _printer.printLabel(
        newTrackingNumber: widget.parcel.newTrackingNumber,
        addressLines: widget.parcel.addressLines,
        cartonDisplay: widget.parcel.cartonDisplay,
        copies: _copies,
      );
      setState(() => _printerStatus = 'Printed $_copies label(s)');
    } catch (e) {
      setState(() => _printerStatus = 'Print error: $e');
    } finally {
      setState(() => _printing = false);
    }
  }

  Future<void> _printToPdf() async {
    final parcel = widget.parcel;
    final pdf = pw.Document();

    const labelW = 30.0 * PdfPageFormat.mm;
    const labelH = 75.0 * PdfPageFormat.mm;

    pdf.addPage(pw.Page(
      pageFormat: const PdfPageFormat(labelW, labelH,
          marginAll: 2 * PdfPageFormat.mm),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NEW TRACKING:',
              style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
          pw.SizedBox(height: 1),
          pw.Text(parcel.newTrackingNumber,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: parcel.newTrackingNumber,
              width: 22 * PdfPageFormat.mm,
              height: 22 * PdfPageFormat.mm,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text('DELIVER TO:',
              style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
          pw.SizedBox(height: 1),
          ...parcel.addressLines.map((l) =>
              pw.Text(l, style: pw.TextStyle(fontSize: 6))),
          pw.Spacer(),
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('CARTON COUNT:',
                  style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
              pw.Text(parcel.cartonDisplay,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    ));

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'label_${parcel.newTrackingNumber}',
    );
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
            Screenshot(
              controller: _screenshotCtrl,
              child: _buildLabelPreview(parcel),
            ),
            const SizedBox(height: 24),

            // Bluetooth status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _scanning
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                _printer.isConnected
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth,
                                color: _printer.isConnected ? Colors.green : Colors.grey,
                              ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_printerStatus,
                              style: TextStyle(
                                color: _printer.isConnected ? Colors.green : Colors.grey[700],
                                fontSize: 13,
                              )),
                        ),
                        if (_printer.isConnected)
                          TextButton(
                            onPressed: _printBluetooth,
                            child: const Text('Print now'),
                          ),
                      ],
                    ),
                    if (_printer.isConnected) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Protocol: ${_printer.protocol == PrintProtocol.cpcl ? "CPCL (HPRT HM-T3 Pro)" : "TSPL (other models)"}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Copies row
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Text('Copies:', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                    ),
                    Text('$_copies',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _copies++),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Main print button — opens options sheet
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _printing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.print),
                label: Text(_printing ? 'Printing...' : 'Print / Save',
                    style: const TextStyle(fontSize: 18)),
                onPressed: _printing ? null : _showPrintOptions,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelPreview(ParcelData parcel) {
    final w = MediaQuery.of(context).size.width - 32;
    final h = w * 2.5;
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(2, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('NEW TRACKING:',
                style: TextStyle(fontSize: 8, color: Colors.grey, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text(parcel.newTrackingNumber,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                softWrap: true),
            const SizedBox(height: 8),
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
            ...parcel.addressLines.map((line) => Text(line,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
            const Spacer(),
            const Divider(height: 8, thickness: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('CARTON COUNT:',
                    style: TextStyle(fontSize: 8, color: Colors.grey)),
                Text(parcel.cartonDisplay,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
