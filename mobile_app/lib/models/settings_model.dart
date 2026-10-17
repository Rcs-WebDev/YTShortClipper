class AppSettings {
  String apiKey;
  String apiBaseUrl;
  String modelName;
  String youtubeCookies;
  int minClipSeconds;
  int maxClipSeconds;

  AppSettings({
    this.apiKey = '',
    this.apiBaseUrl = 'https://api.openai.com/v1',
    this.modelName = 'gpt-4o-mini',
    this.youtubeCookies = '',
    this.minClipSeconds = 30,
    this.maxClipSeconds = 60,
  });

  Map<String, dynamic> toJson() => {
    'apiKey': apiKey,
    'apiBaseUrl': apiBaseUrl,
    'modelName': modelName,
    'youtubeCookies': youtubeCookies,
    'minClipSeconds': minClipSeconds,
    'maxClipSeconds': maxClipSeconds,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    apiKey: json['apiKey'] ?? '',
    apiBaseUrl: json['apiBaseUrl'] ?? 'https://api.openai.com/v1',
    modelName: json['modelName'] ?? 'gpt-4o-mini',
    youtubeCookies: json['youtubeCookies'] ?? '',
    minClipSeconds: json['minClipSeconds'] ?? 30,
    maxClipSeconds: json['maxClipSeconds'] ?? 60,
  );
}
