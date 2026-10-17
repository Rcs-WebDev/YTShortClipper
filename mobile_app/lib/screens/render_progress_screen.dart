import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';
import '../services/ffmpeg_render_service.dart';

class RenderProgressScreen extends StatefulWidget {
  final File sourceVideoFile;
  final ClipSegment clip;
  final LayoutConfig layout;
  final SubtitleStyleConfig subtitleStyle;

  const RenderProgressScreen({
    super.key,
    required this.sourceVideoFile,
    required this.clip,
    required this.layout,
    required this.subtitleStyle,
  });

  @override
  State<RenderProgressScreen> createState() => _RenderProgressScreenState();
}

class _RenderProgressScreenState extends State<RenderProgressScreen> {
  double _progress = 0.0;
  String _statusMessage = 'Memulai proses render...';
  bool _isCompleted = false;
  String? _errorMessage;
  File? _renderedFile;
  VideoPlayerController? _previewController;

  @override
  void initState() {
    super.initState();
    _startRender();
  }

  Future<void> _startRender() async {
    try {
      final file = await FFmpegRenderService.renderClip(
        sourceVideoFile: widget.sourceVideoFile,
        clip: widget.clip,
        layout: widget.layout,
        subtitleStyle: widget.subtitleStyle,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onStatus: (s) {
          if (mounted) setState(() => _statusMessage = s);
        },
      );

      _previewController = VideoPlayerController.file(file);
      await _previewController!.initialize();
      _previewController!.setLooping(true);
      _previewController!.play();

      if (mounted) {
        setState(() {
          _isCompleted = true;
          _renderedFile = file;
          _progress = 1.0;
          _statusMessage = 'Video berhasil dirender & disimpan ke Galeri HP!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111118),
      appBar: AppBar(
        title: const Text('Render Video 9:16'),
        backgroundColor: const Color(0xFF191924),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _errorMessage != null
              ? _buildErrorView()
              : _isCompleted
                  ? _buildSuccessView()
                  : _buildProgressView(),
        ),
      ),
    );
  }

  Widget _buildProgressView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  strokeWidth: 8,
                  color: Colors.amber,
                  backgroundColor: Colors.white12,
                ),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'FFmpeg on-device sedang memproses crop 9:16,\nkaraoke subtitle, dan kompresi H.264 langsung di HP Anda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 48),
        const SizedBox(height: 8),
        const Text(
          'Render Berhasil Selesai! 🎉',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Video klip vertikal siap diupload ke TikTok, Reels, & Shorts',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 16),
        // Preview Result
        Expanded(
          child: _previewController != null && _previewController!.value.isInitialized
              ? AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: VideoPlayer(_previewController!),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF222235),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Edit Ulang'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (_renderedFile != null) {
                    Share.shareXFiles([XFile(_renderedFile!.path)], text: 'Video Short Hasil YT Clipper!');
                  }
                },
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share Video', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Proses Render Gagal',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _errorMessage ?? 'Terjadi kesalahan teknis pada sistem.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text('Kembali ke Editor'),
          ),
        ],
      ),
    );
  }
}
