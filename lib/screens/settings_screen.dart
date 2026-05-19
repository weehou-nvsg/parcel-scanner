import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsScreen({super.key, required this.prefs});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _geminiCtrl;
  bool _saved = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _prefixCtrl = TextEditingController(text: widget.prefs.getString('prefix') ?? '');
    _geminiCtrl = TextEditingController(text: widget.prefs.getString('gemini_api_key') ?? '');
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _geminiCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.prefs.setString('prefix', _prefixCtrl.text.trim());
    await widget.prefs.setString('gemini_api_key', _geminiCtrl.text.trim());
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
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

            // --- Gemini AI ---
            _sectionTitle('Gemini AI (TID detection)'),
            const Text(
              'Add your free Gemini API key to enable AI-powered label reading. '
              'Without it the app uses basic on-device OCR.\n\n'
              'Get a free key at: aistudio.google.com/app/apikey',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _geminiCtrl,
              obscureText: _obscureKey,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Gemini API Key',
                hintText: 'AIza...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (_geminiCtrl.text.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  const Text('Gemini AI enabled',
                      style: TextStyle(color: Colors.green, fontSize: 13)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _geminiCtrl.clear();
                      setState(() {});
                    },
                    child: const Text('Remove', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),

            // --- Printer ---
            _sectionTitle('Bluetooth Printer'),
            const Text(
              'Pair your printer in Android Bluetooth settings first, '
              'then connect from the Label screen.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (widget.prefs.getString('printer_address') != null) ...[
              Text('Saved printer: ${widget.prefs.getString('printer_address')}',
                  style: const TextStyle(fontSize: 13)),
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

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );
}
