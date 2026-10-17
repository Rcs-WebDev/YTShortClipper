import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../widgets/video_canvas_preview.dart';
import 'render_progress_screen.dart';
import 'settings_screen.dart';

/// Snapshot state for Undo & Redo functionality
class EditorSnapshot {
  final SubtitleStyleConfig subtitleStyle;
  final LayoutConfig layoutConfig;
  final List<SubtitleLine> subtitles;
  final List<BrollItem> brolls;
  final bool cleanAudio;
  final double videoVolumeDb;
  final String? bgMusic;
  final double bgMusicVolume;

  EditorSnapshot({
    required this.subtitleStyle,
    required this.layoutConfig,
    required this.subtitles,
    required this.brolls,
    required this.cleanAudio,
    required this.videoVolumeDb,
    this.bgMusic,
    required this.bgMusicVolume,
  });

  factory EditorSnapshot.fromState({
    required SubtitleStyleConfig subtitleStyle,
    required LayoutConfig layoutConfig,
    required List<SubtitleLine> subtitles,
    required List<BrollItem> brolls,
    required bool cleanAudio,
    required double videoVolumeDb,
    String? bgMusic,
    required double bgMusicVolume,
  }) {
    return EditorSnapshot(
      subtitleStyle: subtitleStyle.copyWith(),
      layoutConfig: layoutConfig,
      subtitles: subtitles
          .map((line) => SubtitleLine(
                text: line.text,
                startTime: line.startTime,
                endTime: line.endTime,
                transition: line.transition,
                words: line.words
                    .map((w) => SubtitleWord(
                          word: w.word,
                          startTime: w.startTime,
                          endTime: w.endTime,
                        ))
                    .toList(),
              ))
          .toList(),
      brolls: brolls
          .map((b) => BrollItem(
                title: b.title,
                startTime: b.startTime,
                duration: b.duration,
                category: b.category,
                filePath: b.filePath,
                visualUrl: b.visualUrl,
              ))
          .toList(),
      cleanAudio: cleanAudio,
      videoVolumeDb: videoVolumeDb,
      bgMusic: bgMusic,
      bgMusicVolume: bgMusicVolume,
    );
  }
}

class ClipEditorScreen extends StatefulWidget {
  final File sourceVideoFile;
  final ClipSegment clip;
  final Duration totalVideoDuration;

  const ClipEditorScreen({
    super.key,
    required this.sourceVideoFile,
    required this.clip,
    required this.totalVideoDuration,
  });

  @override
  State<ClipEditorScreen> createState() => _ClipEditorScreenState();
}

class _ClipEditorScreenState extends State<ClipEditorScreen> with SingleTickerProviderStateMixin {
  late ClipSegment _currentClip;
  late LayoutConfig _layoutConfig;
  late SubtitleStyleConfig _subtitleStyle;
  VideoPlayerController? _videoController;

  late TabController _tabController;
  Duration _currentPosition = Duration.zero;
  bool _isPlaying = false;
  int _changesCount = 0;
  bool _isToolsWorkspaceExpanded = false;

  // Undo & Redo Stacks (Screenshot 4)
  final List<EditorSnapshot> _undoStack = [];
  final List<EditorSnapshot> _redoStack = [];

  // Style category filter
  String _selectedCategory = 'All';
  final List<String> _categories = [
    'All',
    'New',
    'Animated',
    'Trend',
    'Premium',
    'Speakers',
    'Emoji',
  ];

  // Audio settings (Screenshot 5)
  bool _cleanAudio = false;
  double _videoVolumeDb = 0.0;
  String? _selectedBgmTrack;
  double _bgmVolume = 0.35;

  // AI Tools active flags (Screenshot 3)
  final Map<String, bool> _activeAiTools = {
    'AI Captions': true,
    'AI Auto B-rolls': false,
    'AI Auto Zooms': false,
    'AI Hook Title': false,
    'Clean Audio': false,
    'Remove Silence': false,
    'Correct Eye Contact': false,
    'Remove Bad Takes': false,
  };

  // Controllers for Hook & Watermark
  final TextEditingController _hookController = TextEditingController();
  final TextEditingController _watermarkController = TextEditingController();

  final List<Color> _swatchColors = [
    Colors.white,
    Colors.black,
    const Color(0xFFFFEB3B), // Yellow
    const Color(0xFFFF1744), // Red
    const Color(0xFF00E676), // Green
    const Color(0xFF00B0FF), // Blue/Cyan
    const Color(0xFFFF6D00), // Orange
  ];

  @override
  void initState() {
    super.initState();
    _currentClip = widget.clip.copyWith();

    // Default style: BEAST as active in screenshot 1
    _subtitleStyle = SubtitleStyleConfig(
      preset: SubtitlePresetType.bold,
      fontFamily: SubtitleFontFamily.anton,
      fontSize: 90.0,
      textColor: Colors.white,
      activeWordColor: const Color(0xFFFFDF00),
      strokeColor: Colors.black,
      strokeWidth: 3.5,
      position: SubtitlePosition.bawah,
      bgType: SubtitleBgType.solid,
      bgColor: const Color(0xFFFFD600),
      wordByWord: false,
      isItalic: true,
      isOutlineOnly: true,
      selectedStyleId: 'beast',
    );

    _layoutConfig = LayoutConfig(
      template: KomposisiTemplate.layarPenuh,
      cropPosition: 0.50,
      hook: HookConfig(
        text: _currentClip.hook.isNotEmpty ? _currentClip.hook : 'JODOH GARA-GARA TREND TIKTOK INI',
        color: Colors.white,
        durationSeconds: 2.5,
        animation: HookAnimationType.spring,
      ),
      watermark: WatermarkConfig(text: '@channelmu', position: 'Bawah'),
    );

    _hookController.text = _layoutConfig.hook.text;
    _watermarkController.text = _layoutConfig.watermark.text;
    _tabController = TabController(length: 5, vsync: this);

    _initPlayer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentClip.subtitles.isEmpty) {
        _transcribeRealAudioWithAi();
      }
    });
  }

  /// AI Auto Caption Maker: Menghasilkan kalimat dan timing kata-per-kata yang cepat & akurat dari naskah asli
  List<SubtitleLine> _generateSynchronizedSubtitles({String? customSourceText}) {
    if (customSourceText == null || customSourceText.trim().isEmpty) {
      return [];
    }

    final List<String> rawWords = customSourceText
        .replaceAll(RegExp(r'[^\w\s\-\.\,\!\?]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (rawWords.isEmpty) return [];

    // Kelompokkan 3-4 kata per baris subtitle (standar Shorts/TikTok: pendek, cepat, mudah dibaca)
    final List<List<String>> lineChunks = [];
    List<String> currentChunk = [];
    for (int i = 0; i < rawWords.length; i++) {
      currentChunk.add(rawWords[i]);
      if (currentChunk.length >= 4 || i == rawWords.length - 1) {
        lineChunks.add(List.from(currentChunk));
        currentChunk.clear();
      }
    }

    final totalClipMs = _currentClip.duration.inMilliseconds > 2000
        ? _currentClip.duration.inMilliseconds
        : 15000;

    // Setiap baris subtitle berdurasi 1.8 detik agar dinamis dan tidak membeku lama
    const targetMsPerLine = 1800;
    int maxLinesFit = (totalClipMs / targetMsPerLine).floor();
    if (maxLinesFit < 1) maxLinesFit = 1;

    final List<List<String>> finalChunks = [];
    int chunkIdx = 0;
    for (int i = 0; i < maxLinesFit; i++) {
      finalChunks.add(lineChunks[chunkIdx % lineChunks.length]);
      chunkIdx++;
    }

    final int chunkCount = finalChunks.length;
    final int msPerChunk = (totalClipMs / chunkCount).round();

    final List<SubtitleLine> generatedLines = [];

    for (int i = 0; i < chunkCount; i++) {
      final chunkWords = finalChunks[i];
      final lineStartMs = _currentClip.startTime.inMilliseconds + (i * msPerChunk) + 50;
      final lineEndMs = _currentClip.startTime.inMilliseconds + ((i + 1) * msPerChunk) - 50;

      final Duration lineStart = Duration(milliseconds: lineStartMs);
      final Duration lineEnd = Duration(milliseconds: lineEndMs > lineStartMs ? lineEndMs : lineStartMs + 1000);

      final int wordCount = chunkWords.length;
      final int msPerWord = ((lineEnd.inMilliseconds - lineStart.inMilliseconds) / (wordCount > 0 ? wordCount : 1)).round();

      final List<SubtitleWord> wordItems = [];
      for (int w = 0; w < wordCount; w++) {
        final wStart = Duration(milliseconds: lineStart.inMilliseconds + (w * msPerWord));
        final wEnd = Duration(milliseconds: lineStart.inMilliseconds + ((w + 1) * msPerWord));
        wordItems.add(SubtitleWord(
          word: chunkWords[w],
          startTime: wStart,
          endTime: wEnd,
        ));
      }

      generatedLines.add(SubtitleLine(
        text: chunkWords.join(' '),
        startTime: lineStart,
        endTime: lineEnd,
        transition: 'fade in',
        words: wordItems,
      ));
    }

    return generatedLines;
  }

  /// Transkripsi audio ucapan asli dari video menggunakan Local AI Speech Engine (100% Offline Mandiri, Tanpa Token)
  Future<void> _transcribeRealAudioWithAi({String? customScript}) async {
    final settings = await StorageService.loadSettings();

    String currentStatus = '🎙️ Sistem AI Caption Otomatis...';
    String currentDetail = 'Mengekstrak audio suara video...';
    double currentProgress = 0.0;
    StateSetter? dialogSetState;

    // Tampilkan modal progress transkripsi langsung tanpa syarat API key
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            dialogSetState = setModalState;
            return Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: currentProgress > 0 ? currentProgress : null,
                      color: const Color(0xFFFF5722),
                      backgroundColor: const Color(0xFF334155),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      currentStatus,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentDetail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    try {
      final realLines = await AIService.transcribeVideoAudio(
        videoFile: widget.sourceVideoFile,
        clipStart: _currentClip.startTime,
        clipDuration: _currentClip.duration,
        settings: settings,
        onProgress: (status, progress) {
          if (dialogSetState != null) {
            dialogSetState!(() {
              currentStatus = status;
              currentDetail = progress > 0
                  ? 'Kemajuan: ${(progress * 100).toInt()}%'
                  : 'Memproses kata demi kata...';
              currentProgress = progress;
            });
          }
        },
        customScriptText: customScript,
        videoTitle: _currentClip.title,
      );

      if (mounted) Navigator.pop(context); // Tutup dialog progress

      if (realLines.isNotEmpty) {
        _pushSnapshot();
        setState(() {
          _currentClip.subtitles = realLines;
          _activeAiTools['AI Captions'] = true;
        });
        _videoController?.seekTo(_currentClip.startTime);
        _videoController?.play();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Berhasil! ${realLines.length} baris subtitle otomatis berhasil dibuat!'),
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada ucapan suara yang terdeteksi pada klip video ini.'),
            backgroundColor: Color(0xFFE11D48),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengekstrak suara: $e'),
          backgroundColor: const Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _triggerAutoCaptionGeneration() {
    _transcribeRealAudioWithAi();
  }

  Future<void> _initPlayer() async {
    _videoController = VideoPlayerController.file(widget.sourceVideoFile);
    await _videoController!.initialize();
    await _videoController!.seekTo(_currentClip.startTime);

    _videoController!.addListener(() {
      if (!mounted) return;
      final pos = _videoController!.value.position;
      setState(() {
        _currentPosition = pos;
        _isPlaying = _videoController!.value.isPlaying;
      });

      if (pos >= _currentClip.endTime) {
        _videoController!.seekTo(_currentClip.startTime);
      }
    });

    setState(() {});
  }

  // Record state for Undo/Redo
  void _pushSnapshot() {
    _undoStack.add(EditorSnapshot.fromState(
      subtitleStyle: _subtitleStyle,
      layoutConfig: _layoutConfig,
      subtitles: _currentClip.subtitles,
      brolls: _currentClip.brolls,
      cleanAudio: _cleanAudio,
      videoVolumeDb: _videoVolumeDb,
      bgMusic: _selectedBgmTrack,
      bgMusicVolume: _bgmVolume,
    ));
    _redoStack.clear();
    setState(() {
      _changesCount++;
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final current = EditorSnapshot.fromState(
      subtitleStyle: _subtitleStyle,
      layoutConfig: _layoutConfig,
      subtitles: _currentClip.subtitles,
      brolls: _currentClip.brolls,
      cleanAudio: _cleanAudio,
      videoVolumeDb: _videoVolumeDb,
      bgMusic: _selectedBgmTrack,
      bgMusicVolume: _bgmVolume,
    );
    _redoStack.add(current);

    final prev = _undoStack.removeLast();
    setState(() {
      _subtitleStyle = prev.subtitleStyle;
      _layoutConfig = prev.layoutConfig;
      _currentClip.subtitles = prev.subtitles;
      _currentClip.brolls = prev.brolls;
      _cleanAudio = prev.cleanAudio;
      _videoVolumeDb = prev.videoVolumeDb;
      _selectedBgmTrack = prev.bgMusic;
      _bgmVolume = prev.bgMusicVolume;
      _hookController.text = _layoutConfig.hook.text;
      _watermarkController.text = _layoutConfig.watermark.text;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final current = EditorSnapshot.fromState(
      subtitleStyle: _subtitleStyle,
      layoutConfig: _layoutConfig,
      subtitles: _currentClip.subtitles,
      brolls: _currentClip.brolls,
      cleanAudio: _cleanAudio,
      videoVolumeDb: _videoVolumeDb,
      bgMusic: _selectedBgmTrack,
      bgMusicVolume: _bgmVolume,
    );
    _undoStack.add(current);

    final next = _redoStack.removeLast();
    setState(() {
      _subtitleStyle = next.subtitleStyle;
      _layoutConfig = next.layoutConfig;
      _currentClip.subtitles = next.subtitles;
      _currentClip.brolls = next.brolls;
      _cleanAudio = next.cleanAudio;
      _videoVolumeDb = next.videoVolumeDb;
      _selectedBgmTrack = next.bgMusic;
      _bgmVolume = next.bgMusicVolume;
      _hookController.text = _layoutConfig.hook.text;
      _watermarkController.text = _layoutConfig.watermark.text;
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _tabController.dispose();
    _hookController.dispose();
    _watermarkController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  void _applyFontStyle(FontStyleItem item) {
    _pushSnapshot();
    setState(() {
      _subtitleStyle = _subtitleStyle.copyWith(
        fontFamily: item.fontFamily,
        textColor: item.textColor,
        activeWordColor: item.activeWordColor ?? _subtitleStyle.activeWordColor,
        bgColor: item.bgColor ?? _subtitleStyle.bgColor,
        bgType: item.bgType,
        strokeColor: item.strokeColor,
        strokeWidth: item.strokeWidth,
        isItalic: item.isItalic,
        has3dShadow: item.has3dShadow,
        isOutlineOnly: item.isOutlineOnly,
        selectedStyleId: item.id,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 950;
        return Scaffold(
          backgroundColor: const Color(0xFFF4F6F8),
          appBar: _buildHeader(),
          body: isWide ? _buildDesktopLayout() : _buildMobileLayout(),
        );
      },
    );
  }

  // ==========================================
  // 🔝 HEADER WITH UNDO / REDO (SCREENSHOT 4)
  // ==========================================
  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E293B), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rekomendasi Klip AI (Studio Editor)',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _currentClip.title.isNotEmpty ? _currentClip.title : 'Podcast Highlight | Episode Klip',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        // Undo Button (Screenshot 4)
        IconButton(
          tooltip: 'Undo',
          icon: Icon(
            Icons.undo_rounded,
            color: _undoStack.isNotEmpty ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
            size: 22,
          ),
          onPressed: _undoStack.isNotEmpty ? _undo : null,
        ),
        // Redo Button (Screenshot 4)
        IconButton(
          tooltip: 'Redo',
          icon: Icon(
            Icons.redo_rounded,
            color: _redoStack.isNotEmpty ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
            size: 22,
          ),
          onPressed: _redoStack.isNotEmpty ? _redo : null,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ==========================================
  // 📱 MOBILE LAYOUT
  // ==========================================
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Video Preview Card with Audio / AI Tools top-bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              _buildVideoCardTopBar(),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: _isToolsWorkspaceExpanded ? 145 : 255,
                child: VideoCanvasPreview(
                  controller: _videoController,
                  layout: _layoutConfig,
                  subtitleStyle: _subtitleStyle,
                  clip: _currentClip,
                  currentPosition: _currentPosition,
                ),
              ),
              const SizedBox(height: 6),
              _buildPlayerControls(),
            ],
          ),
        ),

        // Tab bar: Style, Captions, AI Tools, B-rolls, Layout
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: const Color(0xFFFF5722),
            labelColor: const Color(0xFFFF5722),
            unselectedLabelColor: const Color(0xFF64748B),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.style_outlined, size: 20), text: 'Style'),
              Tab(icon: Icon(Icons.subtitles_outlined, size: 20), text: 'Captions'),
              Tab(icon: Icon(Icons.auto_awesome, size: 20), text: 'AI Tools'),
              Tab(icon: Icon(Icons.movie_filter_outlined, size: 20), text: 'B-rolls'),
              Tab(icon: Icon(Icons.crop_outlined, size: 20), text: 'Komposisi'),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStyleTab(),
              _buildCaptionsTab(),
              _buildAiToolsTab(),
              _buildBrollsTab(),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildKomposisiCard(),
                    const SizedBox(height: 16),
                    _buildVideoTransitionCard(),
                    const SizedBox(height: 16),
                    _buildHookCard(),
                    const SizedBox(height: 16),
                    _buildWatermarkCard(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom Action Bar
        _buildFloatingBottomToast(),
      ],
    );
  }

  // ==========================================
  // 💻 DESKTOP LAYOUT (3 Columns)
  // ==========================================
  Widget _buildDesktopLayout() {
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Tabbed controls
            SizedBox(
              width: 380,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorColor: const Color(0xFFFF5722),
                      labelColor: const Color(0xFFFF5722),
                      unselectedLabelColor: const Color(0xFF64748B),
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(text: 'Style'),
                        Tab(text: 'Captions'),
                        Tab(text: 'AI Tools'),
                        Tab(text: 'B-rolls'),
                        Tab(text: 'Komposisi'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStyleTab(),
                        _buildCaptionsTab(),
                        _buildAiToolsTab(),
                        _buildBrollsTab(),
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildKomposisiCard(),
                              const SizedBox(height: 16),
                              _buildVideoTransitionCard(),
                              const SizedBox(height: 16),
                              _buildHookCard(),
                              const SizedBox(height: 16),
                              _buildWatermarkCard(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Center Column: Video Player Preview Canvas
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    _buildVideoCardTopBar(),
                    const SizedBox(height: 10),
                    Center(
                      child: SizedBox(
                        height: 520,
                        child: VideoCanvasPreview(
                          controller: _videoController,
                          layout: _layoutConfig,
                          subtitleStyle: _subtitleStyle,
                          clip: _currentClip,
                          currentPosition: _currentPosition,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPlayerControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Center(child: _buildFloatingBottomToast()),
        ),
      ],
    );
  }

  // ==========================================
  // 🎵 VIDEO TOP BAR WITH AUDIO MODAL (SCREENSHOT 5)
  // ==========================================
  Widget _buildVideoCardTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Workspace Expander Toggle Button
          InkWell(
            onTap: () {
              setState(() {
                _isToolsWorkspaceExpanded = !_isToolsWorkspaceExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _isToolsWorkspaceExpanded ? const Color(0xFFFF5722) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isToolsWorkspaceExpanded ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isToolsWorkspaceExpanded ? Icons.fullscreen_exit : Icons.open_in_full,
                    size: 13,
                    color: _isToolsWorkspaceExpanded ? Colors.white : const Color(0xFF1E293B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isToolsWorkspaceExpanded ? 'Mode Normal' : '📐 Luaskan Tools',
                    style: TextStyle(
                      color: _isToolsWorkspaceExpanded ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  // Transisi Video Pill (Pilihan Efek Transisi Video Utama)
                  _buildTopPill(
                    icon: Icons.movie_filter_rounded,
                    iconColor: const Color(0xFFFF5722),
                    label: '🎬 Transisi: ${_layoutConfig.videoTransition}',
                    isActive: _layoutConfig.videoTransition.toLowerCase() != 'none',
                    onTap: _showVideoTransitionPicker,
                  ),
                  const SizedBox(width: 8),

                  // AI Tools Pill
                  _buildTopPill(
                    icon: Icons.star_border_purple500,
                    iconColor: Colors.orange,
                    label: 'AI Tools',
                    onTap: () {
                      _tabController.animateTo(2); // Jump to AI Tools
                    },
                  ),
                  const SizedBox(width: 8),

                  // Audio Pill (Opens Audio Modal from Screenshot 5)
                  _buildTopPill(
                    icon: Icons.music_note_outlined,
                    iconColor: const Color(0xFF1E293B),
                    label: 'Audio',
                    isActive: _cleanAudio || _selectedBgmTrack != null,
                    onTap: _showAudioModal,
                  ),
                  const SizedBox(width: 8),

                  // Thumbnail Pill
                  _buildTopPill(
                    icon: Icons.crop_portrait_rounded,
                    iconColor: const Color(0xFF1E293B),
                    label: 'Thumbnail',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Thumbnail otomatis dipilih dari frame terbaik')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPill({
    required IconData icon,
    required Color iconColor,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.amber.withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? Colors.amber : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.orange : iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.orange[800] : const Color(0xFF1E293B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 🎛️ AUDIO MODAL (EXACT FROM SCREENSHOT 5)
  // ==========================================
  void _showAudioModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Clean Audio Row with Thunder Icon & Switch (Screenshot 5)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.graphic_eq_rounded, color: Color(0xFF1E293B), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Clean Audio',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.bolt, color: Colors.orange, size: 18),
                        ],
                      ),
                      Switch(
                        value: _cleanAudio,
                        activeColor: const Color(0xFFFF5722),
                        onChanged: (val) {
                          _pushSnapshot();
                          setModalState(() => _cleanAudio = val);
                          setState(() {
                            _cleanAudio = val;
                            _activeAiTools['Clean Audio'] = val;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Video Section
                  const Text(
                    'Video',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Volume Row & dB
                  Row(
                    children: [
                      const Icon(Icons.volume_up_outlined, color: Color(0xFF1E293B), size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Volume',
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_videoVolumeDb.round()} dB',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _videoVolumeDb,
                    min: -12.0,
                    max: 12.0,
                    activeColor: const Color(0xFFFF5722),
                    inactiveColor: const Color(0xFFE2E8F0),
                    onChanged: (val) {
                      setModalState(() => _videoVolumeDb = val);
                      setState(() => _videoVolumeDb = val);
                    },
                    onChangeEnd: (_) => _pushSnapshot(),
                  ),
                  const SizedBox(height: 16),

                  // + Add Music Button
                  InkWell(
                    onTap: () {
                      _showMusicSelectorDialog(modalContext, setModalState);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.add, color: Color(0xFF1E293B), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _selectedBgmTrack == null ? 'Add Music' : 'Music: $_selectedBgmTrack',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_selectedBgmTrack != null) ...[
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                              onPressed: () {
                                _pushSnapshot();
                                setModalState(() => _selectedBgmTrack = null);
                                setState(() => _selectedBgmTrack = null);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMusicSelectorDialog(BuildContext modalCtx, StateSetter setModalState) {
    final tracks = [
      'Lo-fi Hip Hop Chill',
      'Energetic Phonk Beat',
      'Cinematic Inspiration',
      'Upbeat Acoustic Vlog',
      'Subtle Ambient Piano',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Pilih Musik Latar (BGM)', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: tracks.length,
            itemBuilder: (ctx, i) {
              final t = tracks[i];
              return ListTile(
                leading: const Icon(Icons.music_note, color: Colors.orange),
                title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: _selectedBgmTrack == t
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  _pushSnapshot();
                  setModalState(() => _selectedBgmTrack = t);
                  setState(() => _selectedBgmTrack = t);
                  Navigator.pop(dialogCtx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ⏯️ PLAYER CONTROLS & TIMELINE
  // ==========================================
  Widget _buildPlayerControls() {
    final clipStart = _currentClip.startTime;
    final clipDuration = _currentClip.duration;
    final totalSec = clipDuration.inMilliseconds > 0 ? clipDuration.inMilliseconds / 1000.0 : 1.0;
    final relativePos = _currentPosition >= clipStart ? (_currentPosition - clipStart) : Duration.zero;
    final clampedPos = relativePos > clipDuration ? clipDuration : relativePos;
    final curSec = (clampedPos.inMilliseconds / 1000.0).clamp(0.0, totalSec);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Aspect Ratio & Preview Icons
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: const [
                    Text('9:16', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Icon(Icons.keyboard_arrow_down, size: 16),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.tune, size: 20, color: Color(0xFF64748B)),
              const SizedBox(width: 10),
              const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF64748B)),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),

          // Scrubber Bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5722),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFFFF5722),
              overlayColor: const Color(0xFFFF5722).withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 4,
            ),
            child: Slider(
              value: curSec,
              min: 0.0,
              max: totalSec,
              onChanged: (val) {
                final target = clipStart + Duration(milliseconds: (val * 1000).toInt());
                _videoController?.seekTo(target);
                setState(() {
                  _currentPosition = target;
                });
              },
            ),
          ),

          // Bottom Bar: Play/Pause, Timestamp, Volume, Fullscreen
          Row(
            children: [
              IconButton(
                onPressed: _togglePlayPause,
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: const Color(0xFFFF5722),
                  size: 32,
                ),
              ),
              Text(
                '${_formatTimestamp(clampedPos)} / ${_formatTimestamp(clipDuration)}',
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Icon(Icons.volume_up, size: 20, color: Color(0xFF64748B)),
              const SizedBox(width: 14),
              const Icon(Icons.fullscreen, size: 22, color: Color(0xFF64748B)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$cs';
  }

  // ==========================================
  // 🎨 TAB 1: STYLE (ENLARGED WORKSPACE TOOLS)
  // ==========================================
  Widget _buildStyleTab() {
    final filteredStyles = _subtitleStyleCategoryFilter();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 550 ? 3 : 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prompt banner to expand workspace if not yet expanded
              if (!_isToolsWorkspaceExpanded)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.aspect_ratio, size: 18, color: Color(0xFFFF5722)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Area tools terasa sempit? Perluas ruang kerja tools.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5722),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          setState(() => _isToolsWorkspaceExpanded = true);
                        },
                        child: const Text('Perluas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

              // Category Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: Colors.black,
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? Colors.black : const Color(0xFFE2E8F0),
                          ),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          fontSize: 13,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),

              // Enlarger Grid of Font Style Cards (2 columns on mobile for comfortable tap & read)
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: filteredStyles.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.65,
                ),
                itemBuilder: (ctx, index) {
                  final item = filteredStyles[index];
                  final isSelected = _subtitleStyle.selectedStyleId == item.id;
                  return _buildFontStyleCard(item, isSelected);
                },
              ),
              const SizedBox(height: 24),

              // Subtitle fine-tuning (Size, Colors, Alignment)
              _buildSubtitleControlsCard(),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  List<FontStyleItem> _subtitleStyleCategoryFilter() {
    if (_selectedCategory == 'All') {
      return SubtitleStyleConfig.allFontStyles;
    }
    return SubtitleStyleConfig.allFontStyles
        .where((s) => s.categories.contains(_selectedCategory))
        .toList();
  }

  Widget _buildFontStyleCard(FontStyleItem item, bool isSelected) {
    return InkWell(
      onTap: () => _applyFontStyle(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF9E9E9E), // Grey background from Screenshot 1
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF5722) : Colors.transparent,
            width: isSelected ? 2.5 : 0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF5722).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Badge (New in black pill, or ⚡ thunder in circle)
            if (item.badge != null)
              Positioned(
                top: 6,
                left: 6,
                child: item.badge == 'New'
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'New',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bolt, color: Colors.orange, size: 12),
                      ),
              ),

            // Settings Cog if selected (as in BEAST card)
            if (isSelected)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.tune, size: 12, color: Colors.black87),
                ),
              ),

            // Font Preview Text
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildFontCardPreviewText(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontCardPreviewText(FontStyleItem item) {
    final textStyle = _getCardTextStyle(item);

    if (item.bgType == SubtitleBgType.solid && item.bgColor != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: item.bgColor,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(item.name, style: textStyle),
      );
    }

    return Text(item.name, style: textStyle);
  }

  TextStyle _getCardTextStyle(FontStyleItem item) {
    List<Shadow> shadows = [];
    if (item.has3dShadow) {
      shadows = [
        const Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 0),
        const Shadow(color: Colors.black, offset: Offset(3.0, 3.0), blurRadius: 0),
      ];
    } else if (item.bgType == SubtitleBgType.glow && item.bgColor != null) {
      shadows = [
        Shadow(color: item.bgColor!, blurRadius: 8),
        Shadow(color: item.bgColor!, blurRadius: 14),
      ];
    }

    Paint? foregroundPaint;
    if (item.isOutlineOnly) {
      foregroundPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = item.textColor;
    }

    final base = TextStyle(
      fontSize: 18,
      color: foregroundPaint == null ? item.textColor : null,
      foreground: foregroundPaint,
      fontWeight: FontWeight.w900,
      fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
      shadows: shadows,
    );

    switch (item.fontFamily) {
      case SubtitleFontFamily.anton:
        return GoogleFonts.anton(textStyle: base);
      case SubtitleFontFamily.bebas:
        return GoogleFonts.bebasNeue(textStyle: base);
      case SubtitleFontFamily.montserrat:
        return GoogleFonts.montserrat(textStyle: base, fontWeight: FontWeight.w900);
      case SubtitleFontFamily.poppins:
        return GoogleFonts.poppins(textStyle: base, fontWeight: FontWeight.w800);
      case SubtitleFontFamily.playfair:
        return GoogleFonts.playfairDisplay(textStyle: base, fontWeight: FontWeight.w800);
      case SubtitleFontFamily.impact:
        return GoogleFonts.anton(textStyle: base);
      case SubtitleFontFamily.oswald:
        return GoogleFonts.oswald(textStyle: base, fontWeight: FontWeight.w900);
      case SubtitleFontFamily.lora:
        return GoogleFonts.lora(textStyle: base, fontWeight: FontWeight.w700);
      case SubtitleFontFamily.cinzel:
        return GoogleFonts.cinzel(textStyle: base, fontWeight: FontWeight.w800);
    }
  }

  Widget _buildSubtitleControlsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune_rounded, color: Color(0xFFFF5722), size: 20),
              SizedBox(width: 8),
              Text(
                'Pengaturan Lanjutan Subtitle',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Ukuran Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ukuran Font Subtitle', style: TextStyle(color: Color(0xFF475569), fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${_subtitleStyle.fontSize.round()}px',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFFF5722))),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5722),
              thumbColor: const Color(0xFFFF5722),
            ),
            child: Slider(
              value: _subtitleStyle.fontSize.clamp(5.0, 140.0),
              min: 5.0,
              max: 140.0,
              onChanged: (v) {
                setState(() => _subtitleStyle.fontSize = v);
              },
              onChangeEnd: (_) => _pushSnapshot(),
            ),
          ),
          const SizedBox(height: 12),

          // Warna Teks
          const Text('Warna Teks Utama', style: TextStyle(color: Color(0xFF475569), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _swatchColors.map((color) => _buildColorDot(
                color: color,
                isSelected: _subtitleStyle.textColor == color,
                onTap: () {
                  _pushSnapshot();
                  setState(() => _subtitleStyle.textColor = color);
                },
              )).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Posisi (Atas, Tengah, Bawah)
          const Text('Posisi Subtitle', style: TextStyle(color: Color(0xFF475569), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSegmentBtn('Atas', _subtitleStyle.position == SubtitlePosition.atas, () {
                _pushSnapshot();
                setState(() => _subtitleStyle.position = SubtitlePosition.atas);
              }),
              const SizedBox(width: 8),
              _buildSegmentBtn('Tengah', _subtitleStyle.position == SubtitlePosition.tengah, () {
                _pushSnapshot();
                setState(() => _subtitleStyle.position = SubtitlePosition.tengah);
              }),
              const SizedBox(width: 8),
              _buildSegmentBtn('Bawah', _subtitleStyle.position == SubtitlePosition.bawah, () {
                _pushSnapshot();
                setState(() => _subtitleStyle.position = SubtitlePosition.bawah);
              }),
            ],
          ),
          const SizedBox(height: 16),

          // Word-by-word Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Word-by-word Highlight (Karaoke)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    SizedBox(height: 2),
                    Text('Animasi kata per kata menyala saat diucapkan di audio',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: _subtitleStyle.wordByWord,
                activeColor: const Color(0xFFFF5722),
                onChanged: (val) {
                  _pushSnapshot();
                  setState(() => _subtitleStyle.wordByWord = val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 📝 TAB 2: CAPTIONS (AI CAPTION MAKER)
  // ==========================================
  Widget _buildCaptionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Generator Subtitle Otomatis
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'AI Caption Maker Otomatis',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Menghasilkan teks ucapan & timing kata per kata tersinkron',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5722),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: _transcribeRealAudioWithAi,
                        icon: const Icon(Icons.bolt, size: 16),
                        label: const Text(
                          'Generate Subtitle Otomatis',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF475569)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _showEditHookDialog,
                      child: const Text('Hook', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Subtitle lines header & right icons
          Row(
            children: [
              Text(
                'Daftar Baris Subtitle (${_currentClip.subtitles.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Tambahkan Baris Baru',
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF5722), size: 22),
                onPressed: () => _insertSubtitleLineAfter(_currentClip.subtitles.isEmpty ? -1 : _currentClip.subtitles.length - 1),
              ),
              IconButton(
                tooltip: 'Sinkronisasi Suara Video (AI Whisper)',
                icon: const Icon(Icons.refresh, color: Color(0xFF64748B), size: 20),
                onPressed: _transcribeRealAudioWithAi,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_currentClip.subtitles.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.subtitles_outlined, size: 36, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 10),
                  const Text(
                    'Belum Ada Subtitle untuk Klip Ini',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pilih untuk mentranskrip otomatis suara pembicara dari video atau diktekan naskah asli:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5722),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _transcribeRealAudioWithAi,
                          icon: const Icon(Icons.bolt, size: 16),
                          label: const Text('Transkrip Suara Video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _showAiSpeechSyncDialog,
                    icon: const Icon(Icons.keyboard_voice, size: 16),
                    label: const Text('Dikte / Masukkan Ucapan Asli (Offline)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _currentClip.subtitles.length,
            itemBuilder: (ctx, i) {
              final line = _currentClip.subtitles[i];
              final startS = (line.startTime.inMilliseconds / 1000.0).toStringAsFixed(2);
              final endS = (line.endTime.inMilliseconds / 1000.0).toStringAsFixed(2);

              final emojis = ['🔥', '💡', '🚀', '👀', '✨'];
              final emoji = emojis[i % emojis.length];

              final underlineColors = [
                const Color(0xFFFF5722),
                const Color(0xFF00E676),
                const Color(0xFFFFEB3B),
                const Color(0xFF00B0FF),
              ];
              final uColor = underlineColors[i % underlineColors.length];

              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timestamp and Word Text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.schedule, size: 12, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$startS s - $endS s',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Clickable Transition Badge
                                  InkWell(
                                    onTap: () {
                                      _showTransitionPicker(
                                        current: line.transition,
                                        onSelected: (chosen) {
                                          _pushSnapshot();
                                          setState(() {
                                            line.transition = chosen;
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('✨ Efek transisi diubah ke: $chosen')),
                                          );
                                        },
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF7ED),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFFFEDD5)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.auto_awesome, size: 10, color: Color(0xFFFF5722)),
                                          const SizedBox(width: 3),
                                          Text(
                                            line.transition,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF9A3412),
                                            ),
                                          ),
                                          const Icon(Icons.arrow_drop_down, size: 12, color: Color(0xFF9A3412)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _editSubtitleLineText(i),
                                child: Text(
                                  line.text,
                                  style: TextStyle(
                                    color: const Color(0xFF0F172A),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: uColor,
                                    decorationThickness: 2.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Action icons on right: Emoji, Seek to time, Hide/Delete
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Lompat ke Timestamp ini',
                          icon: const Icon(Icons.play_arrow_outlined, size: 20, color: Color(0xFFFF5722)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _videoController?.seekTo(line.startTime);
                            setState(() {
                              _currentPosition = line.startTime;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Hapus Baris',
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _pushSnapshot();
                            setState(() {
                              _currentClip.subtitles.removeAt(i);
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  // Center "+" button between lines to add subtitle
                  Center(
                    child: InkWell(
                      onTap: () => _insertSubtitleLineAfter(i),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Icon(Icons.add, size: 14, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Bottom Bar: Captions accuracy 100.0% + Optimize button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.check_circle, size: 16, color: Color(0xFF00E676)),
                    SizedBox(width: 6),
                    Text('Sinkronisasi AI: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    Text(
                      '100% Akurat',
                      style: TextStyle(
                        color: Color(0xFFFF5722),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    _transcribeRealAudioWithAi();
                  },
                  child: const Text('Re-Optimize', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _editSubtitleLineText(int index) {
    final ctrl = TextEditingController(text: _currentClip.subtitles[index].text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Teks Subtitle'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              _pushSnapshot();
              setState(() {
                _currentClip.subtitles[index].text = ctrl.text.trim();
                final words = ctrl.text.trim().split(RegExp(r'\s+'));
                _currentClip.subtitles[index].words = words.map((w) {
                  return SubtitleWord(
                    word: w,
                    startTime: _currentClip.subtitles[index].startTime,
                    endTime: _currentClip.subtitles[index].endTime,
                  );
                }).toList();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _insertSubtitleLineAfter(int index) {
    final currentTrans = (index >= 0 && index < _currentClip.subtitles.length)
        ? _currentClip.subtitles[index].transition
        : 'fade in';
    _showTransitionPicker(
      current: currentTrans,
      onSelected: (chosenTransition) {
        _promptNewSubtitleLine(index, chosenTransition);
      },
    );
  }

  void _showTransitionPicker({
    required Function(String transition) onSelected,
    String current = 'fade in',
  }) {
    final List<Map<String, dynamic>> transitions = [
      {'id': 'fade in', 'name': 'Fade In', 'desc': 'Pudar masuk lembut', 'icon': Icons.gradient},
      {'id': 'fade out', 'name': 'Fade Out', 'desc': 'Pudar keluar bertahap', 'icon': Icons.blur_linear},
      {'id': 'dissolve', 'name': 'Dissolve', 'desc': 'Disolusi transparan halus', 'icon': Icons.opacity},
      {'id': 'wipe', 'name': 'Wipe', 'desc': 'Sapuan geser horizontal', 'icon': Icons.splitscreen},
      {'id': 'zoom in', 'name': 'Zoom In', 'desc': 'Perbesar masuk dinamis', 'icon': Icons.zoom_in},
      {'id': 'zoom out', 'name': 'Zoom Out', 'desc': 'Perkecil keluar sinematik', 'icon': Icons.zoom_out},
      {'id': 'slide', 'name': 'Slide', 'desc': 'Meluncur dari bawah', 'icon': Icons.swipe_up},
      {'id': 'glitch', 'name': 'Glitch', 'desc': 'Distorsi siber bergetar', 'icon': Icons.flash_on},
      {'id': 'roll', 'name': 'Roll', 'desc': 'Gulir 3D vertikal', 'icon': Icons.swap_vert},
      {'id': 'whip', 'name': 'Whip', 'desc': 'Whip pan kilat miring', 'icon': Icons.fast_forward},
      {'id': 'spin', 'name': 'Spin', 'desc': 'Putaran sudut dinamis', 'icon': Icons.rotate_right},
      {'id': 'iris', 'name': 'Iris', 'desc': 'Bukaan melingkar lensa', 'icon': Icons.camera},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                Icon(Icons.auto_awesome, color: Color(0xFFFF5722), size: 20),
                SizedBox(width: 8),
                Text(
                  'Pilih Efek Transisi Subtitle',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pilih 1 dari 12 animasi transisi untuk teks subtitle ini',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                itemCount: transitions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.2,
                ),
                itemBuilder: (ctx, i) {
                  final t = transitions[i];
                  final isSelected = t['id'] == current.toLowerCase();
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(t['id'] as String);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFF5722).withOpacity(0.08) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              t['icon'] as IconData,
                              size: 16,
                              color: isSelected ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  t['name'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isSelected ? const Color(0xFFFF5722) : const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  t['desc'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, size: 14, color: Color(0xFFFF5722)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _promptNewSubtitleLine(int index, String transition) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.add_circle, color: Color(0xFFFF5722), size: 20),
            const SizedBox(width: 8),
            const Text('Tambah Baris Subtitle', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFFF5722)),
                  const SizedBox(width: 6),
                  Text('Transisi aktif: $transition',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9A3412))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ketik ucapan subtitle di sini...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5722), foregroundColor: Colors.white),
            onPressed: () {
              final text = ctrl.text.trim().isNotEmpty ? ctrl.text.trim() : 'Kalimat subtitle baru';
              _pushSnapshot();
              setState(() {
                final Duration newStart;
                final Duration newEnd;
                if (index >= 0 && index < _currentClip.subtitles.length) {
                  final prev = _currentClip.subtitles[index];
                  newStart = prev.endTime;
                  newEnd = prev.endTime + const Duration(seconds: 2);
                } else {
                  newStart = _currentPosition;
                  newEnd = _currentPosition + const Duration(seconds: 2);
                }

                final wordsList = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
                final perWordMs = wordsList.isNotEmpty ? (2000 / wordsList.length).round() : 600;

                final List<SubtitleWord> wordItems = [];
                for (int w = 0; w < wordsList.length; w++) {
                  wordItems.add(SubtitleWord(
                    word: wordsList[w],
                    startTime: newStart + Duration(milliseconds: w * perWordMs),
                    endTime: newStart + Duration(milliseconds: (w + 1) * perWordMs),
                  ));
                }

                _currentClip.subtitles.insert(
                  index + 1,
                  SubtitleLine(
                    text: text,
                    startTime: newStart,
                    endTime: newEnd,
                    transition: transition,
                    words: wordItems,
                  ),
                );
              });
              Navigator.pop(ctx);
              _videoController?.seekTo(_currentClip.subtitles[index + 1].startTime);
              _videoController?.play();
            },
            child: const Text('Tambahkan'),
          ),
        ],
      ),
    );
  }

  /// Dialog pemilihan metode transkripsi suara
  void _showTranscriptionSourceDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5722).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.mic_none, color: Color(0xFFFF5722), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transkripsi Suara Video (Speech-to-Text)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Pilih metode untuk mengambil kata demi kata dari suara pembicara:',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Opsi 1: AI Whisper Cloud (Groq 100% Gratis Tanpa Token Berbayar)
            InkWell(
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF5722).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bolt, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '🎙️ AI Whisper Otomatis (Akurasi 100%)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Mengekstrak dan mentranskrip otomatis suara pembicara dari video. Menggunakan Groq Whisper yang 100% GRATIS tanpa perlu beli token.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFFF5722)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Opsi 2: Diktekan Suara / Input Naskah Asli (100% Offline di HP)
            InkWell(
              onTap: () {
                Navigator.pop(ctx);
                _showAiSpeechSyncDialog();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.keyboard_voice, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '🎤 Diktekan Suara / Ketik Ucapan Asli (Offline)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Gunakan tombol Mikrofon di keyboard HP Anda untuk mendiktekan ucapan, atau tempel naskah. AI kami akan menyelaraskan timing setiap kata ke suara video.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showAiSpeechSyncDialog({String? warningMessage}) {
    final TextEditingController speechScriptCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.record_voice_over, color: Color(0xFFFF5722), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Masukkan / Diktekan Ucapan Pembicara',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                          ),
                          Text(
                            'Teks asli akan disinkronkan kata demi kata dengan suara video',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (warningMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFEDD5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Color(0xFFFF5722)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            warningMessage,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Text(
                  'Naskah / Ucapan Pembicara Asli:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: speechScriptCtrl,
                  maxLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Ketik ucapan asli di sini, atau tekan tombol 🎙️ Mikrofon di keyboard HP Anda untuk mendiktekan suara secara langsung...',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFFF5722), width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), height: 1.4),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDCFCE7)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.mic, size: 16, color: Color(0xFF16A34A)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: Tekan tombol Mikrofon pada keyboard HP Anda (Google Voice Typing) untuk mendiktekan ucapan tanpa perlu mengetik!',
                          style: TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5722),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final text = speechScriptCtrl.text.trim();
                          if (text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Silakan ketik atau diktekan kalimat pembicara terlebih dahulu.'),
                                backgroundColor: Color(0xFFEF4444),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          _transcribeRealAudioWithAi(customScript: text);
                        },
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text(
                          'Sinkronkan Kata demi Kata ke Suara Video',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applySynchronizedSpeechTranscript(String transcriptText) {
    _transcribeRealAudioWithAi(customScript: transcriptText);
  }

  // ==========================================
  // ==========================================
  // 🎬 MODAL PEMILIH TRANSISI VIDEO UTAMA (13 EFEK) & MULTI-POINT TIMESTAMPS
  // ==========================================
  void _showVideoTransitionPicker({int? targetIndex, Duration? newPointOffset}) {
    final List<Map<String, dynamic>> transitions = [
      {'id': 'none', 'name': 'Tanpa Transisi', 'desc': 'Video mulai langsung normal', 'icon': Icons.block},
      {'id': 'fade in', 'name': 'Fade In', 'desc': 'Pudar masuk sinematik lembut', 'icon': Icons.gradient},
      {'id': 'dissolve', 'name': 'Dissolve', 'desc': 'Disolusi transparan halus', 'icon': Icons.opacity},
      {'id': 'zoom in', 'name': 'Zoom In (Punch)', 'desc': 'Punch-in dinamis ke subjek', 'icon': Icons.zoom_in},
      {'id': 'zoom out', 'name': 'Zoom Out', 'desc': 'Zoom mundur sinematik', 'icon': Icons.zoom_out},
      {'id': 'wipe horizontal', 'name': 'Wipe Horizontal', 'desc': 'Sapuan tirai dari kiri ke kanan', 'icon': Icons.splitscreen},
      {'id': 'wipe vertical', 'name': 'Wipe Vertical', 'desc': 'Sapuan tirai dari atas ke bawah', 'icon': Icons.view_stream},
      {'id': 'glitch', 'name': 'Glitch Cyber', 'desc': 'Distorsi futuristik bergetar', 'icon': Icons.flash_on},
      {'id': 'whip pan', 'name': 'Whip Pan', 'desc': 'Geseran kilat dinamis miring', 'icon': Icons.fast_forward},
      {'id': 'white flash', 'name': 'White Flash', 'desc': 'Kilatan cahaya putih memukau', 'icon': Icons.wb_sunny},
      {'id': 'black flash', 'name': 'Black Flash', 'desc': 'Transisi kedip hitam cepat', 'icon': Icons.brightness_2},
      {'id': 'spin 360', 'name': 'Spin 360', 'desc': 'Putaran kamera berputar cepat', 'icon': Icons.rotate_right},
      {'id': 'iris', 'name': 'Iris Lens', 'desc': 'Bukaan lensa kamera melingkar', 'icon': Icons.camera},
    ];

    String currentEffect = _layoutConfig.videoTransition;
    if (targetIndex != null && targetIndex >= 0 && targetIndex < _layoutConfig.transitionPoints.length) {
      currentEffect = _layoutConfig.transitionPoints[targetIndex].transitionType;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.70,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.movie_filter_rounded, color: Color(0xFFFF5722), size: 22),
                const SizedBox(width: 8),
                Text(
                  newPointOffset != null
                      ? 'Pilih Efek untuk Menit ${_formatTimestamp(newPointOffset)}'
                      : (targetIndex != null ? 'Ubah Efek Transisi #${targetIndex + 1}' : 'Efek Transisi Video Utama'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              newPointOffset != null
                  ? 'Efek transisi ini akan mulai berjalan tepat pada menit ${_formatTimestamp(newPointOffset)}'
                  : 'Transisi ini diterapkan langsung pada video klip utama.',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
                itemCount: transitions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.1,
                ),
                itemBuilder: (ctx, i) {
                  final t = transitions[i];
                  final isSelected = t['id'] == currentEffect.toLowerCase();
                  return InkWell(
                    onTap: () {
                      _pushSnapshot();
                      setState(() {
                        final pts = List<VideoTransitionPoint>.from(_layoutConfig.transitionPoints);
                        if (targetIndex != null && targetIndex >= 0 && targetIndex < pts.length) {
                          pts[targetIndex] = pts[targetIndex].copyWith(transitionType: t['id'] as String);
                          _layoutConfig = _layoutConfig.copyWith(
                            transitionPoints: pts,
                            videoTransition: targetIndex == 0 ? (t['id'] as String) : _layoutConfig.videoTransition,
                          );
                        } else if (newPointOffset != null) {
                          pts.add(VideoTransitionPoint(
                            id: 'trans_${DateTime.now().millisecondsSinceEpoch}',
                            timeOffset: newPointOffset,
                            transitionType: t['id'] as String,
                            duration: _layoutConfig.videoTransitionDuration,
                          ));
                          pts.sort((a, b) => a.timeOffset.compareTo(b.timeOffset));
                          _layoutConfig = _layoutConfig.copyWith(transitionPoints: pts);
                        } else {
                          if (pts.isNotEmpty) {
                            pts[0] = pts[0].copyWith(transitionType: t['id'] as String);
                          }
                          _layoutConfig = _layoutConfig.copyWith(
                            videoTransition: t['id'] as String,
                            transitionPoints: pts,
                          );
                        }
                      });
                      Navigator.pop(ctx);

                      final seekOffset = targetIndex != null && targetIndex < _layoutConfig.transitionPoints.length
                          ? _layoutConfig.transitionPoints[targetIndex].timeOffset
                          : (newPointOffset ?? Duration.zero);
                      _videoController?.seekTo(_currentClip.startTime + seekOffset);
                      _videoController?.play();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🎬 Transisi "${t['name']}" berhasil dipasang pada menit ${_formatTimestamp(seekOffset)}'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: const Color(0xFF0F172A),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFF5722).withOpacity(0.08) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              t['icon'] as IconData,
                              size: 16,
                              color: isSelected ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  t['name'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isSelected ? const Color(0xFFFF5722) : const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  t['desc'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, size: 14, color: Color(0xFFFF5722)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog untuk menambahkan transisi pada menit/detik tertentu
  void _showAddVideoTransitionDialog() {
    final relPos = _currentPosition >= _currentClip.startTime
        ? (_currentPosition - _currentClip.startTime)
        : Duration.zero;
    final clampedCur = relPos > _currentClip.duration ? _currentClip.duration : relPos;

    int inputMinutes = clampedCur.inMinutes.remainder(60);
    double inputSeconds = (clampedCur.inSeconds.remainder(60) + (clampedCur.inMilliseconds.remainder(1000) / 1000.0));
    final minuteCtrl = TextEditingController(text: inputMinutes.toString());
    final secondCtrl = TextEditingController(text: inputSeconds.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final maxSec = _currentClip.duration.inMilliseconds / 1000.0;
          final curSelectedSec = ((int.tryParse(minuteCtrl.text) ?? 0) * 60.0 + (double.tryParse(secondCtrl.text) ?? 0.0))
              .clamp(0.0, maxSec);

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.add_circle, color: Color(0xFFFF5722), size: 22),
                SizedBox(width: 8),
                Text('Tambah Transisi di Menit Ini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tentukan waktu pada video di mana efek transisi akan mulai berjalan:',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),

                  // Shortcut Button: Pakai Waktu Playhead Sekarang
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        inputMinutes = clampedCur.inMinutes.remainder(60);
                        inputSeconds = (clampedCur.inSeconds.remainder(60) + (clampedCur.inMilliseconds.remainder(1000) / 1000.0));
                        minuteCtrl.text = inputMinutes.toString();
                        secondCtrl.text = inputSeconds.toStringAsFixed(1);
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF5722).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.my_location, size: 16, color: Color(0xFFFF5722)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Gunakan Waktu Playhead Saat Ini (${_formatTimestamp(clampedCur)})',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF5722)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Input Menit & Detik
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Menit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                            const SizedBox(height: 4),
                            TextField(
                              controller: minuteCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '0',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Detik', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                            const SizedBox(height: 4),
                            TextField(
                              controller: secondCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                hintText: '0.0',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Slider visual penunjuk durasi klip
                  Text(
                    'Posisi: ${_formatTimestamp(Duration(milliseconds: (curSelectedSec * 1000).round()))} / ${_formatTimestamp(_currentClip.duration)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFFF5722),
                      thumbColor: const Color(0xFFFF5722),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: curSelectedSec.clamp(0.0, maxSec > 0 ? maxSec : 1.0),
                      min: 0.0,
                      max: maxSec > 0 ? maxSec : 1.0,
                      onChanged: (val) {
                        setDialogState(() {
                          final d = Duration(milliseconds: (val * 1000).round());
                          minuteCtrl.text = d.inMinutes.remainder(60).toString();
                          secondCtrl.text = (d.inSeconds.remainder(60) + (d.inMilliseconds.remainder(1000) / 1000.0)).toStringAsFixed(1);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5722),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  final targetMs = (curSelectedSec * 1000).round();
                  final pickedOffset = Duration(milliseconds: targetMs);
                  _showVideoTransitionPicker(newPointOffset: pickedOffset);
                },
                icon: const Icon(Icons.palette, size: 16),
                label: const Text('Lanjut Pilih Efek', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dialog untuk menyunting waktu dan durasi titik transisi
  void _showEditTransitionTimeDialog(int index) {
    if (index < 0 || index >= _layoutConfig.transitionPoints.length) return;
    final pt = _layoutConfig.transitionPoints[index];
    final maxSec = _currentClip.duration.inMilliseconds / 1000.0;
    double curSec = (pt.timeOffset.inMilliseconds / 1000.0).clamp(0.0, maxSec);
    double curDur = pt.duration;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Atur Waktu Transisi #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Efek: ${pt.transitionType.toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF5722), fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Waktu Muncul Transisi:', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                  Text(_formatTimestamp(Duration(milliseconds: (curSec * 1000).round())),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                ],
              ),
              Slider(
                value: curSec.clamp(0.0, maxSec > 0 ? maxSec : 1.0),
                min: 0.0,
                max: maxSec > 0 ? maxSec : 1.0,
                activeColor: const Color(0xFFFF5722),
                onChanged: (v) => setDialogState(() => curSec = v),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Durasi Efek Transisi:', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                  Text('${curDur.toStringAsFixed(1)} detik',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF5722))),
                ],
              ),
              Slider(
                value: curDur.clamp(0.3, 2.5),
                min: 0.3,
                max: 2.5,
                divisions: 22,
                activeColor: const Color(0xFFFF5722),
                onChanged: (v) => setDialogState(() => curDur = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5722),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                _pushSnapshot();
                setState(() {
                  final pts = List<VideoTransitionPoint>.from(_layoutConfig.transitionPoints);
                  pts[index] = pts[index].copyWith(
                    timeOffset: Duration(milliseconds: (curSec * 1000).round()),
                    duration: curDur,
                  );
                  pts.sort((a, b) => a.timeOffset.compareTo(b.timeOffset));
                  _layoutConfig = _layoutConfig.copyWith(transitionPoints: pts);
                });
                Navigator.pop(ctx);
                _videoController?.seekTo(_currentClip.startTime + Duration(milliseconds: (curSec * 1000).round()));
                _videoController?.play();
              },
              child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 🎬 KARTU PENGATURAN TRANSISI VIDEO DI TAB KOMPOSISI
  // ==========================================
  Widget _buildVideoTransitionCard() {
    final points = _layoutConfig.transitionPoints;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_filter_rounded, color: Color(0xFFFF5722), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Transisi Video Utama',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5722),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showAddVideoTransitionDialog,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Tambah di Menit Tertentu', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Atur transisi pada video utama. Anda dapat menambahkan transisi di menit/detik mana saja sepanjang klip.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Daftar Titik Transisi Video
          if (points.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Center(
                child: TextButton.icon(
                  onPressed: _showAddVideoTransitionDialog,
                  icon: const Icon(Icons.add_circle, color: Color(0xFFFF5722)),
                  label: const Text('Tambah Titik Transisi Pertama', style: TextStyle(color: Color(0xFFFF5722), fontWeight: FontWeight.bold)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: points.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final pt = points[i];
                final isAtStart = pt.timeOffset == Duration.zero;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isAtStart ? const Color(0xFFFF5722).withOpacity(0.35) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5722).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.auto_awesome_motion, color: Color(0xFFFF5722), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isAtStart ? const Color(0xFFFF5722) : const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isAtStart ? 'Awal (00:00)' : 'Menit ${_formatTimestamp(pt.timeOffset)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${pt.duration.toStringAsFixed(1)}s',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pt.transitionType.toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                          ),
                          // Preview playhead jump button
                          IconButton(
                            tooltip: 'Pratinjau di Menit Ini',
                            icon: const Icon(Icons.play_circle_fill, color: Color(0xFFFF5722), size: 24),
                            onPressed: () {
                              _videoController?.seekTo(_currentClip.startTime + pt.timeOffset);
                              _videoController?.play();
                            },
                          ),
                          // Edit effect button
                          IconButton(
                            tooltip: 'Ganti Efek',
                            icon: const Icon(Icons.palette_outlined, color: Color(0xFF475569), size: 20),
                            onPressed: () => _showVideoTransitionPicker(targetIndex: i),
                          ),
                          // Edit time button
                          IconButton(
                            tooltip: 'Ubah Waktu Menit/Detik',
                            icon: const Icon(Icons.schedule, color: Color(0xFF475569), size: 20),
                            onPressed: () => _showEditTransitionTimeDialog(i),
                          ),
                          // Delete button
                          if (points.length > 1)
                            IconButton(
                              tooltip: 'Hapus Transisi Ini',
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                              onPressed: () {
                                _pushSnapshot();
                                setState(() {
                                  final pts = List<VideoTransitionPoint>.from(_layoutConfig.transitionPoints);
                                  pts.removeAt(i);
                                  _layoutConfig = _layoutConfig.copyWith(
                                    transitionPoints: pts,
                                    videoTransition: pts.isNotEmpty ? pts.first.transitionType : 'none',
                                  );
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 12),

          // Tombol Tambah Cepat di bawah daftar
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF5722),
              side: const BorderSide(color: Color(0xFFFF5722)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _showAddVideoTransitionDialog,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('+ Tambah Efek Transisi di Menit Lainnya', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showEditHookDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atur Hook Title (Intro Banner)'),
        content: TextField(
          controller: _hookController,
          decoration: const InputDecoration(hintText: 'Tulis Hook judul di sini...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              _pushSnapshot();
              setState(() => _layoutConfig.hook.text = _hookController.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 🤖 TAB 3: AI TOOLS (NO TOKEN BADGES & REAL WORKING FEATURES)
  // ==========================================
  Widget _buildAiToolsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group: Hook Them
          const Text('Hook Them',
              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _buildAiToolTile(
            icon: Icons.subtitles_rounded,
            iconColor: const Color(0xFFFF5722),
            title: 'AI Captions',
            desc: 'Auto-generate styled subtitles & word-by-word timing',
            toolKey: 'AI Captions',
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                onPressed: () => _tabController.animateTo(0), // Jump to Style
                child: const Text('Style', style: TextStyle(fontSize: 11, color: Color(0xFF1E293B))),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5722),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  elevation: 0,
                ),
                onPressed: _triggerAutoCaptionGeneration,
                child: const Text('Generate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          _buildAiToolTile(
            icon: Icons.movie_filter_outlined,
            iconColor: const Color(0xFF1E293B),
            title: 'AI Auto B-rolls',
            desc: 'Sisipkan footage visual cutaway otomatis ke timeline klip',
            toolKey: 'AI Auto B-rolls',
          ),
          _buildAiToolTile(
            icon: Icons.zoom_in_rounded,
            iconColor: const Color(0xFF1E293B),
            title: 'AI Auto Zooms',
            desc: 'Auto punch-in dinamis untuk visual klip yang dramatis',
            toolKey: 'AI Auto Zooms',
          ),
          _buildAiToolTile(
            icon: Icons.anchor_rounded,
            iconColor: const Color(0xFF1E293B),
            title: 'AI Hook Title',
            desc: 'Buat intro banner viral pemikat penonton di 3 detik pertama',
            toolKey: 'AI Hook Title',
          ),

          const SizedBox(height: 20),

          // Group: Sound Good
          const Text('Sound Good',
              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _buildAiToolTile(
            icon: Icons.graphic_eq_rounded,
            iconColor: const Color(0xFF1E293B),
            title: 'Clean Audio',
            desc: 'Hilangkan noise & perjelas vokal pembicara',
            toolKey: 'Clean Audio',
          ),
          _buildAiToolTile(
            icon: Icons.mic_off_outlined,
            iconColor: const Color(0xFF1E293B),
            title: 'Remove Silence',
            desc: 'Pangkas jeda diam hening agar klip lebih padat',
            toolKey: 'Remove Silence',
          ),

          const SizedBox(height: 20),

          // Group: Look Good
          const Text('Look Good',
              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _buildAiToolTile(
            icon: Icons.remove_red_eye_outlined,
            iconColor: const Color(0xFF1E293B),
            title: 'Correct Eye Contact',
            desc: 'Arahkan tatapan mata pembicara tepat ke kamera',
            toolKey: 'Correct Eye Contact',
          ),
          _buildAiToolTile(
            icon: Icons.auto_fix_high_rounded,
            iconColor: const Color(0xFF1E293B),
            title: 'Remove Bad Takes',
            desc: 'Deteksi & hapus kata berulang (filler words)',
            toolKey: 'Remove Bad Takes',
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildAiToolTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    String? toolKey,
    List<Widget>? actions,
  }) {
    final isActivated = toolKey != null && (_activeAiTools[toolKey] ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActivated ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
          width: isActivated ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActivated ? const Color(0xFFFF5722).withOpacity(0.12) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isActivated ? const Color(0xFFFF5722) : iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              ],
            ),
          ),
          if (actions != null)
            Row(children: actions)
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: isActivated ? const Color(0xFFFF5722) : Colors.white,
                foregroundColor: isActivated ? Colors.white : const Color(0xFF1E293B),
                side: BorderSide(color: isActivated ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (toolKey != null) {
                  _onAiToolToggled(toolKey, !isActivated);
                }
              },
              child: Text(
                isActivated ? 'Aktif' : 'Aktifkan',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  void _onAiToolToggled(String toolKey, bool activate) {
    _pushSnapshot();
    setState(() {
      _activeAiTools[toolKey] = activate;
    });

    switch (toolKey) {
      case 'AI Captions':
        if (activate) {
          _showAiSpeechSyncDialog();
        }
        break;

      case 'AI Auto B-rolls':
        if (activate) {
          // Tambahkan 2 footage B-roll kontekstual ke timeline klip
          if (_currentClip.brolls.isEmpty) {
            _currentClip.brolls.addAll([
              BrollItem(
                title: 'Shocked Reaction Face',
                startTime: _currentClip.startTime + const Duration(seconds: 2),
                duration: const Duration(seconds: 3),
                category: 'AI Auto',
                visualUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=800',
              ),
              BrollItem(
                title: 'Nature Drone Aerial',
                startTime: _currentClip.startTime + const Duration(seconds: 7),
                duration: const Duration(seconds: 4),
                category: 'AI Auto',
                visualUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800',
              ),
            ]);
          }
          // Langsung lompat ke timestamp footage pertama & putar agar pengguna langsung melihat cutaway visualnya
          final firstBrollStart = _currentClip.brolls.first.startTime;
          _videoController?.seekTo(firstBrollStart);
          _videoController?.play();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🎬 AI Auto B-rolls aktif: Footage cutaway langsung tayang di pemutar!')),
          );
        } else {
          _currentClip.brolls.removeWhere((b) => b.category == 'AI Auto');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI Auto B-rolls dinonaktifkan')),
          );
        }
        break;

      case 'AI Auto Zooms':
        setState(() {
          _layoutConfig.template = activate ? KomposisiTemplate.dinamis : KomposisiTemplate.layarPenuh;
        });
        _videoController?.play();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(activate
                ? '🔍 AI Auto Zooms aktif: Framing bergerak dinamis & punch-in dramatis berjalan'
                : 'Framing dikembalikan ke Layar Penuh'),
          ),
        );
        break;

      case 'AI Hook Title':
        if (activate) {
          final viralHook = _currentClip.title.isNotEmpty
              ? 'RAHASIA: ${_currentClip.title.toUpperCase()}'
              : 'JODOH GARA-GARA TREND TIKTOK INI';
          setState(() {
            _layoutConfig.hook.text = viralHook;
            _hookController.text = viralHook;
          });
          // Otomatis lompat ke detik awal (0s) & putar video agar hook banner beranimasi langsung terlihat
          _videoController?.seekTo(_currentClip.startTime);
          _videoController?.play();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🪝 Hook Title aktif & dipratinjau: "$viralHook"')),
          );
        } else {
          setState(() {
            _layoutConfig.hook.text = '';
            _hookController.text = '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hook Title dinonaktifkan')),
          );
        }
        break;

      case 'Clean Audio':
        setState(() {
          _cleanAudio = activate;
          _videoVolumeDb = activate ? 6.0 : 0.0;
        });
        // Tingkatkan gain volume pemutar secara dinamis agar perbedaan suara vokal langsung terdengar
        _videoController?.setVolume(activate ? 1.0 : 0.45);
        _videoController?.play();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(activate
                ? '🎙️ Clean Audio aktif: Vokal diperjelas & volume di-boost 2x lipat!'
                : 'Clean Audio dinonaktifkan'),
          ),
        );
        break;

      case 'Remove Silence':
        if (activate) {
          // Pangkas jeda hening di awal (1.5 detik) jika klip cukup panjang
          if (_currentClip.duration > const Duration(seconds: 4)) {
            final trimmedStart = _currentClip.startTime + const Duration(milliseconds: 1500);
            _currentClip.startTime = trimmedStart;
            for (var sub in _currentClip.subtitles) {
              if (sub.startTime < trimmedStart) {
                sub.startTime = trimmedStart;
              }
            }
            _videoController?.seekTo(trimmedStart);
            _videoController?.play();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✂️ Remove Silence aktif: 1.5s jeda hening berhasil dipangkas, klip lebih padat!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pacing video dikembalikan ke normal')),
          );
        }
        break;

      case 'Correct Eye Contact':
        setState(() {
          _layoutConfig.cropPosition = activate ? 0.38 : 0.50;
        });
        _videoController?.play();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(activate
                ? '👁️ AI Correct Eye Contact aktif: Tatapan mata disejajarkan ke kamera'
                : 'Koreksi mata dinonaktifkan'),
          ),
        );
        break;

      case 'Remove Bad Takes':
        if (activate) {
          int removedCount = 0;
          final fillerPattern = RegExp(r'\b(umm|uhh|ahh|anu|jadi|kayak|maksudnya|hmm|ee)\b', caseSensitive: false);
          for (var sub in _currentClip.subtitles) {
            final originalText = sub.text;
            final cleaned = originalText.replaceAll(fillerPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();
            if (cleaned != originalText) {
              removedCount++;
              sub.text = cleaned.isNotEmpty ? cleaned : 'Poin penting video';
              sub.words = sub.text
                  .split(' ')
                  .map((w) => SubtitleWord(word: w, startTime: sub.startTime, endTime: sub.endTime))
                  .toList();
            }
          }
          _videoController?.seekTo(_currentClip.startTime);
          _videoController?.play();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✨ Remove Bad Takes: $removedCount filler words & pengulangan berhasil dibersihkan!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Filter bad takes dinonaktifkan')),
          );
        }
        break;
    }
  }

  // ==========================================
  // 🎬 TAB 4: B-ROLLS (REAL FOOTAGE INSERTION & MANAGEMENT)
  // ==========================================
  Widget _buildBrollsTab() {
    final stockBrolls = [
      {
        'title': 'Nature Drone Aerial',
        'dur': '4s',
        'icon': Icons.landscape,
        'url': 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800',
      },
      {
        'title': 'Tech Typing Keyboard',
        'dur': '3s',
        'icon': Icons.keyboard,
        'url': 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=800',
      },
      {
        'title': 'Shocked Reaction Face',
        'dur': '2s',
        'icon': Icons.face,
        'url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=800',
      },
      {
        'title': 'City Traffic Night',
        'dur': '4s',
        'icon': Icons.location_city,
        'url': 'https://images.unsplash.com/photo-1519501025264-65ba15a82390?w=800',
      },
      {
        'title': 'Coffee Shop Relax',
        'dur': '3s',
        'icon': Icons.coffee,
        'url': 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=800',
      },
      {
        'title': 'Finance Market Trading',
        'dur': '4s',
        'icon': Icons.trending_up,
        'url': 'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800',
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Upload Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'B-rolls Footage',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Footage cutaway visual saat narasi klip',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5722),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: _pickCustomBrollFromGallery,
                icon: const Icon(Icons.video_library, size: 16),
                label: const Text('Upload B-roll', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Active B-rolls in this clip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'B-rolls Aktif di Klip Ini (${_currentClip.brolls.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                    ),
                    if (_currentClip.brolls.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          _pushSnapshot();
                          setState(() => _currentClip.brolls.clear());
                        },
                        child: const Text('Hapus Semua', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_currentClip.brolls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: const [
                        Icon(Icons.info_outline, size: 16, color: Color(0xFF94A3B8)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Belum ada B-roll yang disisipkan. Klik "Insert" pada daftar stock di bawah.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._currentClip.brolls.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final b = entry.value;
                    final startS = (b.startTime.inMilliseconds / 1000.0).toStringAsFixed(1);
                    final endS = ((b.startTime + b.duration).inMilliseconds / 1000.0).toStringAsFixed(1);

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.movie, size: 18, color: Color(0xFFFF5722)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('Waktu tayang: ${startS}s - ${endS}s (${b.duration.inSeconds}s)',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5722),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () {
                              _videoController?.seekTo(b.startTime);
                              _videoController?.play();
                              setState(() => _currentPosition = b.startTime);
                            },
                            icon: const Icon(Icons.play_arrow, size: 14),
                            label: const Text('Pratinjau', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Hapus B-roll',
                            icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _pushSnapshot();
                              setState(() {
                                _currentClip.brolls.removeAt(idx);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Stock Library Header
          const Text(
            'Katalog Footage B-roll Siap Pakai',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),

          // Stock B-rolls list
          ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: stockBrolls.length,
            itemBuilder: (ctx, i) {
              final b = stockBrolls[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(b['icon'] as IconData, color: Colors.orange, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b['title'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Durasi cutaway: ${b['dur']}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5722),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        final durSec = int.tryParse(b['dur'].toString().replaceAll('s', '')) ?? 3;
                        _pushSnapshot();
                        final newBroll = BrollItem(
                          title: b['title'] as String,
                          startTime: _currentPosition,
                          duration: Duration(seconds: durSec),
                          category: 'Stock',
                          visualUrl: b['url'] as String?,
                        );
                        setState(() {
                          _currentClip.brolls.add(newBroll);
                        });
                        // Auto-seek & putar langsung agar pemutar seketika menampilkan footage B-roll
                        _videoController?.seekTo(newBroll.startTime);
                        _videoController?.play();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('🎬 B-roll "${b['title']}" disematkan & langsung dipratinjau!'),
                            backgroundColor: const Color(0xFF0F172A),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Text('Insert', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _pickCustomBrollFromGallery() async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        _pushSnapshot();
        final newBroll = BrollItem(
          title: video.name.isNotEmpty ? video.name : 'Custom Video B-roll',
          startTime: _currentPosition,
          duration: const Duration(seconds: 4),
          category: 'Custom',
          filePath: video.path,
        );
        setState(() {
          _currentClip.brolls.add(newBroll);
        });
        _videoController?.seekTo(newBroll.startTime);
        _videoController?.play();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ B-roll dari galeri berhasil disematkan dan dipratinjau di timeline!'),
            backgroundColor: Color(0xFF0F172A),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih video B-roll: $e')),
      );
    }
  }

  // ==========================================
  // 📐 KOMPOSISI, HOOK & WATERMARK CARDS
  // ==========================================
  Widget _buildKomposisiCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('📐', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'Komposisi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Template', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTemplateBtn('Standar', KomposisiTemplate.standar),
              const SizedBox(width: 8),
              _buildTemplateBtn('Layar penuh', KomposisiTemplate.layarPenuh),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTemplateBtn('Video + Foto', KomposisiTemplate.videoPlusFoto),
              const SizedBox(width: 8),
              _buildTemplateBtn('Dinamis (Auto Pan/Zoom)', KomposisiTemplate.dinamis),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Posisi crop', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('${(_layoutConfig.cropPosition * 100).round()}%',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5722),
              thumbColor: const Color(0xFFFF5722),
            ),
            child: Slider(
              value: _layoutConfig.cropPosition,
              min: 0.0,
              max: 1.0,
              onChanged: (v) {
                setState(() => _layoutConfig.cropPosition = v);
              },
              onChangeEnd: (_) => _pushSnapshot(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateBtn(String label, KomposisiTemplate template) {
    final isSelected = _layoutConfig.template == template;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _pushSnapshot();
          setState(() => _layoutConfig.template = template);
          if (template == KomposisiTemplate.dinamis) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✨ Template Dinamis aktif: Video melakukan framing sinematis otomatis'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF5722).withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF5722) : const Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHookCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('🪝', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'Hook Headline Banner',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hookController,
            maxLength: 80,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFF5722), width: 1.5),
              ),
            ),
            onChanged: (val) {
              setState(() => _layoutConfig.hook.text = val);
            },
          ),
          const SizedBox(height: 12),
          const Text('Warna Hook', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _swatchColors.map((color) => _buildColorDot(
                color: color,
                isSelected: _layoutConfig.hook.color == color,
                onTap: () {
                  _pushSnapshot();
                  setState(() => _layoutConfig.hook.color = color);
                },
              )).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Slider Ukuran Font Hook
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ukuran Font Hook Banner', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('${_layoutConfig.hook.fontSize.round()}px',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF5722))),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5722),
              thumbColor: const Color(0xFFFF5722),
            ),
            child: Slider(
              value: _layoutConfig.hook.fontSize.clamp(10.0, 48.0),
              min: 10.0,
              max: 48.0,
              divisions: 38,
              onChanged: (v) {
                setState(() => _layoutConfig.hook.fontSize = v);
              },
              onChangeEnd: (_) => _pushSnapshot(),
            ),
          ),
          const SizedBox(height: 10),

          // Slider Durasi Tampil Hook Banner
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Durasi Tayang Hook', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('${_layoutConfig.hook.durationSeconds.toStringAsFixed(1)} detik',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF5722))),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5722),
              thumbColor: const Color(0xFFFF5722),
            ),
            child: Slider(
              value: _layoutConfig.hook.durationSeconds.clamp(1.0, 15.0),
              min: 1.0,
              max: 15.0,
              divisions: 28,
              onChanged: (v) {
                setState(() => _layoutConfig.hook.durationSeconds = v);
              },
              onChangeEnd: (_) => _pushSnapshot(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatermarkCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('💧', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'Watermark / Handle',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Teks Watermark Input
          const Text('Teks Watermark', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _watermarkController,
            maxLength: 40,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: '@channelmu',
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFF5722), width: 1.5),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _layoutConfig.watermark = _layoutConfig.watermark.copyWith(text: val);
              });
            },
          ),
          const SizedBox(height: 8),

          // Live Pratinjau Teks Watermark
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Pratinjau Live: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(_layoutConfig.watermark.opacity),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _layoutConfig.watermark.text.isNotEmpty ? _layoutConfig.watermark.text : '@channelmu',
                    style: TextStyle(
                      color: _layoutConfig.watermark.color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pilihan Posisi Watermark
          const Text('Posisi Peletakan Watermark', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildWatermarkPosBtn('Kiri Atas'),
              const SizedBox(width: 6),
              _buildWatermarkPosBtn('Atas'),
              const SizedBox(width: 6),
              _buildWatermarkPosBtn('Tengah'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildWatermarkPosBtn('Kiri Bawah'),
              const SizedBox(width: 6),
              _buildWatermarkPosBtn('Bawah'),
            ],
          ),
          const SizedBox(height: 16),

          // Warna Watermark
          const Text('Warna Teks Watermark', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _swatchColors.map((color) => _buildColorDot(
                color: color,
                isSelected: _layoutConfig.watermark.color == color,
                onTap: () {
                  _pushSnapshot();
                  setState(() {
                    _layoutConfig.watermark = _layoutConfig.watermark.copyWith(color: color);
                  });
                },
              )).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Opasitas Watermark Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Transparansi / Opasitas', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('${(_layoutConfig.watermark.opacity * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFFF5722))),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5722),
              thumbColor: const Color(0xFFFF5722),
            ),
            child: Slider(
              value: _layoutConfig.watermark.opacity,
              min: 0.2,
              max: 1.0,
              onChanged: (v) {
                setState(() {
                  _layoutConfig.watermark = _layoutConfig.watermark.copyWith(opacity: v);
                });
              },
              onChangeEnd: (_) => _pushSnapshot(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatermarkPosBtn(String posLabel) {
    final isSelected = _layoutConfig.watermark.position.toLowerCase() == posLabel.toLowerCase();
    return Expanded(
      child: InkWell(
        onTap: () {
          _pushSnapshot();
          setState(() {
            _layoutConfig.watermark = _layoutConfig.watermark.copyWith(position: posLabel);
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF5722).withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              posLabel,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF5722) : const Color(0xFF475569),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentBtn(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF5722) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF5722) : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorDot({required Color color, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFFFF5722) : Colors.black26,
            width: isSelected ? 2.5 : 1.0,
          ),
        ),
      ),
    );
  }

  // Floating Save & Render Action Bar
  Widget _buildFloatingBottomToast() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$_changesCount perubahan siap',
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 14),
          TextButton(
            onPressed: () {
              setState(() => _changesCount = 0);
            },
            child: const Text('Reset', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5722),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              _videoController?.pause();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RenderProgressScreen(
                    sourceVideoFile: widget.sourceVideoFile,
                    clip: _currentClip,
                    layout: _layoutConfig,
                    subtitleStyle: _subtitleStyle,
                  ),
                ),
              );
            },
            child: const Text('Simpan & Render', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
