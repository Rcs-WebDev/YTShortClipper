class SubtitleWord {
  String word;
  Duration startTime;
  Duration endTime;

  SubtitleWord({
    required this.word,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'startTimeMs': startTime.inMilliseconds,
    'endTimeMs': endTime.inMilliseconds,
  };

  factory SubtitleWord.fromJson(Map<String, dynamic> json) => SubtitleWord(
    word: json['word'] ?? '',
    startTime: Duration(milliseconds: json['startTimeMs'] ?? 0),
    endTime: Duration(milliseconds: json['endTimeMs'] ?? 0),
  );
}

class SubtitleLine {
  String text;
  Duration startTime;
  Duration endTime;
  List<SubtitleWord> words;
  String transition; // 'dissolve', 'wipe', 'fade in', 'fade out', 'zoom in', 'zoom out', 'slide', 'glitch', 'roll', 'whip', 'spin', 'iris'

  SubtitleLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.words,
    this.transition = 'fade in',
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'startTimeMs': startTime.inMilliseconds,
    'endTimeMs': endTime.inMilliseconds,
    'words': words.map((w) => w.toJson()).toList(),
    'transition': transition,
  };

  factory SubtitleLine.fromJson(Map<String, dynamic> json) => SubtitleLine(
    text: json['text'] ?? '',
    startTime: Duration(milliseconds: json['startTimeMs'] ?? 0),
    endTime: Duration(milliseconds: json['endTimeMs'] ?? 0),
    words: (json['words'] as List<dynamic>? ?? [])
        .map((w) => SubtitleWord.fromJson(w))
        .toList(),
    transition: json['transition'] ?? 'fade in',
  );
}

class BrollItem {
  final String id;
  final String title;
  final Duration startTime;
  final Duration duration;
  final String? localPath;
  final String category;
  final String? visualUrl;

  String? get filePath => localPath;

  BrollItem({
    String? id,
    required this.title,
    required this.startTime,
    required this.duration,
    String? localPath,
    String? filePath,
    this.category = 'General',
    this.visualUrl,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
        localPath = localPath ?? filePath;

  Duration get endTime => startTime + duration;

  BrollItem copyWith({
    String? id,
    String? title,
    Duration? startTime,
    Duration? duration,
    String? localPath,
    String? category,
    String? visualUrl,
  }) {
    return BrollItem(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      localPath: localPath ?? this.localPath,
      category: category ?? this.category,
      visualUrl: visualUrl ?? this.visualUrl,
    );
  }
}

class ClipSegment {
  final String id;
  String title;
  String hook;
  String viralReason;
  double viralityScore; // 0.0 to 10.0
  Duration startTime;
  Duration endTime;
  List<SubtitleLine> subtitles;
  List<BrollItem> brolls;

  ClipSegment({
    required this.id,
    required this.title,
    required this.hook,
    required this.viralReason,
    required this.viralityScore,
    required this.startTime,
    required this.endTime,
    required this.subtitles,
    List<BrollItem>? brolls,
  }) : brolls = brolls ?? [];

  String get summary => viralReason;

  Duration get duration => endTime - startTime;

  ClipSegment copyWith({
    String? id,
    String? title,
    String? hook,
    String? viralReason,
    double? viralityScore,
    Duration? startTime,
    Duration? endTime,
    List<SubtitleLine>? subtitles,
    List<BrollItem>? brolls,
  }) {
    return ClipSegment(
      id: id ?? this.id,
      title: title ?? this.title,
      hook: hook ?? this.hook,
      viralReason: viralReason ?? this.viralReason,
      viralityScore: viralityScore ?? this.viralityScore,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      subtitles: subtitles ?? this.subtitles,
      brolls: brolls ?? this.brolls.map((b) => b.copyWith()).toList(),
    );
  }
}
