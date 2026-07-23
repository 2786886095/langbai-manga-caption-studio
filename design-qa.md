# Design QA

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
