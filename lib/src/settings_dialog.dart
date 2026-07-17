import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_settings.dart';
import 'update_service.dart';

Future<AppSettings?> showAppSettingsDialog(
  BuildContext context,
  AppSettings initial,
) async {
  var settings = initial;
  return showDialog<AppSettings>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_outlined),
            SizedBox(width: 10),
            Text('设置'),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '保存与导出',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    settings.exportDirectory.isEmpty
                        ? '尚未设置默认保存目录'
                        : settings.exportDirectory,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('批量成图会以 PNG 图片直接写入这里，不再生成 ZIP'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final directory = await chooseExportDirectory();
                      if (directory != null) {
                        setDialogState(() {
                          settings = settings.copyWith(
                            exportDirectory: directory,
                          );
                        });
                      }
                    },
                    child: const Text('选择目录'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('每次导出都询问保存位置'),
                  subtitle: const Text('关闭后直接写入上面的默认目录'),
                  value: settings.askExportLocation,
                  onChanged: (value) => setDialogState(() {
                    settings = settings.copyWith(askExportLocation: value);
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导出文件添加 0001、0002 序号'),
                  subtitle: const Text('关闭后保留原文件名；同名图片会在覆盖前询问'),
                  value: settings.numberedExportNames,
                  onChanged: (value) => setDialogState(() {
                    settings = settings.copyWith(numberedExportNames: value);
                  }),
                ),
                const Divider(height: 28),
                const Text(
                  '项目保护',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动保存当前项目'),
                  subtitle: const Text('切换项目时无论此开关如何都会保存一次'),
                  value: settings.autoSave,
                  onChanged: (value) => setDialogState(() {
                    settings = settings.copyWith(autoSave: value);
                  }),
                ),
                if (settings.autoSave)
                  Row(
                    children: [
                      const Expanded(child: Text('自动保存间隔')),
                      DropdownButton<int>(
                        value: const {
                          3,
                          5,
                          10,
                          30,
                        }.contains(settings.autoSaveSeconds)
                            ? settings.autoSaveSeconds
                            : 3,
                        items: const [
                          DropdownMenuItem(value: 3, child: Text('3 秒')),
                          DropdownMenuItem(value: 5, child: Text('5 秒')),
                          DropdownMenuItem(value: 10, child: Text('10 秒')),
                          DropdownMenuItem(value: 30, child: Text('30 秒')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            settings = settings.copyWith(
                              autoSaveSeconds: value,
                            );
                          });
                        },
                      ),
                    ],
                  ),
                const Divider(height: 28),
                const _UpdateSettingsSection(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await saveAppSettings(settings);
              if (context.mounted) Navigator.pop(context, settings);
            },
            child: const Text('保存设置'),
          ),
        ],
      ),
    ),
  );
}

class _UpdateSettingsSection extends StatefulWidget {
  const _UpdateSettingsSection();

  @override
  State<_UpdateSettingsSection> createState() => _UpdateSettingsSectionState();
}

class _UpdateSettingsSectionState extends State<_UpdateSettingsSection> {
  Timer? _pollTimer;
  AppUpdateInfo? _info;
  String _currentVersion = '读取中';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final package = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _currentVersion = package.version);
    final info = await getAppUpdateStatus();
    if (!mounted) return;
    _updateInfo(info);
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    final info = await checkForAppUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    _updateInfo(info);
  }

  void _updateInfo(AppUpdateInfo info) {
    setState(() => _info = info);
    if (!const {'checking', 'available', 'downloading'}.contains(info.state)) {
      _pollTimer?.cancel();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final next = await getAppUpdateStatus();
      if (!mounted) return;
      setState(() => _info = next);
      if (!const {'checking', 'available', 'downloading'}
          .contains(next.state)) {
        _pollTimer?.cancel();
      }
    });
  }

  String get _statusText {
    final info = _info;
    if (_checking || info?.state == 'checking') return '正在检测更新…';
    if (info == null) return '正在读取更新状态…';
    return switch (info.state) {
      'available' => '发现 ${info.latestVersion}，正在准备下载…',
      'downloading' =>
        '正在下载 ${info.latestVersion} · ${info.progress.clamp(0, 100).round()}%',
      'downloaded' => '${info.latestVersion} 已下载，可以立即安装',
      'external' => '发现 ${info.latestVersion}，当前平台需前往 GitHub 更新',
      'upToDate' => '当前已经是最新版本',
      'error' => info.message.isEmpty ? '检测更新失败，请稍后重试' : info.message,
      _ => '尚未检测更新',
    };
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final canInstall = info?.state == 'downloaded';
    final openGitHub = info?.state == 'external';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '软件与更新',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_alt),
          title: Text('浪白漫画字幕工坊 $_currentVersion'),
          subtitle: Text(_statusText),
          trailing: FilledButton.icon(
            onPressed: _checking
                ? null
                : canInstall || openGitHub
                    ? () => installOrOpenAppUpdate(info!)
                    : _checkForUpdates,
            icon: Icon(
              canInstall
                  ? Icons.restart_alt
                  : openGitHub
                      ? Icons.open_in_new
                      : Icons.refresh,
              size: 18,
            ),
            label: Text(
              canInstall
                  ? '安装并重启'
                  : openGitHub
                      ? '前往 GitHub'
                      : _checking
                          ? '检测中'
                          : '检测更新',
            ),
          ),
        ),
        const Text(
          'Windows Setup 版可在软件内下载并安装；Portable 和其他平台会打开 GitHub Releases。',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }
}
