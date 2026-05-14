import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import '../screens/one_day_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../gen_l10n/app_localizations.dart';
//import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/ai_comment_service.dart';
import 'dart:async';

class ManualInputView extends StatefulWidget {
  final VoidCallback? onSaved;
  final List<List<dynamic>>? csvData;
  final Map<String, dynamic>? selectedRow;

  const ManualInputView({
    super.key,
    this.onSaved,
    required this.csvData,
    required this.selectedRow,
  });

  @override
  State<ManualInputView> createState() => _ManualInputViewState();
}

class _ManualInputViewState extends State<ManualInputView> {
  DateTime selectedDate = DateTime.now();
  int stretchDuration = 0;
  int walkingDuration = 0;
  double sleepQuality = 0.0;
  int sleepHours = 0;
  int sleepMinutes = 0;
  int fallingAsleepSatisfaction = 0;
  int deepSleepFeeling = 0;
  int wakeUpFeeling = 0;
  int motivation = 0;
  int threeAppreciations = 0;

  final appreciation1Controller = TextEditingController();
  final appreciation2Controller = TextEditingController();
  final appreciation3Controller = TextEditingController();

  bool isConfirmed = false;

  bool _isSaving = false;

  String _loadingMessage = '';
  Timer? _loadingTimer;

  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/HappinessLevelDB1_v2.csv');
  }

  Future<void> saveEntry() async {
    if (_isSaving) return;

    final t = AppLocalizations.of(context)!;

    setState(() {
      _isSaving = true;
    });
    _loadingMessage = t.aiThinking;

    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isSaving) {
        setState(() {
          _loadingMessage = t.aiGeneratingMessage;
        });
      }
    });

    try {

    final t = AppLocalizations.of(context)!; // ✅ 追加：saveEntry内でも使えるように
    final file = await _localFile;
    List<List<dynamic>> csvData = [];

    // ──────────────────────────────
    // ① ファイルが無ければ初期化（ヘッダー付き）
    // ──────────────────────────────
    if (!await file.exists()) {
      csvData.add([
        '日付',
        '幸せ感レベル',
        'ストレッチ時間',
        'ウォーキング時間',
        '睡眠の質',
        '睡眠時間（時間換算）',
        '睡眠時間（分換算）',
        '睡眠時間（時間）',
        '睡眠時間（分）',
        '寝付き満足度',
        '深い睡眠感',
        '目覚め感',
        'モチベーション',
        '感謝数',
        '感謝1',
        '感謝2',
        '感謝3',
      ]);
      await file.writeAsString(
        const ListToCsvConverter(eol: '\n').convert(csvData),
      );
    }

    // ──────────────────────────────
    // ② 読み込み & 列数補正
    // ──────────────────────────────
    final content = await file.readAsString();
    csvData = const CsvToListConverter(eol: '\n').convert(content);
    const expectedLen = 18; // ← 感謝3つ + メモで1列増える

    // ヘッダー補正
    if (csvData.isEmpty || csvData.first.length != expectedLen) {
      debugPrint('🔧 ヘッダーを再生成');
      if (csvData.isNotEmpty) csvData.removeAt(0);
      csvData.insert(0, [
        '日付',
        '幸せ感レベル',
        'ストレッチ時間',
        'ウォーキング時間',
        '睡眠の質',
        '睡眠時間（時間換算）',
        '睡眠時間（分換算）',
        '睡眠時間（時間）',
        '睡眠時間（分）',
        '寝付き満足度',
        '深い睡眠感',
        '目覚め感',
        'モチベーション',
        '感謝数',
        '感謝1',
        '感謝2',
        '感謝3',
        'memo',
      ]);
    }

    // データ行補正
    for (int i = 1; i < csvData.length; i++) {
      if (csvData[i].length > expectedLen) {
        csvData[i] = csvData[i].sublist(0, expectedLen);
      } else if (csvData[i].length < expectedLen) {
        csvData[i] = [
          ...csvData[i],
          ...List.filled(expectedLen - csvData[i].length, ''),
        ];
      }
    }

    // ──────────────────────────────
    // ③ 上書き確認
    // ──────────────────────────────
    final formattedDate = DateFormat('yyyy/MM/dd').format(selectedDate);
    final existingIndex = csvData.indexWhere(
      (row) => row.isNotEmpty && row[0].toString().trim() == formattedDate,
    );
    if (existingIndex != -1) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final t = AppLocalizations.of(ctx)!;

          return AlertDialog(
            title: Text(t.dateDuplicateTitle),
            content: Text(t.dateDuplicateMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t.overwrite),
              ),
            ],
          );
        },
      );

      if (overwrite != true) return;
      csvData.removeAt(existingIndex);
    }

    // ──────────────────────────────
    // ④ 計算ロジック（修正版）
    // ──────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final wStretch = prefs.getDouble('weightStretch') ?? 0.1;
    final wWalking = prefs.getDouble('weightWalking') ?? 0.3;
    final wSleep = prefs.getDouble('weightSleep') ?? 0.3;
    final wAppreciation = prefs.getDouble('weightAppreciation') ?? 0.3;

    final sleepMinutesTotal = sleepHours * 60 + sleepMinutes;
    final sleepHoursTotal = sleepMinutesTotal / 60.0;

    // 句読点/改行をCSV互換に整える
    String _sanitize(String txt) =>
        txt.replaceAll(RegExp(r'[\r\n]'), ' ').replaceAll(',', '、');

    // 感謝テキスト（3本に揃える）
    final appreciationList = [
      _sanitize(appreciation1Controller.text.trim()),
      _sanitize(appreciation2Controller.text.trim()),
      _sanitize(appreciation3Controller.text.trim()),
    ]..length = 3;

    threeAppreciations = appreciationList.where((e) => e.isNotEmpty).length;

    // 0.0〜1.0に正規化 → 100点満点へ変換するヘルパ
    double _pct(double v) {
      final n = v.isNaN ? 0.0 : v;
      final clamped = n.clamp(0.0, 1.0);
      return clamped * 100.0;
    }

    // 睡眠の質 = 5要素を各20%で合算（最大100）
    final sleepQualityFactor1 = _pct(sleepHoursTotal / 8.0) * 0.2; // 目標8h
    final sleepQualityFactor2 = _pct(fallingAsleepSatisfaction / 5) * 0.2;
    final sleepQualityFactor3 = _pct(deepSleepFeeling / 5) * 0.2;
    final sleepQualityFactor4 = _pct(wakeUpFeeling / 5) * 0.2;
    final sleepQualityFactor5 = _pct(motivation / 5) * 0.2;

    sleepQuality = (sleepQualityFactor1 +
            sleepQualityFactor2 +
            sleepQualityFactor3 +
            sleepQualityFactor4 +
            sleepQualityFactor5)
        .clamp(0.0, 100.0);

    // レーダー用の各サブスコア（重みは設定に依存）
    final stretchScore = (stretchDuration / 30.0) * wStretch * 100.0;
    final walkingScore = (walkingDuration / 90.0) * wWalking * 100.0;
    final sleepScore = (sleepQuality / 100.0) * wSleep * 100.0;
    final appreciationScore =
        (threeAppreciations / 3.0) * wAppreciation * 100.0;

    // 幸せ感レベル（0〜100想定）
    final happinessLevel = (stretchScore +
            walkingScore +
            sleepScore +
            appreciationScore)
        .clamp(0.0, 100.0);

    // メモ（200字・CSV安全化）
    final memo = _sanitize(memoController.text.trim());

    // 保存行（ヘッダー18列に揃える）
    final newRow = [
      formattedDate,
      happinessLevel.toStringAsFixed(1),
      stretchDuration,
      walkingDuration,
      sleepQuality.toStringAsFixed(1),
      sleepHoursTotal.toStringAsFixed(1),
      sleepMinutesTotal,
      sleepHours,
      sleepMinutes,
      fallingAsleepSatisfaction,
      deepSleepFeeling,
      wakeUpFeeling,
      motivation,
      threeAppreciations,
      ...appreciationList,
      memo, // 18列目
    ];

    // 列数チェック（ヘッダーと同数=18）
    if (csvData.isNotEmpty && csvData[0].length != newRow.length) {
      debugPrint("⚠️ 列数が合いません: ${csvData[0].length} vs ${newRow.length}");
    }
    if (newRow.length != expectedLen) {
      debugPrint('❌ newRow 列数異常: ${newRow.length}');
      ScaffoldMessenger.of(context).showSnackBar(
        //  const SnackBar(content: Text('保存に失敗しました（列数が異常です）')),
        SnackBar(content: Text(t.saveFailedColumnMismatch)),
      );
      return;
    }

    // ──────────────────────────────
    // ⑤ 保存・画面遷移
    // ──────────────────────────────
    csvData.add(newRow);
    final csvContent = const ListToCsvConverter(eol: '\n').convert(csvData);
    await file.writeAsString(csvContent);
    debugPrint('[DEBUG] CSVファイル保存完了: ${file.path}');

    String initialAiDailyText = '';

    try {
      final savedDate = DateFormat('yyyy/MM/dd').parseStrict(formattedDate);

      debugPrint('[AI save] formattedDate=$formattedDate');

      // 保存直後も、AIパートナー画面と同じ高品質ルートを使う
      final rec = await AiCommentService.ensureDailySaved(savedDate);

      debugPrint('[AI save] rec=$rec');

      initialAiDailyText = (rec['comment'] ?? '').trim();

      if (initialAiDailyText.isEmpty) {
        final saved = await AiCommentService.getSavedComment(
          date: formattedDate,
          type: 'daily',
        );
        debugPrint('[AI save] saved after ensure=$saved');
        initialAiDailyText = (saved ?? '').trim();
      }

      debugPrint('[AI save] initialAiDailyText=$initialAiDailyText');
    } catch (e, st) {
      debugPrint('[AI save] ERROR=$e');
      debugPrint('[AI save] STACK=$st');
    }

    final updatedCsv = csvData;

    // ▼▼▼ ここから差し替え：OneDayView に渡す Map を “渡す一覧から日付で引き直す” ▼▼▼
    final headers = updatedCsv.first.map((e) => e.toString()).toList();

    final mappedList =
        updatedCsv
            .skip(1)
            .map(
              (row) => Map<String, String>.fromIterables(
                headers,
                row.map((e) => e.toString()),
              ),
            )
            .toList();

    // newRow で保存した日付文字列（あなたのCSVはキーが「日付」になっている）
    final savedDateStr = newRow.first.toString();

    // 一覧から同日付の行を引き直す（＝保存直後でも memo を確実に含むrowを渡す）
    Map<String, String> selected = mappedList.lastWhere(
      (m) => (m['日付'] ?? '') == savedDateStr,
      orElse: () {
        // 念のため fallback（ここに来るのは想定外）
        return Map<String, String>.fromIterables(
          headers,
          newRow.map((e) => e.toString()),
        );
      },
    );

    // 念のため memo を上書き（UI入力→保存直後の表示を確実に一致させる）
    selected['memo'] = memoController.text.trim();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => OneDayView(
              csvData: mappedList,
              selectedRow: selected,
              selectedDate: selectedDate,
              initialAiDailyText: initialAiDailyText,
            ),
      ),
    );
    // ▲▲▲ ここまで差し替え ▲▲▲
    } finally {
      _loadingTimer?.cancel();

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
 // }
    }

  // ❶ State追加
  final memoController = TextEditingController();
  int memoCharCount = 0;

  @override
  void dispose() {
    appreciation1Controller.dispose();
    appreciation2Controller.dispose();
    appreciation3Controller.dispose();
    memoController.dispose(); // ← 追加
    super.dispose();
  }

  Widget buildDropdown(
    String label,
    int value,
    List<int> options,
    Function(int?) onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        DropdownButton<int>(
          value: value,
          items:
              options
                  .map((e) => DropdownMenuItem(value: e, child: Text("$e")))
                  .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      textInputAction: TextInputAction.next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final memoMaxLength =
    Localizations.localeOf(context).languageCode == 'ja' ? 200 : 400;

    final dateStr = DateFormat('yyyy/MM/dd').format(selectedDate);

    if (widget.csvData == null || widget.csvData!.length <= 1) {
      return Scaffold(
        //appBar: AppBar(title: const Text('📝 毎日の入力画面')),
        appBar: AppBar(title: Text('📝 ${t.dailyInputTitle}')),

        //body: const Center(child: Text('⚠️ データがありません。入力してください。')),
        body: Center(child: Text(t.noDataPleaseInput)),
      );
    }

    return Scaffold(
      //appBar: AppBar(title: const Text('📝 毎日の入力画面')),
      appBar: AppBar(title: Text(t.dailyInputTitle)),
      body: Stack(
        children: [


//      body:

      SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    //  const Text('📅 日付を選択:'),
                    Text(t.selectDateLabel),

                    Text(dateStr),
                  ],
                ),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                  // child: const Text("日付を選ぶ"),
                  child: Text(t.pickDate),
                ),
              ],
            ),
            const Divider(),
            //buildDropdown("🧘 昨日のストレッチ（分）", stretchDuration, [0, 10, 20, 30], (val) => setState(() => stretchDuration = val!)),
            buildDropdown(
              t.stretchYesterdayMinutes,
              stretchDuration,
              [0, 10, 20, 30],
              (val) => setState(() => stretchDuration = val!),
            ),

            //buildDropdown("🚶 昨日のウォーキング（分）", walkingDuration, List.generate(10, (i) => i * 10), (val) => setState(() => walkingDuration = val!)),
            buildDropdown(
              t.walkingYesterdayMinutes,
              walkingDuration,
              List.generate(10, (i) => i * 10),
              (val) => setState(() => walkingDuration = val!),
            ),
            // buildDropdown("😴 睡眠時間（時間）", sleepHours, List.generate(13, (i) => i), (val) => setState(() => sleepHours = val!)),
            // buildDropdown("😴 睡眠時間（分）", sleepMinutes, [0, 10, 20, 30, 40, 50], (val) => setState(() => sleepMinutes = val!)),
            // buildDropdown("😴 寝付きの満足度", fallingAsleepSatisfaction, List.generate(6, (i) => i), (val) => setState(() => fallingAsleepSatisfaction = val!)),
            // buildDropdown("😴 深い睡眠感", deepSleepFeeling, List.generate(6, (i) => i), (val) => setState(() => deepSleepFeeling = val!)),
            // buildDropdown("😴 目覚め感", wakeUpFeeling, List.generate(6, (i) => i), (val) => setState(() => wakeUpFeeling = val!)),
            // buildDropdown("😄 モチベーション", motivation, List.generate(6, (i) => i), (val) => setState(() => motivation = val!)),
            buildDropdown(
              "😴 ${t.sleepHoursLabel}",
              sleepHours,
              List.generate(13, (i) => i),
              (val) => setState(() => sleepHours = val!),
            ),
            buildDropdown(
              "😴 ${t.sleepMinutesLabel}",
              sleepMinutes,
              [0, 10, 20, 30, 40, 50],
              (val) => setState(() => sleepMinutes = val!),
            ),
            buildDropdown(
              "😴 ${t.sleepFallingAsleepLabel}",
              fallingAsleepSatisfaction,
              List.generate(6, (i) => i),
              (val) => setState(() => fallingAsleepSatisfaction = val!),
            ),
            buildDropdown(
              "😴 ${t.sleepDeepLabel}",
              deepSleepFeeling,
              List.generate(6, (i) => i),
              (val) => setState(() => deepSleepFeeling = val!),
            ),
            buildDropdown(
              "😴 ${t.sleepWakeupLabel}",
              wakeUpFeeling,
              List.generate(6, (i) => i),
              (val) => setState(() => wakeUpFeeling = val!),
            ),
            buildDropdown(
              "😄 ${t.motivationLabel}",
              motivation,
              List.generate(6, (i) => i),
              (val) => setState(() => motivation = val!),
            ),

            const Divider(),
            //const Text("🙏 3つの感謝（日本語入力）"),
            Text(t.gratitudeSectionTitle),

            // buildTextField("感謝 1", appreciation1Controller),
            // buildTextField("感謝 2", appreciation2Controller),
            // buildTextField("感謝 3", appreciation3Controller),
            buildTextField(t.gratitude1, appreciation1Controller),
            buildTextField(t.gratitude2, appreciation2Controller),
            buildTextField(t.gratitude3, appreciation3Controller),

            const Divider(),
            Text(
              '🌱 ${t.memoSectionTitle}',

              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: memoController,
              maxLength: memoMaxLength,
              maxLines: 3,
              onChanged: (text) => setState(() => memoCharCount = text.length),
              // decoration: const InputDecoration(
              //   hintText: '例：昨日より少し元気が出た気がします🌱',
              //   border: OutlineInputBorder(),
              decoration: InputDecoration(
                hintText: t.memoPlaceholder,
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                //  '$memoCharCount / 200文字',
                  Localizations.localeOf(context).languageCode == 'ja'
                      ? '$memoCharCount / $memoMaxLength文字'
                      : '$memoCharCount/$memoMaxLength',

                style: const TextStyle(fontSize: 12),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder:
                          (ctx) => AlertDialog(
                            // title: const Text("確認"),
                            // content: const Text("この内容で保存してよろしいですか？"),
                            // actions: [
                            //   TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("キャンセル")),
                            //   TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OK")),
                            // ],
                            title: Text(t.confirmTitle),
                            content: Text(t.confirmSaveMessage),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(t.cancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(t.ok),
                              ),
                            ],
                          ),
                    );
                    if (confirmed == true) setState(() => isConfirmed = true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: //const Text("確認"),
                      Text(t.confirmTitle),
                ),
                ElevatedButton(
                  onPressed: (isConfirmed && !_isSaving) ? saveEntry : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isConfirmed && !_isSaving)
                        ? Colors.green
                        : Colors.grey,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(t.save),
                ),


                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: //const Text("閉じる"),
                      Text(t.close),
                ),
              ],
            ),
          ],
        ),
      ),

    if (_isSaving)
    Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _loadingMessage,

                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                t.aiAnalyzing,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),

            ],
          ),
        ),
      ),
    ),
    ],
    ),




    );
  }
}
