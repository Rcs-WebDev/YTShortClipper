import 'package:flutter/material.dart';
import '../models/settings_model.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _cookiesCtrl;
  int _minSec = 30;
  int _maxSec = 60;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StorageService.loadSettings();
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _baseUrlCtrl = TextEditingController(text: s.apiBaseUrl);
    _modelCtrl = TextEditingController(text: s.modelName);
    _cookiesCtrl = TextEditingController(text: s.youtubeCookies);
    _minSec = s.minClipSeconds;
    _maxSec = s.maxClipSeconds;
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final s = AppSettings(
      apiKey: _apiKeyCtrl.text.trim(),
      apiBaseUrl: _baseUrlCtrl.text.trim(),
      modelName: _modelCtrl.text.trim(),
      youtubeCookies: _cookiesCtrl.text.trim(),
      minClipSeconds: _minSec,
      maxClipSeconds: _maxSec,
    );
    await StorageService.saveSettings(s);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan berhasil disimpan!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _cookiesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF111118),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF111118),
      appBar: AppBar(
        title: const Text('Pengaturan & AI API'),
        backgroundColor: const Color(0xFF191924),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check, color: Colors.amber),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Konfigurasi AI Highlight & Subtitles',
            style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Mendukung OpenAI, Groq, OpenRouter, DeepSeek, atau Gemini API.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF232336),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.bolt, color: Colors.amber, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Rekomendasi AI Whisper Gratis (Groq):',
                      style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Groq menyediakan Whisper AI 100% GRATIS tanpa kartu kredit & tanpa bayar token. Dapatkan API key gratis di console.groq.com/keys',
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    setState(() {
                      _baseUrlCtrl.text = 'https://api.groq.com/openai/v1';
                      _modelCtrl.text = 'whisper-large-v3';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚡ Preset Groq Whisper diterapkan! Masukkan Groq API key gratis Anda di kotak atas lalu klik Simpan.'),
                        backgroundColor: Color(0xFF191924),
                      ),
                    );
                  },
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('Pasang Preset Groq Whisper Gratis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'AI API Key',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(),
              hintText: 'sk-...',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Base URL API',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(),
              hintText: 'https://api.openai.com/v1',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Model Name',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(),
              hintText: 'gpt-4o-mini',
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'Durasi Target Klip (Detik)',
            style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RangeSlider(
            values: RangeValues(_minSec.toDouble(), _maxSec.toDouble()),
            min: 15,
            max: 120,
            divisions: 21,
            activeColor: Colors.amber,
            labels: RangeLabels('$_minSec detik', '$_maxSec detik'),
            onChanged: (RangeValues v) {
              setState(() {
                _minSec = v.start.round();
                _maxSec = v.end.round();
              });
            },
          ),
          Center(
            child: Text(
              'Target: $_minSec s/d $_maxSec detik',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'YouTube Cookies (Opsional)',
            style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Masukkan teks cookies jika video membutuhkan login atau verifikasi umur.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cookiesCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Cookies.txt Content',
              border: OutlineInputBorder(),
              hintText: '# Netscape HTTP Cookie File...',
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _save,
            child: const Text('SIMPAN PENGATURAN', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
