import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_settings.dart';
import 'app_localization.dart';
import 'models.dart';
import 'update_service.dart';

/// A saved preference and an explicit, one-shot project edit request.
/// The project action is deliberately not persisted in [AppSettings].
class AppSettingsDialogResult {
  const AppSettingsDialogResult({
    required this.settings,
    this.applyTextSizeModeToCurrentProject = false,
  });

  final AppSettings settings;
  final bool applyTextSizeModeToCurrentProject;
}

Future<AppSettingsDialogResult?> showAppSettingsDialog(
  BuildContext context,
  AppSettings initial, {
  bool canApplyTextSizeModeToCurrentProject = false,
}) async {
  var settings = initial;
  var applyToCurrentProject = false;
  var saving = false;
  String? saveError;
  final formKey = GlobalKey<FormState>();
  return showDialog<AppSettingsDialogResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => PopScope(
        canPop: !saving,
        child: AlertDialog(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_outlined),
                  const SizedBox(width: 10),
                  LText('设置'),
                ],
              ),
              if (saveError != null) ...[
                const SizedBox(height: 10),
                Text(
                  saveError!,
                  key: const ValueKey('settings-save-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      '语言',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: settings.languageCode,
                      decoration: InputDecoration(
                        labelText: tr('界面与指南语言'),
                        prefixIcon: const Icon(Icons.language),
                      ),
                      items: [
                        for (final option in AppLocaleController.languages)
                          DropdownMenuItem(
                            value: option.code,
                            child: Text(option.nativeName),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                settings =
                                    settings.copyWith(languageCode: value);
                              });
                            },
                    ),
                    const Divider(height: 28),
                    LText(
                      '全局默认字号模式',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<TextSizeMode>(
                      key: const ValueKey('settings-default-text-size-mode'),
                      segments: [
                        ButtonSegment(
                          value: TextSizeMode.fit,
                          icon: const Icon(Icons.fit_screen),
                          label: LText('自动挡'),
                        ),
                        ButtonSegment(
                          value: TextSizeMode.fixed,
                          icon: const Icon(Icons.format_size),
                          label: LText('手动挡'),
                        ),
                      ],
                      selected: {settings.defaultTextSizeMode},
                      onSelectionChanged: saving
                          ? null
                          : (value) => setDialogState(() {
                                settings = settings.copyWith(
                                  defaultTextSizeMode: value.first,
                                );
                              }),
                    ),
                    const SizedBox(height: 10),
                    LText(
                      '默认只影响新建及未指定模式的新脚本对象；不会改变已保存、复制或明确指定模式的对象。',
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    if (settings.defaultTextSizeMode == TextSizeMode.fit)
                      Text(
                        trArgs('自动挡会在 {min}–{max} 内选取不溢出的最大字号', {
                          'min': TextStyleLimits.minFontSize.toInt(),
                          'max': TextStyleLimits.maxFontSize.toInt(),
                        }),
                      )
                    else
                      TextFormField(
                        key:
                            const ValueKey('settings-default-manual-font-size'),
                        initialValue: settings.defaultManualFontSize ==
                                settings.defaultManualFontSize.roundToDouble()
                            ? settings.defaultManualFontSize.toInt().toString()
                            : settings.defaultManualFontSize.toString(),
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: tr('新建对象手动字号（8–200）'),
                          helperText: tr('手动挡严格使用该字号；调整文字框不会自动缩放文字。'),
                          helperMaxLines: 3,
                        ),
                        validator: (value) {
                          if (settings.defaultTextSizeMode !=
                              TextSizeMode.fixed) {
                            return null;
                          }
                          final number = double.tryParse(value?.trim() ?? '');
                          if (number == null ||
                              !number.isFinite ||
                              number < TextStyleLimits.minFontSize ||
                              number > TextStyleLimits.maxFontSize) {
                            return tr('请输入 8–200 之间的有效字号');
                          }
                          return null;
                        },
                        onChanged: (value) {
                          final number = double.tryParse(value.trim());
                          if (number != null &&
                              number.isFinite &&
                              number >= TextStyleLimits.minFontSize &&
                              number <= TextStyleLimits.maxFontSize) {
                            // Do not rebuild this field while a user is typing.
                            settings = settings.copyWith(
                              defaultManualFontSize: number,
                            );
                          }
                        },
                      ),
                    if (canApplyTextSizeModeToCurrentProject) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        key: const ValueKey(
                          'settings-apply-text-size-mode-to-project',
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: LText('同时应用到当前项目全部文字和气泡'),
                        subtitle: LText(
                          '仅修改当前项目，可撤销，不改其他项目。自动挡上限200；切手动保留各对象当前可见字号，不使用上面的新建字号。实际改变的对象会解除文字样式关联。',
                        ),
                        value: applyToCurrentProject,
                        onChanged: saving
                            ? null
                            : (value) => setDialogState(() {
                                  applyToCurrentProject = value == true;
                                }),
                      ),
                    ],
                    const Divider(height: 28),
                    LText(
                      '保存与导出',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        settings.exportDirectory.isEmpty
                            ? tr('尚未设置默认保存目录')
                            : settings.exportDirectory,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: LText('批量成图会以 PNG 图片直接写入这里，不再生成 ZIP'),
                      trailing: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final directory = await chooseExportDirectory();
                                if (directory != null && context.mounted) {
                                  setDialogState(() {
                                    settings = settings.copyWith(
                                      exportDirectory: directory,
                                    );
                                  });
                                }
                              },
                        child: LText('选择目录'),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: LText('每次导出都询问保存位置'),
                      subtitle: LText('关闭后直接写入上面的默认目录'),
                      value: settings.askExportLocation,
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(() {
                                settings =
                                    settings.copyWith(askExportLocation: value);
                              }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: LText('导出文件添加 0001、0002 序号'),
                      subtitle: LText('关闭后保留原文件名；同名图片会在覆盖前询问'),
                      value: settings.numberedExportNames,
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(() {
                                settings = settings.copyWith(
                                    numberedExportNames: value);
                              }),
                    ),
                    const Divider(height: 28),
                    const _UpdateSettingsSection(),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: LText('取消'),
            ),
            FilledButton(
              key: const ValueKey('settings-save'),
              onPressed: saving
                  ? null
                  : () async {
                      if (saving) return;
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() {
                        saving = true;
                        saveError = null;
                      });
                      try {
                        await saveAppSettings(settings);
                        AppLocaleController.instance
                            .setLanguage(settings.languageCode);
                        if (context.mounted) {
                          Navigator.pop(
                            context,
                            AppSettingsDialogResult(
                              settings: settings,
                              applyTextSizeModeToCurrentProject:
                                  canApplyTextSizeModeToCurrentProject &&
                                      applyToCurrentProject,
                            ),
                          );
                        }
                      } catch (error) {
                        if (!context.mounted) return;
                        setDialogState(() {
                          saving = false;
                          saveError = trArgs('保存设置失败：{error}', {
                            'error': error,
                          });
                        });
                      }
                    },
              child: saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: tr('正在保存设置…'),
                      ),
                    )
                  : LText('保存设置'),
            ),
          ],
        ),
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

  Future<void> _downloadUpdate() async {
    final info = await downloadAppUpdate();
    if (!mounted) return;
    _updateInfo(info);
  }

  void _updateInfo(AppUpdateInfo info) {
    setState(() => _info = info);
    if (!const {'checking', 'downloading'}.contains(info.state)) {
      _pollTimer?.cancel();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final next = await getAppUpdateStatus();
      if (!mounted) return;
      setState(() => _info = next);
      if (!const {'checking', 'downloading'}.contains(next.state)) {
        _pollTimer?.cancel();
      }
    });
  }

  String get _statusText {
    final info = _info;
    if (_checking || info?.state == 'checking') return '正在检测更新…';
    if (info == null) return '正在读取更新状态…';
    return switch (info.state) {
      'available' => '发现 ${info.latestVersion}，等待你确认下载',
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
    final canDownload =
        info?.state == 'available' && info?.installSupported == true;
    final openGitHub = info?.state == 'external';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText(
          '软件与更新',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_alt),
          title: LText('浪白漫画字幕工坊 $_currentVersion'),
          subtitle: LText(_statusText),
          trailing: FilledButton.icon(
            onPressed: _checking
                ? null
                : canDownload
                    ? _downloadUpdate
                    : canInstall || openGitHub
                        ? () => installOrOpenAppUpdate(info!)
                        : _checkForUpdates,
            icon: Icon(
              canInstall
                  ? Icons.restart_alt
                  : canDownload
                      ? Icons.download_outlined
                      : openGitHub
                          ? Icons.open_in_new
                          : Icons.refresh,
              size: 18,
            ),
            label: LText(
              canInstall
                  ? '安装并重启'
                  : canDownload
                      ? '下载更新'
                      : openGitHub
                          ? '前往 GitHub'
                          : _checking
                              ? '检测中'
                              : '检测更新',
            ),
          ),
        ),
        LText(
          'Windows Setup 版可在软件内下载并安装；Portable 和其他平台会打开 GitHub Releases。',
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }
}
