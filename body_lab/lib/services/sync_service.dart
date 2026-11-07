import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/sync_entities.dart';
import 'sync_api.dart';
import 'sync_tables.dart';

/// 這台裝置認領的帳號 uid。第一次登入時寫入，之後用來擋「換帳號登入」。
const kSyncOwnerUidKey = 'syncOwnerUid';

/// 上次同步成功的本機時間（ISO8601）。只拿來顯示。
const kSyncLastOkKey = 'syncLastOk';

/// 下拉時從游標往回退的秒數。
///
/// 伺服器的 `updated_at` 取的是交易開始時間，一筆交易可能在我們讀過游標之後
/// 才 commit——完全等於游標的話就會永遠漏掉它。往回多抓一點，
/// 重複的部分靠 upsert 的冪等性吸收，重抓無害。
const Duration kCursorSlack = Duration(seconds: 5);

/// 下拉一次抓幾列。
///
/// 伺服器的 `PGRST_DB_MAX_ROWS` 預設是 1000，不分頁的話第一次同步會被截斷，
/// 而被截掉的列 updated_at 早於新游標，之後再也不會被抓回來——悄悄少資料。
const int kPageSize = 500;

/// 本機資料已經屬於另一個帳號。
class WrongOwnerException implements Exception {
  WrongOwnerException(this.existingUid, this.incomingUid);
  final String existingUid;
  final String incomingUid;

  @override
  String toString() =>
      '這台裝置的資料屬於另一個帳號，不能用現在這個帳號同步。'
      '要換帳號請先匯出備份，再清除資料重來。';
}

class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.deleted,
    required this.pulled,
    required this.removedLocally,
  });

  final int uploaded;
  final int deleted;
  final int pulled;
  final int removedLocally;

  bool get idle =>
      uploaded == 0 && deleted == 0 && pulled == 0 && removedLocally == 0;

  @override
  String toString() =>
      '上傳 $uploaded 筆、刪除 $deleted 筆、下載 $pulled 筆、本機移除 $removedLocally 筆';
}

/// 跨裝置同步。
///
/// 每張表的規則寫在 [syncTables]；健康資料快取只上傳，見 [_pushHealthCaches]。
class SyncService {
  SyncService(this._db, this._api);

  final AppDatabase _db;
  final SyncApi _api;

  /// 第一次登入時認領這台的既有資料。
  ///
  /// 單機時期累積的紀錄沒有歸屬，登入後整批算成這個帳號的。
  /// 如果這台已經認領過別的帳號就擋下來——不擋的話，
  /// 用錯帳號登入一次，整份歷史紀錄就被接收走了。
  Future<void> claimForCurrentUser() async {
    final uid = _api.currentUserId;
    if (uid == null) throw StateError('尚未登入');
    final existing = await _readSetting(kSyncOwnerUidKey);
    if (existing != null && existing != uid) {
      throw WrongOwnerException(existing, uid);
    }
    if (existing == null) await _writeSetting(kSyncOwnerUidKey, uid);
  }

  /// 這台認領過的帳號 uid；還沒登入過是 null。
  Future<String?> ownerUid() => _readSetting(kSyncOwnerUidKey);

  /// 上次同步成功的時間（本機時鐘，只拿來顯示）。
  Future<DateTime?> lastSyncedAt() async {
    final v = await _readSetting(kSyncLastOkKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// 還有多少本機變更在等著上傳。離家時看這個就知道累積了多少。
  Future<int> pendingCount() async {
    var total = 0;
    for (final table in syncTables) {
      total += await table.pendingCount(_db);
    }
    total += (await _db.select(_db.pendingDeletes).get()).length;
    return total;
  }

  Future<SyncResult> sync() async {
    var uploaded = 0;
    var deleted = 0;
    var pulled = 0;
    var removed = 0;

    for (final table in syncTables) {
      final r = await _pushTable(table);
      uploaded += r.$1;
      deleted += r.$2;
    }
    uploaded += await _pushHealthCaches();
    for (final table in syncTables) {
      if (!table.pullable) continue;
      final r = await _pullTable(table);
      pulled += r.$1;
      removed += r.$2;
    }

    await _writeSetting(kSyncLastOkKey, DateTime.now().toIso8601String());
    return SyncResult(
      uploaded: uploaded,
      deleted: deleted,
      pulled: pulled,
      removedLocally: removed,
    );
  }

  // ---------------------------------------------------------------------
  // 上傳
  // ---------------------------------------------------------------------

  Future<(int uploaded, int deleted)> _pushTable(SyncTable table) async {
    var deleted = 0;
    if (table.entity.isNotEmpty) {
      final pending = await (_db.select(
        _db.pendingDeletes,
      )..where((r) => r.entity.equals(table.entity))).get();
      if (pending.isNotEmpty) {
        await _api.markDeleted(table.remote, [
          for (final d in pending) _deleteKey(table, d.syncId),
        ]);
        await (_db.delete(_db.pendingDeletes)..where(
              (r) =>
                  r.entity.equals(table.entity) &
                  r.syncId.isIn([for (final d in pending) d.syncId]),
            ))
            .go();
        deleted = pending.length;
      }
    }

    final rows = await table.pendingRows(_db);
    if (rows.isEmpty) return (0, deleted);
    await _api.upsert(table.remote, table.onConflict, rows);

    // 只有「送出去之後沒再被改過」的才清掉待上傳旗標。
    // 每張表的 clearPending 都帶內容條件比對，上傳期間使用者又改了同一筆時
    // 條件就對不上，旗標留著，下一輪再送。
    await _db.transaction(() => table.clearPending(_db, rows));
    return (rows.length, deleted);
  }

  /// 待辦表裡的鍵換成伺服器的等值條件。
  Map<String, String> _deleteKey(SyncTable table, String key) {
    if (table.entity == kEntityDailyChecks) {
      final parts = key.split('|');
      return {'day': parts.first, 'item': parts.last};
    }
    return {'sync_id': key};
  }

  /// 健康資料快取：只上傳，用 syncedAt 當游標判斷哪些是新的。
  Future<int> _pushHealthCaches() async {
    var count = 0;

    final bmCursor = await _readSetting(kBodyMetricsPushCursor);
    final bmSince = bmCursor == null ? null : DateTime.parse(bmCursor);
    final metrics = await (_db.select(_db.dailyBodyMetrics)..where(
          (r) => bmSince == null
              ? const Constant(true)
              : r.syncedAt.isBiggerThanValue(bmSince),
        ))
        .get();
    if (metrics.isNotEmpty) {
      await _api.upsert('body_metrics', 'user_id,day', [
        for (final m in metrics)
          {
            'day': m.day,
            'measured_at': m.measuredAt.toUtc().toIso8601String(),
            'weight_kg': m.weightKg,
            'body_fat_percent': m.bodyFatPercent,
            'lean_mass_kg': m.leanMassKg,
            'lean_mass_estimated': m.leanMassEstimated,
            'deleted_at': null,
          },
      ]);
      final newest = metrics
          .map((m) => m.syncedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _writeSetting(kBodyMetricsPushCursor, newest.toIso8601String());
      count += metrics.length;
    }

    final daCursor = await _readSetting(kDailyActivityPushCursor);
    final daSince = daCursor == null ? null : DateTime.parse(daCursor);
    final activity = await (_db.select(_db.dailyActivity)..where(
          (r) => daSince == null
              ? const Constant(true)
              : r.syncedAt.isBiggerThanValue(daSince),
        ))
        .get();
    if (activity.isNotEmpty) {
      await _api.upsert('daily_activity', 'user_id,day', [
        for (final a in activity)
          {'day': a.day, 'active_kcal': a.activeKcal, 'deleted_at': null},
      ]);
      final newest = activity
          .map((a) => a.syncedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _writeSetting(kDailyActivityPushCursor, newest.toIso8601String());
      count += activity.length;
    }
    return count;
  }

  // ---------------------------------------------------------------------
  // 下拉
  // ---------------------------------------------------------------------

  Future<(int pulled, int removed)> _pullTable(SyncTable table) async {
    final key = 'syncCursor_${table.remote}';
    final cursorText = await _readSetting(key);
    final cursor = cursorText == null ? null : DateTime.parse(cursorText);

    // 整輪下拉用同一個 since，靠 offset 翻頁翻到底，最後才推進游標。
    // 邊翻邊推進游標的話，updated_at 相同的列會在頁與頁之間互相擠掉。
    final since = cursor?.subtract(kCursorSlack);
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _api.fetch(
        table.remote,
        since: since,
        offset: offset,
        limit: kPageSize,
      );
      // 收到的列數可能少於要求的 limit——伺服器的 PGRST_DB_MAX_ROWS 壓在
      // 我們的 limit 之上。所以「比 limit 短」不代表沒了，要收到空頁才算完，
      // 而且 offset 要照實際收到的筆數推進。
      if (page.isEmpty) break;
      rows.addAll(page);
      offset += page.length;
    }
    if (rows.isEmpty) return (0, 0);

    DateTime? newest;
    for (final row in rows) {
      final updatedAt = DateTime.parse(row['updated_at'] as String).toUtc();
      if (newest == null || updatedAt.isAfter(newest)) newest = updatedAt;
    }

    final result = await _db.transaction(
      () => table.applyPulled!(_db, rows),
    );
    if (newest != null) {
      await _writeSetting(key, newest.toIso8601String());
    }
    return result;
  }

  // ---------------------------------------------------------------------

  Future<String?> _readSetting(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    final v = row?.value.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> _writeSetting(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
