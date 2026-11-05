import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';

class FFmpegRenderService {
  /// Probes the exact duration of a local video file using FFmpeg
  static Future<Duration?> probeVideoDuration(File videoFile) async {
    try {
      final session = await FFmpegKit.execute('-hide_banner -i "${videoFile.path}"');
      final logs = await session.getAllLogsAsString();
      if (logs != null && logs.isNotEmpty) {
        final match = RegExp(r'Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d{2})').firstMatch(logs);
        if (match != null) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final s = int.parse(match.group(3)!);
          final cs = int.parse(match.group(4)!);
          final d = Duration(hours: h, minutes: m, seconds: s, milliseconds: cs * 10);
          if (d.inMilliseconds > 0) return d;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Normalizes an imported video (from Gallery or B-roll) so that:
  /// 1. Width and height are exact multiples of 64 (prevents GPU MediaCodec SurfaceTexture diagonal stride skew & green lines on Android).
  /// 2. Rotation metadata from phone cameras is baked into the frame pixels and stripped.
  /// 3. Pixel format is standard 8-bit yuv420p H.264 Baseline with SAR 1:1 for 100% hardware compatibility.
  static Future<File> normalizeVideoForPlayback(
    File inputFile, {
    Function(String status)? onStatus,
  }) async {
    try {
      if (!await inputFile.exists()) return inputFile;
      final workDir = await getTemporaryDirectory();
      final fileLen = await inputFile.length();
      final safeBase = inputFile.path
          .split(Platform.pathSeparator)
          .last
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\.]'), '_');
      final normalizedPath = '${workDir.path}/norm64_${fileLen}_$safeBase.mp4';
      final normalizedFile = File(normalizedPath);

      if (await normalizedFile.exists() && await normalizedFile.length() > 1024) {
        return normalizedFile;
      }

      onStatus?.call('Mengoptimalkan format & resolusi video agar tidak rusak...');

      // Scale width & height to exact multiples of 64 (e.g. 640x1152 or 1280x704)
      // so every Android GPU (Mali/Adreno/PowerVR) has zero stride padding mismatch.
      const vf =
          "scale='max(64,trunc(iw*min(1,1280/max(iw,ih))/64)*64)':'max(64,trunc(ih*min(1,1280/max(iw,ih))/64)*64)',setsar=1:1,format=yuv420p";

      final cmd = '-y '
          '-i "${inputFile.path}" '
          '-vf "$vf" '
          '-metadata:s:v:0 rotate=0 '
          '-c:v libx264 '
          '-profile:v baseline '
          '-level 3.1 '
          '-pix_fmt yuv420p '
          '-preset ultrafast '
          '-crf 20 '
          '-c:a aac '
          '-b:a 128k '
          '-ac 2 '
          '-ar 44100 '
          '-movflags +faststart '
          '"$normalizedPath"';

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) &&
          await normalizedFile.exists() &&
          await normalizedFile.length() > 1024) {
        return normalizedFile;
      }
    } catch (_) {}
    return inputFile;
  }

  /// Checks if a file path points to a video file
  static bool isVideoFilePath(String? path) {
    if (path == null || path.isEmpty) return false;
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.m4v');
  }

  /// Converts a Flutter Color into ASS format: &HAABBGGRR& (or &H00BBGGRR&)
  static String _colorToAss(Color c, {int alpha = 0}) {
    final a = alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = ((c.b * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = ((c.g * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0').toUpperCase();
    final r = ((c.r * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H$a$b$g$r&';
  }

  /// Finds a valid Android system font file for FFmpeg drawtext
  static String? _findAndroidSystemFont() {
    const candidates = [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/Roboto-Bold.ttf',
      '/system/fonts/DroidSans.ttf',
      '/system/fonts/DroidSans-Bold.ttf',
    ];
    for (final p in candidates) {
      try {
        if (File(p).existsSync()) return p;
      } catch (_) {}
    }
    return null;
  }

  /// Formats Duration into ASS timestamp: H:MM:SS.cs
  static String _formatAssTime(Duration d) {
    final safe = d.isNegative ? Duration.zero : d;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    final centiseconds = (safe.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds.$centiseconds';
  }

  /// Creates a styled ASS subtitle file matching the exact tools from the studio editor
  static Future<File> _generateAssSubtitleFile({
    required ClipSegment clip,
    required SubtitleStyleConfig style,
    required Directory workDir,
    required int playResX,
    required int playResY,
  }) async {
    final file = File('${workDir.path}/subs_${clip.id}.ass');
    final isLightSolidBg = style.bgType == SubtitleBgType.solid &&
        (style.bgColor == const Color(0xFFFFD600) ||
            style.bgColor == Colors.yellow ||
            style.bgColor == const Color(0xFFD6FF00) ||
            style.bgColor == const Color(0xFF00FF2A) ||
            style.bgColor == const Color(0xFFF3ECE0));
    final effectiveTextColor = isLightSolidBg ? Colors.black : style.textColor;

    final primaryAss = _colorToAss(effectiveTextColor);
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
    buffer.writeln('PlayResX: $playResX');
    buffer.writeln('PlayResY: $playResY');
    buffer.writeln('WrapStyle: 0');
    buffer.writeln('');
    buffer.writeln('[V4+ Styles]');
    buffer.writeln(
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding');
    buffer.writeln(
        'Style: ViralStyle,${style.fontName},${(style.fontSize * 1.1).round()},$primaryAss,&H0000FFFF&,$strokeAss,$backAss,-1,${style.isItalic ? -1 : 0},0,0,100,100,0,0,$borderStyle,$outlineSize,2,$alignment,60,60,$marginV,1');
    buffer.writeln('');
    buffer.writeln('[Events]');
    buffer.writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');

    // Generate dialogue lines
    for (final line in clip.subtitles) {
      final lineRelStart = line.startTime > clip.startTime ? line.startTime - clip.startTime : Duration.zero;
      final lineRelEnd = line.endTime > clip.startTime ? line.endTime - clip.startTime : lineRelStart + const Duration(seconds: 1);

      if (style.wordByWord && line.words.isNotEmpty) {
        for (final w in line.words) {
          final wRelStart = w.startTime > clip.startTime ? w.startTime - clip.startTime : Duration.zero;
          final wRelEnd = w.endTime > clip.startTime ? w.endTime - clip.startTime : wRelStart + const Duration(milliseconds: 350);
          final text = w.word.toUpperCase().replaceAll('\n', ' ');
          buffer.writeln('Dialogue: 0,${_formatAssTime(wRelStart)},${_formatAssTime(wRelEnd)},ViralStyle,,0,0,0,,$text');
        }
      } else {
        final plainText = line.text.toUpperCase().replaceAll('\n', ' ');
        buffer.writeln('Dialogue: 0,${_formatAssTime(lineRelStart)},${_formatAssTime(lineRelEnd)},ViralStyle,,0,0,0,,$plainText');
      }
    }

    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Prepares local files for any active B-rolls (downloads stock URLs if needed)
  static Future<List<Map<String, dynamic>>> _prepareBrollInputs(
    ClipSegment clip,
    Directory workDir,
  ) async {
    final List<Map<String, dynamic>> prepared = [];
    for (int i = 0; i < clip.brolls.length; i++) {
      final b = clip.brolls[i];
      File? bFile;
      bool isVideo = false;

      if (b.filePath != null && b.filePath!.isNotEmpty) {
        final f = File(b.filePath!);
        if (await f.exists()) {
          bFile = f;
          isVideo = isVideoFilePath(f.path);
        }
      } else if (b.visualUrl != null && b.visualUrl!.isNotEmpty) {
        try {
          final res = await http.get(Uri.parse(b.visualUrl!)).timeout(const Duration(seconds: 10));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            final imgFile = File('${workDir.path}/broll_stock_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await imgFile.writeAsBytes(res.bodyBytes);
            bFile = imgFile;
            isVideo = false;
          }
        } catch (_) {}
      }

      if (bFile != null) {
        final relStartMs = (b.startTime - clip.startTime).inMilliseconds.clamp(0, clip.duration.inMilliseconds);
        final relEndMs = (relStartMs + b.duration.inMilliseconds).clamp(0, clip.duration.inMilliseconds);
        if (relEndMs > relStartMs) {
          prepared.add({
            'file': bFile,
            'isVideo': isVideo,
            'startSec': (relStartMs / 1000.0).toStringAsFixed(2),
            'endSec': (relEndMs / 1000.0).toStringAsFixed(2),
            'durSec': ((relEndMs - relStartMs) / 1000.0).toStringAsFixed(2),
          });
        }
      }
    }
    return prepared;
  }

  /// Renders 9:16 video on-device with Layout, B-rolls, Subtitles, Hook, Watermark, and Audio Settings
  static Future<File> renderClip({
    required File sourceVideoFile,
    required ClipSegment clip,
    required LayoutConfig layout,
    required SubtitleStyleConfig subtitleStyle,
    bool cleanAudio = false,
    double videoVolumeDb = 0.0,
    required Function(double progress) onProgress,
    required Function(String status) onStatus,
  }) async {
    final workDir = await getTemporaryDirectory();
    final outputPath = '${workDir.path}/short_export_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Use 1088x1920 (both 1088 = 17*64 and 1920 = 30*64 are exact multiples of 64!)
    // This guarantees zero GPU stride distortion on all Android devices while keeping full 1080p HD quality.
    const int outW = 1088;
    const int outH = 1920;

    onStatus('Menyiapkan subtitle, B-roll, dan komposisi...');
    final assFile = await _generateAssSubtitleFile(
      clip: clip,
      style: subtitleStyle,
      workDir: workDir,
      playResX: outW,
      playResY: outH,
    );

    final preparedBrolls = await _prepareBrollInputs(clip, workDir);
    final escapedAssPath = assFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');

    // Filter Graph based on Komposisi Template and Crop Position
    String filterGraph = '';
    final cp = layout.cropPosition.clamp(0.0, 1.0);
    if (layout.template == KomposisiTemplate.standar) {
      filterGraph =
          '[0:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,boxblur=25:5,eq=brightness=-0.15[bg];'
          '[0:v]scale=$outW:-2[fg];'
          '[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1:1[vbase]';
    } else {
      // Layar Penuh or Dinamis: use cropPosition (0.0 = Kiri, 0.5 = Tengah, 1.0 = Kanan)
      filterGraph =
          '[0:v]crop=w=\'trunc(min(iw,ih*9/16)/2)*2\':h=ih:x=\'trunc((iw-out_w)*$cp/2)*2\':y=0,scale=$outW:$outH,setsar=1:1[vbase]';
    }

    String currentChain = 'vbase';

    // Overlay any active B-rolls onto the video timeline cleanly
    for (int i = 0; i < preparedBrolls.length; i++) {
      final bInfo = preparedBrolls[i];
      final inputIdx = i + 1;
      final st = bInfo['startSec'];
      final en = bInfo['endSec'];
      final dur = bInfo['durSec'];
      final isVideo = bInfo['isVideo'] as bool;
      final bLabel = 'vbroll_$i';
      final nextChain = 'vwithbroll_$i';

      if (isVideo) {
        filterGraph +=
            ';[$inputIdx:v]scale=$outW:$outH,setsar=1:1,trim=0:$dur,setpts=PTS-STARTPTS+$st/TB[$bLabel]'
            ';[$currentChain][$bLabel]overlay=0:0:enable=\'between(t,$st,$en)\':eof_action=pass[$nextChain]';
      } else {
        filterGraph +=
            ';[$inputIdx:v]scale=$outW:$outH,setsar=1:1[$bLabel]'
            ';[$currentChain][$bLabel]overlay=0:0:enable=\'between(t,$st,$en)\':eof_action=pass[$nextChain]';
      }
      currentChain = nextChain;
    }

    final fontPath = _findAndroidSystemFont();
    final fontArg = fontPath != null ? 'fontfile=\'$fontPath\':' : '';

    // Attach Hook (Teks besar yang muncul di atas klip)
    if (layout.hook.text.trim().isNotEmpty && fontPath != null) {
      final safeHook = layout.hook.text.replaceAll("'", "").replaceAll(':', ' ').replaceAll('"', '').replaceAll('\\', '');
      final hookHex = '0x${layout.hook.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      final hookDuration = layout.hook.durationSeconds;

      filterGraph += ';[$currentChain]drawtext=${fontArg}text=\'$safeHook\':'
          'fontsize=54:fontcolor=$hookHex:borderw=4:bordercolor=black:'
          'x=(w-text_w)/2:y=180:enable=\'between(t,0,$hookDuration)\'[vhook]';
      currentChain = 'vhook';
    }

    // Attach Watermark if present
    if (layout.watermark.text.trim().isNotEmpty && fontPath != null) {
      final safeWm = layout.watermark.text.replaceAll("'", "").replaceAll(':', ' ').replaceAll('"', '').replaceAll('\\', '');
      final yPos = layout.watermark.position == 'Atas' ? '100' : 'h-120';
      filterGraph += ';[$currentChain]drawtext=${fontArg}text=\'$safeWm\':'
          'fontsize=32:fontcolor=white@0.85:borderw=2:bordercolor=black:'
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

    // Burn-in ASS Subtitle only if subtitles exist, otherwise just finalize pixel format
    if (clip.subtitles.isNotEmpty) {
      filterGraph += ';[$currentChain]ass=\'$escapedAssPath\',format=yuv420p[vout]';
    } else {
      filterGraph += ';[$currentChain]format=yuv420p[vout]';
    }

    final startSec = (clip.startTime.inMilliseconds / 1000.0).toStringAsFixed(2);
    final durationSec = (clip.duration.inMilliseconds / 1000.0).clamp(1.0, 180.0);

    // Extra inputs for B-rolls
    final extraInputs = StringBuffer();
    for (final bInfo in preparedBrolls) {
      final bFile = bInfo['file'] as File;
      final isVideo = bInfo['isVideo'] as bool;
      if (isVideo) {
        extraInputs.write('-stream_loop -1 -i "${bFile.path}" ');
      } else {
        extraInputs.write('-loop 1 -i "${bFile.path}" ');
      }
    }

    // Audio filter for volume & clean audio
    final List<String> audioFilters = [];
    if (cleanAudio) {
      audioFilters.add('highpass=f=80,lowpass=f=8000,dynaudnorm=f=150:g=15');
    }
    if (videoVolumeDb.abs() > 0.1) {
      audioFilters.add('volume=${videoVolumeDb.toStringAsFixed(1)}dB');
    }
    final afArg = audioFilters.isNotEmpty ? '-af "${audioFilters.join(',')}" ' : '';

    final cmd = '-y '
        '-ss $startSec '
        '-i "${sourceVideoFile.path}" '
        '${extraInputs.toString()}'
        '-filter_complex "$filterGraph" '
        '-map "[vout]" '
        '-map 0:a? '
        '$afArg'
        '-c:v libx264 '
        '-profile:v baseline '
        '-level 3.1 '
        '-pix_fmt yuv420p '
        '-preset ultrafast '
        '-crf 22 '
        '-c:a aac '
        '-b:a 128k '
        '-movflags +faststart '
        '-t ${durationSec.toStringAsFixed(2)} '
        '"$outputPath"';

    onStatus('Merender video vertikal 9:16 di HP...');

    final completer = Completer<Session>();
    await FFmpegKit.executeAsync(
      cmd,
      (completedSession) {
        if (!completer.isCompleted) {
          completer.complete(completedSession);
        }
      },
      (log) {},
      (statistics) {
        final timeMs = statistics.getTime();
        if (timeMs > 0 && durationSec > 0) {
          final p = (timeMs / (durationSec * 1000)).clamp(0.0, 0.99);
          onProgress(p);
        }
      },
    );

    final session = await completer.future;
    var returnCode = await session.getReturnCode();
    Session? fallbackSession;

    if (!ReturnCode.isSuccess(returnCode)) {
      // Safe fallback: jika filter teks/broll kompleks terbentur di device tertentu, render 9:16 dasar agar tetap berhasil 100%
      onStatus('Menjalankan render pengaman (mode stabil)...');
      try {
        final outF = File(outputPath);
        if (await outF.exists()) {
          await outF.delete();
        }
      } catch (_) {}

      final fallbackFilter = (layout.template == KomposisiTemplate.standar)
          ? '[0:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,boxblur=25:5[bg];[0:v]scale=$outW:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1:1,format=yuv420p[vout]'
          : '[0:v]crop=w=\'trunc(min(iw,ih*9/16)/2)*2\':h=ih:x=\'trunc((iw-out_w)*$cp/2)*2\':y=0,scale=$outW:$outH,setsar=1:1,format=yuv420p[vout]';

      final fallbackCmd = '-y -ss $startSec -i "${sourceVideoFile.path}" '
          '-filter_complex "$fallbackFilter" -map "[vout]" -map 0:a? $afArg '
          '-c:v libx264 -profile:v baseline -level 3.1 -pix_fmt yuv420p -preset ultrafast -crf 22 -c:a aac -b:a 128k -movflags +faststart -t ${durationSec.toStringAsFixed(2)} "$outputPath"';

      fallbackSession = await FFmpegKit.execute(fallbackCmd);
      returnCode = await fallbackSession.getReturnCode();
    }

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
      final activeSession = fallbackSession ?? session;
      final logs = await activeSession.getAllLogsAsString();
      throw Exception('Gagal merender video: $logs');
    }
  }
}
