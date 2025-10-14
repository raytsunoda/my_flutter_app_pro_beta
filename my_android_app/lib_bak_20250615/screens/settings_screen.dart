import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';



class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay _morningTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _eveningTime = const TimeOfDay(hour: 20, minute: 0);
  bool _isEditing = false;

  double _weightSleep = 0.3;
  double _weightStretch = 0.1;
  double _weightWalking = 0.3;
  double _weightAppreciation = 0.3;

  List<List<dynamic>> _csvData = [];
  List<bool> _expanded = [];
  List<bool> _selected = [];

  @override
  void initState() {
    super.initState();
    _loadNotificationTimes();
    _loadPreferences();
    _loadCSV();
  }

  Widget _kv(String label, dynamic value) {
    final s = (value ?? '').toString();
    if (s.isEmpty) return const SizedBox.shrink(); // 空なら出さない
    return Text('$label: $s');
  }


  Future<void> _loadNotificationTimes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _morningTime = TimeOfDay(
        hour: prefs.getInt('morning_hour') ?? 8,
        minute: prefs.getInt('morning_minute') ?? 0,
      );
      _eveningTime = TimeOfDay(
        hour: prefs.getInt('evening_hour') ?? 20,
        minute: prefs.getInt('evening_minute') ?? 0,
      );
    });
  }

  Future<void> _saveNotificationTimes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('morning_hour', _morningTime.hour);
    await prefs.setInt('morning_minute', _morningTime.minute);
    await prefs.setInt('evening_hour', _eveningTime.hour);
    await prefs.setInt('evening_minute', _eveningTime.minute);

    await _scheduleNotification(id: 1, time: _morningTime, title: '朝の記録時間', body: '今日の記録をお忘れなく！');
    await _scheduleNotification(id: 2, time: _eveningTime, title: '夜の振り返り', body: 'ヒントや名言をチェックしましょう！');
  }

  Future<void> _scheduleNotification({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'basic_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
      ),
      schedule: NotificationCalendar(
        hour: scheduledDate.hour,
        minute: scheduledDate.minute,
        second: 0,
        repeats: true,
      ),
    );
  }

  Future<void> _pickTime({required bool isMorning}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isMorning ? _morningTime : _eveningTime,
    );
    if (picked != null) {
      setState(() {
        if (isMorning) {
          _morningTime = picked;
        } else {
          _eveningTime = picked;
        }
      });
    }
  }

  Widget _buildTimePickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('通知時刻設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ListTile(
          title: const Text('朝の通知時間'),
          trailing: Text(_morningTime.format(context)),
          onTap: () => _pickTime(isMorning: true),
        ),
        ListTile(
          title: const Text('夜の通知時間'),
          trailing: Text(_eveningTime.format(context)),
          onTap: () => _pickTime(isMorning: false),
        ),
        Center(
          child: ElevatedButton(
            onPressed: _saveNotificationTimes,
            child: const Text('保存'),
          ),
        )
      ],
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _weightSleep = prefs.getDouble('weightSleep') ?? _weightSleep;
      _weightStretch = prefs.getDouble('weightStretch') ?? _weightStretch;
      _weightWalking = prefs.getDouble('weightWalking') ?? _weightWalking;
      _weightAppreciation = prefs.getDouble('weightAppreciation') ?? _weightAppreciation;
    });
  }

  Future<void> _saveWeightPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('weightSleep', _weightSleep);
    await prefs.setDouble('weightStretch', _weightStretch);
    await prefs.setDouble('weightWalking', _weightWalking);
    await prefs.setDouble('weightAppreciation', _weightAppreciation);
  }

  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Text('$label: ${value.toStringAsFixed(1)}'),
        Slider(
          min: 0.0,
          max: 1.0,
          divisions: 10,
          value: value,
          label: value.toStringAsFixed(1),
          onChanged: _isEditing ? (v) => setState(() => onChanged(double.parse(v.toStringAsFixed(1)))) : null,
        ),
      ],
    );
  }

  Widget _buildWeightSection() {
    final total = _weightSleep + _weightStretch + _weightWalking + _weightAppreciation;
    return ExpansionTile(
      title: const Text('重み設定'),
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('合計は1.0にしてください。'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('合計: ${total.toStringAsFixed(1)} / 1.0'),
              TextButton(
                onPressed: () => setState(() => _isEditing = !_isEditing),
                child: Text(_isEditing ? '編集中' : '編集'),
              ),
            ],
          ),
        ),
        _buildSlider('睡眠', _weightSleep, (v) => _weightSleep = v),
        _buildSlider('ストレッチ', _weightStretch, (v) => _weightStretch = v),
        _buildSlider('ウォーキング', _weightWalking, (v) => _weightWalking = v),
        _buildSlider('感謝', _weightAppreciation, (v) => _weightAppreciation = v),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: () {
              if (total.toStringAsFixed(1) == '1.0') {
                _saveWeightPreferences();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重みを保存しました')));
                setState(() => _isEditing = false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('合計が1.0ではありません')));
              }
            },
            child: const Text('保存'),
          ),
        )
      ],
    );
  }

  Future<void> _loadCSV() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/HappinessLevelDB1_v2.csv');
      if (!file.existsSync()) return;
      final csv = await file.readAsString();
      final rows = CsvToListConverter().convert(csv).skip(1).toList();
      rows.sort((a, b) => b[0].toString().compareTo(a[0].toString()));
      setState(() {
        _csvData = rows;
        _expanded = List.filled(rows.length, false);
        _selected = List.filled(rows.length, false);
      });
    } catch (e) {
      print('CSV読み込み失敗: $e');
    }
  }

  Future<void> _deleteSelectedRows() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/HappinessLevelDB1_v2.csv');
    if (!file.existsSync()) return;
    final csv = await file.readAsString();
    final table = CsvToListConverter().convert(csv);
    final header = table.first;
    final data = table.sublist(1);

    final updated = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      if (!_selected[i]) updated.add(data[i]);
    }

    final newCsv = const ListToCsvConverter().convert([header, ...updated]);
    await file.writeAsString(newCsv);
    _loadCSV();
  }

  Future<void> _deleteAll() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/HappinessLevelDB1_v2.csv');
    if (!file.existsSync()) return;
    final csv = await file.readAsString();
    final header = CsvToListConverter().convert(csv).first;
    final newCsv = const ListToCsvConverter().convert([header]);
    await file.writeAsString(newCsv);
    _loadCSV();
  }

  Widget _buildDataSection() {
    return ExpansionTile(
      title: const Text('保存データの管理'),
      children: [
        if (_csvData.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('保存データが存在しません。'),
          )
        else
          Column(
            children: [
              for (int i = 0; i < _csvData.length; i++)
                Column(
                  children: [
                    ListTile(
                      leading: Checkbox(
                        value: _selected[i],
                        onChanged: (v) => setState(() => _selected[i] = v ?? false),
                      ),
                      title: Text(_csvData[i][0].toString()),
                      trailing: IconButton(
                        icon: Icon(_expanded[i] ? Icons.expand_less : Icons.expand_more),
                        onPressed: () => setState(() => _expanded[i] = !_expanded[i]),
                      ),
                    ),
                    if (_expanded[i])
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('幸せ感レベル',       _csvData[i][1]),
                            _kv('ストレッチ時間',     _csvData[i][2]),
                            _kv('ウォーキング時間',   _csvData[i][3]),
                            _kv('睡眠の質',           _csvData[i][4]),
                            _kv('睡眠時間（時間）',   _csvData[i][5]),
                            _kv('睡眠時間（分）',     _csvData[i][6]),
                            _kv('寝付き満足度',       _csvData[i][7]),
                            _kv('深い睡眠感',         _csvData[i][8]),
                            _kv('目覚め感',           _csvData[i][9]),
                            _kv('モチベーション',     _csvData[i][10]),
                            _kv('感謝数',             _csvData[i][11]),
                            _kv('感謝1',              _csvData[i][12]),
                            _kv('感謝2',              _csvData[i][13]),
                            _kv('感謝3',              _csvData[i][14]),
                            _kv('今日のひとことメモ',  _csvData[i][15]),
                          ],
                        ),
                      ),

                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: _deleteSelectedRows, child: const Text('選択削除')),
                  ElevatedButton(onPressed: _deleteAll, child: const Text('全削除')),
                ],
              )
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("設定")),
      body: ListView(
        children: [
          ExpansionTile(title: const Text('通知設定'), children: [_buildTimePickerSection()]),
          _buildWeightSection(),
          _buildDataSection(),
        ],
      ),
    );
  }
  class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionHeader({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
  final style = Theme.of(context).textTheme.titleMedium?.copyWith(
  fontWeight: FontWeight.w600,
  );
  return Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
  child: Row(
  children: [
  Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
  const SizedBox(width: 8),
  Text(text, style: style),
  ],
  ),
  );
  }
  }
}



