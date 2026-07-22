import 'package:flutter/material.dart';

import 'app_settings.dart';

class AppLanguageOption {
  const AppLanguageOption(this.code, this.nativeName, this.locale);

  final String code;
  final String nativeName;
  final Locale locale;
}

class AppLocaleController extends ChangeNotifier {
  AppLocaleController._();

  static final instance = AppLocaleController._();

  static const languages = <AppLanguageOption>[
    AppLanguageOption('zh_CN', '简体中文', Locale('zh', 'CN')),
    AppLanguageOption('zh_TW', '繁體中文', Locale('zh', 'TW')),
    AppLanguageOption('en', 'English', Locale('en')),
    AppLanguageOption('ja', '日本語', Locale('ja')),
    AppLanguageOption('ko', '한국어', Locale('ko')),
  ];

  static const supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];

  String _languageCode = 'zh_CN';
  bool _initialized = false;

  String get languageCode => _languageCode;
  Locale get locale => languages
      .firstWhere((item) => item.code == _languageCode,
          orElse: () => languages.first)
      .locale;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final settings = await loadAppSettings();
    setLanguage(settings.languageCode);
  }

  void setLanguage(String code) {
    final normalized = supportedLanguageCodes.contains(code) ? code : 'zh_CN';
    if (_languageCode == normalized) return;
    _languageCode = normalized;
    notifyListeners();
  }
}

String tr(String source, {String? languageCode}) {
  final code = languageCode ?? AppLocaleController.instance.languageCode;
  if (code == 'zh_CN' || source.isEmpty) return source;
  final translated =
      _translations[source]?[code] ?? _workspaceTranslations[source]?[code];
  if (translated != null) return translated;
  return _translateDynamic(source, code);
}

String trArgs(
  String source,
  Map<String, Object?> values, {
  String? languageCode,
}) {
  var result = tr(source, languageCode: languageCode);
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

String _translateDynamic(String source, String code) {
  for (final pattern in _dynamicPatterns) {
    final match = pattern.expression.firstMatch(source);
    if (match == null) continue;
    var output = pattern.values[code] ?? source;
    for (var i = 1; i <= match.groupCount; i++) {
      output = output.replaceAll('{$i}', match.group(i) ?? '');
    }
    return output;
  }
  if (code == 'zh_TW') return _toTraditional(source);
  return source;
}

class _TranslationPattern {
  const _TranslationPattern(this.expression, this.values);

  final RegExp expression;
  final Map<String, String> values;
}

final _dynamicPatterns = <_TranslationPattern>[
  _TranslationPattern(
    RegExp(r'^气泡 (\d+) 没有文字$'),
    const {
      'en': 'Bubble {1} has no text',
      'ja': '吹き出し {1} に文字がありません',
      'ko': '말풍선 {1}에 글자가 없습니다',
      'zh_TW': '氣泡 {1} 沒有文字'
    },
  ),
  _TranslationPattern(
    RegExp(r'^气泡 (\d+) 尺寸过小$'),
    const {
      'en': 'Bubble {1} is too small',
      'ja': '吹き出し {1} が小さすぎます',
      'ko': '말풍선 {1} 크기가 너무 작습니다',
      'zh_TW': '氣泡 {1} 尺寸過小'
    },
  ),
  _TranslationPattern(
    RegExp(r'^气泡 (\d+) 超出图片边界$'),
    const {
      'en': 'Bubble {1} extends outside the image',
      'ja': '吹き出し {1} が画像の外に出ています',
      'ko': '말풍선 {1}이 이미지 경계를 벗어납니다',
      'zh_TW': '氣泡 {1} 超出圖片邊界'
    },
  ),
  _TranslationPattern(
    RegExp(r'^气泡 (\d+) 的文字可能溢出$'),
    const {
      'en': 'Text may overflow bubble {1}',
      'ja': '吹き出し {1} の文字があふれる可能性があります',
      'ko': '말풍선 {1}의 글자가 넘칠 수 있습니다',
      'zh_TW': '氣泡 {1} 的文字可能溢出'
    },
  ),
  _TranslationPattern(
    RegExp(r'^气泡 (\d+) 与气泡 (\d+) 明显重叠$'),
    const {
      'en': 'Bubbles {1} and {2} overlap significantly',
      'ja': '吹き出し {1} と {2} が大きく重なっています',
      'ko': '말풍선 {1}과 {2}가 크게 겹칩니다',
      'zh_TW': '氣泡 {1} 與氣泡 {2} 明顯重疊'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：位置“(.+)”无效，请使用(.+)。$'),
    const {
      'en': 'Line {1}: invalid position “{2}”. Use {3}.',
      'ja': '{1} 行目：位置「{2}」は無効です。{3} を使用してください。',
      'ko': '{1}행: 위치 “{2}”이 유효하지 않습니다. {3} 중 하나를 사용하세요.',
      'zh_TW': '第 {1} 行：位置「{2}」無效，請使用{3}。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@尾巴位置 已停用；尾部固定在气泡边缘，只需设置四向 @尾巴。$'),
    const {
      'en':
          'Line {1}: @尾巴位置 is retired. The tail is fixed to the bubble edge; set only the four-way @尾巴.',
      'ja': '{1} 行目：@尾巴位置 は廃止されました。しっぽは吹き出し端に固定されるため、4方向の @尾巴 だけを指定してください。',
      'ko': '{1}행: @尾巴位置는 더 이상 사용하지 않습니다. 꼬리는 말풍선 가장자리에 고정되므로 4방향 @尾巴만 설정하세요.',
      'zh_TW': '第 {1} 行：@尾巴位置 已停用；尾部固定在氣泡邊緣，只需設定四向 @尾巴。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@(.+) 必须包含两个百分比，例如 68%,12%。$'),
    const {
      'en': 'Line {1}: @{2} must contain two percentages, for example 68%,12%.',
      'ja': '{1} 行目：@{2} には 68%,12% のように2つの百分率が必要です。',
      'ko': '{1}행: @{2}에는 68%,12%처럼 백분율 2개가 필요합니다.',
      'zh_TW': '第 {1} 行：@{2} 必須包含兩個百分比，例如 68%,12%。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@(.+) 的数值必须在 0% 到 100% 之间。$'),
    const {
      'en': 'Line {1}: @{2} values must be between 0% and 100%.',
      'ja': '{1} 行目：@{2} の値は 0%～100% にしてください。',
      'ko': '{1}행: @{2} 값은 0%에서 100% 사이여야 합니다.',
      'zh_TW': '第 {1} 行：@{2} 的數值必須在 0% 到 100% 之間。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@(.+) 必须在 (.+) 到 (.+) 之间。$'),
    const {
      'en': 'Line {1}: @{2} must be between {3} and {4}.',
      'ja': '{1} 行目：@{2} は {3}～{4} にしてください。',
      'ko': '{1}행: @{2}는 {3}에서 {4} 사이여야 합니다.',
      'zh_TW': '第 {1} 行：@{2} 必須在 {3} 到 {4} 之間。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(.+) 的原图尺寸记录与图片数据不一致$', dotAll: true),
    const {
      'en': '{1}: recorded source dimensions do not match the image data',
      'ja': '{1}：記録された元画像サイズが画像データと一致しません',
      'ko': '{1}: 기록된 원본 크기가 이미지 데이터와 일치하지 않습니다',
      'zh_TW': '{1} 的原圖尺寸記錄與圖片資料不一致'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(.+) 的字幕与气泡数量不一致$', dotAll: true),
    const {
      'en': '{1}: caption and bubble counts do not match',
      'ja': '{1}：字幕数と吹き出し数が一致しません',
      'ko': '{1}: 자막 수와 말풍선 수가 일치하지 않습니다',
      'zh_TW': '{1} 的字幕與氣泡數量不一致'
    },
  ),
  _TranslationPattern(
    RegExp(r'^项目图片不存在：(.+)$'),
    const {
      'en': 'Project image does not exist: {1}',
      'ja': 'プロジェクト画像がありません：{1}',
      'ko': '프로젝트 이미지가 없습니다: {1}',
      'zh_TW': '專案圖片不存在：{1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(已导入|已添加) (\d+) 张图片，项目共 (\d+) 张。$'),
    const {
      'en': '{2} images processed; the project now has {3} images.',
      'ja': '{2} 枚を追加し、プロジェクトは合計 {3} 枚になりました。',
      'ko': '이미지 {2}장을 처리했으며 프로젝트에는 총 {3}장이 있습니다.',
      'zh_TW': '{1} {2} 張圖片，專案共 {3} 張。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^跳过 (\d+) 个无法读取的文件。$'),
    const {
      'en': 'Skipped {1} unreadable files.',
      'ja': '読み込めないファイル {1} 件をスキップしました。',
      'ko': '읽을 수 없는 파일 {1}개를 건너뛰었습니다.',
      'zh_TW': '略過 {1} 個無法讀取的檔案。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(\d+) 张图片已按确认顺序放在第 (\d+)–(\d+) 位。$'),
    const {
      'en':
          '{1} images were placed at positions {2}–{3} in the confirmed order.',
      'ja': '{1} 枚を確認済み順序で {2}～{3} 番に配置しました。',
      'ko': '이미지 {1}장을 확정 순서에 따라 {2}–{3}번 위치에 배치했습니다.',
      'zh_TW': '{1} 張圖片已依確認順序放在第 {2}–{3} 位。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^字幕已应用并完成排版：(\d+) 张图片，共 (\d+) 个气泡。脚本中的矩形坐标和样式已生效。$'),
    const {
      'en':
          'Captions applied and laid out: {1} images, {2} bubbles. Script rectangles and styles are active.',
      'ja': '字幕を適用して配置しました：{1} 枚、{2} 吹き出し。スクリプトの矩形とスタイルが反映されています。',
      'ko': '자막 적용 및 배치 완료: 이미지 {1}장, 말풍선 {2}개. 스크립트의 사각형 좌표와 스타일이 적용되었습니다.',
      'zh_TW': '字幕已套用並完成排版：{1} 張圖片，共 {2} 個氣泡。腳本中的矩形座標和樣式已生效。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^另有 (\d+) 条格式警告。$'),
    const {
      'en': 'There are {1} more format warnings.',
      'ja': 'ほかに {1} 件の形式警告があります。',
      'ko': '형식 경고가 {1}개 더 있습니다.',
      'zh_TW': '另有 {1} 條格式警告。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^将根据图片尺寸重新计算 (\d+) 张图片中的气泡位置。(.+)$', dotAll: true),
    const {
      'en':
          'Bubble positions in {1} images will be recalculated from image dimensions. {2}',
      'ja': '{1} 枚の吹き出し位置を画像寸法から再計算します。{2}',
      'ko': '이미지 {1}장의 말풍선 위치를 이미지 크기에 따라 다시 계산합니다. {2}',
      'zh_TW': '將依圖片尺寸重新計算 {1} 張圖片中的氣泡位置。{2}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^排版完成：(\d+) 张图片，共 (\d+) 个气泡。可继续手动微调。$'),
    const {
      'en':
          'Layout complete: {1} images, {2} bubbles. You can continue fine-tuning manually.',
      'ja': '配置完了：{1} 枚、{2} 吹き出し。引き続き手動で微調整できます。',
      'ko': '배치 완료: 이미지 {1}장, 말풍선 {2}개. 계속 수동으로 미세 조정할 수 있습니다.',
      'zh_TW': '排版完成：{1} 張圖片，共 {2} 個氣泡。可繼續手動微調。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^已将 (\d+) 项属性应用到 (\d+) 个气泡$'),
    const {
      'en': 'Applied {1} properties to {2} bubbles',
      'ja': '{1} 項目を {2} 個の吹き出しに適用しました',
      'ko': '속성 {1}개를 말풍선 {2}개에 적용했습니다',
      'zh_TW': '已將 {1} 項屬性套用到 {2} 個氣泡'
    },
  ),
  _TranslationPattern(
    RegExp(r'^导出完成：已直接写入 (\d+) 张 PNG，跳过 (\d+) 张\n(.+)$', dotAll: true),
    const {
      'en': 'Export complete: wrote {1} PNG images; skipped {2}\n{3}',
      'ja': '書き出し完了：PNG {1} 枚を書き込み、{2} 枚をスキップしました\n{3}',
      'ko': '내보내기 완료: PNG 이미지 {1}장을 저장하고 {2}장을 건너뛰었습니다\n{3}',
      'zh_TW': '匯出完成：已直接寫入 {1} 張 PNG，略過 {2} 張\n{3}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^导出完成：已直接写入 (\d+) 张 PNG\n(.+)$', dotAll: true),
    const {
      'en': 'Export complete: wrote {1} PNG images\n{2}',
      'ja': '書き出し完了：PNG {1} 枚を書き込みました\n{2}',
      'ko': '내보내기 완료: PNG 이미지 {1}장을 저장했습니다\n{2}',
      'zh_TW': '匯出完成：已直接寫入 {1} 張 PNG\n{2}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(\d+) 张$'),
    const {'en': '{1} images', 'ja': '{1} 枚', 'ko': '{1}장', 'zh_TW': '{1} 張'},
  ),
  _TranslationPattern(
    RegExp(r'^(\d+)/(\d+) 已匹配$'),
    const {
      'en': '{1}/{2} matched',
      'ja': '{1}/{2} 割り当て済み',
      'ko': '{1}/{2} 매칭됨',
      'zh_TW': '{1}/{2} 已配對'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(\d+)/(\d+) 已匹配字幕$'),
    const {
      'en': '{1}/{2} captions matched',
      'ja': '{1}/{2} 字幕割り当て済み',
      'ko': '{1}/{2} 자막 매칭됨',
      'zh_TW': '{1}/{2} 已配對字幕'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(\d+) 条字幕$'),
    const {
      'en': '{1} captions',
      'ja': '字幕 {1} 件',
      'ko': '자막 {1}개',
      'zh_TW': '{1} 條字幕'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(.+) × (.+) · (\d+) 个气泡$'),
    const {
      'en': '{1} × {2} · {3} bubbles',
      'ja': '{1} × {2}・吹き出し {3} 個',
      'ko': '{1} × {2} · 말풍선 {3}개',
      'zh_TW': '{1} × {2} · {3} 個氣泡'
    },
  ),
  _TranslationPattern(
    RegExp(r'^当前：第01话 · (.+)$', dotAll: true),
    const {
      'en': 'Current: Episode 01 · {1}',
      'ja': '現在：第01話・{1}',
      'ko': '현재: 01화 · {1}',
      'zh_TW': '目前：第01話 · {1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^已导入 · (.+)$'),
    const {
      'en': 'Imported · {1}',
      'ja': '読み込み済み・{1}',
      'ko': '가져옴 · {1}',
      'zh_TW': '已匯入 · {1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^图片 (\d+) → (.+)：(\d+) 个气泡$', dotAll: true),
    const {
      'en': 'Image {1} → {2}: {3} bubbles',
      'ja': '画像 {1} → {2}：吹き出し {3} 個',
      'ko': '이미지 {1} → {2}: 말풍선 {3}개',
      'zh_TW': '圖片 {1} → {2}：{3} 個氣泡'
    },
  ),
  _TranslationPattern(
    RegExp(r'^另有 (\d+) 张图片，匹配规则相同。$'),
    const {
      'en': '{1} more images use the same matching rules.',
      'ja': 'ほかの {1} 枚にも同じ照合規則を適用します。',
      'ko': '나머지 이미지 {1}장에도 같은 매칭 규칙이 적용됩니다.',
      'zh_TW': '另有 {1} 張圖片，配對規則相同。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^本地项目数据可能已经损坏：(.+)$', dotAll: true),
    const {
      'en': 'Local project data may be corrupted: {1}',
      'ja': 'ローカルのプロジェクトデータが破損している可能性があります：{1}',
      'ko': '로컬 프로젝트 데이터가 손상되었을 수 있습니다: {1}',
      'zh_TW': '本機專案資料可能已損壞：{1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^选择目录并导出 (\d+) 张$'),
    const {
      'en': 'Choose folder and export {1} images',
      'ja': 'フォルダーを選択して {1} 枚を書き出す',
      'ko': '폴더를 선택하고 이미지 {1}장 내보내기',
      'zh_TW': '選擇目錄並匯出 {1} 張'
    },
  ),
  _TranslationPattern(
    RegExp(r'^“(.+)”已在导出目录中。是否用当前修改后的成图覆盖它？$', dotAll: true),
    const {
      'en':
          '“{1}” already exists in the export folder. Overwrite it with the current edited image?',
      'ja': '「{1}」は書き出し先に既にあります。現在の編集済み画像で上書きしますか？',
      'ko': '“{1}”이(가) 내보내기 폴더에 이미 있습니다. 현재 수정된 이미지로 덮어쓸까요?',
      'zh_TW': '「{1}」已在匯出目錄中。是否用目前修改後的成圖覆蓋？'
    },
  ),
  _TranslationPattern(
    RegExp(r'^(.+)\n\n请确认文件由本软件生成，且内容未被破坏。$', dotAll: true),
    const {
      'en':
          '{1}\n\nMake sure the file was created by this app and has not been altered or corrupted.',
      'ja': '{1}\n\nこのアプリで作成され、内容が変更・破損していないファイルか確認してください。',
      'ko': '{1}\n\n이 앱에서 생성되었고 내용이 변경되거나 손상되지 않은 파일인지 확인하세요.',
      'zh_TW': '{1}\n\n請確認檔案由本軟體產生，且內容未被破壞。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^导出失败：(.+)$', dotAll: true),
    const {
      'en': 'Export failed: {1}',
      'ja': '書き出しに失敗しました：{1}',
      'ko': '내보내기 실패: {1}',
      'zh_TW': '匯出失敗：{1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^保存工程失败：(.+)$', dotAll: true),
    const {
      'en': 'Failed to save project: {1}',
      'ja': 'プロジェクトの保存に失敗しました：{1}',
      'ko': '프로젝트 저장 실패: {1}',
      'zh_TW': '儲存工程失敗：{1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^字幕文件读取失败：(.+)$', dotAll: true),
    const {
      'en': 'Failed to read caption file: {1}',
      'ja': '字幕ファイルを読み込めませんでした：{1}',
      'ko': '자막 파일 읽기 실패: {1}',
      'zh_TW': '字幕檔案讀取失敗：{1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^模板导出失败：(.+)$', dotAll: true),
    const {
      'en': 'Failed to export template: {1}',
      'ja': 'テンプレートの書き出しに失敗しました：{1}',
      'ko': '템플릿 내보내기 실패: {1}',
      'zh_TW': '範本匯出失敗：{1}'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：字幕正文为空，已忽略。$'),
    const {
      'en': 'Line {1}: empty caption body was ignored.',
      'ja': '{1} 行目：字幕本文が空のため無視しました。',
      'ko': '{1}행: 자막 본문이 비어 있어 무시했습니다.',
      'zh_TW': '第 {1} 行：字幕正文為空，已忽略。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：指令必须使用 @名称=值。$'),
    const {
      'en': 'Line {1}: directives must use @name=value.',
      'ja': '{1} 行目：指令は @名前=値 の形式にしてください。',
      'ko': '{1}행: 지시문은 @이름=값 형식을 사용해야 합니다.',
      'zh_TW': '第 {1} 行：指令必須使用 @名稱=值。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@原图尺寸 必须是正整数宽x高，例如 1080x1920。$'),
    const {
      'en':
          'Line {1}: @原图尺寸 must be positive integer widthxheight, for example 1080x1920.',
      'ja': '{1} 行目：@原图尺寸 は正の整数の幅x高さ（例 1080x1920）で指定してください。',
      'ko': '{1}행: @原图尺寸는 양의 정수 너비x높이여야 합니다(예: 1080x1920).',
      'zh_TW': '第 {1} 行：@原图尺寸 必須是正整數寬x高，例如 1080x1920。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：未知指令 @(.+)，请检查拼写。$'),
    const {
      'en': 'Line {1}: unknown directive @{2}; check its spelling.',
      'ja': '{1} 行目：不明な指令 @{2} です。綴りを確認してください。',
      'ko': '{1}행: 알 수 없는 지시문 @{2}입니다. 철자를 확인하세요.',
      'zh_TW': '第 {1} 行：未知指令 @{2}，請檢查拼字。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^图片段顺序错误：第 (\d+) 段应写为 \[图片 (\d+)\]。$'),
    const {
      'en': 'Image section order error: section {1} must be [图片 {2}].',
      'ja': '画像段の順序エラー：第 {1} 段は [图片 {2}] としてください。',
      'ko': '이미지 구간 순서 오류: {1}번째 구간은 [图片 {2}]여야 합니다.',
      'zh_TW': '圖片段順序錯誤：第 {1} 段應寫為 [图片 {2}]。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 张缺少有效的 @原图尺寸。$'),
    const {
      'en': 'Image {1} is missing a valid @原图尺寸.',
      'ja': '画像 {1} に有効な @原图尺寸 がありません。',
      'ko': '이미지 {1}에 유효한 @原图尺寸가 없습니다.',
      'zh_TW': '第 {1} 張缺少有效的 @原图尺寸。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^图片共 (\d+) 张，但脚本有 (\d+) 个图片段。两者必须完全一致。$'),
    const {
      'en':
          'The project has {1} images but the script has {2} image sections; they must match exactly.',
      'ja': '画像は {1} 枚ですが、スクリプトには {2} 個の画像段があります。完全に一致させてください。',
      'ko': '프로젝트에는 이미지 {1}장이 있지만 스크립트에는 이미지 구간이 {2}개입니다. 정확히 일치해야 합니다.',
      'zh_TW': '圖片共 {1} 張，但腳本有 {2} 個圖片段。兩者必須完全一致。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 个图片段必须写为 \[图片 (\d+)\]。$'),
    const {
      'en': 'Image section {1} must be written as [图片 {2}].',
      'ja': '第 {1} 画像段は [图片 {2}] と記述してください。',
      'ko': '{1}번째 이미지 구간은 [图片 {2}]로 작성해야 합니다.',
      'zh_TW': '第 {1} 個圖片段必須寫為 [图片 {2}]。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 张缺少 @原图尺寸。$'),
    const {
      'en': 'Image {1} is missing @原图尺寸.',
      'ja': '画像 {1} に @原图尺寸 がありません。',
      'ko': '이미지 {1}에 @原图尺寸가 없습니다.',
      'zh_TW': '第 {1} 張缺少 @原图尺寸。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 张尺寸不一致：脚本 (.+)，实际 (.+)。$'),
    const {
      'en': 'Image {1} dimensions differ: script {2}, actual {3}.',
      'ja': '画像 {1} の寸法が一致しません：スクリプト {2}、実際 {3}。',
      'ko': '이미지 {1} 크기가 일치하지 않습니다: 스크립트 {2}, 실제 {3}.',
      'zh_TW': '第 {1} 張尺寸不一致：腳本 {2}，實際 {3}。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 张 / 气泡 (\d+) 缺少 @气泡ID。$'),
    const {
      'en': 'Image {1} / bubble {2} is missing @气泡ID.',
      'ja': '画像 {1}／吹き出し {2} に @气泡ID がありません。',
      'ko': '이미지 {1} / 말풍선 {2}에 @气泡ID가 없습니다.',
      'zh_TW': '第 {1} 張 / 氣泡 {2} 缺少 @气泡ID。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^气泡 ID“(.+)”重复；每个气泡必须使用唯一 ID。$'),
    const {
      'en': 'Bubble ID “{1}” is duplicated; every bubble must use a unique ID.',
      'ja': '吹き出し ID「{1}」が重複しています。各吹き出しには一意の ID が必要です。',
      'ko': '말풍선 ID “{1}”이 중복되었습니다. 각 말풍선은 고유 ID를 사용해야 합니다.',
      'zh_TW': '氣泡 ID「{1}」重複；每個氣泡必須使用唯一 ID。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 张 / 气泡 (\d+) 的 @矩形 超出原图。$'),
    const {
      'en': 'Image {1} / bubble {2}: @矩形 extends outside the source image.',
      'ja': '画像 {1}／吹き出し {2}：@矩形 が元画像の外に出ています。',
      'ko': '이미지 {1} / 말풍선 {2}: @矩形가 원본 이미지 경계를 벗어납니다.',
      'zh_TW': '第 {1} 張 / 氣泡 {2} 的 @矩形 超出原圖。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@矩形 必须是 x,y,宽,高 四个像素数值。$'),
    const {
      'en': 'Line {1}: @矩形 must contain four pixel values: x,y,width,height.',
      'ja': '{1} 行目：@矩形 は x,y,幅,高さ の4つのピクセル値で指定してください。',
      'ko': '{1}행: @矩形는 x,y,너비,높이의 픽셀 값 4개여야 합니다.',
      'zh_TW': '第 {1} 行：@矩形 必須是 x,y,寬,高 四個像素數值。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@矩形 坐标不能为负，宽高必须大于 0。$'),
    const {
      'en':
          'Line {1}: @矩形 coordinates cannot be negative and width/height must be greater than 0.',
      'ja': '{1} 行目：@矩形 の座標は負にできず、幅と高さは 0 より大きくしてください。',
      'ko': '{1}행: @矩形 좌표는 음수일 수 없고 너비와 높이는 0보다 커야 합니다.',
      'zh_TW': '第 {1} 行：@矩形 座標不能為負，寬高必須大於 0。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@颜色 必须是六位十六进制颜色，例如 #141518。$'),
    const {
      'en': 'Line {1}: @颜色 must be a six-digit HEX color, for example #141518.',
      'ja': '{1} 行目：@颜色 は6桁の16進色（例 #141518）で指定してください。',
      'ko': '{1}행: @颜色은 6자리 HEX 색상이어야 합니다(예: #141518).',
      'zh_TW': '第 {1} 行：@颜色 必須是六位十六進位顏色，例如 #141518。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^第 (\d+) 行：@(.+) 的值“(.+)”无效，已使用默认值。$'),
    const {
      'en': 'Line {1}: invalid value “{3}” for @{2}; the default was used.',
      'ja': '{1} 行目：@{2} の値「{3}」は無効なため既定値を使用しました。',
      'ko': '{1}행: @{2} 값 “{3}”이 유효하지 않아 기본값을 사용했습니다.',
      'zh_TW': '第 {1} 行：@{2} 的值「{3}」無效，已使用預設值。'
    },
  ),
  _TranslationPattern(
    RegExp(r'^共(\d+)张$'),
    const {
      'en': '{1} images',
      'ja': '{1} 枚',
      'ko': '{1}장',
      'zh_TW': '共{1}張',
    },
  ),
  _TranslationPattern(
    RegExp(r'^工程已保存：(.+)$'),
    const {
      'en': 'Project saved: {1}',
      'ja': 'プロジェクトを保存しました：{1}',
      'ko': '프로젝트 저장됨: {1}',
      'zh_TW': '工程已儲存：{1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^已打开工程：(.+)$'),
    const {
      'en': 'Project opened: {1}',
      'ja': 'プロジェクトを開きました：{1}',
      'ko': '프로젝트 열림: {1}',
      'zh_TW': '已開啟工程：{1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^字幕模板已保存：(.+)$'),
    const {
      'en': 'Caption template saved: {1}',
      'ja': '字幕テンプレートを保存しました：{1}',
      'ko': '자막 템플릿 저장됨: {1}',
      'zh_TW': '字幕範本已儲存：{1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^BCS 字幕脚本已保存：(.+)$'),
    const {
      'en': 'BCS caption script saved: {1}',
      'ja': 'BCS 字幕スクリプトを保存しました：{1}',
      'ko': 'BCS 자막 스크립트 저장됨: {1}',
      'zh_TW': 'BCS 字幕腳本已儲存：{1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^(保存工程失败|导出失败|字幕文件读取失败|模板导出失败)：(.+)$'),
    const {
      'en': '{1}: {2}',
      'ja': '{1}：{2}',
      'ko': '{1}: {2}',
      'zh_TW': '{1}：{2}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^已选 (\d+) 项$'),
    const {
      'en': '{1} selected',
      'ja': '{1} 項目を選択',
      'ko': '{1}개 선택됨',
      'zh_TW': '已選 {1} 項',
    },
  ),
  _TranslationPattern(
    RegExp(r'^当前已经是最新版本 (.+)$'),
    const {
      'en': 'You are already using the latest version {1}',
      'ja': '現在のバージョン {1} は最新です',
      'ko': '현재 버전 {1}이(가) 최신입니다',
      'zh_TW': '目前已是最新版本 {1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^发现新版本 (.+)$'),
    const {
      'en': 'New version {1} available',
      'ja': '新しいバージョン {1} があります',
      'ko': '새 버전 {1}을(를) 사용할 수 있습니다',
      'zh_TW': '發現新版本 {1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^新版本 (.+) 已准备完成$'),
    const {
      'en': 'Version {1} is ready to install',
      'ja': 'バージョン {1} のインストール準備が完了しました',
      'ko': '버전 {1} 설치 준비가 완료되었습니다',
      'zh_TW': '新版本 {1} 已準備完成',
    },
  ),
  _TranslationPattern(
    RegExp(r'^正在下载新版本 (.+) · (.+)%$'),
    const {
      'en': 'Downloading version {1} · {2}%',
      'ja': 'バージョン {1} をダウンロード中 · {2}%',
      'ko': '버전 {1} 다운로드 중 · {2}%',
      'zh_TW': '正在下載新版本 {1} · {2}%',
    },
  ),
  _TranslationPattern(
    RegExp(r'^已选 (\d+) 项$'),
    const {
      'en': '{1} selected',
      'ja': '{1} 項目を選択',
      'ko': '{1}개 선택됨',
      'zh_TW': '已選 {1} 項',
    },
  ),
  _TranslationPattern(
    RegExp(r'^已选 (\d+) / (\d+)$'),
    const {
      'en': '{1} / {2} selected',
      'ja': '{1} / {2} を選択',
      'ko': '{1} / {2} 선택됨',
      'zh_TW': '已選 {1} / {2}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^浪白漫画字幕工坊 (.+)$'),
    const {
      'en': 'Langbai Manga Caption Studio {1}',
      'ja': '浪白マンガ字幕工房 {1}',
      'ko': '랑바이 만화 자막 공방 {1}',
      'zh_TW': '浪白漫畫字幕工坊 {1}',
    },
  ),
  _TranslationPattern(
    RegExp(r'^发现 (.+)，等待你确认下载$'),
    const {
      'en': 'Version {1} is available. Confirm to download.',
      'ja': 'バージョン {1} があります。確認後にダウンロードします。',
      'ko': '버전 {1}을(를) 사용할 수 있습니다. 확인 후 다운로드합니다.',
      'zh_TW': '發現 {1}，等待你確認下載',
    },
  ),
  _TranslationPattern(
    RegExp(r'^正在下载 (.+) · (.+)%$'),
    const {
      'en': 'Downloading {1} · {2}%',
      'ja': '{1} をダウンロード中 · {2}%',
      'ko': '{1} 다운로드 중 · {2}%',
      'zh_TW': '正在下載 {1} · {2}%',
    },
  ),
  _TranslationPattern(
    RegExp(r'^(.+) 已下载，可以立即安装$'),
    const {
      'en': '{1} downloaded and ready to install',
      'ja': '{1} のダウンロードが完了し、インストールできます',
      'ko': '{1} 다운로드가 완료되어 설치할 수 있습니다',
      'zh_TW': '{1} 已下載，可以立即安裝',
    },
  ),
  _TranslationPattern(
    RegExp(r'^发现 (.+)，当前平台需前往 GitHub 更新$'),
    const {
      'en': 'Version {1} is available. Update from GitHub on this platform.',
      'ja': 'バージョン {1} があります。この環境では GitHub から更新してください。',
      'ko': '버전 {1}을(를) 사용할 수 있습니다. 이 플랫폼에서는 GitHub에서 업데이트하세요.',
      'zh_TW': '發現 {1}，目前平台需前往 GitHub 更新',
    },
  ),
];

const _translations = <String, Map<String, String>>{
  '浪白漫画字幕工坊': {
    'en': 'Langbai Manga Caption Studio',
    'ja': '浪白マンガ字幕工房',
    'ko': '랑바이 만화 자막 공방',
    'zh_TW': '浪白漫畫字幕工坊',
  },
  '设置': {'en': 'Settings', 'ja': '設定', 'ko': '설정', 'zh_TW': '設定'},
  '语言': {'en': 'Language', 'ja': '言語', 'ko': '언어', 'zh_TW': '語言'},
  '界面与指南语言': {
    'en': 'Interface and guide language',
    'ja': '画面とガイドの言語',
    'ko': '인터페이스 및 가이드 언어',
    'zh_TW': '介面與指南語言',
  },
  '保存与导出': {
    'en': 'Save and export',
    'ja': '保存と書き出し',
    'ko': '저장 및 내보내기',
    'zh_TW': '儲存與匯出',
  },
  '软件与更新': {
    'en': 'App and updates',
    'ja': 'アプリと更新',
    'ko': '앱 및 업데이트',
    'zh_TW': '軟體與更新',
  },
  '取消': {'en': 'Cancel', 'ja': 'キャンセル', 'ko': '취소', 'zh_TW': '取消'},
  '知道了': {'en': 'Got it', 'ja': '了解', 'ko': '확인', 'zh_TW': '知道了'},
  '关闭': {'en': 'Close', 'ja': '閉じる', 'ko': '닫기', 'zh_TW': '關閉'},
  '保存设置': {
    'en': 'Save settings',
    'ja': '設定を保存',
    'ko': '설정 저장',
    'zh_TW': '儲存設定',
  },
  '尚未设置默认保存目录': {
    'en': 'No default folder selected',
    'ja': '既定の保存先が未設定です',
    'ko': '기본 저장 폴더가 설정되지 않음',
    'zh_TW': '尚未設定預設儲存目錄',
  },
  '批量成图会以 PNG 图片直接写入这里，不再生成 ZIP': {
    'en': 'Exported PNG images are written here directly; no ZIP is created.',
    'ja': '一括書き出しした PNG はここへ直接保存され、ZIP は作成されません。',
    'ko': '일괄 내보낸 PNG가 여기에 직접 저장되며 ZIP은 생성되지 않습니다.',
    'zh_TW': '批次成圖會以 PNG 圖片直接寫入此處，不再產生 ZIP。',
  },
  '选择目录': {
    'en': 'Choose folder',
    'ja': 'フォルダーを選択',
    'ko': '폴더 선택',
    'zh_TW': '選擇目錄',
  },
  '每次导出都询问保存位置': {
    'en': 'Ask where to save every export',
    'ja': '書き出すたびに保存先を確認',
    'ko': '내보낼 때마다 저장 위치 묻기',
    'zh_TW': '每次匯出都詢問儲存位置',
  },
  '关闭后直接写入上面的默认目录': {
    'en': 'When off, files are written to the default folder above.',
    'ja': 'オフの場合は上の既定フォルダーへ直接保存します。',
    'ko': '끄면 위의 기본 폴더에 바로 저장합니다.',
    'zh_TW': '關閉後直接寫入上方的預設目錄',
  },
  '导出文件添加 0001、0002 序号': {
    'en': 'Add 0001, 0002 numbering to exports',
    'ja': '書き出し名に 0001、0002 の連番を追加',
    'ko': '내보내기 파일에 0001, 0002 번호 추가',
    'zh_TW': '匯出檔案加入 0001、0002 序號',
  },
  '关闭后保留原文件名；同名图片会在覆盖前询问': {
    'en': 'When off, original names are kept and overwrite is confirmed.',
    'ja': 'オフの場合は元の名前を保ち、上書き前に確認します。',
    'ko': '끄면 원래 파일명을 유지하고 덮어쓰기 전에 확인합니다.',
    'zh_TW': '關閉後保留原檔名；同名圖片會在覆寫前詢問',
  },
  '检查更新': {
    'en': 'Check for updates',
    'ja': '更新を確認',
    'ko': '업데이트 확인',
    'zh_TW': '檢查更新',
  },
  '检测更新': {
    'en': 'Check updates',
    'ja': '更新を確認',
    'ko': '업데이트 확인',
    'zh_TW': '檢查更新',
  },
  '检测中': {'en': 'Checking', 'ja': '確認中', 'ko': '확인 중', 'zh_TW': '檢查中'},
  '下载更新': {
    'en': 'Download update',
    'ja': '更新をダウンロード',
    'ko': '업데이트 다운로드',
    'zh_TW': '下載更新',
  },
  '安装并重启': {
    'en': 'Install and restart',
    'ja': 'インストールして再起動',
    'ko': '설치 후 다시 시작',
    'zh_TW': '安裝並重新啟動',
  },
  '立即安装并重启': {
    'en': 'Install and restart now',
    'ja': '今すぐインストールして再起動',
    'ko': '지금 설치 후 다시 시작',
    'zh_TW': '立即安裝並重新啟動',
  },
  '前往 GitHub': {
    'en': 'Open GitHub',
    'ja': 'GitHub へ',
    'ko': 'GitHub 열기',
    'zh_TW': '前往 GitHub'
  },
  '前往 GitHub 更新': {
    'en': 'Update on GitHub',
    'ja': 'GitHub で更新',
    'ko': 'GitHub에서 업데이트',
    'zh_TW': '前往 GitHub 更新',
  },
  '当前已经是最新版本': {
    'en': 'You are using the latest version',
    'ja': '現在のバージョンは最新です',
    'ko': '현재 최신 버전입니다',
    'zh_TW': '目前已是最新版本',
  },
  '正在检测更新…': {
    'en': 'Checking for updates…',
    'ja': '更新を確認中…',
    'ko': '업데이트 확인 중…',
    'zh_TW': '正在檢查更新…',
  },
  '正在读取更新状态…': {
    'en': 'Reading update status…',
    'ja': '更新状況を読み込み中…',
    'ko': '업데이트 상태 확인 중…',
    'zh_TW': '正在讀取更新狀態…',
  },
  '检测更新失败，请稍后重试': {
    'en': 'Update check failed. Try again later.',
    'ja': '更新の確認に失敗しました。後でもう一度お試しください。',
    'ko': '업데이트 확인에 실패했습니다. 잠시 후 다시 시도하세요.',
    'zh_TW': '檢查更新失敗，請稍後重試',
  },
  '尚未检测更新': {
    'en': 'Updates have not been checked',
    'ja': '更新はまだ確認されていません',
    'ko': '아직 업데이트를 확인하지 않음',
    'zh_TW': '尚未檢查更新',
  },
  'Windows Setup 版可在软件内下载并安装；Portable 和其他平台会打开 GitHub Releases。': {
    'en':
        'Windows Setup can update in-app. Portable and other platforms open GitHub Releases.',
    'ja': 'Windows Setup 版はアプリ内更新に対応し、Portable とその他の環境は GitHub Releases を開きます。',
    'ko':
        'Windows Setup 버전은 앱에서 업데이트할 수 있으며 Portable 및 기타 플랫폼은 GitHub Releases를 엽니다.',
    'zh_TW': 'Windows Setup 版可在軟體內下載並安裝；Portable 和其他平台會開啟 GitHub Releases。',
  },
  '本地项目 · 图片与字幕不会上传': {
    'en': 'Local projects · Images and captions are never uploaded',
    'ja': 'ローカルプロジェクト · 画像と字幕はアップロードされません',
    'ko': '로컬 프로젝트 · 이미지와 자막은 업로드되지 않습니다',
    'zh_TW': '本機專案 · 圖片與字幕不會上傳',
  },
  '新建项目': {
    'en': 'New project',
    'ja': '新規プロジェクト',
    'ko': '새 프로젝트',
    'zh_TW': '新增專案'
  },
  '创建项目': {
    'en': 'Create project',
    'ja': 'プロジェクトを作成',
    'ko': '프로젝트 만들기',
    'zh_TW': '建立專案'
  },
  '创建第一个项目': {
    'en': 'Create your first project',
    'ja': '最初のプロジェクトを作成',
    'ko': '첫 프로젝트 만들기',
    'zh_TW': '建立第一個專案',
  },
  '项目名称（可选）': {
    'en': 'Project name (optional)',
    'ja': 'プロジェクト名（任意）',
    'ko': '프로젝트 이름(선택)',
    'zh_TW': '專案名稱（選填）',
  },
  '例如：第 01 话 初遇': {
    'en': 'Example: Episode 01 · First encounter',
    'ja': '例：第01話 出会い',
    'ko': '예: 제01화 첫 만남',
    'zh_TW': '例如：第 01 話 初遇',
  },
  '可以输入项目名；留空会自动按创建时间命名。': {
    'en': 'Enter a name, or leave blank to use the creation time.',
    'ja': '名前を入力するか、空欄のまま作成日時を使用します。',
    'ko': '이름을 입력하거나 비워 두면 생성 시간으로 이름을 정합니다.',
    'zh_TW': '可輸入專案名稱；留空會依建立時間自動命名。',
  },
  '删除项目': {
    'en': 'Delete project',
    'ja': 'プロジェクトを削除',
    'ko': '프로젝트 삭제',
    'zh_TW': '刪除專案'
  },
  '删除项目？': {
    'en': 'Delete project?',
    'ja': 'プロジェクトを削除しますか？',
    'ko': '프로젝트를 삭제할까요?',
    'zh_TW': '刪除專案？'
  },
  '确认删除': {'en': 'Delete', 'ja': '削除する', 'ko': '삭제', 'zh_TW': '確認刪除'},
  '还没有项目': {
    'en': 'No projects yet',
    'ja': 'プロジェクトはまだありません',
    'ko': '아직 프로젝트가 없습니다',
    'zh_TW': '尚無專案'
  },
  '每个项目独立保存图片、字幕和排版。创建后即可添加图片。': {
    'en':
        'Each project stores its own images, captions, and layout. Add images after creating one.',
    'ja': '画像・字幕・レイアウトはプロジェクトごとに保存されます。作成後に画像を追加できます。',
    'ko': '각 프로젝트는 이미지, 자막, 배치를 독립적으로 저장합니다. 만든 뒤 이미지를 추가하세요.',
    'zh_TW': '每個專案獨立儲存圖片、字幕與排版。建立後即可加入圖片。',
  },
  '暂无首图': {'en': 'No cover', 'ja': '表紙なし', 'ko': '대표 이미지 없음', 'zh_TW': '暫無首圖'},
  '首图': {'en': 'Cover', 'ja': '表紙', 'ko': '대표 이미지', 'zh_TW': '首圖'},
  '已有工程内容': {
    'en': 'Project has content',
    'ja': 'プロジェクト内容あり',
    'ko': '프로젝트 내용 있음',
    'zh_TW': '已有工程內容'
  },
  '等待添加图片': {
    'en': 'Waiting for images',
    'ja': '画像を追加してください',
    'ko': '이미지 추가 대기 중',
    'zh_TW': '等待加入圖片'
  },
  '图片': {'en': 'Images', 'ja': '画像', 'ko': '이미지', 'zh_TW': '圖片'},
  '字幕': {'en': 'Captions', 'ja': '字幕', 'ko': '자막', 'zh_TW': '字幕'},
  '排版': {'en': 'Layout', 'ja': 'レイアウト', 'ko': '배치', 'zh_TW': '排版'},
  '等待字幕': {
    'en': 'Waiting for captions',
    'ja': '字幕待ち',
    'ko': '자막 대기 중',
    'zh_TW': '等待字幕'
  },
  '等待图片': {
    'en': 'Waiting for images',
    'ja': '画像待ち',
    'ko': '이미지 대기 중',
    'zh_TW': '等待圖片'
  },
  '匹配字幕': {
    'en': 'Match captions',
    'ja': '字幕を割り当て',
    'ko': '자막 매칭',
    'zh_TW': '配對字幕'
  },
  '批量导出': {
    'en': 'Batch export',
    'ja': '一括書き出し',
    'ko': '일괄 내보내기',
    'zh_TW': '批次匯出'
  },
  '添加图片': {'en': 'Add images', 'ja': '画像を追加', 'ko': '이미지 추가', 'zh_TW': '加入圖片'},
  '使用指南': {'en': 'User guide', 'ja': '使い方', 'ko': '사용 안내', 'zh_TW': '使用指南'},
  '打开工程': {
    'en': 'Open project file',
    'ja': 'プロジェクトを開く',
    'ko': '프로젝트 파일 열기',
    'zh_TW': '開啟工程'
  },
  '保存工程': {
    'en': 'Save project',
    'ja': 'プロジェクトを保存',
    'ko': '프로젝트 저장',
    'zh_TW': '儲存工程'
  },
  '切换项目': {
    'en': 'Switch project',
    'ja': 'プロジェクトを切替',
    'ko': '프로젝트 전환',
    'zh_TW': '切換專案'
  },
  '未命名项目': {
    'en': 'Untitled project',
    'ja': '名称未設定',
    'ko': '이름 없는 프로젝트',
    'zh_TW': '未命名專案'
  },
  '未命名工程': {
    'en': 'Untitled project',
    'ja': '名称未設定',
    'ko': '이름 없는 프로젝트',
    'zh_TW': '未命名工程'
  },
  '项目': {'en': 'Project', 'ja': 'プロジェクト', 'ko': '프로젝트', 'zh_TW': '專案'},
  '“{name}”及其本地图片、字幕和排版将被永久删除。': {
    'en':
        '“{name}” and its local images, captions, and layout will be permanently deleted.',
    'ja': '「{name}」とローカルの画像・字幕・レイアウトは完全に削除されます。',
    'ko': '“{name}” 및 로컬 이미지, 자막, 배치가 영구적으로 삭제됩니다.',
    'zh_TW': '「{name}」及其本機圖片、字幕與排版將被永久刪除。',
  },
  '项目第一张图片：{name}': {
    'en': 'First image in project: {name}',
    'ja': 'プロジェクトの最初の画像：{name}',
    'ko': '프로젝트 첫 이미지: {name}',
    'zh_TW': '專案第一張圖片：{name}',
  },
  '已保存 · 本地': {
    'en': 'Saved · Local',
    'ja': '保存済み · ローカル',
    'ko': '저장됨 · 로컬',
    'zh_TW': '已儲存 · 本機'
  },
  '有未保存修改': {
    'en': 'Unsaved changes',
    'ja': '未保存の変更',
    'ko': '저장하지 않은 변경 사항',
    'zh_TW': '有未儲存修改'
  },
  '按确认顺序': {
    'en': 'Confirmed order',
    'ja': '確認済み順序',
    'ko': '확정 순서',
    'zh_TW': '依確認順序'
  },
  '未匹配': {'en': 'Unmatched', 'ja': '未割り当て', 'ko': '미매칭', 'zh_TW': '未配對'},
  '已匹配': {'en': 'Matched', 'ja': '割り当て済み', 'ko': '매칭됨', 'zh_TW': '已配對'},
};

const _workspaceTranslations = <String, Map<String, String>>{
  '更多操作': {
    'en': 'More actions',
    'ja': 'その他の操作',
    'ko': '추가 작업',
    'zh_TW': '更多操作'
  },
  '剪切': {'en': 'Cut', 'ja': '切り取り', 'ko': '잘라내기', 'zh_TW': '剪下'},
  '复制': {'en': 'Copy', 'ja': 'コピー', 'ko': '복사', 'zh_TW': '複製'},
  '粘贴': {'en': 'Paste', 'ja': '貼り付け', 'ko': '붙여넣기', 'zh_TW': '貼上'},
  '字幕与气泡数量不一致': {
    'en': 'Caption and bubble counts do not match',
    'ja': '字幕数と吹き出し数が一致しません',
    'ko': '자막 수와 말풍선 수가 일치하지 않습니다',
    'zh_TW': '字幕與氣泡數量不一致'
  },
  '没有匹配到字幕': {
    'en': 'No captions matched',
    'ja': '字幕が割り当てられていません',
    'ko': '매칭된 자막이 없습니다',
    'zh_TW': '沒有配對到字幕'
  },
  '对话': {'en': 'Dialogue', 'ja': '会話', 'ko': '대화', 'zh_TW': '對話'},
  '心理': {'en': 'Thought', 'ja': '心理', 'ko': '생각', 'zh_TW': '心理'},
  '旁白': {'en': 'Narration', 'ja': '語り', 'ko': '내레이션', 'zh_TW': '旁白'},
  '耳语': {'en': 'Whisper', 'ja': '囁き', 'ko': '속삭임', 'zh_TW': '耳語'},
  '惊喊': {'en': 'Shout', 'ja': '叫び', 'ko': '외침', 'zh_TW': '驚喊'},
  '工程图片缺少 pageId': {
    'en': 'A project image is missing its pageId',
    'ja': 'プロジェクト画像に pageId がありません',
    'ko': '프로젝트 이미지에 pageId가 없습니다',
    'zh_TW': '工程圖片缺少 pageId'
  },
  '工程中没有可读取的页面': {
    'en': 'The project has no readable pages',
    'ja': 'プロジェクトに読み込めるページがありません',
    'ko': '프로젝트에 읽을 수 있는 페이지가 없습니다',
    'zh_TW': '工程中沒有可讀取的頁面'
  },
  '无法编码图片': {
    'en': 'Could not encode the image',
    'ja': '画像をエンコードできません',
    'ko': '이미지를 인코딩할 수 없습니다',
    'zh_TW': '無法編碼圖片'
  },
  '新字幕 {index}': {
    'en': 'New caption {index}',
    'ja': '新しい字幕 {index}',
    'ko': '새 자막 {index}',
    'zh_TW': '新字幕 {index}'
  },
  '（副本）': {'en': ' (copy)', 'ja': '（コピー）', 'ko': ' (복사본)', 'zh_TW': '（副本）'},
  '开始添加': {'en': 'Add images', 'ja': '画像を追加', 'ko': '이미지 추가', 'zh_TW': '開始加入'},
  '等待匹配字幕': {
    'en': 'Waiting for captions',
    'ja': '字幕の割り当て待ち',
    'ko': '자막 매칭 대기',
    'zh_TW': '等待配對字幕'
  },
  '字幕匹配检查通过': {
    'en': 'Caption matching passed',
    'ja': '字幕の照合に合格しました',
    'ko': '자막 매칭 검사 통과',
    'zh_TW': '字幕配對檢查通過'
  },
  '字幕匹配检查未通过': {
    'en': 'Caption matching failed',
    'ja': '字幕の照合に問題があります',
    'ko': '자막 매칭 검사 실패',
    'zh_TW': '字幕配對檢查未通過'
  },
  '对比：': {'en': 'Compare:', 'ja': '比較：', 'ko': '비교:', 'zh_TW': '對比：'},
  '精准格式': {
    'en': 'Precise format',
    'ja': '精密形式',
    'ko': '정밀 형식',
    'zh_TW': '精準格式'
  },
  '章节：第01话 初遇': {
    'en': 'Chapter: Episode 01 · First Meeting',
    'ja': '章：第01話・出会い',
    'ko': '장: 01화 첫 만남',
    'zh_TW': '章節：第01話 初遇'
  },
  '正在加载高清原图': {
    'en': 'Loading full-resolution image',
    'ja': '高解像度の元画像を読み込み中',
    'ko': '고해상도 원본 로드 중',
    'zh_TW': '正在載入高畫質原圖'
  },
  '1. 软件启动后先进入项目页。可以创建、删除或切换项目；名称留空时会按创建时间自动命名。\n\n2. 点击“添加图片”后，图片默认按文件名自然排序，例如 1、2、10。可以在顺序确认窗口继续拖动调整。\n\n3. 点击顶部“字幕”。每个 [图片 N] 段必须包含 @原图尺寸；气泡使用原图像素 @矩形=x,y,宽,高。字幕只按确认顺序对应，不按文件名匹配。\n\n4. 字幕编辑器采用草稿模式；点击取消不会改变工程。稳定的 @气泡ID 可在再次应用时保留手工位置和样式。\n\n5. 单击气泡会立即显示选框；单击画布空白处会关闭选框，直到再次单击气泡。右侧可修改文字、形状、字体、颜色、字号、行距、描边和尾巴方向。\n\n6. 项目不再持续自动保存。点击右上角保存按钮，或切换回项目页时保存一次。导出位于右上角，不属于编辑流程。\n\n图片和字幕始终只在当前设备处理，不会上传。':
      {
    'en':
        '1. The app opens on the Projects page. Create, delete, or switch projects; leaving the name blank uses the creation time.\n\n2. After Add images, files use natural file-name order (1, 2, 10). Drag to adjust them in the confirmation dialog.\n\n3. Open Captions. Every [图片 N] section requires @原图尺寸; bubbles use source-pixel @矩形=x,y,width,height. Matching follows confirmed order, not file name.\n\n4. The caption editor uses a draft. Cancel leaves the project unchanged. Stable @气泡ID values preserve manual positions and styles when applying again.\n\n5. Click a bubble to show its selection frame immediately. Click empty canvas to hide it until a bubble is clicked again. Edit text, shape, font, color, size, spacing, outline, and tail direction on the right.\n\n6. Projects are not saved continuously. Use Save at the top right, or save once when returning to Projects. Export is at the top right and is not an editing step.\n\nImages and captions stay on this device and are never uploaded.',
    'ja':
        '1. 起動後はプロジェクト画面が開きます。作成・削除・切替ができ、名前を空欄にすると作成時刻で自動命名されます。\n\n2. 「画像を追加」後、既定ではファイル名の自然順（1、2、10）です。確認画面でドラッグして調整できます。\n\n3. 上部の「字幕」を開きます。各 [图片 N] 段には @原图尺寸 が必要で、吹き出しは元画像ピクセルの @矩形=x,y,幅,高さ を使います。字幕は確認順で対応し、ファイル名では照合しません。\n\n4. 字幕エディターは下書き方式です。キャンセルしてもプロジェクトは変わりません。安定した @气泡ID は再適用時に手動位置とスタイルを保持します。\n\n5. 吹き出しをクリックすると選択枠がすぐ表示され、空白をクリックすると次に吹き出しをクリックするまで消えます。右側で文字、形、フォント、色、サイズ、行間、枠線、しっぽ方向を編集できます。\n\n6. 常時自動保存はしません。右上の保存、またはプロジェクト画面へ戻る際に保存します。書き出しは右上にあり、編集工程には含まれません。\n\n画像と字幕は端末内だけで処理され、アップロードされません。',
    'ko':
        '1. 앱은 프로젝트 화면에서 시작합니다. 프로젝트를 만들고 삭제하거나 전환할 수 있으며 이름을 비우면 생성 시간으로 자동 이름을 정합니다.\n\n2. 이미지 추가 후 기본값은 파일명 자연 정렬(1, 2, 10)입니다. 확인 창에서 드래그해 조정할 수 있습니다.\n\n3. 상단 자막을 엽니다. 모든 [图片 N] 구간에는 @原图尺寸가 필요하며 말풍선은 원본 픽셀 @矩形=x,y,너비,높이를 사용합니다. 자막은 파일명이 아니라 확인된 순서로 매칭됩니다.\n\n4. 자막 편집기는 초안 방식입니다. 취소해도 프로젝트는 바뀌지 않습니다. 안정적인 @气泡ID는 다시 적용할 때 수동 위치와 스타일을 유지합니다.\n\n5. 말풍선을 클릭하면 선택 프레임이 즉시 표시됩니다. 빈 캔버스를 클릭하면 다음에 말풍선을 클릭할 때까지 숨겨집니다. 오른쪽에서 글자, 모양, 글꼴, 색상, 크기, 줄 간격, 외곽선, 꼬리 방향을 수정할 수 있습니다.\n\n6. 프로젝트는 계속 자동 저장되지 않습니다. 오른쪽 위 저장을 누르거나 프로젝트 화면으로 돌아갈 때 한 번 저장합니다. 내보내기는 오른쪽 위에 있으며 편집 단계가 아닙니다.\n\n이미지와 자막은 이 기기에서만 처리되며 업로드되지 않습니다.',
    'zh_TW':
        '1. 軟體啟動後先進入專案頁。可以建立、刪除或切換專案；名稱留空時會依建立時間自動命名。\n\n2. 按「加入圖片」後，圖片預設依檔名自然排序，例如 1、2、10。可在順序確認視窗繼續拖曳調整。\n\n3. 按頂端「字幕」。每個 [图片 N] 段必須包含 @原图尺寸；氣泡使用原圖像素 @矩形=x,y,寬,高。字幕只依確認順序對應，不依檔名配對。\n\n4. 字幕編輯器採用草稿模式；按取消不會改變工程。穩定的 @气泡ID 可在再次套用時保留手動位置和樣式。\n\n5. 單擊氣泡會立即顯示選框；單擊畫布空白處會關閉選框，直到再次單擊氣泡。右側可修改文字、形狀、字體、顏色、字號、行距、描邊與尾巴方向。\n\n6. 專案不再持續自動儲存。按右上角儲存按鈕，或切換回專案頁時儲存一次。匯出位於右上角，不屬於編輯流程。\n\n圖片和字幕始終只在目前裝置處理，不會上傳。',
  },
  '当前项目的精确输入': {
    'en': 'Exact input for the current project',
    'ja': '現在のプロジェクトの正確な入力',
    'ko': '현재 프로젝트의 정확한 입력',
    'zh_TW': '目前專案的精確輸入'
  },
  '下面的数据由软件直接生成。图片顺序和尺寸是强制约束，不允许 AI 修改或重新排序。': {
    'en':
        'The data below is generated by the app. Image order and dimensions are mandatory constraints; the AI must not change or reorder them.',
    'ja': '以下のデータはアプリが直接生成したものです。画像順と寸法は必須条件であり、AI が変更・並べ替えしてはいけません。',
    'ko': '아래 데이터는 앱이 직접 생성했습니다. 이미지 순서와 크기는 필수 제약이며 AI가 변경하거나 재정렬하면 안 됩니다.',
    'zh_TW': '以下資料由軟體直接產生。圖片順序與尺寸是強制約束，不允許 AI 修改或重新排序。'
  },
  '图片顺序与原图尺寸': {
    'en': 'Image order and source dimensions',
    'ja': '画像順と元画像サイズ',
    'ko': '이미지 순서와 원본 크기',
    'zh_TW': '圖片順序與原圖尺寸'
  },
  '当前项目完整模板': {
    'en': 'Complete template for the current project',
    'ja': '現在のプロジェクトの完全なテンプレート',
    'ko': '현재 프로젝트 전체 템플릿',
    'zh_TW': '目前專案完整範本'
  },
  '图片 {index}：{name}，原图尺寸={width}x{height}': {
    'en': 'Image {index}: {name}, source dimensions={width}x{height}',
    'ja': '画像 {index}：{name}、元画像サイズ={width}x{height}',
    'ko': '이미지 {index}: {name}, 원본 크기={width}x{height}',
    'zh_TW': '圖片 {index}：{name}，原圖尺寸={width}x{height}'
  },
  '请把实际图片、需要加入的对白或旁白，与以上规范和模板一起提供给 AI。AI 必须只返回最终的 BCS 纯文本脚本。': {
    'en':
        'Provide the actual images and required dialogue or narration to the AI together with the rules and template above. The AI must return only the final plain-text BCS script.',
    'ja':
        '実際の画像と追加する会話・ナレーションを、上記の仕様とテンプレートと一緒に AI に渡してください。AI は最終的な BCS プレーンテキストだけを返す必要があります。',
    'ko':
        '실제 이미지와 필요한 대화 또는 내레이션을 위 규격 및 템플릿과 함께 AI에 제공하세요. AI는 최종 BCS 일반 텍스트 스크립트만 반환해야 합니다.',
    'zh_TW': '請把實際圖片、需要加入的對白或旁白，與以上規範和範本一起提供給 AI。AI 必須只回傳最終的 BCS 純文字腳本。'
  },
  '以下内容使用当前界面的 AI 指南语言，并在末尾附加当前项目的真实顺序、原图尺寸和完整模板。': {
    'en':
        'The guide below uses the current interface language and appends the project’s actual order, source dimensions, and full template.',
    'ja': '以下のガイドは現在の画面言語を使用し、末尾にプロジェクトの実際の順序、元画像サイズ、完全なテンプレートを追加します。',
    'ko': '아래 안내는 현재 인터페이스 언어를 사용하며 끝에 프로젝트의 실제 순서, 원본 크기 및 전체 템플릿을 추가합니다.',
    'zh_TW': '以下內容使用目前介面的 AI 指南語言，並在末尾附加目前專案的真實順序、原圖尺寸和完整範本。'
  },
  '气泡属性': {
    'en': 'Bubble properties',
    'ja': '吹き出し設定',
    'ko': '말풍선 속성',
    'zh_TW': '氣泡屬性'
  },
  '文本内容': {'en': 'Text', 'ja': 'テキスト', 'ko': '텍스트', 'zh_TW': '文字內容'},
  '气泡样式': {
    'en': 'Bubble style',
    'ja': '吹き出しスタイル',
    'ko': '말풍선 스타일',
    'zh_TW': '氣泡樣式'
  },
  '字体': {'en': 'Font', 'ja': 'フォント', 'ko': '글꼴', 'zh_TW': '字體'},
  '字体颜色': {'en': 'Text color', 'ja': '文字色', 'ko': '글자 색상', 'zh_TW': '字體顏色'},
  '字体大小': {'en': 'Font size', 'ja': '文字サイズ', 'ko': '글자 크기', 'zh_TW': '字體大小'},
  '行间距': {'en': 'Line spacing', 'ja': '行間', 'ko': '줄 간격', 'zh_TW': '行間距'},
  '行距': {'en': 'Line spacing', 'ja': '行間', 'ko': '줄 간격', 'zh_TW': '行距'},
  '描边粗细': {
    'en': 'Outline width',
    'ja': '枠線の太さ',
    'ko': '외곽선 굵기',
    'zh_TW': '描邊粗細'
  },
  '白底透明度': {
    'en': 'Fill opacity',
    'ja': '白背景の不透明度',
    'ko': '흰 배경 불투명도',
    'zh_TW': '白底不透明度'
  },
  '指向方向': {
    'en': 'Tail direction',
    'ja': 'しっぽの方向',
    'ko': '꼬리 방향',
    'zh_TW': '指向方向'
  },
  '尾部位置固定，不可拖动': {
    'en': 'The tail is fixed and cannot be dragged',
    'ja': 'しっぽの位置は固定され、ドラッグできません',
    'ko': '꼬리 위치는 고정되어 드래그할 수 없습니다',
    'zh_TW': '尾部位置固定，不可拖曳'
  },
  '选择属性并应用到全部': {
    'en': 'Apply selected properties to all',
    'ja': '選択した設定をすべてに適用',
    'ko': '선택한 속성을 모두 적용',
    'zh_TW': '選擇屬性並套用到全部'
  },
  '选择应用到全部气泡的属性': {
    'en': 'Choose properties to apply to every bubble',
    'ja': 'すべての吹き出しに適用する設定を選択',
    'ko': '모든 말풍선에 적용할 속성 선택',
    'zh_TW': '選擇套用到全部氣泡的屬性'
  },
  '删除此气泡': {
    'en': 'Delete bubble',
    'ja': '吹き出しを削除',
    'ko': '말풍선 삭제',
    'zh_TW': '刪除此氣泡'
  },
  '添加空白气泡': {
    'en': 'Add empty bubble',
    'ja': '空の吹き出しを追加',
    'ko': '빈 말풍선 추가',
    'zh_TW': '加入空白氣泡'
  },
  '为图片匹配字幕': {
    'en': 'Match captions to image',
    'ja': '画像に字幕を割り当て',
    'ko': '이미지에 자막 매칭',
    'zh_TW': '為圖片配對字幕'
  },
  '这张图片还没有可编辑气泡': {
    'en': 'This image has no editable bubbles yet',
    'ja': 'この画像には編集できる吹き出しがありません',
    'ko': '이 이미지에는 편집 가능한 말풍선이 없습니다',
    'zh_TW': '這張圖片還沒有可編輯氣泡'
  },
  '原图里已经存在的文字属于图片像素，不能直接编辑。你可以匹配字幕，也可以先添加一个空白气泡。': {
    'en':
        'Text already in the source image is part of its pixels and cannot be edited. Match a caption script or add an empty bubble.',
    'ja': '元画像の文字は画像の一部なので直接編集できません。字幕を割り当てるか、空の吹き出しを追加してください。',
    'ko': '원본 이미지의 글자는 픽셀에 포함되어 직접 편집할 수 없습니다. 자막을 매칭하거나 빈 말풍선을 추가하세요.',
    'zh_TW': '原圖中已有的文字屬於圖片像素，無法直接編輯。你可以配對字幕，或先加入一個空白氣泡。'
  },
  '请先添加图片': {
    'en': 'Add images first',
    'ja': '先に画像を追加してください',
    'ko': '먼저 이미지를 추가하세요',
    'zh_TW': '請先加入圖片'
  },
  '导入图片': {
    'en': 'Import images',
    'ja': '画像を読み込む',
    'ko': '이미지 가져오기',
    'zh_TW': '匯入圖片'
  },
  '添加图片': {'en': 'Add images', 'ja': '画像を追加', 'ko': '이미지 추가', 'zh_TW': '加入圖片'},
  '更多图片选项': {
    'en': 'More image options',
    'ja': 'その他の画像オプション',
    'ko': '추가 이미지 옵션',
    'zh_TW': '更多圖片選項'
  },
  '清空图片并重新导入': {
    'en': 'Clear images and re-import',
    'ja': '画像を消去して再読み込み',
    'ko': '이미지 지우고 다시 가져오기',
    'zh_TW': '清空圖片並重新匯入'
  },
  '确认图片顺序': {
    'en': 'Confirm image order',
    'ja': '画像順を確認',
    'ko': '이미지 순서 확인',
    'zh_TW': '確認圖片順序'
  },
  '当前默认按文件名自然排序；可以拖动调整。字幕将严格按确认后的第 1、2、3 张依次对应。': {
    'en':
        'Images are naturally sorted by file name by default. Drag to reorder. Captions will follow the confirmed 1st, 2nd, 3rd image order exactly.',
    'ja': '既定ではファイル名の自然順です。ドラッグで並べ替えられます。字幕は確認後の1、2、3枚目に厳密に対応します。',
    'ko':
        '기본값은 파일명 자연 정렬입니다. 드래그해 순서를 바꿀 수 있으며 자막은 확정된 1, 2, 3번째 이미지 순서대로 정확히 적용됩니다.',
    'zh_TW': '目前預設按檔名自然排序；可拖曳調整。字幕會嚴格依確認後的第 1、2、3 張依序對應。'
  },
  '取消导入': {
    'en': 'Cancel import',
    'ja': '読み込みをキャンセル',
    'ko': '가져오기 취소',
    'zh_TW': '取消匯入'
  },
  '确认此顺序': {
    'en': 'Confirm order',
    'ja': 'この順序で確定',
    'ko': '이 순서로 확정',
    'zh_TW': '確認此順序'
  },
  '没有读取到有效图片，请检查文件格式或文件是否损坏。': {
    'en': 'No valid images were found. Check the file format and integrity.',
    'ja': '有効な画像を読み込めませんでした。形式や破損を確認してください。',
    'ko': '유효한 이미지를 읽지 못했습니다. 파일 형식이나 손상 여부를 확인하세요.',
    'zh_TW': '沒有讀取到有效圖片，請檢查檔案格式或檔案是否損壞。'
  },
  '原图': {'en': 'Original', 'ja': '元画像', 'ko': '원본', 'zh_TW': '原圖'},
  '渲染': {'en': 'Rendered', 'ja': 'レンダー', 'ko': '렌더링', 'zh_TW': '渲染'},
  '对比': {'en': 'Compare', 'ja': '比較', 'ko': '비교', 'zh_TW': '對比'},
  '撤销': {'en': 'Undo', 'ja': '元に戻す', 'ko': '실행 취소', 'zh_TW': '復原'},
  '重做': {'en': 'Redo', 'ja': 'やり直す', 'ko': '다시 실행', 'zh_TW': '重做'},
  '气泡编辑命令': {
    'en': 'Bubble editing commands',
    'ja': '吹き出し編集コマンド',
    'ko': '말풍선 편집 명령',
    'zh_TW': '氣泡編輯指令'
  },
  '新建气泡': {'en': 'New bubble', 'ja': '新規吹き出し', 'ko': '새 말풍선', 'zh_TW': '新增氣泡'},
  '复制气泡': {
    'en': 'Duplicate bubble',
    'ja': '吹き出しを複製',
    'ko': '말풍선 복제',
    'zh_TW': '複製氣泡'
  },
  '下移一层': {
    'en': 'Send backward',
    'ja': '背面へ移動',
    'ko': '뒤로 보내기',
    'zh_TW': '下移一層'
  },
  '上移一层': {
    'en': 'Bring forward',
    'ja': '前面へ移動',
    'ko': '앞으로 가져오기',
    'zh_TW': '上移一層'
  },
  '删除气泡': {
    'en': 'Delete bubble',
    'ja': '吹き出しを削除',
    'ko': '말풍선 삭제',
    'zh_TW': '刪除氣泡'
  },
  '打开属性面板': {
    'en': 'Open properties',
    'ja': '設定パネルを開く',
    'ko': '속성 패널 열기',
    'zh_TW': '開啟屬性面板'
  },
  '关闭属性面板': {
    'en': 'Close properties',
    'ja': '設定パネルを閉じる',
    'ko': '속성 패널 닫기',
    'zh_TW': '關閉屬性面板'
  },
  '适应画布': {
    'en': 'Fit canvas',
    'ja': 'キャンバスに合わせる',
    'ko': '캔버스에 맞추기',
    'zh_TW': '適應畫布'
  },
  '重置': {'en': 'Reset', 'ja': 'リセット', 'ko': '초기화', 'zh_TW': '重設'},
  '匹配字幕': {
    'en': 'Match captions',
    'ja': '字幕を割り当て',
    'ko': '자막 매칭',
    'zh_TW': '配對字幕'
  },
  '重新自动排版': {
    'en': 'Run auto layout again',
    'ja': '自動配置をやり直す',
    'ko': '자동 배치 다시 실행',
    'zh_TW': '重新自動排版'
  },
  '开始排版': {'en': 'Start layout', 'ja': '配置を開始', 'ko': '배치 시작', 'zh_TW': '開始排版'},
  '当前没有可排版字幕，请先进入“字幕”导入或添加气泡。': {
    'en':
        'There are no captions to arrange. Import a script under Captions or add a bubble first.',
    'ja': '配置できる字幕がありません。「字幕」から読み込むか、吹き出しを追加してください。',
    'ko': '배치할 자막이 없습니다. 자막에서 스크립트를 가져오거나 말풍선을 추가하세요.',
    'zh_TW': '目前沒有可排版字幕，請先進入「字幕」匯入或加入氣泡。'
  },
  '仅重置了当前图片的气泡排版': {
    'en': 'Reset the current image layout only',
    'ja': '現在の画像の配置のみリセットしました',
    'ko': '현재 이미지의 말풍선 배치만 초기화했습니다',
    'zh_TW': '僅重設目前圖片的氣泡排版'
  },
  '新建图片项目？': {
    'en': 'Create a new image project?',
    'ja': '新しい画像プロジェクトを作成しますか？',
    'ko': '새 이미지 프로젝트를 만들까요?',
    'zh_TW': '建立新圖片專案？'
  },
  '这会替换当前工程。请先保存需要保留的修改。': {
    'en':
        'This replaces the current project. Save any changes you want to keep first.',
    'ja': '現在のプロジェクトを置き換えます。残したい変更を先に保存してください。',
    'ko': '현재 프로젝트를 대체합니다. 유지할 변경 사항을 먼저 저장하세요.',
    'zh_TW': '這會取代目前工程。請先儲存需要保留的修改。'
  },
  '放弃并新建': {
    'en': 'Discard and create',
    'ja': '破棄して新規作成',
    'ko': '버리고 새로 만들기',
    'zh_TW': '放棄並新建'
  },
  '打开其他工程？': {
    'en': 'Open another project?',
    'ja': '別のプロジェクトを開きますか？',
    'ko': '다른 프로젝트를 열까요?',
    'zh_TW': '開啟其他工程？'
  },
  '当前工程有未保存修改。继续打开会放弃这些修改。': {
    'en':
        'The current project has unsaved changes. Opening another project will discard them.',
    'ja': '現在のプロジェクトには未保存の変更があります。続行すると破棄されます。',
    'ko': '현재 프로젝트에 저장하지 않은 변경 사항이 있습니다. 계속 열면 변경 사항이 삭제됩니다.',
    'zh_TW': '目前工程有未儲存修改。繼續開啟會放棄這些修改。'
  },
  '放弃并打开': {
    'en': 'Discard and open',
    'ja': '破棄して開く',
    'ko': '버리고 열기',
    'zh_TW': '放棄並開啟'
  },
  '项目无法打开': {
    'en': 'Cannot open project',
    'ja': 'プロジェクトを開けません',
    'ko': '프로젝트를 열 수 없음',
    'zh_TW': '專案無法開啟'
  },
  '无法打开工程': {
    'en': 'Cannot open project',
    'ja': 'プロジェクトを開けません',
    'ko': '프로젝트를 열 수 없음',
    'zh_TW': '無法開啟工程'
  },
  '切换项目': {
    'en': 'Switch project',
    'ja': 'プロジェクトを切替',
    'ko': '프로젝트 전환',
    'zh_TW': '切換專案'
  },
  '打开工程': {
    'en': 'Open project',
    'ja': 'プロジェクトを開く',
    'ko': '프로젝트 열기',
    'zh_TW': '開啟工程'
  },
  '保存工程': {
    'en': 'Save project',
    'ja': 'プロジェクトを保存',
    'ko': '프로젝트 저장',
    'zh_TW': '儲存工程'
  },
  '使用指南': {'en': 'User guide', 'ja': '使い方', 'ko': '사용 안내', 'zh_TW': '使用指南'},
  '批量导出': {
    'en': 'Batch export',
    'ja': '一括書き出し',
    'ko': '일괄 내보내기',
    'zh_TW': '批次匯出'
  },
  '选择任意字体颜色': {
    'en': 'Choose any text color',
    'ja': '文字色を選択',
    'ko': '글자 색상 선택',
    'zh_TW': '選擇任意字體顏色'
  },
  '应用颜色': {'en': 'Apply color', 'ja': '色を適用', 'ko': '색상 적용', 'zh_TW': '套用顏色'},
  '全部颜色 / 输入 HEX': {
    'en': 'All colors / Enter HEX',
    'ja': 'すべての色 / HEX入力',
    'ko': '모든 색상 / HEX 입력',
    'zh_TW': '全部顏色 / 輸入 HEX'
  },
  '导入 TTF / OTF / TTC 字体': {
    'en': 'Import TTF / OTF / TTC font',
    'ja': 'TTF / OTF / TTC フォントを読み込む',
    'ko': 'TTF / OTF / TTC 글꼴 가져오기',
    'zh_TW': '匯入 TTF / OTF / TTC 字體'
  },
  '全选': {'en': 'Select all', 'ja': 'すべて選択', 'ko': '모두 선택', 'zh_TW': '全選'},
  '清空': {'en': 'Clear', 'ja': 'クリア', 'ko': '지우기', 'zh_TW': '清空'},
  '应用': {'en': 'Apply', 'ja': '適用', 'ko': '적용', 'zh_TW': '套用'},
  '覆盖此图': {
    'en': 'Overwrite this image',
    'ja': 'この画像を上書き',
    'ko': '이 이미지 덮어쓰기',
    'zh_TW': '覆蓋此圖'
  },
  '全部覆盖': {
    'en': 'Overwrite all',
    'ja': 'すべて上書き',
    'ko': '모두 덮어쓰기',
    'zh_TW': '全部覆蓋'
  },
  '跳过此图': {
    'en': 'Skip this image',
    'ja': 'この画像をスキップ',
    'ko': '이 이미지 건너뛰기',
    'zh_TW': '略過此圖'
  },
  '取消导出': {
    'en': 'Cancel export',
    'ja': '書き出しをキャンセル',
    'ko': '내보내기 취소',
    'zh_TW': '取消匯出'
  },
  '图片已存在': {
    'en': 'Image already exists',
    'ja': '画像は既に存在します',
    'ko': '이미지가 이미 존재함',
    'zh_TW': '圖片已存在'
  },
  '选择要导出的图片': {
    'en': 'Choose images to export',
    'ja': '書き出す画像を選択',
    'ko': '내보낼 이미지 선택',
    'zh_TW': '選擇要匯出的圖片'
  },
  '仅当前图片': {
    'en': 'Current image only',
    'ja': '現在の画像のみ',
    'ko': '현재 이미지만',
    'zh_TW': '僅目前圖片'
  },
  '检测到超大图片': {
    'en': 'Very large image detected',
    'ja': '非常に大きな画像を検出',
    'ko': '매우 큰 이미지 감지됨',
    'zh_TW': '偵測到超大圖片'
  },
  '继续逐张导出': {
    'en': 'Continue exporting one by one',
    'ja': '1枚ずつ書き出す',
    'ko': '한 장씩 계속 내보내기',
    'zh_TW': '繼續逐張匯出'
  },
  '匹配字幕脚本': {
    'en': 'Match caption script',
    'ja': '字幕スクリプトを割り当て',
    'ko': '자막 스크립트 매칭',
    'zh_TW': '配對字幕腳本'
  },
  '导入 TXT': {
    'en': 'Import TXT',
    'ja': 'TXTを読み込む',
    'ko': 'TXT 가져오기',
    'zh_TW': '匯入 TXT'
  },
  '导出当前模板': {
    'en': 'Export current template',
    'ja': '現在のテンプレートを書き出す',
    'ko': '현재 템플릿 내보내기',
    'zh_TW': '匯出目前範本'
  },
  '格式规范': {
    'en': 'Format specification',
    'ja': '形式仕様',
    'ko': '형식 규격',
    'zh_TW': '格式規範'
  },
  'AI 生成指南': {
    'en': 'AI generation guide',
    'ja': 'AI生成ガイド',
    'ko': 'AI 생성 안내',
    'zh_TW': 'AI 生成指南'
  },
  '检查匹配': {
    'en': 'Validate matching',
    'ja': '割り当てを検証',
    'ko': '매칭 검사',
    'zh_TW': '檢查配對'
  },
  '应用并自动排版': {
    'en': 'Apply and auto layout',
    'ja': '適用して自動配置',
    'ko': '적용 및 자동 배치',
    'zh_TW': '套用並自動排版'
  },
  '字幕脚本无法应用': {
    'en': 'Caption script cannot be applied',
    'ja': '字幕スクリプトを適用できません',
    'ko': '자막 스크립트를 적용할 수 없음',
    'zh_TW': '字幕腳本無法套用'
  },
  '字幕格式检查': {
    'en': 'Caption format check',
    'ja': '字幕形式チェック',
    'ko': '자막 형식 검사',
    'zh_TW': '字幕格式檢查'
  },
  '返回修改': {
    'en': 'Back to edit',
    'ja': '編集に戻る',
    'ko': '편집으로 돌아가기',
    'zh_TW': '返回修改'
  },
  '精准字幕格式规范': {
    'en': 'Precise caption format',
    'ja': '字幕の精密形式仕様',
    'ko': '정밀 자막 형식 규격',
    'zh_TW': '精準字幕格式規範'
  },
  '完整 AI 字幕脚本生成指南': {
    'en': 'Complete AI caption-script guide',
    'ja': '完全版 AI 字幕スクリプト生成ガイド',
    'ko': '전체 AI 자막 스크립트 생성 안내',
    'zh_TW': '完整 AI 字幕腳本生成指南'
  },
  '复制精确规范 + 当前模板': {
    'en': 'Copy exact rules + current template',
    'ja': '正確な仕様＋現在のテンプレートをコピー',
    'ko': '정확한 규격 + 현재 템플릿 복사',
    'zh_TW': '複製精確規範 + 目前範本'
  },
  '完整规范、图片顺序、原图尺寸和当前模板已复制': {
    'en':
        'Copied the full rules, image order, source dimensions, and current template',
    'ja': '完全な仕様、画像順、元画像サイズ、現在のテンプレートをコピーしました',
    'ko': '전체 규격, 이미지 순서, 원본 크기 및 현재 템플릿을 복사했습니다',
    'zh_TW': '已複製完整規範、圖片順序、原圖尺寸和目前範本'
  },
  '对话气泡': {'en': 'Dialogue', 'ja': '会話', 'ko': '대화', 'zh_TW': '對話氣泡'},
  '心理气泡': {'en': 'Thought', 'ja': '心の声', 'ko': '생각', 'zh_TW': '心理氣泡'},
  '旁白框': {'en': 'Narration', 'ja': 'ナレーション', 'ko': '내레이션', 'zh_TW': '旁白框'},
  '耳语气泡': {'en': 'Whisper', 'ja': 'ささやき', 'ko': '속삭임', 'zh_TW': '耳語氣泡'},
  '惊喊气泡': {'en': 'Shout', 'ja': '叫び', 'ko': '외침', 'zh_TW': '驚喊氣泡'},
  '左上': {'en': 'Top left', 'ja': '左上', 'ko': '왼쪽 위', 'zh_TW': '左上'},
  '右上': {'en': 'Top right', 'ja': '右上', 'ko': '오른쪽 위', 'zh_TW': '右上'},
  '左下': {'en': 'Bottom left', 'ja': '左下', 'ko': '왼쪽 아래', 'zh_TW': '左下'},
  '右下': {'en': 'Bottom right', 'ja': '右下', 'ko': '오른쪽 아래', 'zh_TW': '右下'},
  '选择默认保存目录': {
    'en': 'Choose default save folder',
    'ja': '既定の保存フォルダーを選択',
    'ko': '기본 저장 폴더 선택',
    'zh_TW': '選擇預設儲存資料夾',
  },
  '选择成图导出文件夹': {
    'en': 'Choose image export folder',
    'ja': '画像の書き出し先を選択',
    'ko': '이미지 내보내기 폴더 선택',
    'zh_TW': '選擇成圖匯出資料夾',
  },
  '保存字幕成图': {
    'en': 'Save captioned image',
    'ja': '字幕入り画像を保存',
    'ko': '자막 이미지 저장',
    'zh_TW': '儲存字幕成圖',
  },
  '保存气泡字幕工程': {
    'en': 'Save caption project',
    'ja': '字幕プロジェクトを保存',
    'ko': '자막 프로젝트 저장',
    'zh_TW': '儲存氣泡字幕工程',
  },
  '导出精准字幕模板': {
    'en': 'Export precise caption template',
    'ja': '精密字幕テンプレートを書き出す',
    'ko': '정밀 자막 템플릿 내보내기',
    'zh_TW': '匯出精準字幕範本',
  },
  '导出完整 BCS 字幕': {
    'en': 'Export complete BCS captions',
    'ja': '完全な BCS 字幕を書き出す',
    'ko': '전체 BCS 자막 내보내기',
    'zh_TW': '匯出完整 BCS 字幕',
  },
  '导出完整 BCS 字幕脚本': {
    'en': 'Export complete BCS caption script',
    'ja': '完全な BCS 字幕スクリプトを書き出す',
    'ko': '전체 BCS 자막 스크립트 내보내기',
    'zh_TW': '匯出完整 BCS 字幕腳本',
  },
  '精准字幕模板.txt': {
    'en': 'precise-caption-template.txt',
    'ja': '精密字幕テンプレート.txt',
    'ko': '정밀-자막-템플릿.txt',
    'zh_TW': '精準字幕範本.txt',
  },
  '目标图片已存在': {
    'en': 'The destination image already exists',
    'ja': '書き出し先に同名の画像があります',
    'ko': '대상 이미지가 이미 존재합니다',
    'zh_TW': '目標圖片已存在',
  },
  '不是受支持的气泡字幕工程文件': {
    'en': 'This is not a supported caption project file',
    'ja': '対応している字幕プロジェクトファイルではありません',
    'ko': '지원되는 자막 프로젝트 파일이 아닙니다',
    'zh_TW': '這不是支援的氣泡字幕工程檔案',
  },
  '不是受支持的增量工程清单': {
    'en': 'This is not a supported incremental project manifest',
    'ja': '対応している差分プロジェクトマニフェストではありません',
    'ko': '지원되는 증분 프로젝트 매니페스트가 아닙니다',
    'zh_TW': '這不是支援的增量工程清單',
  },
  '工程中没有图片页面': {
    'en': 'The project contains no image pages',
    'ja': 'プロジェクトに画像ページがありません',
    'ko': '프로젝트에 이미지 페이지가 없습니다',
    'zh_TW': '工程中沒有圖片頁面',
  },
};

String _toTraditional(String source) {
  var result = source;
  const phrases = <String, String>{
    '软件': '軟體',
    '项目': '專案',
    '图片': '圖片',
    '字幕': '字幕',
    '气泡': '氣泡',
    '设置': '設定',
    '保存': '儲存',
    '导出': '匯出',
    '导入': '匯入',
    '选择': '選擇',
    '删除': '刪除',
    '创建': '建立',
    '打开': '開啟',
    '关闭': '關閉',
    '更新': '更新',
    '下载': '下載',
    '检查': '檢查',
    '默认': '預設',
    '目录': '目錄',
    '文件': '檔案',
    '颜色': '顏色',
    '字体': '字體',
    '边界': '邊界',
    '宽': '寬',
    '高': '高',
    '编号': '編號',
    '顺序': '順序',
    '确认': '確認',
    '继续': '繼續',
    '应用': '套用',
    '自动': '自動',
    '重新': '重新',
    '当前': '目前',
    '发现': '發現',
    '读取': '讀取',
    '显示': '顯示',
    '点击': '點擊',
    '添加': '加入',
    '弹出': '彈出',
    '错误': '錯誤',
    '无效': '無效',
    '无法': '無法',
    '已经': '已經',
    '进行': '進行',
    '返回': '返回',
    '话': '話',
    '画面': '畫面',
    '漫画': '漫畫',
    '简体': '簡體',
    '繁体': '繁體',
  };
  for (final entry in phrases.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

class LText extends Text {
  LText(
    String data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaleFactor,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  }) : super(tr(data));
}
