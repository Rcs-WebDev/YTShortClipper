import 'package:flutter/material.dart';

enum KomposisiTemplate {
  standar,      // Fit with background
  layarPenuh,   // Full 9:16 crop
  dinamis,      // Dynamic face track / split
  videoPlusFoto,// Video + photo overlay
}

enum HookAnimationType {
  spring,
  fade,
  slide,
}

class HookConfig {
  String text;
  Color color;
  double durationSeconds; // 1.5, 2.5, 4.0, 6.0, dll
  double fontSize; // Ukuran font Hook Headline Banner (default: 24.0)
  HookAnimationType animation;

  HookConfig({
    this.text = 'JODOH GARA-GARA TREND TIKTOK INI',
    this.color = Colors.white,
    this.durationSeconds = 2.5,
    this.fontSize = 24.0,
    this.animation = HookAnimationType.spring,
  });

  HookConfig copyWith({
    String? text,
    Color? color,
    double? durationSeconds,
    double? fontSize,
    HookAnimationType? animation,
  }) {
    return HookConfig(
      text: text ?? this.text,
      color: color ?? this.color,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fontSize: fontSize ?? this.fontSize,
      animation: animation ?? this.animation,
    );
  }
}

class WatermarkConfig {
  String text;
  String position; // 'Atas', 'Tengah', 'Bawah', 'Kiri Atas', 'Kiri Bawah'
  Color color;
  double opacity;

  WatermarkConfig({
    this.text = '@channelmu',
    this.position = 'Bawah',
    this.color = Colors.white,
    this.opacity = 0.85,
  });

  WatermarkConfig copyWith({
    String? text,
    String? position,
    Color? color,
    double? opacity,
  }) {
    return WatermarkConfig(
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
    );
  }
}

/// Titik penanda Efek Transisi Video Utama di menit/detik tertentu
class VideoTransitionPoint {
  final String id;
  Duration timeOffset; // Posisi relatif dari awal klip (misal: 00:00, 00:15, dll)
  String transitionType; // 'fade in', 'dissolve', 'zoom in', 'white flash', 'glitch', 'wipe horizontal', dll
  double duration; // Durasi efek dalam detik (default 0.8s)

  VideoTransitionPoint({
    required this.id,
    required this.timeOffset,
    required this.transitionType,
    this.duration = 0.8,
  });

  VideoTransitionPoint copyWith({
    String? id,
    Duration? timeOffset,
    String? transitionType,
    double? duration,
  }) {
    return VideoTransitionPoint(
      id: id ?? this.id,
      timeOffset: timeOffset ?? this.timeOffset,
      transitionType: transitionType ?? this.transitionType,
      duration: duration ?? this.duration,
    );
  }
}

class LayoutConfig {
  KomposisiTemplate template;
  double cropPosition; // 0.0 (Kiri) to 1.0 (Kanan), default 0.50 (50% Tengah)
  HookConfig hook;
  WatermarkConfig watermark;
  String videoTransition; // Transisi video utama di awal
  double videoTransitionDuration;
  List<VideoTransitionPoint> transitionPoints; // Daftar transisi video di detik/menit tertentu

  LayoutConfig({
    this.template = KomposisiTemplate.layarPenuh,
    this.cropPosition = 0.50,
    HookConfig? hook,
    WatermarkConfig? watermark,
    this.videoTransition = 'fade in',
    this.videoTransitionDuration = 0.8,
    List<VideoTransitionPoint>? transitionPoints,
  })  : hook = hook ?? HookConfig(),
        watermark = watermark ?? WatermarkConfig(),
        transitionPoints = transitionPoints ?? [
          VideoTransitionPoint(
            id: 'trans_0',
            timeOffset: Duration.zero,
            transitionType: videoTransition,
            duration: videoTransitionDuration,
          ),
        ];

  LayoutConfig copyWith({
    KomposisiTemplate? template,
    double? cropPosition,
    HookConfig? hook,
    WatermarkConfig? watermark,
    String? videoTransition,
    double? videoTransitionDuration,
    List<VideoTransitionPoint>? transitionPoints,
  }) {
    return LayoutConfig(
      template: template ?? this.template,
      cropPosition: cropPosition ?? this.cropPosition,
      hook: hook ?? this.hook,
      watermark: watermark ?? this.watermark,
      videoTransition: videoTransition ?? this.videoTransition,
      videoTransitionDuration: videoTransitionDuration ?? this.videoTransitionDuration,
      transitionPoints: transitionPoints ?? this.transitionPoints.map((p) => p.copyWith()).toList(),
    );
  }
}
