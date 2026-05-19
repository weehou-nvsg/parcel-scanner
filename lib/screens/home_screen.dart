import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const HomeScreen({super.key, required this.prefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _prefix = '';

  @override
  void initState() {
    super.initState();
    _prefix = widget.prefs.getString('prefix') ?? '';
  }

  void _refreshPrefix() {
    setState(() {
      _prefix = widget.prefs.getString('prefix') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parcel Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(prefs: widget.prefs),
                ),
              );
              _refreshPrefix();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner, size: 96, color: Color(0xFF1565C0)),
              const SizedBox(height: 24),
              const Text(
                'Parcel Label Scanner',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _prefix.isEmpty
                    ? 'No prefix set — tap Settings to configure'
                    : 'Prefix: $_prefix',
                style: TextStyle(
                  fontSize: 14,
                  color: _prefix.isEmpty ? Colors.orange : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Scan Parcel Label', style: TextStyle(fontSize: 18)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScanScreen(prefs: widget.prefs),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Settings', style: TextStyle(fontSize: 18)),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(prefs: widget.prefs),
                      ),
                    );
                    _refreshPrefix();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
