import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import 'clip_editor_screen.dart';
import 'clip_selection_screen.dart';
import 'settings_screen.dart';

enum VideoSourceType {
  youtube,
  gallery,
}

enum ClipModeType {
  autoAi,
  byRequest,
}

class ManualClipItem {
  final TextEditingController startCtrl;
  final TextEditingController endCtrl;

  ManualClipItem({String start = '00:15', String end = '01:00'})
      : startCtrl = TextEditingController(text: start),
        endCtrl = TextEditingController(text: end);

  Duration? get startDuration => parseTimeString(startCtrl.text);
  Duration? get endDuration => parseTimeString(endCtrl.text);

  static Duration? parseTimeString(String text) {
    text = text.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    } else {
      final s = int.tryParse(text);
      if (s != null) return Duration(seconds: s);
    }
    return null;
  }

  void dispose() {
    startCtrl.dispose();
    endCtrl.dispose();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlCtrl = TextEditingController();
  final YouTubeService _ytService = YouTubeService();
  final ImagePicker _picker = ImagePicker();

  VideoSourceType _sourceType = VideoSourceType.youtube;
  ClipModeType _clipMode = ClipModeType.autoAi;

  // Gallery local video state
  File? _pickedGalleryVideo;
  String? _galleryVideoName;
  int _galleryVideoSize = 0;

  // Auto AI Clip Count
  int _clipCount = 3;

  // Manual Clip by Request list
  final List<ManualClipItem> _manualClips = [
    ManualClipItem(start: '00:15', end: '01:00'),
  ];

  bool _isProcessing = false;
  String _processStatus = '';
  double _downloadProgress = 0.0;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _ytService.dispose();
    for (final item in _manualClips) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _urlCtrl.text = data.text!.trim();
      });
    }
  }

  Duration _pickedGalleryDuration = const Duration(minutes: 3);

  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        final file = File(video.path);
        final size = await file.length();
        
        Duration detectedDuration = const Duration(minutes: 3);
        try {
          final tempCtrl = VideoPlayerController.file(file);
          await tempCtrl.initialize();
          detectedDuration = tempCtrl.value.duration;
          await tempCtrl.dispose();
        } catch (_) {}

        setState(() {
          _pickedGalleryVideo = file;
          _galleryVideoName = video.name.isNotEmpty ? video.name : file.path.split(Platform.pathSeparator).last;
          _galleryVideoSize = size;
          _pickedGalleryDuration = detectedDuration;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih video dari galeri: $e')),
      );
    }
  }

  void _addManualClipRow() {
    setState(() {
      final last = _manualClips.lastOrNull;
      String nextStart = '01:05';
      String nextEnd = '01:50';
      if (last != null && last.endDuration != null) {
        final nextStartSec = last.endDuration!.inSeconds + 10;
        final nextEndSec = nextStartSec + 45;
        final m1 = (nextStartSec ~/ 60).toString().padLeft(2, '0');
        final s1 = (nextStartSec % 60).toString().padLeft(2, '0');
        final m2 = (nextEndSec ~/ 60).toString().padLeft(2, '0');
        final s2 = (nextEndSec % 60).toString().padLeft(2, '0');
        nextStart = '$m1:$s1';
        nextEnd = '$m2:$s2';
      }
      _manualClips.add(ManualClipItem(start: nextStart, end: nextEnd));
    });
  }

  void _removeManualClipRow(int index) {
    if (_manualClips.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal harus ada 1 klip')),
      );
      return;
    }
    setState(() {
      final item = _manualClips.removeAt(index);
      item.dispose();
    });
  }

  // ==========================================
  // 🚀 PROCESS & ROUTING
  // ==========================================
  Future<void> _processVideo() async {
    // 1. Validasi Video Source
    if (_sourceType == VideoSourceType.youtube) {
      final url = _urlCtrl.text.trim();
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silakan masukkan link video YouTube')),
        );
        return;
      }
    } else {
      if (_pickedGalleryVideo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silakan pilih video dari galeri HP Anda')),
        );
        return;
      }
    }

    // 2. Validasi Klip by Request jika mode manual
    if (_clipMode == ClipModeType.byRequest) {
      for (int i = 0; i < _manualClips.length; i++) {
        final item = _manualClips[i];
        final start = item.startDuration;
        final end = item.endDuration;
        if (start == null || end == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Klip #${i + 1}: Format menit salah! Gunakan format MM:SS (contoh 01:30)')),
          );
          return;
        }
        if (end <= start) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Klip #${i + 1}: Menit akhir harus lebih besar dari menit awal!')),
          );
          return;
        }
      }
    }

    setState(() {
      _isProcessing = true;
      _downloadProgress = 0.0;
      _processStatus = _sourceType == VideoSourceType.youtube
          ? 'Memuat metadata video YouTube...'
          : 'Mempersiapkan video galeri HP...';
    });

    try {
      File videoFile;
      VideoMetaData meta;
      List<SubtitleLine> captions = [];

      if (_sourceType == VideoSourceType.youtube) {
        final url = _urlCtrl.text.trim();
        meta = await _ytService.getVideoDetails(url);

        setState(() => _processStatus = 'Mengambil transkrip / subtitle...');
        captions = await _ytService.fetchYouTubeCaptions(meta.id);

        setState(() => _processStatus = 'Mengunduh video ke penyimpanan HP...');
        videoFile = await _ytService.downloadVideoStream(
          meta.id,
          onProgress: (p) {
            if (mounted) setState(() => _downloadProgress = p);
          },
        );
      } else {
        // Video dari Galeri HP
        videoFile = _pickedGalleryVideo!;
        meta = VideoMetaData(
          id: 'gallery_${DateTime.now().millisecondsSinceEpoch}',
          title: _galleryVideoName ?? 'Video Galeri HP',
          author: 'Galeri HP',
          duration: _pickedGalleryDuration,
          thumbnailUrl: 'https://images.unsplash.com/photo-1574717024653-61fd2cf4d44d?w=400',
          description: 'Video diunggah dari galeri HP',
        );
      }

      if (!mounted) return;

      // ==========================================
      // ALUR A: AUTO KLIP DENGAN AI -> KE REVIEW KLIP
      // ==========================================
      if (_clipMode == ClipModeType.autoAi) {
        setState(() => _processStatus = 'AI sedang mendeteksi $_clipCount momen klip viral...');
        final settings = await StorageService.loadSettings();
        final clips = await AIService.analyzeAndDetectHighlights(
          videoTitle: meta.title,
          videoDuration: meta.duration,
          captions: captions,
          settings: settings,
          clipCount: _clipCount,
        );

        if (!mounted) return;
        setState(() => _isProcessing = false);

        // Masuk ke Review Clip Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ClipSelectionScreen(
              videoMeta: meta,
              sourceVideoFile: videoFile,
              clips: clips,
            ),
          ),
        );
      } else {
        // ==========================================
        // ALUR B: KLIP BY REQUEST -> LANGSUNG KE EDIT KLIP / REKOMENDASI KLIP AI
        // ==========================================
        setState(() => _processStatus = 'Membuat klip by request...');
        final List<ClipSegment> customClips = [];

        for (int i = 0; i < _manualClips.length; i++) {
          final item = _manualClips[i];
          final start = item.startDuration!;
          final end = item.endDuration!;

          final clipSubs = captions.where((l) {
            return l.endTime > start && l.startTime < end;
          }).toList();

          customClips.add(ClipSegment(
            id: 'manual_clip_${i + 1}',
            title: 'Klip Request #${i + 1} (${item.startCtrl.text} - ${item.endCtrl.text})',
            hook: 'HIGHLIGHT VIRAL PILIHAN! ⚡',
            viralReason: 'Klip dipotong manual sesuai request menit Anda',
            viralityScore: 9.8,
            startTime: start,
            endTime: end,
            subtitles: clipSubs,
          ));
        }

        if (!mounted) return;
        setState(() => _isProcessing = false);

        // Langsung masuk ke Studio Editor (atau Review Klip jika > 1 klip)
        if (customClips.length == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClipEditorScreen(
                sourceVideoFile: videoFile,
                clip: customClips.first,
                totalVideoDuration: meta.duration,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClipSelectionScreen(
                videoMeta: meta,
                sourceVideoFile: videoFile,
                clips: customClips,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          title: const Text('Gagal Memproses Video', style: TextStyle(color: Colors.redAccent)),
          content: Text(e.toString(), style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF191924),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('YT Short Clipper AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Banner
              _buildHeroBanner(),
              const SizedBox(height: 24),

              // ==========================================
              // 1. PILIHAN SUMBER VIDEO (YOUTUBE / GALERI HP)
              // ==========================================
              const Text(
                '1. Pilih Sumber Video:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSourceButton(
                    title: 'Link YouTube',
                    icon: Icons.play_circle_fill,
                    iconColor: Colors.redAccent,
                    isSelected: _sourceType == VideoSourceType.youtube,
                    onTap: () => setState(() => _sourceType = VideoSourceType.youtube),
                  ),
                  const SizedBox(width: 12),
                  _buildSourceButton(
                    title: 'Galeri HP',
                    icon: Icons.video_library_rounded,
                    iconColor: Colors.amber,
                    isSelected: _sourceType == VideoSourceType.gallery,
                    onTap: () => setState(() => _sourceType = VideoSourceType.gallery),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Source Input Body
              if (_sourceType == VideoSourceType.youtube)
                _buildYoutubeInputBox()
              else
                _buildGalleryUploadBox(),

              const SizedBox(height: 24),

              // ==========================================
              // 2. PILIHAN MODE KLIP (AUTO AI / BY REQUEST)
              // ==========================================
              const Text(
                '2. Pilih Metode Klip:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildModeButton(
                    title: 'Auto Klip AI',
                    desc: 'AI otomatis deteksi momen viral',
                    icon: Icons.auto_awesome,
                    isSelected: _clipMode == ClipModeType.autoAi,
                    onTap: () => setState(() => _clipMode = ClipModeType.autoAi),
                  ),
                  const SizedBox(width: 12),
                  _buildModeButton(
                    title: 'Klip by Request',
                    desc: 'Tentukan menit awal & akhir',
                    icon: Icons.content_cut_rounded,
                    isSelected: _clipMode == ClipModeType.byRequest,
                    onTap: () => setState(() => _clipMode = ClipModeType.byRequest),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Mode Specific Options
              if (_clipMode == ClipModeType.autoAi)
                _buildAutoAiClipCountSection()
              else
                _buildManualClipRequestSection(),

              const SizedBox(height: 24),

              // ==========================================
              // 3. ACTION BUTTON / LOADING BAR
              // ==========================================
              if (_isProcessing)
                _buildLoadingCard()
              else
                _buildSubmitButton(),

              const SizedBox(height: 32),

              // Feature Highlights List
              const Text(
                'Fitur Utama Aplikasi Mobile:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 12),
              _buildFeatureTile(
                icon: Icons.movie_filter_rounded,
                title: 'Pre-Render Studio Editor',
                desc: 'Atur trim waktu, layout 9:16, subtitle gaya Hormozi, dan headline banner sebelum dirender.',
              ),
              _buildFeatureTile(
                icon: Icons.subtitles,
                title: 'Karaoke Subtitle & Word Highlight',
                desc: 'Subtitle animasi kata per kata yang menyala saat diucapkan, bebas koreksi teks jika ada typo.',
              ),
              _buildFeatureTile(
                icon: Icons.offline_bolt_rounded,
                title: 'Render 100% On-Device di HP',
                desc: 'Menggunakan engine FFmpeg langsung di Android tanpa perlu sewa server backend.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Hero Banner Widget
  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF24143D), Color(0xFF1B1B26)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '⚡ AUTO CLIPPER 9:16 + PRE-RENDER STUDIO',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ubah Video Panjang Jadi Shorts Viral dari HP!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bisa dari YouTube atau Galeri HP. AI otomatis mendeteksi klip viral atau potong manual by request menit awal & akhir.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // Source Type Selector
  Widget _buildSourceButton({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.amber.withOpacity(0.12) : const Color(0xFF1B1B26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white12,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? Colors.amber : iconColor, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.amber : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // YouTube URL Input Box
  Widget _buildYoutubeInputBox() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Icons.link_rounded, color: Colors.amber, size: 26),
          ),
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'https://youtube.com/watch?v=...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Paste Link',
            onPressed: _pasteFromClipboard,
            icon: const Icon(Icons.paste_rounded, color: Colors.amber),
          ),
        ],
      ),
    );
  }

  // Gallery Upload Box
  Widget _buildGalleryUploadBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: _pickedGalleryVideo == null
          ? Column(
              children: [
                const Icon(Icons.cloud_upload_outlined, color: Colors.amber, size: 36),
                const SizedBox(height: 8),
                const Text(
                  'Upload Video dari Galeri HP',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Format .mp4 / .mov / video rekaman kamera HP',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _pickVideoFromGallery,
                  icon: const Icon(Icons.video_collection, size: 18),
                  label: const Text('Buka Galeri HP', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.amber, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _galleryVideoName ?? 'Video Galeri',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ukuran: ${(_galleryVideoSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _pickVideoFromGallery,
                  child: const Text('Ganti', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }

  // Mode Button (Auto AI vs By Request)
  Widget _buildModeButton({
    required String title,
    required String desc,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2B1D3A) : const Color(0xFF1B1B26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white12,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: isSelected ? Colors.amber : Colors.white60, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.amber : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                maxLines: 2,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Auto AI Clip Count Section
  Widget _buildAutoAiClipCountSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181824),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Jumlah Klip yang Mau Dihasilkan:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              // Stepper
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: Colors.white70, size: 18),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        if (_clipCount > 1) {
                          setState(() => _clipCount--);
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '$_clipCount',
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white70, size: 18),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        if (_clipCount < 10) {
                          setState(() => _clipCount++);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Preset chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [1, 3, 5, 8, 10].map((num) {
              final isSel = _clipCount == num;
              return ChoiceChip(
                label: Text('$num Klip'),
                selected: isSel,
                selectedColor: Colors.amber,
                backgroundColor: const Color(0xFF1B1B26),
                labelStyle: TextStyle(
                  color: isSel ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _clipCount = num);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Manual Clip by Request Section
  Widget _buildManualClipRequestSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181824),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Rentang Waktu Klip (Menit Awal s/d Akhir):',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Format MM:SS', style: TextStyle(color: Colors.amber, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // List of manual clip inputs
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _manualClips.length,
            itemBuilder: (ctx, index) {
              final item = _manualClips[index];
              final start = item.startDuration;
              final end = item.endDuration;
              final valid = start != null && end != null && end > start;
              final durSec = valid ? (end.inSeconds - start.inSeconds) : 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Klip #${index + 1}',
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        if (valid)
                          Text(
                            'Durasi: ${durSec ~/ 60}m ${durSec % 60}s',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        const SizedBox(width: 8),
                        if (_manualClips.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _removeManualClipRow(index),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Menit Awal
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Menit Awal (Start):', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF13131D),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: TextField(
                                  controller: item.startCtrl,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    hintText: '00:30',
                                    hintStyle: TextStyle(color: Colors.white30),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          child: Text('s/d', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                        ),
                        // Menit Akhir
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Sampai Menit (End):', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF13131D),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: TextField(
                                  controller: item.endCtrl,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    hintText: '01:15',
                                    hintStyle: TextStyle(color: Colors.white30),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // Button + (Tambah klip auto di bawahnya)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber,
                side: const BorderSide(color: Colors.amber, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _addManualClipRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah Klip (+)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // Loading Card Widget
  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            color: Colors.amber,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 14),
          Text(
            _processStatus,
            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600),
          ),
          if (_downloadProgress > 0)
            Text(
              'Progress: ${(_downloadProgress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
        ],
      ),
    );
  }

  // Submit Button
  Widget _buildSubmitButton() {
    final label = _clipMode == ClipModeType.autoAi
        ? 'PROSES AUTO KLIP DENGAN AI'
        : 'LANJUT KE EDIT KLIP / REKOMENDASI KLIP';

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
        ),
        onPressed: _processVideo,
        icon: Icon(_clipMode == ClipModeType.autoAi ? Icons.auto_awesome : Icons.arrow_forward_rounded, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildFeatureTile({required IconData icon, required String title, required String desc}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181824),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
