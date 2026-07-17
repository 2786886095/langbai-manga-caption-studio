# 浪白漫画字幕工坊

<p align="center">
  <img src="assets/浪白漫画字幕工坊-宣传图-v2.png" alt="浪白漫画字幕工坊全平台宣传图" width="100%">
</p>

<p align="center">
  <strong>全本地运行的批量漫画气泡字幕编辑器</strong><br>
  为漫画、条漫、视觉小说截图和批量 AI 图片提供精准、可复用的气泡字幕工作流。
</p>

<p align="center">
  <a href="https://github.com/2786886095/langbai-manga-caption-studio/releases/latest"><strong>下载 Windows Setup</strong></a>
  ·
  <a href="https://2786886095.github.io/langbai-manga-caption-studio/"><strong>打开 Web 在线版</strong></a>
  ·
  <a href="AI字幕脚本生成指南.md">AI 字幕脚本指南</a>
  ·
  <a href="字幕导入格式规范.md">字幕格式规范</a>
</p>

## 软件能做什么

浪白漫画字幕工坊可以按照确认后的图片顺序，批量导入字幕脚本、自动生成气泡排版，再逐张进行精确微调。图片、字体、项目和最终渲染全部保留在当前设备，不需要上传原图。

| 功能 | 说明 |
| --- | --- |
| 批量图片项目 | 一次导入多张图片，按文件名自然排序，也可拖动确认最终顺序 |
| 精准字幕脚本 | 使用图片原始尺寸和像素坐标描述每个气泡，字幕严格按第 1、2、3 张图片对应 |
| 自动排版 | 根据图片尺寸自动计算气泡位置，并允许继续拖动和八向缩放 |
| 多种漫画气泡 | 支持对话气泡、云朵心理气泡、旁白框和耳语气泡等样式 |
| 四角固定尾巴 | 对话与心理气泡可指向左上、右上、左下、右下，尾巴保持短小清晰 |
| 字体与颜色 | 可导入 TTF/OTF 字体，支持完整色域、HEX、字号、行距与描边设置 |
| 项目管理 | 新建、删除和随时切换项目；项目卡片显示第一张图片缩略图 |
| 直接导出 PNG | 批量成图直接写入目标文件夹，不使用 ZIP；同名图片覆盖前会询问 |
| AI 脚本指南 | 自动附加当前项目的真实图片顺序、图片尺寸和完整脚本模板 |
| 安装版自动更新 | Windows Setup 版可在软件内检查、下载并重启安装新版本 |

## 为什么选择它

### 全程本地处理

原图、字幕、字体和工程文件不会上传到服务器。编辑预览使用轻量图像，最终导出时才逐张读取原图并以原始尺寸渲染。

### 为批量漫画而设计

图片顺序是整个项目的唯一对应依据。即使图片重名，也不会错误匹配字幕；确认顺序会同时用于字幕脚本、工程保存和导出命名。

### 可以精确复现排版

BCS 顺序字幕脚本 v2 会记录原图尺寸、气泡 ID、矩形坐标、气泡类型、字体和颜色。稳定的气泡 ID 能在修改脚本后尽量保留已有手工排版。

### 自动与手动可以配合

先用自动排版快速得到初稿，再在画布中拖动、缩放和调整样式。点击“排版”会明确提示影响范围，并在结束后报告处理的图片和气泡数量。

### 面向大量图片优化

编辑过程采用轻量预览、轻量自动保存和按需重绘。批量导出逐张渲染并主动让出界面线程，减少大项目中的卡顿和内存占用。

## 使用流程

1. **创建项目并添加图片**

   软件默认按文件名自然排序；在确认窗口拖动图片即可确定最终顺序。

2. **导入字幕并自动排版**

   打开“字幕”，导入 UTF-8 TXT，或将软件生成的精确模板交给 AI 填写，然后点击“应用并自动排版”。

3. **检查、微调并导出**

   在画布中修改气泡位置、大小、字体和颜色，最后点击右上角“批量导出”，直接得到多张 PNG 成图。

## 精准字幕脚本示例

```text
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px

[图片 1]
@原文件名=scene-001.png
@原图尺寸=1080x1920

@气泡ID=p1-b1
@矩形=80,100,520,260
@气泡=对话气泡
@尾巴=右下
@字体=Microsoft YaHei
@字号=34
@颜色=#141518
@行距=1.25
@描边=3
你迟到了整整十分钟！
```

每个 `[图片 N]` 段只对应确认顺序中的第 N 张图片，文件名仅作为人工检查信息，不参与自动匹配。完整说明请阅读 [AI字幕脚本生成指南.md](AI字幕脚本生成指南.md) 和 [字幕导入格式规范.md](字幕导入格式规范.md)。

## 下载与更新

- [GitHub Releases](https://github.com/2786886095/langbai-manga-caption-studio/releases/latest) 同时提供以下平台版本：

| 平台 | 发布形式 | 说明 |
| --- | --- | --- |
| Windows | Setup EXE、Portable EXE | 推荐 Setup；支持软件内下载并安装更新 |
| Android | 签名 APK、AAB | APK 可直接安装；AAB 用于应用商店发布 |
| macOS | ZIP 应用包 | 使用临时签名，首次运行可能需要在系统安全设置中允许 |
| Linux | x64 TAR.GZ | 解压后运行主程序 |
| Web | [GitHub Pages 在线版](https://2786886095.github.io/langbai-manga-caption-studio/)、ZIP | 浏览器直接使用，数据保存在当前浏览器 |
| iOS | 未签名 IPA | 供拥有 Apple 开发者证书的开发者重新签名；不能作为 App Store 正式包直接安装 |

Windows Setup 检测到新版后，会在项目页顶部显示醒目的更新提示，并支持软件内下载安装。其他平台检测到新版后会打开 GitHub Releases。

## 常用快捷键

| 快捷键 | 操作 |
| --- | --- |
| `Ctrl + S` | 保存工程 |
| `Ctrl + O` | 打开工程 |
| `Ctrl + Z` / `Ctrl + Y` | 撤销 / 重做 |
| `Ctrl + D` | 复制当前气泡 |
| `Delete` | 删除当前气泡 |
| 鼠标右键 / 移动端长按 | 剪切、复制、粘贴、全选文字 |

<details>
<summary><strong>本地开发与 Windows 构建</strong></summary>

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release
(Get-Content build/web/index.html -Raw).Replace('<base href="/">', '<base href="./">') | Set-Content build/web/index.html -NoNewline
Copy-Item -Path build/web/* -Destination desktop-shell/web -Recurse -Force
cd desktop-shell
pnpm install
pnpm run dist
```

推送 `v*` 标签会触发 `.github/workflows/release.yml`，自动执行分析、测试并构建 Android、iOS、Windows、macOS、Linux 和 Web 版本。Windows Release 同时包含 `latest.yml` 与差分更新元数据。

</details>

## 技术与设计方向

软件核心使用 Flutter，实现 Android、iOS、Windows、macOS、Linux 与 Web 的共享界面和本地渲染逻辑；Windows 发布版使用 Electron 壳提供本地项目存储、文件夹导出和安装更新能力。

产品交互参考 Excalidraw 的本地优先工程思路、tldraw 的画布操作、manga-editor-desu 的漫画气泡流程与 Koharu 的文字排版方向；未复制这些项目的界面或源码。

## License

[MIT](LICENSE)
