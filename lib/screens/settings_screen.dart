import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/printer_service.dart';

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsScreen({super.key, required this.prefs});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _geminiCtrl;
  late final TextEditingController _claudeCtrl;
  bool _saved = false;
  bool _obscureGemini = true;
  bool _obscureClaude = true;

  // 'gemini', 'claude', 'ocr'
  late String _selectedAi;
  final _printer = PrinterService();
  bool _scanning = false;
  List<PrinterDevice> _bleDevices = [];

  @override
  void initState() {
    super.initState();
    _prefixCtrl = TextEditingController(text: widget.prefs.getString('prefix') ?? '');
    _geminiCtrl = TextEditingController(text: widget.prefs.getString('gemini_api_key') ?? '');
    _claudeCtrl = TextEditingController(text: widget.prefs.getString('claude_api_key') ?? '');
    _selectedAi = widget.prefs.getString('selected_ai') ?? 'ocr';
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _geminiCtrl.dispose();
    _claudeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.prefs.setString('prefix', _prefixCtrl.text.trim());
    await widget.prefs.setString('gemini_api_key', _geminiCtrl.text.trim());
    await widget.prefs.setString('claude_api_key', _claudeCtrl.text.trim());
    await widget.prefs.setString('selected_ai', _selectedAi);
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  Future<void> _scanAndConnect() async {
    // Request runtime permissions
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth & Location permissions required.')),
      );
      return;
    }

    final bleState = await FlutterBluePlus.adapterState.first;
    if (bleState != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please turn on Bluetooth and try again.')),
      );
      return;
    }

    setState(() => _scanning = true);
    try {
      _bleDevices = await _printer.scanBleDevices(seconds: 6);
    } catch (_) {
      _bleDevices = [];
    }
    setState(() => _scanning = false);

    if (!mounted) return;

    if (_bleDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No BLE printers found. Make sure your printer is on.')),
      );
      return;
    }

    // Show picker
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
              child: Text('Select Printer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                children: _bleDevices.map((d) => ListTile(
                  leading: const Icon(Icons.bluetooth, color: Colors.blue),
                  title: Text(d.name),
                  subtitle: Text('${d.id}  •  ${d.rssi} dBm'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connecting to ${d.name}...')),
                    );
                    try {
                      await _printer.connect(d);
                      await widget.prefs.setString('printer_address', d.id);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Connected to ${d.name}')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to connect: $e')),
                        );
                      }
                    }
                  },
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Prefix ---
            _sectionTitle('Tracking Number Prefix'),
            const Text(
              'Prepended to every tracking number.\n'
              'e.g. prefix "AU" + tracking "123456" + carton "2/5" → "AU1234562/5"',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prefixCtrl,
              decoration: const InputDecoration(
                labelText: 'Prefix',
                hintText: 'e.g. AU, TRK-, SHIP',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),

            // --- AI Engine selector ---
            _sectionTitle('AI Engine for Label Reading'),
            const Text(
              'Choose which AI reads your parcel label to identify the TID and address.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _aiOptionTile(
              value: 'ocr',
              icon: Icons.text_fields,
              label: 'On-device OCR only',
              description: 'Free, works offline. Basic pattern matching.',
            ),
            _aiOptionTile(
              value: 'gemini',
              icon: Icons.auto_awesome,
              label: 'Google Gemini',
              description: 'Free tier available. Best for most labels.',
              keyController: _geminiCtrl,
              obscure: _obscureGemini,
              onToggleObscure: () => setState(() => _obscureGemini = !_obscureGemini),
              hint: 'AIza...',
              helpText: 'Get free key at: aistudio.google.com/app/apikey',
            ),
            _aiOptionTile(
              value: 'claude',
              icon: Icons.psychology,
              label: 'Claude (Anthropic)',
              description: 'Highly accurate. Requires Anthropic API key.',
              keyController: _claudeCtrl,
              obscure: _obscureClaude,
              onToggleObscure: () => setState(() => _obscureClaude = !_obscureClaude),
              hint: 'sk-ant-...',
              helpText: 'Get key at: console.anthropic.com/settings/keys',
            ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),

            // --- Printer ---
            _sectionTitle('Bluetooth Printer'),
            if (widget.prefs.getString('printer_address') != null) ...[
              Text('Saved: ${widget.prefs.getString('printer_address')}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () async {
                  await widget.prefs.remove('printer_address');
                  setState(() {});
                },
                child: const Text('Forget saved printer',
                    style: TextStyle(color: Colors.red)),
              ),
            ] else
              const Text('No printer saved yet.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _scanning
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_scanning ? 'Scanning...' : 'Scan & Connect Printer'),
                onPressed: _scanning ? null : _scanAndConnect,
              ),
            ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(_saved ? 'Saved!' : 'Save Settings'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _aiOptionTile({
    required String value,
    required IconData icon,
    required String label,
    required String description,
    TextEditingController? keyController,
    bool obscure = true,
    VoidCallback? onToggleObscure,
    String? hint,
    String? helpText,
  }) {
    final selected = _selectedAi == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedAi = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? const Color(0xFF1565C0) : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: selected ? const Color(0xFF1565C0).withOpacity(0.05) : Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      color: selected ? const Color(0xFF1565C0) : Colors.grey,
                      size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selected ? const Color(0xFF1565C0) : Colors.black87,
                            )),
                        Text(description,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Radio<String>(
                    value: value,
                    groupValue: _selectedAi,
                    onChanged: (v) => setState(() => _selectedAi = v!),
                    activeColor: const Color(0xFF1565C0),
                  ),
                ],
              ),
              if (selected && keyController != null) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: keyController,
                  obscureText: obscure,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: hint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: onToggleObscure,
                    ),
                  ),
                ),
                if (helpText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(helpText,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                if (keyController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 15),
                        const SizedBox(width: 4),
                        const Text('API key set',
                            style: TextStyle(color: Colors.green, fontSize: 12)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            keyController.clear();
                            setState(() {});
                          },
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0)),
                          child: const Text('Clear',
                              style: TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );
}
