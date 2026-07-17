import 'package:flutter/material.dart';

import 'app_settings.dart';

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
