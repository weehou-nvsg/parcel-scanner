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
  final List<String> ocrTokens;

  const ReviewScreen({
    super.key,
    required this.parcel,
    required this.rawText,
    required this.imagePath,
    required this.prefs,
    this.ocrTokens = const [],
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

  // Which field's OCR picker is currently open; null = none
  String? _activePickerField;

  @override
  void initState() {
    super.initState();
    final p = widget.parcel;
    _trackingCtrl    = TextEditingController(text: p.trackingNumber);
    _cartonCurrentCtrl = TextEditingController(text: p.cartonCurrent);
    _cartonTotalCtrl   = TextEditingController(text: p.cartonTotal);
    _addr1Ctrl = TextEditingController(text: p.addressLines.isNotEmpty ? p.addressLines[0] : '');
    _addr2Ctrl = TextEditingController(text: p.addressLines.length > 1  ? p.addressLines[1] : '');
    _addr3Ctrl = TextEditingController(text: p.addressLines.length > 2  ? p.addressLines[2] : '');
    _prefixCtrl = TextEditingController(text: p.prefix);
    // Auto-open tracking picker if OCR ran but couldn't detect a TID
    if (widget.ocrTokens.isNotEmpty && p.trackingNumber.isEmpty) {
      _activePickerField = 'tracking';
    }
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
      cartonCurrent:  _cartonCurrentCtrl.text.trim(),
      cartonTotal:    _cartonTotalCtrl.text.trim(),
      addressLines:   addr,
      prefix:         _prefixCtrl.text.trim(),
    );
  }

  String get _previewTracking => _buildParcel().newTrackingNumber;

  // ── OCR picker helpers ──────────────────────────────────────────────────────

  /// Returns the token list sorted appropriately for the given field.
  /// Tracking / carton fields: numbers first (default sort from OcrService).
  /// Address fields: text-heavy tokens first.
  List<String> _tokensFor(String fieldKey) {
    if (!fieldKey.startsWith('addr')) return widget.ocrTokens;
    return [...widget.ocrTokens]..sort((a, b) {
        final aNum = RegExp(r'^\d+$').hasMatch(a);
        final bNum = RegExp(r'^\d+$').hasMatch(b);
        if (!aNum && bNum) return -1;
        if (aNum && !bNum) return 1;
        return b.length.compareTo(a.length);
      });
  }

  Widget _pickerPanel(String fieldKey, TextEditingController ctrl) {
    final tokens = _tokensFor(fieldKey);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tap a value to use it:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tokens.map((token) {
              final isSelected = ctrl.text == token;
              final isNumeric  = RegExp(r'^\d+$').hasMatch(token);
              return GestureDetector(
                onTap: () => setState(() {
                  ctrl.text = token;
                  _activePickerField = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1565C0)
                        : isNumeric ? Colors.blue.shade50 : Colors.grey.shade100,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF1565C0)
                          : isNumeric ? Colors.blue.shade300 : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    token,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: isNumeric ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// A text field with an optional OCR pick button on the right.
  /// Renders the picker panel inline below the field when active.
  Widget _fieldRow(
    String fieldKey,
    TextEditingController ctrl,
    String hint,
  ) {
    final active = _activePickerField == fieldKey;
    final hasTokens = widget.ocrTokens.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            if (hasTokens)
              SizedBox(
                width: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    active ? Icons.expand_less : Icons.list_alt,
                    size: 18,
                    color: active ? const Color(0xFF1565C0) : Colors.grey,
                  ),
                  tooltip: 'Pick from OCR tokens',
                  onPressed: () => setState(() {
                    _activePickerField = active ? null : fieldKey;
                  }),
                ),
              ),
          ],
        ),
        if (active) _pickerPanel(fieldKey, ctrl),
      ],
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

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

        // Generated tracking number preview
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
              Text(_previewTracking,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Prefix
        _sectionLabel('Prefix'),
        _field(_prefixCtrl, 'e.g. AU, TRK-', onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),

        // Tracking Number
        _sectionLabel('Tracking Number (TID)'),
        _fieldRow('tracking', _trackingCtrl, 'e.g. 1234567890123456'),
        const SizedBox(height: 16),

        // Carton Count — two fields side by side, each with its own picker
        _sectionLabel('Carton Count'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _fieldRow('cartonCurrent', _cartonCurrentCtrl, 'Current (e.g. 3)')),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              child: const Text('/',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: _fieldRow('cartonTotal', _cartonTotalCtrl, 'Total (e.g. 17)')),
          ],
        ),
        const SizedBox(height: 16),

        // Delivery Address — three lines, each with its own picker
        _sectionLabel('Delivery Address'),
        _fieldRow('addr1', _addr1Ctrl, 'Line 1 (e.g. 123 Main St)'),
        const SizedBox(height: 8),
        _fieldRow('addr2', _addr2Ctrl, 'Line 2 (e.g. Suburb)'),
        const SizedBox(height: 8),
        _fieldRow('addr3', _addr3Ctrl, 'Line 3 (e.g. NSW 2000)'),
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
              color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Text(widget.rawText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
      );

  Widget _field(TextEditingController ctrl, String hint,
          {ValueChanged<String>? onChanged}) =>
      TextField(
        controller: ctrl,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}
