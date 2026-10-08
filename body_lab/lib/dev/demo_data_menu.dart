import 'package:flutter/material.dart';

import '../data/body_repository.dart';
import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/phase_repository.dart';
import '../data/template_repository.dart';
import 'demo_data.dart';

/// 開發用選單：產生示範資料 / 清空資料。只在 debug 版顯示（見 main.dart）。
class DemoDataMenu extends StatelessWidget {
  const DemoDataMenu({
    super.key,
    required this.db,
    required this.body,
    required this.templates,
    required this.checks,
    required this.phases,
  });

  final AppDatabase db;
  final BodyRepository body;
  final TemplateRepository templates;
  final CheckRepository checks;
  final PhaseRepository phases;

  Future<void> _run(
    BuildContext context, {
    required String title,
    required String message,
    required String done,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('處理中…')));
    await action();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.bug_report_outlined),
      tooltip: '開發用',
      onSelected: (value) => switch (value) {
        'seed' => _run(
          context,
          title: '產生示範資料？',
          message: '會先清空所有資料（飲食、範本、階段、快取），再產生 12 週示範資料。',
          done: '已產生 12 週示範資料',
          action: () => seedDemoData(
            db: db,
            body: body,
            templates: templates,
            checks: checks,
            phases: phases,
          ),
        ),
        'clear' => _run(
          context,
          title: '清空所有資料？',
          message: '飲食紀錄、範本、打勾、階段與健康資料快取都會刪除，無法復原。',
          done: '已清空',
          action: db.clearAllData,
        ),
        _ => null,
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'seed', child: Text('產生示範資料')),
        PopupMenuItem(value: 'clear', child: Text('清空所有資料')),
      ],
    );
  }
}
