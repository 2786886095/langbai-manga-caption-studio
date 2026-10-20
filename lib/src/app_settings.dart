import 'models.dart' show TextSizeMode, TextStyleLimits;

import 'app_settings_io.dart'
    if (dart.library.js_interop) 'app_settings_web.dart' as implementation;

class AppSettings {
  const AppSettings({
    this.exportDirectory = '',
    this.askExportLocation = true,
    this.numberedExportNames = true,
    this.languageCode = 'zh_CN',
    this.defaultTextSizeMode = TextSizeMode.fit,
    this.defaultManualFontSize = 34,
  });

  final String exportDirectory;
  final bool askExportLocation;
  final bool numberedExportNames;
  final String languageCode;

  // Defaults apply only to new objects without an explicit script style.
  final TextSizeMode defaultTextSizeMode;
  final double defaultManualFontSize;

  AppSettings copyWith({
    String? exportDirectory,
    bool? askExportLocation,
    bool? numberedExportNames,
    String? languageCode,
    TextSizeMode? defaultTextSizeMode,
    double? defaultManualFontSize,
  }) =>
      AppSettings(
        exportDirectory: exportDirectory ?? this.exportDirectory,
        askExportLocation: askExportLocation ?? this.askExportLocation,
        numberedExportNames: numberedExportNames ?? this.numberedExportNames,
        languageCode: languageCode ?? this.languageCode,
        defaultTextSizeMode: defaultTextSizeMode ?? this.defaultTextSizeMode,
        defaultManualFontSize: defaultManualFontSize == null
            ? this.defaultManualFontSize
            : _readManualFontSize(defaultManualFontSize),
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        exportDirectory: json['exportDirectory']?.toString() ?? '',
        askExportLocation: json['askExportLocation'] != false,
        numberedExportNames: json['numberedExportNames'] != false,
        languageCode: supportedLanguageCodes.contains(json['languageCode'])
            ? json['languageCode'].toString()
            : 'zh_CN',
        defaultTextSizeMode:
            json['defaultTextSizeMode'] == TextSizeMode.fixed.name
                ? TextSizeMode.fixed
                : TextSizeMode.fit,
        defaultManualFontSize:
            _readManualFontSize(json['defaultManualFontSize']),
      );

  Map<String, Object?> toJson() => {
        'exportDirectory': exportDirectory,
        'askExportLocation': askExportLocation,
        'numberedExportNames': numberedExportNames,
        'languageCode': languageCode,
        'defaultTextSizeMode': defaultTextSizeMode.name,
        'defaultManualFontSize': defaultManualFontSize,
      };
}

// Missing, malformed or unsupported old values must never turn Auto into Manual.
double _readManualFontSize(Object? value) {
  final number = value is num ? value.toDouble() : null;
  if (number == null ||
      !number.isFinite ||
      number < TextStyleLimits.minFontSize ||
      number > TextStyleLimits.maxFontSize) {
    return 34;
  }
  return number;
}

const supportedLanguageCodes = <String>{
  'zh_CN',
  'zh_TW',
  'en',
  'ja',
  'ko',
};

Future<AppSettings> loadAppSettings() => implementation.loadAppSettings();
Future<void> saveAppSettings(AppSettings settings) =>
    implementation.saveAppSettings(settings);
Future<String?> chooseExportDirectory() =>
    implementation.chooseExportDirectory();
