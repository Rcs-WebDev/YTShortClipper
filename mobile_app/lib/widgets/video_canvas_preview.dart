import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';
import '../services/ffmpeg_render_service.dart';

class VideoCanvasPreview extends StatefulWidget {
  final VideoPlayerController? controller;
  final LayoutConfig layout;
  final SubtitleStyleConfig subtitleStyle;
  final ClipSegment clip;
  final Duration currentPosition;
  final bool hideOverlays;

  const VideoCanvasPreview({
    super.key,
    required this.controller,
    required this.layout,
    required this.subtitleStyle,
    required this.clip,
    required this.currentPosition,
    this.hideOverlays = false,
  });

  @override
  State<VideoCanvasPreview> createState() => _VideoCanvasPreviewState();
}

class _VideoCanvasPreviewState extends State<VideoCanvasPreview> {
  VideoPlayerController? _brollController;
  String? _activeBrollVideoPath;
  bool _isInitializingBroll = false;

  @override
  void initState() {
    super.initState();
    _syncActiveBrollVideo();
  }

  @override
  void didUpdateWidget(covariant VideoCanvasPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBroll = _getBrollAt(oldWidget.clip, oldWidget.currentPosition);
    final newBroll = _getCurrentActiveBroll();
    final playChanged = oldWidget.controller?.value.isPlaying != widget.controller?.value.isPlaying;

    if (oldBroll?.id != newBroll?.id || playChanged) {
      _syncActiveBrollVideo();
    }
  }

  @override
  void dispose() {
    _brollController?.dispose();
    super.dispose();
  }

  BrollItem? _getBrollAt(ClipSegment clip, Duration pos) {
    for (int i = clip.brolls.length - 1; i >= 0; i--) {
      final b = clip.brolls[i];
      if (pos >= b.startTime && pos < b.endTime) {
        return b;
      }
    }
    return null;
  }

  BrollItem? _getCurrentActiveBroll() {
    return _getBrollAt(widget.clip, widget.currentPosition);
  }

  Future<void> _syncActiveBrollVideo() async {
    final activeBroll = _getCurrentActiveBroll();
    if (activeBroll == null ||
        activeBroll.filePath == null ||
        !FFmpegRenderService.isVideoFilePath(activeBroll.filePath)) {
      if (_brollController != null && _brollController!.value.isPlaying) {
        _brollController!.pause();
      }
      _activeBrollVideoPath = null;
      return;
    }

    final path = activeBroll.filePath!;
    if (_activeBrollVideoPath != path && !_isInitializingBroll) {
      _isInitializingBroll = true;
      final oldCtrl = _brollController;
      _brollController = null;
      _activeBrollVideoPath = path;
      await oldCtrl?.dispose();

      try {
        final file = File(path);
        if (await file.exists()) {
          final ctrl = VideoPlayerController.file(file);
          await ctrl.initialize();
          await ctrl.setVolume(0.0); // Mute B-roll video so main clip speech remains clear
          await ctrl.setLooping(true);

          final elapsed = widget.currentPosition - activeBroll.startTime;
          if (!elapsed.isNegative) {
            final vidDur = ctrl.value.duration;
            final targetSeek = vidDur.inMilliseconds > 0
                ? Duration(milliseconds: elapsed.inMilliseconds % vidDur.inMilliseconds)
                : Duration.zero;
            await ctrl.seekTo(targetSeek);
          }

          if (widget.controller?.value.isPlaying == true) {
            await ctrl.play();
          }

          if (mounted && _activeBrollVideoPath == path) {
            setState(() {
              _brollController = ctrl;
            });
          } else {
            await ctrl.dispose();
          }
        }
      } catch (_) {
        // Ignore initialization errors
      } finally {
        _isInitializingBroll = false;
      }
      return;
    }

    // Sync play/pause & position with main controller
    if (_brollController != null && _brollController!.value.isInitialized) {
      final mainPlaying = widget.controller?.value.isPlaying ?? false;
      if (mainPlaying && !_brollController!.value.isPlaying) {
        _brollController!.play();
      } else if (!mainPlaying && _brollController!.value.isPlaying) {
        _brollController!.pause();
      }

      final elapsed = widget.currentPosition - activeBroll.startTime;
      final vidDur = _brollController!.value.duration;
      if (!elapsed.isNegative && vidDur.inMilliseconds > 300) {
        final expectedMs = elapsed.inMilliseconds % vidDur.inMilliseconds;
        final actualMs = _brollController!.value.position.inMilliseconds;
        if ((expectedMs - actualMs).abs() > 750) {
          _brollController!.seekTo(Duration(milliseconds: expectedMs));
        }
      }
    }
  }

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
      fontStyle: widget.subtitleStyle.isItalic ? FontStyle.italic : FontStyle.normal,
      shadows: shadows,
      letterSpacing: 0.5,
    );

    switch (widget.subtitleStyle.fontFamily) {
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
    final activeBroll = _getCurrentActiveBroll();

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
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
            if (widget.controller != null && widget.controller!.value.isInitialized)
              _applyVideoTransition(_buildVideoLayout())
            else
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
              ),

            // Active B-roll Cutaway Footage (Clean video/image overlay without template cards)
            if (activeBroll != null)
              _buildBrollOverlay(activeBroll),

            // Hook Overlay (Teks besar yang muncul di atas klip)
            if (!widget.hideOverlays &&
                widget.layout.hook.text.trim().isNotEmpty &&
                _isHookVisible())
              _buildHookOverlay(),

            // Watermark Overlay
            if (!widget.hideOverlays && widget.layout.watermark.text.trim().isNotEmpty)
              _buildWatermarkOverlay(),

            // Live Subtitle Overlay
            if (!widget.hideOverlays)
              _buildSubtitleOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBrollOverlay(BrollItem broll) {
    final isVideoFile = broll.filePath != null && FFmpegRenderService.isVideoFilePath(broll.filePath);

    if (isVideoFile) {
      if (_brollController != null && _brollController!.value.isInitialized) {
        final bAspect = _brollController!.value.aspectRatio > 0
            ? _brollController!.value.aspectRatio
            : 16 / 9;
        final bw = bAspect >= 1.0 ? 1000.0 * bAspect : 1000.0;
        final bh = bAspect >= 1.0 ? 1000.0 : 1000.0 / bAspect;

        return Positioned.fill(
          child: Container(
            color: Colors.black,
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: bw,
                  height: bh,
                  child: AspectRatio(
                    aspectRatio: bAspect,
                    child: VideoPlayer(_brollController!),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        return Positioned.fill(
          child: Container(
            color: Colors.black,
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Color(0xFFFF5722),
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
        );
      }
    }

    // Image B-roll (from Gallery or Stock Footage URL) with smooth Ken-Burns zoom (1.0 -> 1.12)
    final elapsedMs = (widget.currentPosition - broll.startTime).inMilliseconds;
    final totalMs = broll.duration.inMilliseconds > 0 ? broll.duration.inMilliseconds : 3000;
    final progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
    final scale = 1.0 + (progress * 0.12);

    String imageUrl = (broll.visualUrl != null && broll.visualUrl!.isNotEmpty)
        ? broll.visualUrl!
        : 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800';
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

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Transform.scale(
          scale: scale,
          child: broll.filePath != null
              ? Image.file(
                  File(broll.filePath!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
        ),
      ),
    );
  }

  bool _isHookVisible() {
    if (widget.controller == null || !widget.controller!.value.isInitialized) return true;
    final relSeconds = (widget.currentPosition - widget.clip.startTime).inMilliseconds / 1000.0;
    return relSeconds <= widget.layout.hook.durationSeconds || !widget.controller!.value.isPlaying;
  }

  Widget _buildVideoLayout() {
    final ctrl = widget.controller!;
    final safeAspect = ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : 16 / 9;
    final targetW = safeAspect >= 1.0 ? 1000.0 * safeAspect : 1000.0;
    final targetH = safeAspect >= 1.0 ? 1000.0 : 1000.0 / safeAspect;

    final videoWidget = SizedBox(
      width: targetW,
      height: targetH,
      child: AspectRatio(
        aspectRatio: safeAspect,
        child: VideoPlayer(ctrl),
      ),
    );

    switch (widget.layout.template) {
      case KomposisiTemplate.standar:
        return Container(
          color: const Color(0xFF0F172A),
          child: Center(
            child: AspectRatio(
              aspectRatio: safeAspect,
              child: VideoPlayer(ctrl),
            ),
          ),
        );

      case KomposisiTemplate.layarPenuh:
        final alignX = (widget.layout.cropPosition - 0.5) * 2.0;
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment(alignX.clamp(-1.0, 1.0), 0.0),
            child: videoWidget,
          ),
        );

      case KomposisiTemplate.dinamis:
        final elapsedSec = (widget.currentPosition - widget.clip.startTime).inMilliseconds / 1000.0;
        final panOffset = math.sin(elapsedSec * 0.9) * 0.50;
        final alignX = ((widget.layout.cropPosition - 0.5) * 1.5 + panOffset).clamp(-1.0, 1.0);
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment(alignX, 0.0),
            child: videoWidget,
          ),
        );

      case KomposisiTemplate.videoPlusFoto:
        return Column(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: videoWidget,
                ),
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
        );
    }
  }

  Widget _buildHookOverlay() {
    return Positioned(
      top: 24,
      left: 14,
      right: 14,
      child: Text(
        widget.layout.hook.text.toUpperCase(),
        textAlign: TextAlign.center,
        style: GoogleFonts.bebasNeue(
          fontSize: widget.layout.hook.fontSize,
          letterSpacing: 1.2,
          color: widget.layout.hook.color,
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
    if (widget.layout.watermark.position == 'Atas') {
      alignment = Alignment.topRight;
    } else if (widget.layout.watermark.position == 'Kiri Atas') {
      alignment = Alignment.topLeft;
    } else if (widget.layout.watermark.position == 'Tengah') {
      alignment = Alignment.center;
    } else if (widget.layout.watermark.position == 'Kiri Bawah') {
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
            widget.layout.watermark.text,
            style: TextStyle(
              color: widget.layout.watermark.color.withValues(alpha: widget.layout.watermark.opacity),
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
    final line = widget.clip.subtitles.firstWhere(
      (l) => widget.currentPosition >= l.startTime && widget.currentPosition <= l.endTime,
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
    if (widget.subtitleStyle.position == SubtitlePosition.atas) {
      alignment = const Alignment(0.0, -0.55);
    } else if (widget.subtitleStyle.position == SubtitlePosition.tengah) {
      alignment = Alignment.center;
    } else {
      alignment = const Alignment(0.0, 0.72);
    }

    final previewFontSize = (widget.subtitleStyle.fontSize * 0.22).clamp(12.0, 36.0);

    List<Shadow> shadows = [];
    if (widget.subtitleStyle.has3dShadow) {
      shadows = [
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(1.5, 1.5), blurRadius: 0),
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(3.0, 3.0), blurRadius: 0),
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(4.5, 4.5), blurRadius: 1),
      ];
    } else if (widget.subtitleStyle.preset == SubtitlePresetType.outline ||
        widget.subtitleStyle.bgType == SubtitleBgType.none) {
      shadows = [
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(1.5, 1.5), blurRadius: 2),
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(-1.5, -1.5), blurRadius: 2),
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(1.5, -1.5), blurRadius: 2),
        Shadow(color: widget.subtitleStyle.strokeColor, offset: const Offset(-1.5, 1.5), blurRadius: 2),
      ];
    } else if (widget.subtitleStyle.bgType == SubtitleBgType.glow) {
      shadows = [
        Shadow(color: widget.subtitleStyle.bgColor, blurRadius: 14),
        Shadow(color: widget.subtitleStyle.bgColor, blurRadius: 24),
      ];
    }

    Paint? outlinePaint;
    if (widget.subtitleStyle.isOutlineOnly) {
      outlinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = widget.subtitleStyle.textColor;
    }

    List<SubtitleWord> wordsToRender = line.words;
    if (widget.subtitleStyle.wordByWord) {
      final activeWord = line.words.where(
        (w) => widget.currentPosition >= w.startTime && widget.currentPosition <= w.endTime,
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
                padding: widget.subtitleStyle.bgType == SubtitleBgType.solid
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                    : EdgeInsets.zero,
                decoration: widget.subtitleStyle.bgType == SubtitleBgType.solid
                    ? BoxDecoration(
                        color: widget.subtitleStyle.bgColor,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
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
                    color: (widget.currentPosition >= w.startTime && widget.currentPosition <= w.endTime)
                        ? widget.subtitleStyle.activeWordColor
                        : (widget.subtitleStyle.bgType == SubtitleBgType.solid &&
                                (widget.subtitleStyle.bgColor == const Color(0xFFFFD600) ||
                                    widget.subtitleStyle.bgColor == Colors.yellow ||
                                    widget.subtitleStyle.bgColor == const Color(0xFFD6FF00) ||
                                    widget.subtitleStyle.bgColor == const Color(0xFF00FF2A) ||
                                    widget.subtitleStyle.bgColor == const Color(0xFFF3ECE0))
                            ? Colors.black
                            : widget.subtitleStyle.textColor),
                    shadows: shadows,
                    foreground: outlinePaint,
                  ),
                ),
              );
            }).toList()
          : [
              Container(
                padding: widget.subtitleStyle.bgType == SubtitleBgType.solid
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                    : EdgeInsets.zero,
                decoration: widget.subtitleStyle.bgType == SubtitleBgType.solid
                    ? BoxDecoration(
                        color: widget.subtitleStyle.bgColor,
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: Text(
                  line.text.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: _getGoogleFontStyle(
                    fontSize: previewFontSize,
                    color: widget.subtitleStyle.textColor,
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

  Widget _applySubtitleTransition(Widget child, SubtitleLine line) {
    final elapsedMs = (widget.currentPosition - line.startTime).inMilliseconds;
    final remainingMs = (line.endTime - widget.currentPosition).inMilliseconds;

    final double enter = (elapsedMs / 280.0).clamp(0.0, 1.0);
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

  Widget _applyVideoTransition(Widget child) {
    final relTimeMs = (widget.currentPosition - widget.clip.startTime).inMilliseconds;

    VideoTransitionPoint? activePoint;
    for (final pt in widget.layout.transitionPoints) {
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
    } else if (widget.layout.transitionPoints.isEmpty) {
      transType = widget.layout.videoTransition.toLowerCase().trim();
      final totalMs = (widget.layout.videoTransitionDuration * 1000).round();
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

      case 'spin 360':
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
