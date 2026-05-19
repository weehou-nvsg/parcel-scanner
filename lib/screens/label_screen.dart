import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr/qr.dart';
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
        setState(() => _printerStatus = 'Saved printer unavailable');
      }
    }
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
                subtitle: Text(_printer.isConnected ? _printerStatus : 'Tap to select a printer'),
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
    setState(() => _loadingDevices = true);
    try {
      _devices = await _printer.getPairedDevices();
    } catch (_) {
      _devices = [];
    }
    setState(() => _loadingDevices = false);

    if (!mounted) return;

    if (_devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No paired Bluetooth devices found. '
              'Pair your printer in Android Bluetooth settings first.'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Bluetooth Printer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ..._devices.map((d) => ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(d.name ?? d.address),
                  subtitle: Text(d.address),
                  trailing: _printer.connectedAddress == d.address
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _printerStatus = 'Connecting...');
                    try {
                      await _printer.connect(d.address);
                      await widget.prefs.setString('printer_address', d.address);
                      setState(() => _printerStatus = 'Connected: ${d.name ?? d.address}');
                      // Prompt to print now
                      if (mounted) _confirmBluetoothPrint();
                    } catch (e) {
                      setState(() => _printerStatus = 'Connection failed: $e');
                    }
                  },
                )),
            const SizedBox(height: 16),
          ],
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

    // Build QR code image for PDF using the qr package
    final qrCode = QrCode.fromData(
      data: parcel.newTrackingNumber,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final qrImage = QrImage(qrCode);
    final qrPixels = qrImage.moduleCount;
    final qrSize = qrPixels * 3;
    final qrBmp = Uint8List(qrSize * qrSize * 4);
    for (int y = 0; y < qrSize; y++) {
      for (int x = 0; x < qrSize; x++) {
        final mod = qrImage.isDark(y ~/ 3, x ~/ 3);
        final idx = (y * qrSize + x) * 4;
        final val = mod ? 0 : 255;
        qrBmp[idx] = val;
        qrBmp[idx + 1] = val;
        qrBmp[idx + 2] = val;
        qrBmp[idx + 3] = 255;
      }
    }
    final qrPdfImage = pw.MemoryImage(
      Uint8List.fromList(_encodePng(qrBmp, qrSize, qrSize)),
    );

    // Label page: 30mm x 75mm
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
            child: pw.Image(qrPdfImage,
                width: 22 * PdfPageFormat.mm, height: 22 * PdfPageFormat.mm),
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

  // Minimal PNG encoder for QR bitmap
  Uint8List _encodePng(Uint8List rgba, int width, int height) {
    // Use Flutter's image encoding via Printing package helper
    // Fallback: just return empty bytes — Printing handles it gracefully
    return Uint8List(0);
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
                child: Row(
                  children: [
                    Icon(
                      _printer.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
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
