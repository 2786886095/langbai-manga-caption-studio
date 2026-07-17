import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_settings.dart';
import 'project_store.dart';
import 'settings_dialog.dart';
import 'text_context_menu.dart';
import 'workspace_screen.dart';
import 'update_service.dart';

class ProjectHubScreen extends StatefulWidget {
  const ProjectHubScreen({super.key});

  @override
  State<ProjectHubScreen> createState() => _ProjectHubScreenState();
}

class _ProjectHubScreenState extends State<ProjectHubScreen> {
  List<LocalProjectSummary> _projects = const [];
  bool _loading = true;
  AppSettings _settings = const AppSettings();
  AppUpdateInfo? _updateInfo;
  Timer? _updatePoll;
  final Map<String, ({String encoded, Uint8List bytes})> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadSettings();
    _checkUpdates();
  }

  @override
  void dispose() {
    _updatePoll?.cancel();
    super.dispose();
  }

  Future<void> _checkUpdates({bool manual = false}) async {
    final info = await checkForAppUpdate();
    if (!mounted) return;
    setState(() => _updateInfo = info);
    if (info.state == 'downloading') {
      _updatePoll?.cancel();
      _updatePoll = Timer.periodic(const Duration(seconds: 1), (_) async {
        final next = await getAppUpdateStatus();
        if (!mounted) return;
        setState(() => _updateInfo = next);
        if (!const {'checking', 'available', 'downloading'}
            .contains(next.state)) {
          _updatePoll?.cancel();
        }
      });
    } else if (manual && info.state == 'upToDate') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('当前已经是最新版本 ${info.currentVersion}'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    }
  }

  Future<void> _downloadUpdate() async {
    final info = await downloadAppUpdate();
    if (!mounted) return;
    setState(() => _updateInfo = info);
    if (info.state != 'downloading') return;
    _updatePoll?.cancel();
    _updatePoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final next = await getAppUpdateStatus();
      if (!mounted) return;
      setState(() => _updateInfo = next);
      if (next.state != 'downloading') _updatePoll?.cancel();
    });
  }

  Widget _updateBanner() {
    final info = _updateInfo;
    if (info == null || !info.shouldShow) return const SizedBox.shrink();
    final downloaded = info.state == 'downloaded';
    final available = info.state == 'available';
    final external = !info.installSupported || info.state == 'external';
    final progress = info.progress.clamp(0, 100).round();
    final title = downloaded
        ? '新版本 ${info.latestVersion} 已准备完成'
        : external
            ? '发现新版本 ${info.latestVersion}'
            : available
                ? '发现新版本 ${info.latestVersion}'
                : '正在下载新版本 ${info.latestVersion} · $progress%';
    final description = downloaded
        ? '点击后将关闭软件、安装更新并重新启动。项目数据不会被删除。'
        : external
            ? '当前平台请前往 GitHub Releases 下载最新版本。'
            : available
                ? '检测完成。只有点击下载后才会获取安装包，不再启动即后台下载。'
                : '安装包正在后台下载，完成后可以直接在软件内安装。';
    return Container(
      width: double.infinity,
      color: AppColors.pink,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          if (downloaded || external || available)
            FilledButton.icon(
              onPressed: available
                  ? _downloadUpdate
                  : () => installOrOpenAppUpdate(info),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.pink,
              ),
              icon: Icon(
                downloaded
                    ? Icons.restart_alt
                    : available
                        ? Icons.download_outlined
                        : Icons.open_in_new,
              ),
              label: Text(
                downloaded
                    ? '立即安装并重启'
                    : available
                        ? '下载更新'
                        : '前往 GitHub 更新',
              ),
            )
          else
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                value: info.progress > 0 ? info.progress / 100 : null,
                minHeight: 8,
                color: Colors.white,
                backgroundColor: Colors.white30,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final settings = await loadAppSettings();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _showSettings() async {
    final settings = await showAppSettingsDialog(context, _settings);
    if (settings != null && mounted) setState(() => _settings = settings);
  }

  Future<void> _refresh() async {
    final projects = await listLocalProjects();
    if (!mounted) return;
    final activeIds = projects.map((project) => project.id).toSet();
    _thumbnailCache.removeWhere((id, _) => !activeIds.contains(id));
    for (final project in projects) {
      final encoded = project.thumbnailBase64;
      if (encoded == null || encoded.isEmpty) continue;
      final cached = _thumbnailCache[project.id];
      if (cached?.encoded == encoded) continue;
      try {
        _thumbnailCache[project.id] = (
          encoded: encoded,
          bytes: base64Decode(encoded),
        );
      } catch (_) {
        _thumbnailCache.remove(project.id);
      }
    }
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  String _defaultName(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '项目 ${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}-${two(value.minute)}-${two(value.second)}';
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建项目'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可以输入项目名；留空会自动按创建时间命名。'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                contextMenuBuilder: buildAppTextContextMenu,
                decoration: const InputDecoration(
                  labelText: '项目名称（可选）',
                  hintText: '例如：第 01 话 初遇',
                ),
                onSubmitted: (_) =>
                    Navigator.pop(context, controller.text.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建项目'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final project = await createLocalProject(
      name.isEmpty ? _defaultName(DateTime.now()) : name,
    );
    if (!mounted) return;
    await _openProject(project);
  }

  Future<void> _openProject(LocalProjectSummary project) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => WorkspaceScreen(
          projectId: project.id,
          projectName: project.name,
          onExitToProjects: () => Navigator.pop(context),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _deleteProject(LocalProjectSummary project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除项目？'),
        content: Text('“${project.name}”及其本地图片、字幕和排版将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteLocalProject(project.id);
    await _refresh();
  }

  String _updatedLabel(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _projectCover(LocalProjectSummary project) {
    final thumbnail = _thumbnailCache[project.id];
    if (thumbnail != null) {
      return Semantics(
        label: '项目第一张图片：${project.name}',
        image: true,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                thumbnail.bytes,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.72),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '首图',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.blush,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined, color: AppColors.pink),
          SizedBox(height: 5),
          Text('暂无首图', style: TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Column(
            children: [
              _updateBanner(),
              Container(
                height: 92,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: AppColors.panel,
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/mascot.png',
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '浪白漫画字幕工坊',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '本地项目 · 图片与字幕不会上传',
                            style:
                                TextStyle(color: AppColors.pink, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _createProject,
                      icon: const Icon(Icons.add),
                      label: const Text('新建项目'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _checkUpdates(manual: true),
                      tooltip: '检查更新',
                      icon: const Icon(Icons.system_update_alt),
                    ),
                    IconButton(
                      onPressed: _showSettings,
                      tooltip: '设置',
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _projects.isEmpty
                        ? _emptyState()
                        : _projectList(),
              ),
            ],
          ),
        ),
      );

  Widget _emptyState() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: AppColors.blush,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.folder_copy_outlined,
                  size: 38,
                  color: AppColors.pink,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '还没有项目',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                '每个项目独立保存图片、字幕和排版。创建后即可添加图片。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.55),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.add),
                label: const Text('创建第一个项目'),
              ),
            ],
          ),
        ),
      );

  Widget _projectList() => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1120
              ? 3
              : constraints.maxWidth >= 720
                  ? 2
                  : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 216,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _projects.length,
            itemBuilder: (context, index) {
              final project = _projects[index];
              return Material(
                color: AppColors.panel,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppColors.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () => _openProject(project),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _projectCover(project),
                            const Spacer(),
                            IconButton(
                              onPressed: () => _deleteProject(project),
                              tooltip: '删除项目',
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          project.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              project.hasData
                                  ? Icons.check_circle_outline
                                  : Icons.add_photo_alternate_outlined,
                              size: 16,
                              color: project.hasData
                                  ? AppColors.success
                                  : AppColors.muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                project.hasData ? '已有工程内容' : '等待添加图片',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              _updatedLabel(project.updatedAt),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}
