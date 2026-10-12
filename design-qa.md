# 设计与交互验证记录

## 商业级编辑体验重构候选：验收进行中

当前候选未正式发布。本节记录本次工作的验收范围；不能将下方历史版本的“passed”、旧截图或旧测试数量当作本候选通过证据。实际结果需要在修复与复测完成后，按对应修订和日志填写。

### 新工作台验收项

| 场景 | 需要观察的行为 | 本次结论 |
| --- | --- | --- |
| 对象选中与输入 | 单击选中、空白取消；输入不丢焦点；预览正文与对象正文一致 | 待记录最终证据 |
| 固定字号 | 缩小矩形不偷偷缩字；超框警告明确；不截断原文 | 待记录最终证据 |
| 自动适应 | 主动开启；显示实际字号；样式和完整正文保留 | 待记录最终证据 |
| 文字与气泡样式 | 文字描边、字距、对齐独立；纯文字没有底色、外框和尾巴 | 待记录最终证据 |
| 章节文本与批量应用 | 列表定位、多选、作用范围与属性勾选；未选择属性不扩散修改 | 待记录最终证据 |
| 关联文字样式 | 关联对象同步；解除关联后可独立修改，不同化正文和矩形 | 待记录最终证据 |
| 本地字体库 | 内置十种完整字体；名称来自名称表；搜索、收藏、最近、真实样本、批量导入 | 待记录最终证据 |
| 字体一致性 | 内容身份去重、项目字体恢复、缺字体身份保留、缺字警告、载入失败不假成功 | 待记录最终证据 |
| BCS v3 / v2 | v3 保留逐行正文和新属性；旧版仍可读；v2 导出先提示属性损失 | 待记录最终证据 |
| 保存与历史 | 成功提交后才显示已保存；失败提示；版本恢复和会话撤销有明确区别 | 待记录最终证据 |
| 打开工程 | 当前修改先提交，另一份工程开成新项目，不覆盖原项目身份 | 待记录最终证据 |
| 导出 | 技术警告、选择图片、目标路径、覆盖询问、进度、取消和失败重试；不把浏览器下载当已写盘 | 待记录最终证据 |

### 平台证据必须分开

- Flutter 自动测试、静态分析与本地 Web 构建分别登记，不写成所有平台实测。
- 浏览器本地存储需验证重载后恢复；仅编译成功或模拟 IndexedDB 不等于真实浏览器验证。
- Windows Setup 安装运行及内更新应做端到端验证，便携版启动不能替代。
- Android 与 iOS 应实测竖横屏、触摸、输入法、文件选择和字体导入；桌面模拟尺寸不替代实机。
- iOS 未签名包不能写成普通用户可直接安装；macOS/Linux 打包也不替代运行依赖检查。
- 完整字体资源会增加包体，启动懒加载、首次字体选择和大项目保存/导出需要独立性能记录。

### 保存安全的验收要求

不能只检查文件存在，应回读确认正文、对象身份、字体和几何属于对应修订。修改发生在保存过程中时，旧写入完成不能把新修改标为已保存；保存失败不得覆盖或清空可恢复数据。关闭、切换项目、导入其他工程和恢复版本都属于需要检查的边界。

当前已观察问题及后续修复状态由执行者在取得新日志后登记，未填写前不宣称“无 P0/P1/P2”或“全端已完成”。操作说明见 [候选指南](docs/commercial-refactor.md)。

## 历史版本档案（不作为本次候选结论）

## 2026-07-23 preset rollback with square narration retained

- Removed the category selector and all 21 proportion presets.
- Restored the original five bubble-type controls in the inspector.
- Kept the narration body as a white rectangle with a pure black outline, exact 90-degree corners, and no tail.
- Removed preset-only localization and tests while retaining a dedicated square-corner narration geometry test.

final result: passed

- Source visual truth: `C:\Users\浪白\.codex\generated_images\019f6de0-8c06-7cb3-a5be-69bd06a3a392\exec-57b6b3e1-c134-4da8-a54a-8d2d44a14e24.png`
- Implementation screenshot: `F:\AI\agent\codex\bubble-caption-studio\qa-0.5.0-pass2.png`
- Viewport: 1424 × 985 desktop
- State: demo chapter, page 1 selected, rendered view, first dialogue bubble selected, inspector open

## Full-view comparison evidence

The source and implementation were opened together at the same desktop state. Both use the selected Chapter Review Desk structure: four-step workflow header, rich chapter queue, large centered canvas, context inspector, batch-status footer, issue navigation, and a dominant approval action. The implementation preserves the production image aspect ratio and existing solid pink anime brand instead of reproducing mock-only sample artwork.

## Focused state evidence

- `qa-0.5.0-original-mode.png`: the 原图/渲染 control was exercised; all rendered bubbles and handles disappear while the source pixels remain unchanged.
- `qa-0.5.0-inspector-closed.png`: the close control was exercised; the inspector collapses and the canvas expands without hiding review navigation.
- Desktop reload console check: 0 runtime or log errors.

## Required fidelity surfaces

- Fonts and typography: Chinese UI uses the existing Microsoft YaHei/PingFang/Noto fallback, 10–14 px compact UI hierarchy, 17–23 px product headings, and stable truncation in the page queue. No clipped primary labels were observed.
- Spacing and layout rhythm: 394 px chapter queue, flexible canvas, 348 px contextual inspector, 104 px header, and 78 px review footer reproduce the selected mock's main proportions. Separators are used before surface tint and shadow.
- Colors and visual tokens: solid `#E94D72` primary, warm paper/panel surfaces, black ink, green success, and pink warning states match the source direction. No gradients are used.
- Image quality and asset fidelity: the supplied mascot and original image are rendered directly, without generated placeholders or altered source pixels. Canvas filtering remains high quality.
- Copy and content: workflow, chapter queue, original/rendered comparison, three bubble presets, fixed four-direction pointer controls, batch state, and approval copy match the selected concept and product requirements.

## Comparison history

### Pass 1 — blocked

- P1: the demo project highlighted 图片 instead of 复核 even though all pages were matched and three required review.
- P2: the canvas toolbar retained five separate bubble commands, compressing the filename, comparison control, and image dimensions.

Fixes made:

- Workflow activation now derives only from actual image, matching, and approval state.
- Bubble creation, duplication, layer order, deletion, and inspector reopening were consolidated into one labeled edit menu; undo/redo and comparison remain directly accessible.

### Pass 2 — passed

- The review step is visibly active and reports three pending pages.
- The canvas toolbar has readable current-page, comparison, history, edit-menu, and dimension regions with no collision.
- No actionable P0, P1, or P2 differences remain.

## Findings

No actionable P0/P1/P2 findings remain.

## Follow-up polish

- P3: real projects with varied artwork will provide stronger thumbnail differentiation than the repeated local demo image.

## Implementation checklist

- [x] Rich page queue with subtitle summaries
- [x] Data-driven workflow state
- [x] Original/rendered comparison
- [x] Context inspector collapse and reopen path
- [x] Consolidated bubble editing commands
- [x] Batch-status footer and issue navigation
- [x] Desktop console check

final result: passed

## 0.7.1 default name ordering QA

- `qa-0.7.1-name-order.png`: the file chooser was deliberately supplied `qa-import-002.png` before `qa-import-001.png`; the confirmation dialog displayed `001` first and `002` second.
- The confirmation dialog explicitly states that filename natural sorting is only the default and remains manually reorderable.
- Script mapping still uses the final confirmed order rather than filenames.
- Static analysis passed; all 16 automated tests passed; Electron runtime console reported 0 errors.

final result: passed

## 0.7.0 project hub and settings QA

- `qa-0.7.0-project-home.png`: application launches on the project hub before any image workspace.
- `qa-0.7.0-create-dialog.png`: project name is optional and the dialog explains time-based naming.
- `qa-0.7.0-workspace.png`: blank-name creation produced `项目 2026-07-17 14-07-29`; the workflow contains only 图片、字幕、排版, with export isolated at the top right.
- `qa-0.7.0-settings.png`: settings expose default save directory, location prompting, export naming, autosave toggle, and autosave interval without gradients or layout clipping.
- `qa-0.7.0-project-saved.png`: switching back preserved the time-named project in the project hub.
- `qa-0.7.0-delete-dialog.png` and `qa-0.7.0-project-deleted.png`: deletion requires confirmation and removes the local project.
- Static analysis passed; all 16 automated tests passed; Electron runtime console reported 0 errors during the full create/switch/delete/settings flow.

final result: passed

## 0.6.0 sequence workflow QA

- `qa-0.6.0-order-dialog.png`: selected `qa-import-002.png` before `qa-import-001.png`; the app displayed both in that exact initial order and required explicit confirmation instead of filename sorting.
- `qa-0.6.0-order-confirmed.png`: the project queue remained `002, 001` after confirmation.
- `qa-0.6.0-script-v2.png`: the generated script uses `[图片 1]`, `[图片 2]`, includes each original filename only as a hint, and records `545x593` for both actual source images.
- `qa-0.6.0-export-gate.png`: export is blocked while two pages are unapproved and invalid.
- Final desktop smoke test: 0 console/runtime errors.
- Static analysis: passed. Automated tests: 15 passed.

final result: passed

## 0.5.1 scoped interaction QA

- Compared the selected design source and `qa-blank-click.png` together at the same 1424 × 985 desktop viewport.
- Removed all user-facing speaker controls and speaker summaries without disturbing the established queue, canvas, inspector, or review flow.
- `qa-dialogue.png`: the dialogue pointer joins the ellipse in the selected lower-right corner region; automated geometry checks cover upper-left, upper-right, lower-left, and lower-right attachment regions.
- `qa-thought.png`: the thought bubble keeps the same elliptical body as dialogue and replaces only the pointer with three decreasing circular dots along the fixed corner direction.
- `qa-blank-click.png`: clicking unused canvas space keeps every bubble in place while hiding the selection rectangle and all eight resize handles.
- Static analysis passed with no issues; all 10 automated tests passed.

final result: passed

## 1.3.0 release verification boundaries — 2026-10-12

- Stable version metadata: Flutter `1.3.0+39`, Windows shell `1.3.0`.
- Local Flutter 3.24 / Dart 3.5: analysis reported no issues; complete VM suite reported `148 passed, 4 skipped, 0 failed`. The four skipped browser-specific cases are not VM acceptance.
- Matching-input source probe: baseline/rollback kept `CHANGED` after attempting undo and disabled undo; modified source restored `BEFORE` and retained undo history after changing pages. Runtime exception was `null` in all three probes.
- Real local browser flow on the same refactored editor before stable version promotion: imported two images; edited and reopened Chinese text; imported a distinct-content same-family font; verified Ctrl+Z/Ctrl+Y, saved-version restoration, object-click selection and background-click deselection.
- Real browser direct-image export produced one downloaded PNG; explicit arbitrary-image batch scope was exercised. A no-op batch application did not create an undo entry.
- The original workspace and original input files were not modified. JPEG/ICC decoding differences mean the export observation is not evidence of universal pixel-identical background output.
- The native directory picker was not completed by automation. Windows Setup installation/in-app update, Android/iOS device permissions and orientation, macOS/Linux desktop use, and measured 100ms/60fps targets remain unverified.
- All-platform build and release asset checks are recorded in the `v1.3.0` GitHub Actions run and release; building a package does not substitute for device acceptance.

Result: local automated and specified browser flows passed; remaining device/performance acceptance explicitly open.
