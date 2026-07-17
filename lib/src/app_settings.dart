import 'app_settings_io.dart'
    if (dart.library.js_interop) 'app_settings_web.dart' as implementation;

class AppSettings {
  const AppSettings({
    this.exportDirectory = '',
    this.askExportLocation = true,
    this.numberedExportNames = true,
  });

  final String exportDirectory;
  final bool askExportLocation;
  final bool numberedExportNames;

  AppSettings copyWith({
    String? exportDirectory,
    bool? askExportLocation,
    bool? numberedExportNames,
  }) =>
      AppSettings(
        exportDirectory: exportDirectory ?? this.exportDirectory,
        askExportLocation: askExportLocation ?? this.askExportLocation,
        numberedExportNames: numberedExportNames ?? this.numberedExportNames,
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        exportDirectory: json['exportDirectory']?.toString() ?? '',
        askExportLocation: json['askExportLocation'] != false,
        numberedExportNames: json['numberedExportNames'] != false,
      );

  Map<String, Object?> toJson() => {
        'exportDirectory': exportDirectory,
        'askExportLocation': askExportLocation,
        'numberedExportNames': numberedExportNames,
      };
}

Future<AppSettings> loadAppSettings() => implementation.loadAppSettings();
Future<void> saveAppSettings(AppSettings settings) =>
    implementation.saveAppSettings(settings);
Future<String?> chooseExportDirectory() =>
    implementation.chooseExportDirectory();
