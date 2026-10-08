import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../utils/dates.dart';

/// 資料備份：匯出到 iCloud Drive（分享選單 → 儲存到檔案）、從檔案匯入。
class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.backup});

  final BackupService backup;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  static const _jsonType = XTypeGroup(
    label: 'Body Lab 備份',
    extensions: ['json'],
    mimeTypes: ['application/json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = await widget.backup.exportJson();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/body_lab_backup_${dayKey(DateTime.now())}.json',
      );
      await file.writeAsString(json);
      if (!mounted) return;

      // iPad 的分享選單需要錨點位置
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Body Lab 備份',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (result.status == ShareResultStatus.success) _toast('已匯出備份');
    } catch (e) {
      _toast('匯出失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [_jsonType]);
    if (file == null || !mounted) return;

    final Map<String, dynamic> json;
    final BackupCounts counts;
    try {
      json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      counts = widget.backup.inspect(json);
    } catch (e) {
      _toast(e is BackupFormatException ? e.message : '無法讀取這個檔案');
      return;
    }
    if (!mounted) return;

    final exportedAt = DateTime.tryParse('${json['exportedAt']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用這份備份取代目前的資料？'),
        content: Text(
          '${exportedAt == null ? '' : '備份時間：${exportedAt.year}/${exportedAt.month}/${exportedAt.day} '
                    '${exportedAt.hour.toString().padLeft(2, '0')}:${exportedAt.minute.toString().padLeft(2, '0')}\n'}'
          '內容：$counts\n\n'
          '目前的飲食紀錄、一鍵項目、打勾、階段、個人資料與自訂消耗都會被取代。'
          '身體組成與活動消耗不受影響（會從 Apple 健康重新同步）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取代'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final restored = await widget.backup.restore(json);
      _toast('已還原：$restored');
    } catch (e) {
      _toast('還原失敗，資料沒有變更：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('資料備份', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'iPhone 開著 iCloud 備份時，App 資料會一起備份，換新手機從 iCloud 還原就會回來；'
              '但刪掉 App 重裝不會。建議定期匯出到 iCloud Drive：'
              '按「匯出」→ 儲存到檔案 → iCloud Drive。',
              style: muted,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('匯出'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('從檔案匯入'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('備份內容：飲食紀錄、一鍵項目、肌酸打勾、實驗階段、個人資料、自訂消耗。', style: muted),
          ],
        ),
      ),
    );
  }
}
