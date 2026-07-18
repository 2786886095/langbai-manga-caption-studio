import 'app_settings_io.dart'
    if (dart.library.js_interop) 'app_settings_web.dart' as implementation;

class AppSettings {
  const AppSettings({
    this.exportDirectory = '',
    this.askExportLocation = true,
    this.numberedExportNames = true,
    this.languageCode = 'zh_CN',
  });

  final String exportDirectory;
  final bool askExportLocation;
  final bool numberedExportNames;
  final String languageCode;

  AppSettings copyWith({
    String? exportDirectory,
    bool? askExportLocation,
    bool? numberedExportNames,
    String? languageCode,
  }) =>
      AppSettings(
        exportDirectory: exportDirectory ?? this.exportDirectory,
        askExportLocation: askExportLocation ?? this.askExportLocation,
        numberedExportNames: numberedExportNames ?? this.numberedExportNames,
        languageCode: languageCode ?? this.languageCode,
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        exportDirectory: json['exportDirectory']?.toString() ?? '',
        askExportLocation: json['askExportLocation'] != false,
        numberedExportNames: json['numberedExportNames'] != false,
        languageCode: supportedLanguageCodes.contains(json['languageCode'])
            ? json['languageCode'].toString()
            : 'zh_CN',
      );

  Map<String, Object?> toJson() => {
        'exportDirectory': exportDirectory,
        'askExportLocation': askExportLocation,
        'numberedExportNames': numberedExportNames,
        'languageCode': languageCode,
      };
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
