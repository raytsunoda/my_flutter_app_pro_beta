import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import '../screens/one_day_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // SharedPreferences保存に必要

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

  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/HappinessLevelDB1_v2.csv');
  }

  Future<void> saveEntry() async {
    final file = await _localFile;
    List<List<dynamic>> csvData = [];

    if (await file.exists()) {
      final content = await file.readAsString();
      csvData = const CsvToListConverter().convert(content);
    } else {
      csvData.add([
        '日付', '幸せ感レベル', 'ストレッチ時間', 'ウォーキング時間', '睡眠の質',
        '睡眠時間（時間換算）', '睡眠時間（分換算）', '睡眠時間（時間）', '睡眠時間（分）',
        '寝付き満足度', '深い睡眠感', '目覚め感', 'モチベーション',
        '感謝数', '感謝1', '感謝2', '感謝3'
      ]);
    }

    final formattedDate = DateFormat('yyyy/MM/dd').format(selectedDate);

    final existingIndex = csvData.indexWhere((row) =>
    row.isNotEmpty && row[0].toString().trim() == formattedDate);

    if (existingIndex != -1) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("日付の重複"),
          content: const Text("この日付のデータはすでに存在します。上書きしてもよろしいですか？"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("キャンセル")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("上書きする")),
          ],
        ),
      );
      if (overwrite != true) return;
      csvData.removeAt(existingIndex);
    }

    final prefs = await SharedPreferences.getInstance();
    double wStretch = prefs.getDouble('weightStretch') ?? 0.1;
    double wWalking = prefs.getDouble('weightWalking') ?? 0.3;
    double wSleep = prefs.getDouble('weightSleep') ?? 0.3;
    double wAppreciation = prefs.getDouble('weightAppreciation') ?? 0.3;


    final sleepMinutesTotal = sleepHours * 60 + sleepMinutes;
    final sleepHoursTotal = sleepMinutesTotal / 60;
    final appreciationList = [
      appreciation1Controller.text.trim(),
      appreciation2Controller.text.trim(),
      appreciation3Controller.text.trim()
    ];
    threeAppreciations = appreciationList.where((e) => e.isNotEmpty).length;

    // 睡眠の質の算出（内部固定ロジック）
    final sleepQualityFactor1 = (sleepHours / 8) * 100 * 0.2;
    final sleepQualityFactor2 = (fallingAsleepSatisfaction / 5) * 100 * 0.2;
    final sleepQualityFactor3 = (deepSleepFeeling / 5) * 100 * 0.2;
    final sleepQualityFactor4 = (wakeUpFeeling / 5) * 100 * 0.2;
    final sleepQualityFactor5 = (motivation / 5) * 100 * 0.2;
    sleepQuality = sleepQualityFactor1 + sleepQualityFactor2 + sleepQualityFactor3 + sleepQualityFactor4 + sleepQualityFactor5;

    // 各スコア計算
    final stretchScore = (stretchDuration / 30) * wStretch * 100;
    final walkingScore = (walkingDuration / 90) * wWalking * 100;
    final sleepScore = (sleepQuality / 100) * wSleep * 100;
    final appreciationScore = (threeAppreciations / 3) * wAppreciation * 100;
    final happinessLevel = stretchScore + walkingScore + sleepScore + appreciationScore;

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
      ...appreciationList
    ];

    csvData.add(newRow);
    final csvContent = const ListToCsvConverter().convert(csvData);
    await file.writeAsString(csvContent);
    print('[DEBUG] newRow保存内容: $newRow');

    final updatedContent = await file.readAsString();
    final updatedCsv = const CsvToListConverter().convert(updatedContent);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => OneDayView(
          csvData: updatedCsv.skip(1).map((row) => Map<String, String>.fromIterables(
            updatedCsv.first.map((e) => e.toString()),
            row.map((e) => e.toString()),
          )).toList(),
          selectedRow: Map<String, String>.fromIterables(
            updatedCsv.first.map((e) => e.toString()),
            newRow.map((e) => e.toString()),
          ),
          selectedDate: selectedDate,
        ),
      ),
    );
  }

  @override
  void dispose() {
    appreciation1Controller.dispose();
    appreciation2Controller.dispose();
    appreciation3Controller.dispose();
    super.dispose();
  }

  Widget buildDropdown(String label, int value, List<int> options, Function(int?) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        DropdownButton<int>(
          value: value,
          items: options.map((e) => DropdownMenuItem(value: e, child: Text("$e"))).toList(),
          onChanged: onChanged,
        )
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
    final dateStr = DateFormat('yyyy/MM/dd').format(selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text('📝 毎日の入力画面')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('📅 日付を選択:'),
                Text(dateStr),
              ]),
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
                child: const Text("日付を選ぶ"),
              )
            ]),
            const Divider(),
            buildDropdown("🧘 ストレッチ（分）", stretchDuration, [0, 10, 20, 30], (val) => setState(() => stretchDuration = val!)),
            buildDropdown("🚶 ウォーキング（分）", walkingDuration, List.generate(10, (i) => i * 10), (val) => setState(() => walkingDuration = val!)),
            buildDropdown("😴 睡眠時間（時間）", sleepHours, List.generate(13, (i) => i), (val) => setState(() => sleepHours = val!)),
            buildDropdown("😴 睡眠時間（分）", sleepMinutes, [0, 10, 20, 30, 40, 50], (val) => setState(() => sleepMinutes = val!)),
            buildDropdown("😴 寝付きの満足度", fallingAsleepSatisfaction, List.generate(6, (i) => i), (val) => setState(() => fallingAsleepSatisfaction = val!)),
            buildDropdown("😴 深い睡眠感", deepSleepFeeling, List.generate(6, (i) => i), (val) => setState(() => deepSleepFeeling = val!)),
            buildDropdown("😴 目覚め感", wakeUpFeeling, List.generate(6, (i) => i), (val) => setState(() => wakeUpFeeling = val!)),
            buildDropdown("😄 モチベーション", motivation, List.generate(6, (i) => i), (val) => setState(() => motivation = val!)),
            const Divider(),
            const Text("🙏 3つの感謝（日本語入力）"),
            buildTextField("感謝 1", appreciation1Controller),
            buildTextField("感謝 2", appreciation2Controller),
            buildTextField("感謝 3", appreciation3Controller),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("確認"),
                      content: const Text("この内容で保存してよろしいですか？"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("キャンセル")),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OK")),
                      ],
                    ),
                  );
                  if (confirmed == true) setState(() => isConfirmed = true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text("確認"),
              ),
              ElevatedButton(
                onPressed: isConfirmed ? saveEntry : null,
                style: ElevatedButton.styleFrom(backgroundColor: isConfirmed ? Colors.green : Colors.grey),
                child: const Text('保存'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("閉じる"),
              ),
            ])
          ],
        ),
      ),
    );
  }
}
