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
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _prefixCtrl = TextEditingController(text: widget.prefs.getString('prefix') ?? '');
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.prefs.setString('prefix', _prefixCtrl.text.trim());
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tracking Number Prefix',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'This prefix is prepended to every tracking number.\nExample: if prefix is "AU" and tracking is "1234", '
              'carton 2/5, the result is "AU12342/5".',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prefixCtrl,
              decoration: const InputDecoration(
                labelText: 'Prefix',
                hintText: 'e.g. AU, TRK-, SHIP',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(_saved ? 'Saved!' : 'Save'),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Printer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pair your HPRT HM-T3 Pro in Android Bluetooth settings before connecting here. '
              'The printer connection is managed on the Label screen.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (widget.prefs.getString('printer_address') != null) ...[
              Text(
                'Saved printer: ${widget.prefs.getString('printer_address')}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await widget.prefs.remove('printer_address');
                  setState(() {});
                },
                child: const Text('Forget saved printer', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
