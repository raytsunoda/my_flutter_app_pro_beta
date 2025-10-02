import 'package:flutter/material.dart';

/// アプリ全体で selectedRow を共有・管理するための Provider
class SelectedRowProvider extends ChangeNotifier {
  Map<String, dynamic>? _selectedRow;

  /// 現在の選択行を取得
  Map<String, dynamic>? get selectedRow => _selectedRow;

  /// 選択行を設定し、リスナーに通知
  void setSelectedRow(Map<String, dynamic> row) {
    _selectedRow = row;
    notifyListeners();
  }

  /// 選択行をクリアし、リスナーに通知
  void clearSelectedRow() {
    _selectedRow = null;
    notifyListeners();
  }
}
