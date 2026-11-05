import 'package:flutter/material.dart';

/// 底部表單的標題列：標題在左，右邊一顆「✕」可以直接關掉。
/// 鍵盤彈出時表單幾乎佔滿畫面，點外面或下滑不好關，所以一律放明確的關閉鈕。
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: '關閉',
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
