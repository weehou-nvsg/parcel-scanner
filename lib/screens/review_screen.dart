import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/parcel_data.dart';
import 'label_screen.dart';

class ReviewScreen extends StatefulWidget {
  final ParcelData parcel;
  final String rawText;
  final String imagePath;
  final SharedPreferences prefs;

  const ReviewScreen({
    super.key,
    required this.parcel,
    required this.rawText,
    required this.imagePath,
    required this.prefs,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final TextEditingController _trackingCtrl;
  late final TextEditingController _cartonCurrentCtrl;
  late final TextEditingController _cartonTotalCtrl;
  late final TextEditingController _addr1Ctrl;
  late final TextEditingController _addr2Ctrl;
  late final TextEditingController _addr3Ctrl;
  late final TextEditingController _prefixCtrl;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    final p = widget.parcel;
    _trackingCtrl = TextEditingController(text: p.trackingNumber);
    _cartonCurrentCtrl = TextEditingController(text: p.cartonCurrent);
    _cartonTotalCtrl = TextEditingController(text: p.cartonTotal);
    _addr1Ctrl = TextEditingController(text: p.addressLines.isNotEmpty ? p.addressLines[0] : '');
    _addr2Ctrl = TextEditingController(text: p.addressLines.length > 1 ? p.addressLines[1] : '');
    _addr3Ctrl = TextEditingController(text: p.addressLines.length > 2 ? p.addressLines[2] : '');
    _prefixCtrl = TextEditingController(text: p.prefix);
  }

  @override
  void dispose() {
    for (final c in [_trackingCtrl, _cartonCurrentCtrl, _cartonTotalCtrl,
        _addr1Ctrl, _addr2Ctrl, _addr3Ctrl, _prefixCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  ParcelData _buildParcel() {
    final addr = [_addr1Ctrl.text, _addr2Ctrl.text, _addr3Ctrl.text]
        .where((s) => s.isNotEmpty)
        .toList();
    return ParcelData(
      trackingNumber: _trackingCtrl.text.trim(),
      cartonCurrent: _cartonCurrentCtrl.text.trim(),
      cartonTotal: _cartonTotalCtrl.text.trim(),
      addressLines: addr,
      prefix: _prefixCtrl.text.trim(),
    );
  }

  String get _previewTracking {
    final p = _prefixCtrl.text.trim();
    final t = _trackingCtrl.text.trim();
    final a = _cartonCurrentCtrl.text.trim();
    final b = _cartonTotalCtrl.text.trim();
    return '$p$t$a/$b';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Edit'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            child: Text(_showRaw ? 'Edit' : 'Raw OCR',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _showRaw ? _buildRawView() : _buildEditView(),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildEditView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scanned image thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(widget.imagePath),
              height: 150, width: double.infinity, fit: BoxFit.cover),
        ),
        const SizedBox(height: 16),

        // Preview of generated tracking number
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generated tracking number:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                _previewTracking,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionLabel('Prefix'),
        _field(_prefixCtrl, 'e.g. AU, TRK-', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),

        _sectionLabel('Tracking Number (from label)'),
        _field(_trackingCtrl, 'e.g. 1234567890123456', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),

        _sectionLabel('Carton Count'),
        Row(
          children: [
            Expanded(child: _field(_cartonCurrentCtrl, 'Current (e.g. 15)',
                onChanged: (_) => setState(() {}))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('/', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: _field(_cartonTotalCtrl, 'Total (e.g. 17)',
                onChanged: (_) => setState(() {}))),
          ],
        ),
        const SizedBox(height: 12),

        _sectionLabel('Delivery Address'),
        _field(_addr1Ctrl, 'Line 1 (e.g. 123 Main St)'),
        const SizedBox(height: 8),
        _field(_addr2Ctrl, 'Line 2 (e.g. Suburb)'),
        const SizedBox(height: 8),
        _field(_addr3Ctrl, 'Line 3 (e.g. NSW 2000)'),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildRawView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Raw OCR output:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(widget.rawText, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.label),
            label: const Text('Generate Label', style: TextStyle(fontSize: 16)),
            onPressed: _trackingCtrl.text.isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LabelScreen(
                          parcel: _buildParcel(),
                          prefs: widget.prefs,
                        ),
                      ),
                    );
                  },
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
      );

  Widget _field(TextEditingController ctrl, String hint, {ValueChanged<String>? onChanged}) =>
      TextField(
        controller: ctrl,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}
