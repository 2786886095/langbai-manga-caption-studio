import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart' show AppSettings;

Future<File> _settingsFile() async => File(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}settings.json',
    );

Future<AppSettings> loadAppSettings() async {
  final file = await _settingsFile();
  if (!await file.exists()) return const AppSettings();
  try {
    return AppSettings.fromJson(jsonDecode(await file.readAsString()));
  } catch (_) {
    return const AppSettings();
  }
}

Future<void> saveAppSettings(AppSettings settings) async {
  final file = await _settingsFile();
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
}

Future<String?> chooseExportDirectory() =>
    FilePicker.platform.getDirectoryPath(dialogTitle: '选择默认保存目录');
