import 'package:flutter/material.dart';

/// 可復原的提示，4 秒後自動消失。
///
/// Flutter 的 SnackBar 只要有按鈕就預設 `persist: true`（為了無障礙，
/// 會一直留到使用者按掉），一鍵 +1 這種頻繁操作會讓提示卡在畫面上。
void showUndoSnackBar(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        persist: false,
        action: SnackBarAction(label: '復原', onPressed: onUndo),
      ),
    );
}
