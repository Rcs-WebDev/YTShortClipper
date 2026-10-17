import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';

class VideoCanvasPreview extends StatelessWidget {
  final VideoPlayerController? controller;
  final LayoutConfig layout;
  final SubtitleStyleConfig subtitleStyle;
  final ClipSegment clip;
  final Duration currentPosition;

  const VideoCanvasPreview({
    super.key,
    required this.controller,
    required this.layout,
    required this.subtitleStyle,
    required this.clip,
    required this.currentPosition,
  });

  TextStyle _getGoogleFontStyle({
    required double fontSize,
    required Color color,
    List<Shadow>? shadows,
    Paint? foreground,
  }) {
    final base = TextStyle(
      fontSize: fontSize,
      color: foreground == null ? color : null,
      foreground: foreground,
      fontWeight: FontWeight.w900,
      fontStyle: subtitleStyle.isItalic ? FontStyle.italic : FontStyle.normal,
      shadows: shadows,
      letterSpacing: 0.5,
    );

    switch (subtitleStyle.fontFamily) {
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

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video Layer (With Video Transition Effect)
            if (controller != null && controller!.value.isInitialized)
              _applyVideoTransition(_buildVideoLayout())
            else
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
              ),

            // Active B-roll Cutaway Overlay
            ..._buildActiveBrolls(),

            // Hook Overlay (Teks besar yang muncul di atas klip)
            if (layout.hook.text.trim().isNotEmpty && _isHookVisible())
              _buildHookOverlay(),

            // Watermark Overlay
            if (layout.watermark.text.trim().isNotEmpty)
              _buildWatermarkOverlay(),

            // Live Subtitle Overlay (Matching Screenshot: Solid Yellow box, Poppins/Anton, etc.)
            _buildSubtitleOverlay(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActiveBrolls() {
    final activeBrolls = clip.brolls.where((b) {
      return currentPosition >= b.startTime && currentPosition <= b.endTime;
    }).toList();

    return activeBrolls.map((b) => _buildBrollOverlay(b)).toList();
  }

  Widget _buildBrollOverlay(BrollItem broll) {
    // Cinematic Ken-Burns progressive scale (1.0 -> 1.15)
    final elapsedMs = (currentPosition - broll.startTime).inMilliseconds;
    final totalMs = broll.duration.inMilliseconds > 0 ? broll.duration.inMilliseconds : 3000;
    final progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
    final scale = 1.0 + (progress * 0.15);

    // Stock footage imagery mapping
    String imageUrl = (broll.visualUrl != null && broll.visualUrl!.isNotEmpty)
        ? broll.visualUrl!
        : 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800'; // default nature
    if (broll.visualUrl == null || broll.visualUrl!.isEmpty) {
      final lowerTitle = broll.title.toLowerCase();
      if (lowerTitle.contains('tech') || lowerTitle.contains('keyboard') || lowerTitle.contains('typing')) {
        imageUrl = 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=800';
      } else if (lowerTitle.contains('shock') || lowerTitle.contains('face') || lowerTitle.contains('reaction')) {
        imageUrl = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=800';
      } else if (lowerTitle.contains('traffic') || lowerTitle.contains('city') || lowerTitle.contains('night')) {
        imageUrl = 'https://images.unsplash.com/photo-1519501025264-65ba15a82390?w=800';
      } else if (lowerTitle.contains('coffee') || lowerTitle.contains('shop') || lowerTitle.contains('relax')) {
        imageUrl = 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=800';
      }
    }

    final remainingSec = ((broll.endTime - currentPosition).inMilliseconds / 1000.0).clamp(0.0, 99.0);

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Visual Image with Ken-Burns Zoom
            Positioned.fill(
              child: Transform.scale(
                scale: scale,
                child: broll.filePath != null
                    ? Image.file(
                        File(broll.filePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackBrollBg(broll),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackBrollBg(broll),
                      ),
              ),
            ),

            // Vignette & gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Top Header: B-roll status badge
            Positioned(
              top: 14,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5722),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF5722).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.movie_filter, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'B-ROLL CUTAWAY',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Text(
                      '${remainingSec.toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

            // Center Title
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF5722), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      broll.title.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Footage disisipkan di ${((broll.startTime - clip.startTime).inMilliseconds / 1000).toStringAsFixed(1)}s klip',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBrollBg(BrollItem broll) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.movie_filter_rounded, color: Colors.orange.withValues(alpha: 0.3), size: 64),
      ),
    );
  }

  bool _isHookVisible() {
    // Show hook during its specified duration from clip start
    final relSeconds = (currentPosition - clip.startTime).inMilliseconds / 1000.0;
    return relSeconds <= layout.hook.durationSeconds || !controller!.value.isPlaying;
  }

  Widget _buildVideoLayout() {
    switch (layout.template) {
      case KomposisiTemplate.standar:
        return Stack(
          fit: StackFit.expand,
          children: [
            // Blurred background video
            Transform.scale(
              scale: 3.2,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.35),
                    BlendMode.darken,
                  ),
                  child: VideoPlayer(controller!),
                ),
              ),
            ),
            Center(
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller!),
              ),
            ),
          ],
        );

      case KomposisiTemplate.layarPenuh:
        // Position crop based on layout.cropPosition (0.0 to 1.0 -> -1.0 to 1.0)
        final alignX = (layout.cropPosition - 0.5) * 2.0;
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment(alignX, 0.0),
            child: SizedBox(
              width: controller!.value.size.width,
              height: controller!.value.size.height,
              child: VideoPlayer(controller!),
            ),
          ),
        );

      case KomposisiTemplate.dinamis:
        // Dynamic smart camera pan: smooth sinusoidal panning based on playback time
        final elapsedSec = (currentPosition - clip.startTime).inMilliseconds / 1000.0;
        final panOffset = math.sin(elapsedSec * 0.9) * 0.50;
        final alignX = ((layout.cropPosition - 0.5) * 1.5 + panOffset).clamp(-1.0, 1.0);
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment(alignX, 0.0),
            child: SizedBox(
              width: controller!.value.size.width,
              height: controller!.value.size.height,
              child: VideoPlayer(controller!),
            ),
          ),
        );

      case KomposisiTemplate.videoPlusFoto:
        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(
                  flex: 3,
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: VideoPlayer(controller!),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    color: const Color(0xFF14141E),
                    child: const Center(
                      child: Icon(Icons.image_outlined, color: Colors.white24, size: 48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildHookOverlay() {
    return Positioned(
      top: 24,
      left: 14,
      right: 14,
      child: Text(
        layout.hook.text.toUpperCase(),
        textAlign: TextAlign.center,
        style: GoogleFonts.bebasNeue(
          fontSize: layout.hook.fontSize,
          letterSpacing: 1.2,
          color: layout.hook.color,
          shadows: const [
            Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 4),
            Shadow(color: Colors.black, offset: Offset(-2, -2), blurRadius: 4),
            Shadow(color: Colors.black, offset: Offset(2, -2), blurRadius: 4),
            Shadow(color: Colors.black, offset: Offset(-2, 2), blurRadius: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildWatermarkOverlay() {
    Alignment alignment;
    if (layout.watermark.position == 'Atas') {
      alignment = Alignment.topRight;
    } else if (layout.watermark.position == 'Kiri Atas') {
      alignment = Alignment.topLeft;
    } else if (layout.watermark.position == 'Tengah') {
      alignment = Alignment.center;
    } else if (layout.watermark.position == 'Kiri Bawah') {
      alignment = Alignment.bottomLeft;
    } else {
      alignment = Alignment.bottomRight;
    }

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24, width: 0.8),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            layout.watermark.text,
            style: TextStyle(
              color: layout.watermark.color.withValues(alpha: layout.watermark.opacity),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleOverlay() {
    // Find active subtitle line
    final line = clip.subtitles.firstWhere(
      (l) => currentPosition >= l.startTime && currentPosition <= l.endTime,
      orElse: () => SubtitleLine(
        text: '',
        startTime: Duration.zero,
        endTime: Duration.zero,
        words: [],
      ),
    );

    if (line.text.isEmpty && line.words.isEmpty) {
      return const SizedBox.shrink();
    }

    Alignment alignment;
    if (subtitleStyle.position == SubtitlePosition.atas) {
      alignment = const Alignment(0.0, -0.55);
    } else if (subtitleStyle.position == SubtitlePosition.tengah) {
      alignment = Alignment.center;
    } else {
      alignment = const Alignment(0.0, 0.72); // Default Bawah
    }

    // Scale font size from the 90px model relative to preview canvas (preview is around ~300px wide, video is 1080px wide)
    final previewFontSize = (subtitleStyle.fontSize * 0.22).clamp(12.0, 36.0);

    // List of shadows according to preset
    List<Shadow> shadows = [];
    if (subtitleStyle.has3dShadow) {
      shadows = [
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(1.5, 1.5), blurRadius: 0),
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(3.0, 3.0), blurRadius: 0),
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(4.5, 4.5), blurRadius: 1),
      ];
    } else if (subtitleStyle.preset == SubtitlePresetType.outline ||
        subtitleStyle.bgType == SubtitleBgType.none) {
      shadows = [
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(1.5, 1.5), blurRadius: 2),
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(-1.5, -1.5), blurRadius: 2),
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(1.5, -1.5), blurRadius: 2),
        Shadow(color: subtitleStyle.strokeColor, offset: const Offset(-1.5, 1.5), blurRadius: 2),
      ];
    } else if (subtitleStyle.bgType == SubtitleBgType.glow) {
      shadows = [
        Shadow(color: subtitleStyle.bgColor, blurRadius: 14),
        Shadow(color: subtitleStyle.bgColor, blurRadius: 24),
      ];
    }

    Paint? outlinePaint;
    if (subtitleStyle.isOutlineOnly) {
      outlinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = subtitleStyle.textColor;
    }

    // Determine words to show
    List<SubtitleWord> wordsToRender = line.words;
    if (subtitleStyle.wordByWord) {
      // Filter only current active word
      final activeWord = line.words.where(
        (w) => currentPosition >= w.startTime && currentPosition <= w.endTime,
      ).firstOrNull;
      if (activeWord != null) {
        wordsToRender = [activeWord];
      }
    }

    final contentWidget = Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: wordsToRender.isNotEmpty
          ? wordsToRender.map((w) {
              return Container(
                padding: subtitleStyle.bgType == SubtitleBgType.solid
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                    : EdgeInsets.zero,
                decoration: subtitleStyle.bgType == SubtitleBgType.solid
                    ? BoxDecoration(
                        color: subtitleStyle.bgColor,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      )
                    : null,
                child: Text(
                  w.word.toUpperCase(),
                  style: _getGoogleFontStyle(
                    fontSize: previewFontSize,
                    color: (currentPosition >= w.startTime && currentPosition <= w.endTime)
                        ? subtitleStyle.activeWordColor
                        : (subtitleStyle.bgType == SubtitleBgType.solid &&
                                (subtitleStyle.bgColor == const Color(0xFFFFD600) ||
                                 subtitleStyle.bgColor == Colors.yellow ||
                                 subtitleStyle.bgColor == const Color(0xFFD6FF00) ||
                                 subtitleStyle.bgColor == const Color(0xFF00FF2A) ||
                                 subtitleStyle.bgColor == const Color(0xFFF3ECE0))
                            ? Colors.black
                            : subtitleStyle.textColor),
                    shadows: shadows,
                    foreground: outlinePaint,
                  ),
                ),
              );
            }).toList()
          : [
              Container(
                padding: subtitleStyle.bgType == SubtitleBgType.solid
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                    : EdgeInsets.zero,
                decoration: subtitleStyle.bgType == SubtitleBgType.solid
                    ? BoxDecoration(
                        color: subtitleStyle.bgColor,
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: Text(
                  line.text.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: _getGoogleFontStyle(
                    fontSize: previewFontSize,
                    color: subtitleStyle.textColor,
                    shadows: shadows,
                    foreground: outlinePaint,
                  ),
                ),
              ),
            ],
    );

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _applySubtitleTransition(contentWidget, line),
      ),
    );
  }

  /// Menerapkan 12 efek transisi visual animasi pada subtitle:
  /// dissolve, wipe, fade in, fade out, zoom in, zoom out, slide, glitch, roll, whip, spin, iris
  Widget _applySubtitleTransition(Widget child, SubtitleLine line) {
    final elapsedMs = (currentPosition - line.startTime).inMilliseconds;
    final remainingMs = (line.endTime - currentPosition).inMilliseconds;

    // Progress 0.0 -> 1.0 pada 280ms pertama kemunculan
    final double enter = (elapsedMs / 280.0).clamp(0.0, 1.0);
    // Progress 1.0 -> 0.0 pada 200ms terakhir sebelum menghilang
    final double exit = (remainingMs / 200.0).clamp(0.0, 1.0);

    final transitionType = line.transition.toLowerCase().trim();

    switch (transitionType) {
      case 'dissolve':
        return Opacity(
          opacity: (enter * exit).clamp(0.0, 1.0),
          child: child,
        );

      case 'wipe':
        return ClipRect(
          clipper: _WipeHorizontalClipper(enter),
          child: child,
        );

      case 'fade out':
        return Opacity(
          opacity: exit,
          child: child,
        );

      case 'zoom in':
        return Transform.scale(
          scale: (0.15 + (0.85 * enter)),
          child: Opacity(opacity: enter, child: child),
        );

      case 'zoom out':
        return Transform.scale(
          scale: (1.7 - (0.7 * enter)),
          child: Opacity(opacity: enter, child: child),
        );

      case 'slide':
        return Transform.translate(
          offset: Offset(0, 36.0 * (1.0 - enter)),
          child: Opacity(opacity: enter, child: child),
        );

      case 'glitch':
        final isJitter = enter < 1.0 && (elapsedMs % 60 < 30);
        final jitterX = isJitter ? ((elapsedMs % 40 < 20) ? 6.0 : -6.0) : 0.0;
        final jitterY = isJitter ? ((elapsedMs % 30 < 15) ? -2.0 : 2.0) : 0.0;
        return Transform.translate(
          offset: Offset(jitterX, jitterY),
          child: ColorFiltered(
            colorFilter: isJitter
                ? const ColorFilter.mode(Colors.cyanAccent, BlendMode.modulate)
                : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
            child: child,
          ),
        );

      case 'roll':
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.003)
            ..rotateX((1.0 - enter) * 1.57),
          child: Opacity(opacity: enter, child: child),
        );

      case 'whip':
        return Transform.translate(
          offset: Offset(90.0 * (1.0 - enter), 0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX((1.0 - enter) * -0.4),
            child: Opacity(opacity: enter, child: child),
          ),
        );

      case 'spin':
        return Transform.rotate(
          angle: (1.0 - enter) * -2.0,
          child: Transform.scale(
            scale: (0.2 + (0.8 * enter)),
            child: Opacity(opacity: enter, child: child),
          ),
        );

      case 'iris':
        return ClipOval(
          clipper: _IrisClipper(enter),
          child: child,
        );

      case 'fade in':
      default:
        return Opacity(
          opacity: enter,
          child: child,
        );
    }
  }

  /// 🎬 Menerapkan Efek Transisi khusus ke VIDEO UTAMA pada menit/detik tertentu
  Widget _applyVideoTransition(Widget child) {
    final relTimeMs = (currentPosition - clip.startTime).inMilliseconds;

    // Cari apakah ada titik transisi yang sedang aktif saat playback berada di menit/detik ini
    VideoTransitionPoint? activePoint;
    for (final pt in layout.transitionPoints) {
      final startMs = pt.timeOffset.inMilliseconds;
      final durMs = (pt.duration * 1000).round();
      if (durMs <= 0) continue;
      if (relTimeMs >= startMs && relTimeMs < startMs + durMs) {
        activePoint = pt;
        break;
      }
    }

    String transType = '';
    double enter = 1.0;
    int elapsedInTransMs = 0;

    if (activePoint != null) {
      transType = activePoint.transitionType.toLowerCase().trim();
      final startMs = activePoint.timeOffset.inMilliseconds;
      final durMs = (activePoint.duration * 1000).round();
      elapsedInTransMs = relTimeMs - startMs;
      enter = (elapsedInTransMs / durMs).clamp(0.0, 1.0);
    } else if (layout.transitionPoints.isEmpty) {
      transType = layout.videoTransition.toLowerCase().trim();
      final totalMs = (layout.videoTransitionDuration * 1000).round();
      if (totalMs > 0 && relTimeMs >= 0 && relTimeMs < totalMs) {
        elapsedInTransMs = relTimeMs;
        enter = (relTimeMs / totalMs).clamp(0.0, 1.0);
      }
    }

    if (transType.isEmpty || transType == 'none' || enter >= 1.0) {
      return child;
    }

    switch (transType) {
      case 'dissolve':
      case 'fade in':
        return Opacity(
          opacity: enter,
          child: child,
        );

      case 'zoom in':
        return Transform.scale(
          scale: 1.35 - (0.35 * enter),
          child: Opacity(opacity: enter, child: child),
        );

      case 'zoom out':
        return Transform.scale(
          scale: 0.65 + (0.35 * enter),
          child: Opacity(opacity: enter, child: child),
        );

      case 'wipe horizontal':
      case 'wipe':
        return ClipRect(
          clipper: _WipeHorizontalClipper(enter),
          child: child,
        );

      case 'wipe vertical':
        return ClipRect(
          clipper: _WipeVerticalClipper(enter),
          child: child,
        );

      case 'glitch':
        final isJitter = enter < 1.0 && (elapsedInTransMs % 80 < 40);
        final jitterX = isJitter ? ((elapsedInTransMs % 40 < 20) ? 14.0 : -14.0) : 0.0;
        return Transform.translate(
          offset: Offset(jitterX, 0),
          child: ColorFiltered(
            colorFilter: isJitter
                ? const ColorFilter.mode(Colors.cyanAccent, BlendMode.modulate)
                : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
            child: child,
          ),
        );

      case 'whip pan':
      case 'whip':
        return Transform.translate(
          offset: Offset(260.0 * (1.0 - enter), 0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX((1.0 - enter) * -0.4),
            child: Opacity(opacity: enter, child: child),
          ),
        );

      case 'white flash':
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Container(color: Colors.white.withValues(alpha: 1.0 - enter)),
          ],
        );

      case 'black flash':
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Container(color: Colors.black.withValues(alpha: 1.0 - enter)),
          ],
        );

      case 'spin':
        return Transform.rotate(
          angle: (1.0 - enter) * -3.1415,
          child: Transform.scale(
            scale: 0.3 + (0.7 * enter),
            child: Opacity(opacity: enter, child: child),
          ),
        );

      case 'iris':
        return ClipOval(
          clipper: _IrisClipper(enter),
          child: child,
        );

      default:
        return Opacity(opacity: enter, child: child);
    }
  }
}

class _WipeHorizontalClipper extends CustomClipper<Rect> {
  final double progress;
  _WipeHorizontalClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(_WipeHorizontalClipper oldClipper) => oldClipper.progress != progress;
}

class _WipeVerticalClipper extends CustomClipper<Rect> {
  final double progress;
  _WipeVerticalClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width, size.height * progress);
  }

  @override
  bool shouldReclip(_WipeVerticalClipper oldClipper) => oldClipper.progress != progress;
}

class _IrisClipper extends CustomClipper<Rect> {
  final double progress;
  _IrisClipper(this.progress);

  @override
  Rect getClip(Size size) {
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
    final curRadius = maxRadius * progress;
    final center = Offset(size.width / 2, size.height / 2);
    return Rect.fromCircle(center: center, radius: curRadius);
  }

  @override
  bool shouldReclip(_IrisClipper oldClipper) => oldClipper.progress != progress;
}
