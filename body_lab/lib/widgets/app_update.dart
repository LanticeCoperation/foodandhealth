import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_updater.dart';

/// 只有 Android 能直接下載 APK 覆蓋安裝；iOS 是 Sideloadly / Xcode 重簽，不提示。
bool get supportsApkUpdate => Platform.isAndroid;

/// 「有新版本」對話框；按下載會用瀏覽器下載 APK，下載完點開即可覆蓋安裝（資料保留）。
Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  InstalledVersion? current,
}) async {
  final download = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('有新版本'),
      content: Text(
        [
          '最新版：${release.label}',
          if (current != null) '目前：${current.label}',
          '',
          '下載後點開 APK 直接覆蓋安裝，紀錄會保留。',
        ].join('\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('稍後'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('下載更新'),
        ),
      ],
    ),
  );
  if (download != true) return;
  final ok = await launchUrl(
    release.apkUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('無法開啟下載連結')));
  }
}

/// 包在首頁外面：Android 正式版啟動時背景檢查 GitHub 上有沒有新版 APK，
/// 有就跳對話框；沒網路就靜靜跳過。iOS、debug 版（flutter run）完全不做事。
class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key, required this.child, this.updater});

  final Widget child;

  /// 測試可傳入假的；預設連 GitHub。
  final AppUpdater? updater;

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  @override
  void initState() {
    super.initState();
    if (supportsApkUpdate && !kDebugMode) _check();
  }

  Future<void> _check() async {
    final updater = widget.updater ?? AppUpdater();
    try {
      final release = await updater.checkForUpdate();
      if (release == null) return;
      final current = await updater.installed();
      if (!mounted) return;
      await showUpdateDialog(context, release, current: current);
    } catch (e) {
      debugPrint('[update] 檢查失敗：$e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 設定頁底部：顯示目前版本；Android 可以手動檢查更新。
class AppVersionTile extends StatefulWidget {
  const AppVersionTile({super.key, this.updater});

  /// 測試可傳入假的；預設連 GitHub。
  final AppUpdater? updater;

  @override
  State<AppVersionTile> createState() => _AppVersionTileState();
}

class _AppVersionTileState extends State<AppVersionTile> {
  late final AppUpdater _updater = widget.updater ?? AppUpdater();
  InstalledVersion? _current;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _updater.installed().then((v) {
      if (mounted) setState(() => _current = v);
    }, onError: (Object e) => debugPrint('[update] 讀不到版本：$e'));
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final release = await _updater.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        messenger.showSnackBar(const SnackBar(content: Text('已經是最新版')));
      } else {
        await showUpdateDialog(context, release, current: _current);
      }
    } catch (e) {
      debugPrint('[update] 檢查失敗：$e');
      messenger.showSnackBar(const SnackBar(content: Text('檢查更新失敗，請確認網路')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline),
      title: Text('版本 ${_current?.label ?? '—'}'),
      trailing: supportsApkUpdate
          ? TextButton(
              onPressed: _checking ? null : _check,
              child: _checking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('檢查更新'),
            )
          : null,
    );
  }
}
