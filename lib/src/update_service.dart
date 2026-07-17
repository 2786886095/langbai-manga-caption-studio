import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'desktop_update_bridge.dart';

const releasePageUrl =
    'https://github.com/2786886095/langbai-manga-caption-studio/releases/latest';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.state,
    required this.currentVersion,
    this.latestVersion,
    this.progress = 0,
    this.releaseUrl = releasePageUrl,
    this.installSupported = false,
    this.message = '',
  });

  final String state;
  final String currentVersion;
  final String? latestVersion;
  final double progress;
  final String releaseUrl;
  final bool installSupported;
  final String message;

  bool get shouldShow =>
      const {
        'available',
        'downloading',
        'downloaded',
        'external',
      }.contains(state) &&
      latestVersion != null;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        state: json['state']?.toString() ?? 'idle',
        currentVersion: json['currentVersion']?.toString() ?? '',
        latestVersion: json['latestVersion']?.toString(),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        releaseUrl: json['releaseUrl']?.toString() ?? releasePageUrl,
        installSupported: json['installSupported'] == true,
        message: json['message']?.toString() ?? '',
      );
}

Future<AppUpdateInfo> checkForAppUpdate() async {
  final desktop = await invokeDesktopUpdate('checkForUpdates');
  if (desktop != null) {
    final info = AppUpdateInfo.fromJson(jsonDecode(desktop));
    if (info.state != 'external') return info;
  }
  return _checkGitHubRelease();
}

Future<AppUpdateInfo> getAppUpdateStatus() async {
  final desktop = await invokeDesktopUpdate('getUpdateStatus');
  if (desktop != null) {
    return AppUpdateInfo.fromJson(jsonDecode(desktop));
  }
  return _checkGitHubRelease();
}

Future<AppUpdateInfo> downloadAppUpdate() async {
  final desktop = await invokeDesktopUpdate('downloadUpdate');
  if (desktop != null) {
    return AppUpdateInfo.fromJson(jsonDecode(desktop));
  }
  return getAppUpdateStatus();
}

Future<AppUpdateInfo> _checkGitHubRelease() async {
  final package = await PackageInfo.fromPlatform();
  try {
    final response = await http.get(
      Uri.parse(
        'https://api.github.com/repos/2786886095/langbai-manga-caption-studio/releases/latest',
      ),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      return AppUpdateInfo(state: 'idle', currentVersion: package.version);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final latest = data['tag_name']?.toString().replaceFirst(RegExp(r'^v'), '');
    if (latest != null && _compareVersions(latest, package.version) > 0) {
      return AppUpdateInfo(
        state: 'external',
        currentVersion: package.version,
        latestVersion: latest,
        releaseUrl: data['html_url']?.toString() ?? releasePageUrl,
      );
    }
    return AppUpdateInfo(
      state: 'upToDate',
      currentVersion: package.version,
      latestVersion: latest,
    );
  } catch (_) {
    return AppUpdateInfo(state: 'idle', currentVersion: package.version);
  }
}

int _compareVersions(String left, String right) {
  final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final difference = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (difference != 0) return difference;
  }
  return 0;
}

Future<void> installOrOpenAppUpdate(AppUpdateInfo info) async {
  if (info.installSupported && info.state == 'downloaded') {
    await invokeDesktopUpdate('installUpdate');
    return;
  }
  final opened = await invokeDesktopUpdate('openUpdatePage');
  if (opened != null) return;
  await launchUrl(
    Uri.parse(info.releaseUrl),
    mode: LaunchMode.externalApplication,
  );
}
