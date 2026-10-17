import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';

class FFmpegRenderService {
  /// Converts a Flutter Color into ASS format: &HAABBGGRR& (or &H00BBGGRR&)
  static String _colorToAss(Color c, {int alpha = 0}) {
    final a = alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = c.blue.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = c.green.toRadixString(16).padLeft(2, '0').toUpperCase();
    final r = c.red.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H$a$b$g$r&';
  }

  /// Formats Duration into ASS timestamp: H:MM:SS.cs
  static String _formatAssTime(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final centiseconds = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds.$centiseconds';
  }

  /// Creates a styled ASS subtitle file matching the exact tools from the screenshot
  static Future<File> _generateAssSubtitleFile({
    required ClipSegment clip,
    required SubtitleStyleConfig style,
    required Directory workDir,
  }) async {
    final file = File('${workDir.path}/subs_${clip.id}.ass');
    final primaryAss = _colorToAss(style.textColor);
    final strokeAss = _colorToAss(style.strokeColor);
    final backAss = _colorToAss(style.bgColor);

    int alignment = 2; // Bottom center
    int marginV = 280;
    if (style.position == SubtitlePosition.atas) {
      alignment = 8;
      marginV = 320;
    } else if (style.position == SubtitlePosition.tengah) {
      alignment = 5;
      marginV = 0;
    }

    // BorderStyle: 3 is opaque box (Solid), 1 is standard outline + shadow
    final borderStyle = style.bgType == SubtitleBgType.solid ? 3 : 1;
    final outlineSize = style.bgType == SubtitleBgType.solid ? 8 : (style.strokeWidth.round());

    final buffer = StringBuffer();
    buffer.writeln('[Script Info]');
    buffer.writeln('ScriptType: v4.00+');
    buffer.writeln('PlayResX: 1080');
    buffer.writeln('PlayResY: 1920');
    buffer.writeln('WrapStyle: 0');
    buffer.writeln('');
    buffer.writeln('[V4+ Styles]');
    buffer.writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding');
    buffer.writeln('Style: ViralStyle,${style.fontName},${style.fontSize.round() * 1.5},$primaryAss,&H0000FFFF&,$strokeAss,$backAss,-1,0,0,0,100,100,0,0,$borderStyle,$outlineSize,2,$alignment,60,60,$marginV,1');
    buffer.writeln('');
    buffer.writeln('[Events]');
    buffer.writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');

    // Generate dialogue lines
    for (final line in clip.subtitles) {
      final lineRelStart = line.startTime > clip.startTime ? line.startTime - clip.startTime : Duration.zero;
      final lineRelEnd = line.endTime > clip.startTime ? line.endTime - clip.startTime : const Duration(seconds: 1);

      if (style.wordByWord && line.words.isNotEmpty) {
        // "Tampilkan satu kata per saat"
        for (final w in line.words) {
          final wRelStart = w.startTime > clip.startTime ? w.startTime - clip.startTime : Duration.zero;
          final wRelEnd = w.endTime > clip.startTime ? w.endTime - clip.startTime : wRelStart + const Duration(milliseconds: 350);
          final text = w.word.toUpperCase();
          buffer.writeln('Dialogue: 0,${_formatAssTime(wRelStart)},${_formatAssTime(wRelEnd)},ViralStyle,,0,0,0,,$text');
        }
      } else {
        final plainText = line.text.toUpperCase();
        buffer.writeln('Dialogue: 0,${_formatAssTime(lineRelStart)},${_formatAssTime(lineRelEnd)},ViralStyle,,0,0,0,,$plainText');
      }
    }

    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Renders 9:16 video on-device with Layout, Subtitles, Hook, and Watermark
  static Future<File> renderClip({
    required File sourceVideoFile,
    required ClipSegment clip,
    required LayoutConfig layout,
    required SubtitleStyleConfig subtitleStyle,
    required Function(double progress) onProgress,
    required Function(String status) onStatus,
  }) async {
    final workDir = await getTemporaryDirectory();
    final outputPath = '${workDir.path}/short_export_${DateTime.now().millisecondsSinceEpoch}.mp4';

    onStatus('Menyiapkan subtitle dan komposisi...');
    final assFile = await _generateAssSubtitleFile(
      clip: clip,
      style: subtitleStyle,
      workDir: workDir,
    );

    final escapedAssPath = assFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');

    // Filter Graph based on Komposisi Template and Crop Position
    String filterGraph = '';
    if (layout.template == KomposisiTemplate.standar) {
      filterGraph =
          '[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=25:5,eq=brightness=-0.15[bg];'
          '[0:v]scale=1080:-1[fg];'
          '[bg][fg]overlay=(W-w)/2:(H-h)/2[vbase]';
    } else {
      // Layar Penuh or Dinamis: use cropPosition (0.0 = Kiri, 0.5 = Tengah, 1.0 = Kanan)
      final xExpr = '(iw-ih*9/16)*${layout.cropPosition}';
      filterGraph =
          '[0:v]crop=ih*9/16:ih:$xExpr:0,scale=1080:1920[vbase]';
    }

    // Attach Hook (Teks besar yang muncul di atas klip)
    String currentChain = 'vbase';
    if (layout.hook.text.trim().isNotEmpty) {
      final safeHook = layout.hook.text.replaceAll("'", "").replaceAll(':', '');
      final hookHex = '0x${layout.hook.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      final hookDuration = layout.hook.durationSeconds;

      filterGraph += ';[$currentChain]drawtext=text=\'$safeHook\':'
          'font=Impact:fontsize=56:fontcolor=$hookHex:borderw=4:bordercolor=black:'
          'x=(w-text_w)/2:y=180:enable=\'between(t,0,$hookDuration)\'[vhook]';
      currentChain = 'vhook';
    }

    // Attach Watermark if present
    if (layout.watermark.text.trim().isNotEmpty) {
      final safeWm = layout.watermark.text.replaceAll("'", "").replaceAll(':', '');
      final yPos = layout.watermark.position == 'Atas' ? '100' : 'h-120';
      filterGraph += ';[$currentChain]drawtext=text=\'$safeWm\':'
          'fontsize=32:fontcolor=white@0.8:borderw=2:bordercolor=black:'
          'x=w-text_w-40:y=$yPos[vwm]';
      currentChain = 'vwm';
    }

    // Apply Video Transition effect on video if set (multi-point support)
    int transIdx = 0;
    final points = layout.transitionPoints.isNotEmpty
        ? layout.transitionPoints
        : [
            VideoTransitionPoint(
              id: 't0',
              timeOffset: Duration.zero,
              transitionType: layout.videoTransition,
              duration: layout.videoTransitionDuration,
            ),
          ];

    for (final pt in points) {
      if (pt.transitionType == 'none' || pt.transitionType.isEmpty) continue;
      final transType = pt.transitionType.toLowerCase().trim();
      final transDur = pt.duration > 0 ? pt.duration : 0.8;
      final stSec = (pt.timeOffset.inMilliseconds / 1000.0).toStringAsFixed(2);
      final nextChain = 'vtrans_$transIdx';
      transIdx++;

      if (transType.contains('white flash')) {
        filterGraph += ';[$currentChain]fade=t=in:st=$stSec:d=$transDur:color=white[$nextChain]';
        currentChain = nextChain;
      } else if (transType.contains('black flash') || transType.contains('fade') || transType.contains('dissolve')) {
        filterGraph += ';[$currentChain]fade=t=in:st=$stSec:d=$transDur:color=black[$nextChain]';
        currentChain = nextChain;
      }
    }

    // Burn-in ASS Subtitle
    filterGraph += ';[$currentChain]ass=\'$escapedAssPath\'[vout]';

    final startSec = clip.startTime.inSeconds;
    final durationSec = clip.duration.inSeconds.clamp(5, 180);

    final cmd = '-y '
        '-ss $startSec '
        '-i "${sourceVideoFile.path}" '
        '-t $durationSec '
        '-filter_complex "$filterGraph" '
        '-map "[vout]" '
        '-map 0:a? '
        '-c:v libx264 '
        '-preset ultrafast '
        '-crf 23 '
        '-c:a aac '
        '-b:a 128k '
        '-movflags +faststart '
        '"$outputPath"';

    onStatus('Merender video vertikal 9:16 di HP...');

    final session = await FFmpegKit.executeAsync(
      cmd,
      (session) async {},
      (log) {},
      (statistics) {
        final timeMs = statistics.getTime();
        if (timeMs > 0 && durationSec > 0) {
          final p = (timeMs / (durationSec * 1000)).clamp(0.0, 0.99);
          onProgress(p);
        }
      },
    );

    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      onProgress(1.0);
      onStatus('Render selesai! Menyimpan ke Galeri HP...');
      final exportedFile = File(outputPath);
      try {
        await GallerySaver.saveVideo(exportedFile.path, albumName: 'YTShortClipper');
      } catch (e) {
        // Fallback
      }
      return exportedFile;
    } else {
      final logs = await session.getAllLogsAsString();
      throw Exception('Gagal merender video: $logs');
    }
  }
}
