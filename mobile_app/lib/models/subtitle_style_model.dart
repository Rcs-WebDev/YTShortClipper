import 'package:flutter/material.dart';

enum SubtitlePresetType {
  bold,
  pop,
  outline,
  gradient,
}

enum SubtitleFontFamily {
  anton,
  bebas,
  montserrat,
  poppins,
  playfair,
  impact,
  oswald,
  lora,
  cinzel,
}

enum SubtitleBgType {
  solid,
  glow,
  none,
  boxRounded,
  outlineOnly,
}

enum SubtitlePosition {
  atas,
  tengah,
  bawah,
}

class FontStyleItem {
  final String id;
  final String name;
  final String? badge; // 'New', '⚡', etc.
  final List<String> categories; // 'All', 'New', 'Animated', 'Trend', 'Premium', etc.
  final SubtitleFontFamily fontFamily;
  final Color textColor;
  final Color? activeWordColor;
  final Color? bgColor;
  final SubtitleBgType bgType;
  final Color strokeColor;
  final double strokeWidth;
  final bool isItalic;
  final bool has3dShadow;
  final bool isOutlineOnly;

  const FontStyleItem({
    required this.id,
    required this.name,
    this.badge,
    required this.categories,
    required this.fontFamily,
    required this.textColor,
    this.activeWordColor,
    this.bgColor,
    this.bgType = SubtitleBgType.none,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.isItalic = false,
    this.has3dShadow = false,
    this.isOutlineOnly = false,
  });
}

class SubtitleStyleConfig {
  SubtitlePresetType preset;
  SubtitleFontFamily fontFamily;
  double fontSize; // e.g. 90px
  Color textColor;
  Color activeWordColor;
  Color strokeColor;
  double strokeWidth;
  SubtitlePosition position;
  SubtitleBgType bgType;
  Color bgColor;
  double bgOpacity;
  bool wordByWord; // "Tampilkan satu kata per saat"
  bool isItalic;
  bool has3dShadow;
  bool isOutlineOnly;
  String? selectedStyleId;

  SubtitleStyleConfig({
    this.preset = SubtitlePresetType.bold,
    this.fontFamily = SubtitleFontFamily.poppins,
    this.fontSize = 90.0,
    this.textColor = Colors.white,
    this.activeWordColor = const Color(0xFFFFE600),
    this.strokeColor = Colors.black,
    this.strokeWidth = 4.0,
    this.position = SubtitlePosition.bawah,
    this.bgType = SubtitleBgType.solid,
    this.bgColor = const Color(0xFFFFD600), // Yellow background box in screenshot
    this.bgOpacity = 1.0,
    this.wordByWord = false,
    this.isItalic = false,
    this.has3dShadow = false,
    this.isOutlineOnly = false,
    this.selectedStyleId = 'beast',
  });

  String get fontName {
    switch (fontFamily) {
      case SubtitleFontFamily.anton:
        return 'Anton';
      case SubtitleFontFamily.bebas:
        return 'Bebas Neue';
      case SubtitleFontFamily.montserrat:
        return 'Montserrat';
      case SubtitleFontFamily.poppins:
        return 'Poppins';
      case SubtitleFontFamily.playfair:
        return 'Playfair Display';
      case SubtitleFontFamily.impact:
        return 'Impact';
      case SubtitleFontFamily.oswald:
        return 'Oswald';
      case SubtitleFontFamily.lora:
        return 'Lora';
      case SubtitleFontFamily.cinzel:
        return 'Cinzel';
    }
  }

  SubtitleStyleConfig copyWith({
    SubtitlePresetType? preset,
    SubtitleFontFamily? fontFamily,
    double? fontSize,
    Color? textColor,
    Color? activeWordColor,
    Color? strokeColor,
    double? strokeWidth,
    SubtitlePosition? position,
    SubtitleBgType? bgType,
    Color? bgColor,
    double? bgOpacity,
    bool? wordByWord,
    bool? isItalic,
    bool? has3dShadow,
    bool? isOutlineOnly,
    String? selectedStyleId,
  }) {
    return SubtitleStyleConfig(
      preset: preset ?? this.preset,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      activeWordColor: activeWordColor ?? this.activeWordColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      position: position ?? this.position,
      bgType: bgType ?? this.bgType,
      bgColor: bgColor ?? this.bgColor,
      bgOpacity: bgOpacity ?? this.bgOpacity,
      wordByWord: wordByWord ?? this.wordByWord,
      isItalic: isItalic ?? this.isItalic,
      has3dShadow: has3dShadow ?? this.has3dShadow,
      isOutlineOnly: isOutlineOnly ?? this.isOutlineOnly,
      selectedStyleId: selectedStyleId ?? this.selectedStyleId,
    );
  }

  // Predefined style list from Screenshot 1
  static final List<FontStyleItem> allFontStyles = [
    const FontStyleItem(
      id: 'adrian',
      name: 'Adrian',
      badge: 'New',
      categories: ['All', 'New', 'Trend', 'Speakers'],
      fontFamily: SubtitleFontFamily.poppins,
      textColor: Color(0xFF1E1E24),
      activeWordColor: Colors.black,
      bgColor: Color(0xFFF3ECE0),
      bgType: SubtitleBgType.solid,
      strokeWidth: 0,
    ),
    const FontStyleItem(
      id: 'nora',
      name: 'Nora',
      badge: 'New',
      categories: ['All', 'New', 'Trend'],
      fontFamily: SubtitleFontFamily.playfair,
      textColor: Color(0xFFD6D6DB),
      bgType: SubtitleBgType.none,
      strokeWidth: 1.0,
      strokeColor: Colors.black54,
    ),
    const FontStyleItem(
      id: 'benie',
      name: 'Benie',
      badge: 'New',
      categories: ['All', 'New', 'Animated', 'Premium'],
      fontFamily: SubtitleFontFamily.montserrat,
      textColor: Color(0xFFE50914),
      activeWordColor: Color(0xFFFF4D4D),
      bgType: SubtitleBgType.none,
      strokeWidth: 3.0,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'matt',
      name: 'Matt',
      categories: ['All', 'Animated', 'Speakers'],
      fontFamily: SubtitleFontFamily.montserrat,
      textColor: Colors.white,
      bgType: SubtitleBgType.none,
      strokeWidth: 2.0,
      strokeColor: Colors.black87,
    ),
    const FontStyleItem(
      id: 'kendrick',
      name: 'Kendrick',
      categories: ['All', 'Trend', 'Speakers'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Colors.black,
      activeWordColor: Colors.black,
      bgColor: Color(0xFF00FF2A),
      bgType: SubtitleBgType.solid,
      strokeWidth: 0,
    ),
    const FontStyleItem(
      id: 'hormozi5',
      name: 'Hormozi 5',
      badge: '⚡',
      categories: ['All', 'Trend', 'Premium', 'Speakers'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Colors.white,
      activeWordColor: Color(0xFFFFDF00),
      bgType: SubtitleBgType.none,
      strokeWidth: 5.0,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'ella',
      name: 'ELLA',
      categories: ['All', 'Animated'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Colors.white,
      bgType: SubtitleBgType.none,
      strokeWidth: 1.0,
      strokeColor: Colors.black87,
      has3dShadow: true,
    ),
    const FontStyleItem(
      id: 'mark',
      name: 'MARK',
      badge: '⚡',
      categories: ['All', 'Speakers', 'Premium'],
      fontFamily: SubtitleFontFamily.bebas,
      textColor: Color(0xFFE8E8EC),
      bgType: SubtitleBgType.none,
      strokeWidth: 3.0,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'karl',
      name: 'KARL',
      categories: ['All', 'Trend', 'Speakers'],
      fontFamily: SubtitleFontFamily.montserrat,
      textColor: Color(0xFFD6DBE1),
      bgType: SubtitleBgType.none,
      strokeWidth: 2.0,
      strokeColor: Colors.black54,
    ),
    const FontStyleItem(
      id: 'dan2',
      name: 'DAN 2',
      categories: ['All', 'Trend', 'Speakers', 'Emoji'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Colors.black,
      activeWordColor: Colors.black,
      bgColor: Color(0xFFFFEB3B),
      bgType: SubtitleBgType.solid,
      strokeWidth: 0,
    ),
    const FontStyleItem(
      id: 'dan',
      name: 'DAN',
      categories: ['All', 'Speakers'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Color(0xFFE0E0E0),
      isItalic: true,
      has3dShadow: true,
      strokeWidth: 2.0,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'kelly2',
      name: 'Kelly 2',
      badge: '⚡',
      categories: ['All', 'Premium', 'Trend'],
      fontFamily: SubtitleFontFamily.poppins,
      textColor: Color(0xFFDCDCE0),
      bgType: SubtitleBgType.none,
      strokeWidth: 1.5,
      strokeColor: Colors.black45,
    ),
    const FontStyleItem(
      id: 'devin',
      name: 'DEVIN',
      categories: ['All', 'Animated', 'Speakers'],
      fontFamily: SubtitleFontFamily.bebas,
      textColor: Colors.white,
      bgType: SubtitleBgType.none,
      strokeWidth: 4.5,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'hormozi4',
      name: 'HORMOZI 4',
      badge: '⚡',
      categories: ['All', 'Trend', 'Premium', 'Speakers'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Color(0xFFFFB300),
      activeWordColor: Color(0xFFFF3D00),
      bgType: SubtitleBgType.none,
      strokeWidth: 4.5,
      strokeColor: Color(0xFF1A1A1A),
      has3dShadow: true,
    ),
    const FontStyleItem(
      id: 'maya',
      name: 'Maya',
      categories: ['All', 'Animated', 'Emoji'],
      fontFamily: SubtitleFontFamily.poppins,
      textColor: Color(0xFFFF9E0D),
      bgType: SubtitleBgType.glow,
      bgColor: Color(0xFFFF9E0D),
      strokeWidth: 0,
    ),
    const FontStyleItem(
      id: 'tracy',
      name: 'TRACY',
      categories: ['All', 'Premium', 'Speakers'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Colors.white,
      bgType: SubtitleBgType.glow,
      bgColor: Colors.white,
      strokeWidth: 0,
    ),
    const FontStyleItem(
      id: 'beast',
      name: 'BEAST',
      categories: ['All', 'Animated', 'Trend', 'Premium'],
      fontFamily: SubtitleFontFamily.anton,
      textColor: Colors.white,
      isItalic: true,
      isOutlineOnly: true,
      strokeWidth: 3.5,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'daniel',
      name: 'Daniel',
      badge: '⚡',
      categories: ['All', 'Speakers'],
      fontFamily: SubtitleFontFamily.poppins,
      textColor: Color(0xFFCCCCCC),
      bgType: SubtitleBgType.none,
      strokeWidth: 1.5,
      strokeColor: Colors.black54,
    ),
    const FontStyleItem(
      id: 'luke',
      name: 'LUKE',
      categories: ['All', 'Speakers'],
      fontFamily: SubtitleFontFamily.oswald,
      textColor: Colors.white,
      bgType: SubtitleBgType.none,
      strokeWidth: 3.0,
      strokeColor: Colors.black,
    ),
    const FontStyleItem(
      id: 'sara',
      name: 'Sara',
      badge: '⚡',
      categories: ['All', 'Trend', 'Premium'],
      fontFamily: SubtitleFontFamily.cinzel,
      textColor: Color(0xFFE2E2E6),
      bgType: SubtitleBgType.none,
      strokeWidth: 1.0,
      strokeColor: Colors.black45,
    ),
    const FontStyleItem(
      id: 'laura',
      name: 'Laura',
      categories: ['All', 'Trend', 'Emoji'],
      fontFamily: SubtitleFontFamily.playfair,
      textColor: Colors.black,
      activeWordColor: Colors.black,
      bgColor: Color(0xFFD6FF00),
      bgType: SubtitleBgType.solid,
      strokeWidth: 0,
    ),
  ];
}
