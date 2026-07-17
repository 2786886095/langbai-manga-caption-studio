import 'app_settings_io.dart'
    if (dart.library.js_interop) 'app_settings_web.dart' as implementation;

class AppSettings {
  const AppSettings({
    this.exportDirectory = '',
    this.askExportLocation = true,
    this.autoSave = true,
    this.autoSaveSeconds = 3,
    this.numberedExportNames = true,
  });

  final String exportDirectory;
  final bool askExportLocation;
  final bool autoSave;
  final int autoSaveSeconds;
  final bool numberedExportNames;

  AppSettings copyWith({
    String? exportDirectory,
    bool? askExportLocation,
    bool? autoSave,
    int? autoSaveSeconds,
    bool? numberedExportNames,
  }) =>
      AppSettings(
        exportDirectory: exportDirectory ?? this.exportDirectory,
        askExportLocation: askExportLocation ?? this.askExportLocation,
        autoSave: autoSave ?? this.autoSave,
        autoSaveSeconds: autoSaveSeconds ?? this.autoSaveSeconds,
        numberedExportNames: numberedExportNames ?? this.numberedExportNames,
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        exportDirectory: json['exportDirectory']?.toString() ?? '',
        askExportLocation: json['askExportLocation'] != false,
        autoSave: json['autoSave'] != false,
        autoSaveSeconds:
            ((json['autoSaveSeconds'] as num?)?.toInt() ?? 3).clamp(
          2,
          60,
        ),
        numberedExportNames: json['numberedExportNames'] != false,
      );

  Map<String, Object?> toJson() => {
        'exportDirectory': exportDirectory,
        'askExportLocation': askExportLocation,
        'autoSave': autoSave,
        'autoSaveSeconds': autoSaveSeconds,
        'numberedExportNames': numberedExportNames,
      };
}

Future<AppSettings> loadAppSettings() => implementation.loadAppSettings();
Future<void> saveAppSettings(AppSettings settings) =>
    implementation.saveAppSettings(settings);
Future<String?> chooseExportDirectory() =>
    implementation.chooseExportDirectory();
