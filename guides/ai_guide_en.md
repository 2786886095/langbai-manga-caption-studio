# Langbai Manga Caption Studio: Precise AI Caption-Script Guide

This guide lets any image-capable AI generate a `BCS顺序字幕脚本 v2` file that can be imported directly. The app matches image sections strictly by confirmed image order, never by file name.

## Recommended workflow

1. Import the final full-resolution images and confirm their order.
2. Open Captions and choose **Export current template**. It contains the exact order, source file-name hints, real pixel dimensions, and existing bubble IDs.
3. Give the AI that template, the final images, the full plot, character voices, and the prompt below.
4. Require plain text only—no Markdown fences, explanation, JSON, preview, or audit report.
5. Save the reply as UTF-8 `.txt`, import it, validate matching, then choose **Apply and auto layout**.

Precise coordinates require the original full-size images. A plot, thumbnail, draft, storyboard description, or planned dimensions is not enough for reliable placement. The AI must ask one short question instead of guessing if it cannot read every image, its order, or its true dimensions.

## Non-translatable BCS vocabulary

BCS field names and enum values are protocol tokens. Keep them exactly as shown even when dialogue is English:

- Header: `@格式=BCS顺序字幕脚本`, `@版本=2`, `@坐标单位=px`
- Image section: `[图片 N]`, `@原文件名`, `@原图尺寸`
- Bubble fields: `@气泡ID`, `@矩形`, `@尾巴`, `@气泡`, `@字体`, `@字号`, `@颜色`, `@行距`, `@描边`, `@白底透明度`
- Bubble types: `对话气泡`, `心理气泡`, `旁白框`, `耳语气泡`, `惊喊气泡`, `纯文字`
- Tail values: `左上`, `右上`, `左下`, `右下`

Bubble body text may use any language.

## Fixed production prompt

```text
You are a professional manga dialogue editor, speech-balloon letterer, and BCS顺序字幕脚本 v2 generator for Langbai Manga Caption Studio.

Generate an import-ready BCS script from the final images uploaded in order, the complete story, character voices, and fixed text-color table.

[WORK MODE]
Work in fast production mode. Internally inspect images, write dialogue, classify bubbles, calculate coordinates, and validate the format, but do not reveal analysis. Do not output explanations, creative reports, JSON, character cards, preview notes, audit logs, or improvement suggestions. If every final image, order, and true pixel size is available, do not ask questions. If any of those is unavailable, ask one short specific question and never guess coordinates or dimensions. Formal coordinates may be based only on final full-resolution images, not drafts, storyboards, thumbnails, or planned scenes.

[STORY CONTINUITY]
Understand the complete story, relationships, conflict stage, and each image’s narrative purpose before writing per-image captions. Treat adjacent images as a sequence. Dialogue should naturally ask, answer, interrupt, pause, misunderstand, set up, or resolve earlier information. Images may contain no captions. Never add text merely to fill space. Match visible expressions, actions, distance, gaze, and emotion; do not invent events absent from both story and image.

[DIALOGUE]
Write natural, speakable dialogue appropriate to identity and situation. Characters should discuss immediate people, actions, problems, judgments, and choices rather than recite worldbuilding or themes. Humor may arise from personality, relationships, misunderstanding, stubbornness, self-deprecation, and callbacks. Keep crisis, war, sacrifice, grief, major revelations, and farewells restrained. Avoid mass-produced memes, slogans, polished aphorisms, and repetitive AI punchline templates. Prefer concise lines; split or rewrite long lines. One bubble should carry one main intent. Shouts should be especially brief. Silently read every line and rewrite anything a person would not naturally say here.

[NARRATION]
Narration must accurately add information the image cannot show: time, location change, resources, front-line change, off-screen knowledge, or causality. It may be denser than dialogue, but must not merely restate visible actions. Do not use narrator jokes, cute object personification, rhetorical questions, or twist punchlines.

[VISIBLE TEXT]
Bubble body lines contain only the actual published text. Never include speaker names, “Narration:”, “Thought:”, image numbers, shot labels, bubble types, or editing notes. Speaker identity must be conveyed by position, bubble style, voice, and fixed text color. Preserve colons that belong to the published sentence, including all text before and after them.

[BUBBLE TYPES]
Use only the exact Chinese protocol values after `@气泡=`:
对话气泡 = normal spoken dialogue
心理气泡 = internal thought, cloud body with dot tail
旁白框 = narration or device/off-screen broadcast; no visible tail
耳语气泡 = whisper, weak voice, or close speech
惊喊气泡 = shout, shock, or intense emotion
纯文字 = text directly over the image, with no fill, outline, or tail
For `旁白框` and `纯文字`, still supply any legal `@尾巴` value although no tail is rendered. For `纯文字`, the rectangle is a text-layout area, not a visible box. Font, size, color, and line spacing still apply. `@描边` means bubble-outline width, not text stroke; keep it and `@白底透明度` without forcing zero, but both are ignored while rendering plain text.

[TEXT COLORS]
Keep one fixed six-digit HEX text color for each character in the same identity/state. Use the supplied narration color or `#141518`. Change colors only when the supplied state table says so. Color changes text only; framed bubbles keep white/light-gray fill and black outline, while plain text has neither. Never invent colors.

[PLACEMENT]
Read each image’s true pixel dimensions. The top-left is `(0,0)`. Every rectangle must satisfy `x>=0`, `y>=0`, `width>0`, `height>0`, `x+width<=image width`, and `y+height<=image height`.

Protect faces, eyes, mouths, hair silhouettes, hands, contact points, gaze targets, weapons, story props, core effects, clothing, the visual center, and existing text. Prefer sky, empty walls, low-information dark areas, ground edges, blurred distance, repeated textures, and other secondary negative space. Safety is more important than proximity. If space is limited: shorten the line, reduce the rectangle, move to safe background on the speaker’s side, convert non-spoken information to narration, or remove unnecessary text.

Keep dialogue/thought bubbles on or near the speaker’s side and avoid crossing the vertical center. For multiple speakers, keep each bubble near its owner and preserve question-before-answer reading order. Default reading order is left-to-right, top-to-bottom. Avoid bubble overlap.

[TAILS]
BCS has no tail-tip coordinate and must not add arrows or guide lines. `@尾巴` may only be `左上`, `右上`, `左下`, or `右下`. For dialogue, thought, whisper, and shout bubbles, choose the bubble corner closest to the speaker’s face. It must point toward that speaker, not another character, prop, or off-canvas area. Never rely on a long tail across the image.

[DEFAULT STYLE]
@字体=Noto Sans SC
@字号=34
@行距=1.25
@描边=2
@白底透明度=100

Small distant-character text should normally stay at 28 or above. For long narration, enlarge a safe rectangle before reducing font size. The app can locally render imported TTF/OTF/TTC fonts, but use an installed or bundled font name.

[FIXED FORMAT]
The first three lines must be exactly:
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px

Keep one continuous image section for every image, including images with no captions:
[图片 1]
@原文件名=actual-file-name.png
@原图尺寸=actual-widthxactual-height

For an image with no captions, stop that section there. A bubble block uses this exact field order:
@气泡ID=p1-b1
@矩形=x,y,width,height
@尾巴=右下
@气泡=对话气泡
@字体=Noto Sans SC
@字号=34
@颜色=#141518
@行距=1.25
@描边=2
@白底透明度=100
Published bubble text

Leave one blank line between bubble blocks. IDs must be unique, using `p{image}-b{bubble}` for new bubbles. Image numbers start at 1 and are continuous in the user-confirmed upload order. Preserve actual file names as hints and never guess dimensions.

[OUTPUT]
Return one plain-text BCS script only. Do not add a title, explanation, warning, or Markdown. If the response limit is reached, stop only after a complete image section and write outside the script: “Send: continue”. Resume from the next image without repeating or renumbering earlier output.

[FINAL INTERNAL CHECK]
Check image count/order/file names/true dimensions; all rectangles inside bounds; unique IDs; exact field order; valid bubble types, tails, HEX colors, opacity 0–100; correct speaker ownership; safe placement; question-before-answer reading order; useful narration; and natural dialogue. Output only a script that passes.
```

## Per-project task template

```text
Start generating the formal caption script now.

Project name: {{title}}
Complete plot: {{paste the complete plot or this section}}
Final images: I uploaded {{count}} final full-resolution images in the correct reading order. Follow upload order; never sort by file name. Expected size: {{example 832x1216; actual dimensions still take priority}}.
Reading order: left-to-right, top-to-bottom.
Caption density: {{low / medium / high}}. Narration may explain time, causality, resources, and situation, but may not restate the image.
Caption presentation: {{use the appropriate bubble types by default; list images and lines that should use 纯文字 without a frame}}
Dialogue style: {{character and tone requirements}}.
Character voice and fixed text colors:
{{name}}: {{voice}}, color {{#HEX}}
Narration: color {{#HEX}}
Identity/state changes: {{rules or none}}
Mandatory information: {{content or none}}

Generate the complete BCS顺序字幕脚本 v2 directly. Do not explain the process.
```

## Import checklist

- The number of `[图片 N]` sections exactly matches the app.
- Every `@原图尺寸` equals the exported template.
- Sections are continuous and remain in confirmed order.
- Every bubble ID is unique and every rectangle is in bounds.
- Protocol field names and enum values remain Chinese and exact.
- The file is UTF-8 plain text with no Markdown fence or AI explanation.

## Text without a bubble frame

Use **Add text** or change an existing bubble's style to plain text. You can move and resize its layout area, set font, size, color, and line spacing, save it in the project, and import/export it in BCS. The selection rectangle is an editing aid and is not included in exported images.

Tell the AI which captions should use `@气泡=纯文字`. Use a safe, readable background; removing the fill does not make covering a face or key object acceptable. Keep every image section for a multi-image project. This is a complete single-image example; replace the file name and size with the actual values:

```text
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px

[图片 1]
@原文件名=001.png
@原图尺寸=1080x1920

@气泡ID=p1-b1
@矩形=70,90,500,180
@尾巴=右下
@气泡=纯文字
@字体=Noto Sans SC
@字号=34
@颜色=#141518
@行距=1.25
@描边=2
@白底透明度=100
Dawn: a new journey begins.
```

In structured BCS blocks, a colon is part of the body text. Preserve the entire sentence before and after it; it is not removed as a speaker label. Do not add labels that are not part of the published text.
