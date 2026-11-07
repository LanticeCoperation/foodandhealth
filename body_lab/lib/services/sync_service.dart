import 'package:drift/drift.dart';

import '../data/database.dart';
import 'sync_api.dart';

/// 這台裝置認領的帳號 uid。第一次登入時寫入，之後用來擋「換帳號登入」。
const kSyncOwnerUidKey = 'syncOwnerUid';

/// 上次下拉到的伺服器時間（ISO8601）。
const kSyncCursorKey = 'syncCursor';

/// 上次同步成功的本機時間（ISO8601）。只拿來顯示。
const kSyncLastOkKey = 'syncLastOk';

/// 下拉時從游標往回退的秒數。
///
/// 伺服器的 `updated_at` 取的是交易開始時間，一筆交易可能在我們讀過游標之後
/// 才 commit——完全等於游標的話就會永遠漏掉它。往回多抓一點，
/// 重複的部分用 syncId 去重，重抓無害。
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

/// 飲食紀錄的雙向同步。
///
/// 只處理 `food_entries` 一張表——它是目前唯一有伺服器 schema 與驗證過契約的
/// （見 infra/supabase/migrations/0002）。其他表之後各自再加。
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
    final edits = await (_db.selectOnly(_db.foodEntries)
          ..addColumns([_db.foodEntries.id.count()])
          ..where(_db.foodEntries.pendingSync.equals(true)))
        .getSingle();
    final deletes = await (_db.selectOnly(_db.pendingDeletes)
          ..addColumns([_db.pendingDeletes.syncId.count()]))
        .getSingle();
    return (edits.read(_db.foodEntries.id.count()) ?? 0) +
        (deletes.read(_db.pendingDeletes.syncId.count()) ?? 0);
  }

  Future<SyncResult> sync() async {
    final pushed = await _push();
    final pulled = await _pull();
    await _writeSetting(kSyncLastOkKey, DateTime.now().toIso8601String());
    return SyncResult(
      uploaded: pushed.$1,
      deleted: pushed.$2,
      pulled: pulled.$1,
      removedLocally: pulled.$2,
    );
  }

  // ---------------------------------------------------------------------
  // 上傳
  // ---------------------------------------------------------------------

  Future<(int uploaded, int deleted)> _push() async {
    final deletes = await _db.select(_db.pendingDeletes).get();
    if (deletes.isNotEmpty) {
      await _api.markDeleted([for (final d in deletes) d.syncId]);
      await (_db.delete(_db.pendingDeletes)..where(
        (r) => r.syncId.isIn([for (final d in deletes) d.syncId]),
      )).go();
    }

    final pending = await (_db.select(_db.foodEntries)
          ..where((r) => r.pendingSync.equals(true) & r.syncId.isNotNull()))
        .get();
    if (pending.isEmpty) return (0, deletes.length);

    await _api.upsertFoodEntries([for (final e in pending) _toRow(e)]);

    // 只有「送出去之後沒再被改過」的才清掉待上傳旗標。
    // 上傳期間使用者可能又改了同一筆，無條件清掉會把那次修改弄丟。
    await _db.transaction(() async {
      for (final sent in pending) {
        final current = await (_db.select(
          _db.foodEntries,
        )..where((r) => r.id.equals(sent.id))).getSingleOrNull();
        if (current == null) continue;
        if (!_sameContent(sent, current)) continue;
        await (_db.update(_db.foodEntries)..where((r) => r.id.equals(sent.id)))
            .write(const FoodEntriesCompanion(pendingSync: Value(false)));
      }
    });
    return (pending.length, deletes.length);
  }

  static bool _sameContent(FoodEntry a, FoodEntry b) =>
      a.syncId == b.syncId &&
      a.eatenAt == b.eatenAt &&
      a.meal == b.meal &&
      a.name == b.name &&
      a.servings == b.servings &&
      a.kcal == b.kcal &&
      a.proteinG == b.proteinG &&
      a.carbsG == b.carbsG &&
      a.fatG == b.fatG &&
      a.note == b.note;

  Map<String, dynamic> _toRow(FoodEntry e) => {
    'sync_id': e.syncId,
    'eaten_at': e.eatenAt.toUtc().toIso8601String(),
    'meal': e.meal.name,
    'name': e.name,
    'servings': e.servings,
    'kcal': e.kcal,
    'protein_g': e.proteinG,
    'carbs_g': e.carbsG,
    'fat_g': e.fatG,
    'note': e.note,
    'created_at': e.createdAt.toUtc().toIso8601String(),
    // 這筆在本機還在，所以明確復活伺服器上的墓碑：
    // 不送的話 merge-duplicates 會保留舊的 deleted_at，
    // 「刪除後又復原」就同步不回來。
    'deleted_at': null,
  };

  // ---------------------------------------------------------------------
  // 下拉
  // ---------------------------------------------------------------------

  Future<(int pulled, int removed)> _pull() async {
    final cursorText = await _readSetting(kSyncCursorKey);
    final cursor = cursorText == null ? null : DateTime.parse(cursorText);
    // 整輪下拉用同一個 since，靠 offset 翻頁翻到底，最後才推進游標。
    // 邊翻邊推進游標的話，updated_at 相同的列會在頁與頁之間互相擠掉。
    final since = cursor?.subtract(kCursorSlack);
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _api.fetchFoodEntries(
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

    final uid = _api.currentUserId;
    var pulled = 0;
    var removed = 0;
    DateTime? newest;

    await _db.transaction(() async {
      for (final row in rows) {
        final updatedAt = DateTime.parse(row['updated_at'] as String).toUtc();
        if (newest == null || updatedAt.isAfter(newest!)) newest = updatedAt;

        final syncId = row['sync_id'] as String;
        final local = await (_db.select(
          _db.foodEntries,
        )..where((r) => r.syncId.equals(syncId))).getSingleOrNull();

        // 本機還沒上傳的修改優先，下一輪上傳時以它為準
        if (local != null && local.pendingSync) continue;

        // 家人的資料不落地：本機資料庫只放自己的
        if (uid != null && row['user_id'] != uid) continue;

        if (row['deleted_at'] != null) {
          if (local != null) {
            await (_db.delete(
              _db.foodEntries,
            )..where((r) => r.id.equals(local.id))).go();
            removed++;
          }
          continue;
        }

        final companion = FoodEntriesCompanion(
          id: local == null ? const Value.absent() : Value(local.id),
          syncId: Value(syncId),
          eatenAt: Value(DateTime.parse(row['eaten_at'] as String).toLocal()),
          meal: Value(MealType.values.byName(row['meal'] as String)),
          name: Value(row['name'] as String),
          servings: Value((row['servings'] as num).toDouble()),
          kcal: Value((row['kcal'] as num?)?.toDouble()),
          proteinG: Value((row['protein_g'] as num?)?.toDouble()),
          carbsG: Value((row['carbs_g'] as num?)?.toDouble()),
          fatG: Value((row['fat_g'] as num?)?.toDouble()),
          note: Value(row['note'] as String?),
          createdAt: Value(
            DateTime.parse(row['created_at'] as String).toLocal(),
          ),
          // 範本還沒同步，所以拉回來的紀錄接不上本機的範本 id
          templateId: const Value(null),
          // 剛從伺服器拿回來的就是最新的，不要再排進上傳
          pendingSync: const Value(false),
        );
        if (local == null) {
          await _db.into(_db.foodEntries).insert(companion);
        } else {
          await (_db.update(
            _db.foodEntries,
          )..where((r) => r.id.equals(local.id))).write(companion);
        }
        pulled++;
      }
    });

    if (newest != null) {
      await _writeSetting(kSyncCursorKey, newest!.toIso8601String());
    }
    return (pulled, removed);
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
