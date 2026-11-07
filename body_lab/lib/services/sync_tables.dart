import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/sync_entities.dart';

/// 一張表要怎麼同步。
///
/// 三種規則（見 infra/supabase/migrations/0003 的說明）：
///
/// - 自動編號的表（飲食、階段、自訂消耗）：裝置產的 `sync_id` 當鍵
/// - 自然鍵的表（打勾、身體基本資料）：伺服器端以 (user_id, …) 為鍵
/// - 健康資料快取（體重、活動消耗）：**只上傳**。正本在 Apple 健康，
///   下拉回本機會被下一次健康資料整理覆蓋
class SyncTable {
  const SyncTable({
    required this.remote,
    required this.onConflict,
    required this.entity,
    required this.pendingRows,
    required this.clearPending,
    required this.pendingCount,
    this.applyPulled,
  });

  /// 伺服器上的表名。
  final String remote;

  /// upsert 的衝突鍵。
  final String onConflict;

  /// [PendingDeletes.entity] 用的值；只上傳的表沒有刪除待辦，給空字串。
  final String entity;

  /// 待上傳的列，已經轉成伺服器要的形狀。
  final Future<List<Map<String, dynamic>>> Function(AppDatabase db) pendingRows;

  /// 上傳成功後清掉旗標。傳入的是剛剛送出去的那批。
  final Future<void> Function(AppDatabase db, List<Map<String, dynamic>> sent)
  clearPending;

  /// 還有幾筆在等著上傳。
  final Future<int> Function(AppDatabase db) pendingCount;

  /// 把伺服器拉回來的列寫進本機；null 表示這張表只上傳。
  final Future<(int applied, int removed)> Function(
    AppDatabase db,
    List<Map<String, dynamic>> rows,
  )?
  applyPulled;

  bool get pullable => applyPulled != null;
}

String _iso(DateTime t) => t.toUtc().toIso8601String();

/// 送出去的那一份和現在本機的內容是否完全一樣。
///
/// 只有一樣才清掉待上傳旗標——上傳期間使用者可能又改了同一筆，
/// 無條件清掉會把那次修改弄丟。比對一定要涵蓋所有會變的欄位，
/// 只比鍵和少數欄位照樣會漏。
bool _sameRow(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}
DateTime _local(Object? v) => DateTime.parse(v! as String).toLocal();
double? _num(Object? v) => (v as num?)?.toDouble();

// ---------------------------------------------------------------------------
// 飲食紀錄
// ---------------------------------------------------------------------------

Map<String, dynamic> _foodRow(FoodEntry e) => {
  'sync_id': e.syncId,
  'eaten_at': _iso(e.eatenAt),
  'meal': e.meal.name,
  'name': e.name,
  'servings': e.servings,
  'kcal': e.kcal,
  'protein_g': e.proteinG,
  'carbs_g': e.carbsG,
  'fat_g': e.fatG,
  'note': e.note,
  'created_at': _iso(e.createdAt),
  // 這筆在本機還在，明確復活伺服器上的墓碑
  'deleted_at': null,
};

final foodEntriesTable = SyncTable(
  remote: 'food_entries',
  onConflict: 'sync_id',
  entity: kEntityFoodEntries,
  pendingRows: (db) async {
    final rows = await (db.select(db.foodEntries)
          ..where((r) => r.pendingSync.equals(true) & r.syncId.isNotNull()))
        .get();
    return [for (final e in rows) _foodRow(e)];
  },
  clearPending: (db, sent) async {
    for (final row in sent) {
      final local =
          await (db.select(db.foodEntries)
                ..where((r) => r.syncId.equals(row['sync_id'] as String)))
              .getSingleOrNull();
      if (local == null || !_sameRow(_foodRow(local), row)) continue;
      await (db.update(db.foodEntries)..where((r) => r.id.equals(local.id)))
          .write(const FoodEntriesCompanion(pendingSync: Value(false)));
    }
  },
  pendingCount: (db) async =>
      (await (db.select(
        db.foodEntries,
      )..where((r) => r.pendingSync.equals(true))).get()).length,
  applyPulled: (db, rows) async {
    var applied = 0;
    var removed = 0;
    for (final row in rows) {
      final syncId = row['sync_id'] as String;
      final local = await (db.select(
        db.foodEntries,
      )..where((r) => r.syncId.equals(syncId))).getSingleOrNull();
      if (local != null && local.pendingSync) continue;
      if (row['deleted_at'] != null) {
        if (local != null) {
          await (db.delete(
            db.foodEntries,
          )..where((r) => r.id.equals(local.id))).go();
          removed++;
        }
        continue;
      }
      final companion = FoodEntriesCompanion(
        id: local == null ? const Value.absent() : Value(local.id),
        syncId: Value(syncId),
        eatenAt: Value(_local(row['eaten_at'])),
        meal: Value(MealType.values.byName(row['meal'] as String)),
        name: Value(row['name'] as String),
        servings: Value(_num(row['servings']) ?? 1),
        kcal: Value(_num(row['kcal'])),
        proteinG: Value(_num(row['protein_g'])),
        carbsG: Value(_num(row['carbs_g'])),
        fatG: Value(_num(row['fat_g'])),
        note: Value(row['note'] as String?),
        createdAt: Value(_local(row['created_at'])),
        // 範本還沒同步，拉回來的紀錄接不上本機的範本 id
        templateId: const Value(null),
        pendingSync: const Value(false),
      );
      if (local == null) {
        await db.into(db.foodEntries).insert(companion);
      } else {
        await (db.update(
          db.foodEntries,
        )..where((r) => r.id.equals(local.id))).write(companion);
      }
      applied++;
    }
    return (applied, removed);
  },
);

// ---------------------------------------------------------------------------
// 實驗階段
// ---------------------------------------------------------------------------

Map<String, dynamic> _phaseRow(Phase p) => {
  'sync_id': p.syncId,
  'name': p.name,
  'start_day': p.startDay,
  'end_day': p.endDay,
  'hypothesis': p.hypothesis,
  'target_kcal': p.targetKcal,
  'target_protein_g': p.targetProteinG,
  'creatine': p.creatine,
  'conclusion': p.conclusion,
  'created_at': _iso(p.createdAt),
  'deleted_at': null,
};

final phasesTable = SyncTable(
  remote: 'phases',
  onConflict: 'sync_id',
  entity: kEntityPhases,
  pendingRows: (db) async {
    final rows = await (db.select(db.phases)
          ..where((r) => r.pendingSync.equals(true) & r.syncId.isNotNull()))
        .get();
    return [for (final p in rows) _phaseRow(p)];
  },
  clearPending: (db, sent) async {
    for (final row in sent) {
      final local =
          await (db.select(db.phases)
                ..where((r) => r.syncId.equals(row['sync_id'] as String)))
              .getSingleOrNull();
      if (local == null || !_sameRow(_phaseRow(local), row)) continue;
      await (db.update(db.phases)..where((r) => r.id.equals(local.id)))
          .write(const PhasesCompanion(pendingSync: Value(false)));
    }
  },
  pendingCount: (db) async =>
      (await (db.select(
        db.phases,
      )..where((r) => r.pendingSync.equals(true))).get()).length,
  applyPulled: (db, rows) async {
    var applied = 0;
    var removed = 0;
    for (final row in rows) {
      final syncId = row['sync_id'] as String;
      final local = await (db.select(
        db.phases,
      )..where((r) => r.syncId.equals(syncId))).getSingleOrNull();
      if (local != null && local.pendingSync) continue;
      if (row['deleted_at'] != null) {
        if (local != null) {
          await (db.delete(
            db.phases,
          )..where((r) => r.id.equals(local.id))).go();
          removed++;
        }
        continue;
      }
      final companion = PhasesCompanion(
        id: local == null ? const Value.absent() : Value(local.id),
        syncId: Value(syncId),
        name: Value(row['name'] as String),
        startDay: Value(row['start_day'] as String),
        endDay: Value(row['end_day'] as String),
        hypothesis: Value(row['hypothesis'] as String?),
        targetKcal: Value(_num(row['target_kcal'])),
        targetProteinG: Value(_num(row['target_protein_g'])),
        creatine: Value(row['creatine'] as bool? ?? false),
        conclusion: Value(row['conclusion'] as String?),
        createdAt: Value(_local(row['created_at'])),
        pendingSync: const Value(false),
      );
      if (local == null) {
        await db.into(db.phases).insert(companion);
      } else {
        await (db.update(
          db.phases,
        )..where((r) => r.id.equals(local.id))).write(companion);
      }
      applied++;
    }
    return (applied, removed);
  },
);

// ---------------------------------------------------------------------------
// 自訂消耗
// ---------------------------------------------------------------------------

Map<String, dynamic> _burnRow(ExtraBurn e) => {
  'sync_id': e.syncId,
  'day': e.day,
  'kcal': e.kcal,
  'note': e.note,
  'created_at': _iso(e.createdAt),
  'deleted_at': null,
};

final extraBurnsTable = SyncTable(
  remote: 'extra_burns',
  onConflict: 'sync_id',
  entity: kEntityExtraBurns,
  pendingRows: (db) async {
    final rows = await (db.select(db.extraBurns)
          ..where((r) => r.pendingSync.equals(true) & r.syncId.isNotNull()))
        .get();
    return [for (final e in rows) _burnRow(e)];
  },
  clearPending: (db, sent) async {
    for (final row in sent) {
      final local =
          await (db.select(db.extraBurns)
                ..where((r) => r.syncId.equals(row['sync_id'] as String)))
              .getSingleOrNull();
      if (local == null || !_sameRow(_burnRow(local), row)) continue;
      await (db.update(db.extraBurns)..where((r) => r.id.equals(local.id)))
          .write(const ExtraBurnsCompanion(pendingSync: Value(false)));
    }
  },
  pendingCount: (db) async =>
      (await (db.select(
        db.extraBurns,
      )..where((r) => r.pendingSync.equals(true))).get()).length,
  applyPulled: (db, rows) async {
    var applied = 0;
    var removed = 0;
    for (final row in rows) {
      final syncId = row['sync_id'] as String;
      final local = await (db.select(
        db.extraBurns,
      )..where((r) => r.syncId.equals(syncId))).getSingleOrNull();
      if (local != null && local.pendingSync) continue;
      if (row['deleted_at'] != null) {
        if (local != null) {
          await (db.delete(
            db.extraBurns,
          )..where((r) => r.id.equals(local.id))).go();
          removed++;
        }
        continue;
      }
      final companion = ExtraBurnsCompanion(
        id: local == null ? const Value.absent() : Value(local.id),
        syncId: Value(syncId),
        day: Value(row['day'] as String),
        kcal: Value(_num(row['kcal']) ?? 0),
        note: Value(row['note'] as String?),
        createdAt: Value(_local(row['created_at'])),
        pendingSync: const Value(false),
      );
      if (local == null) {
        await db.into(db.extraBurns).insert(companion);
      } else {
        await (db.update(
          db.extraBurns,
        )..where((r) => r.id.equals(local.id))).write(companion);
      }
      applied++;
    }
    return (applied, removed);
  },
);

// ---------------------------------------------------------------------------
// 每日打勾（自然鍵）
// ---------------------------------------------------------------------------

Map<String, dynamic> _checkRow(DailyCheck c) => {
  'day': c.day,
  'item': c.item.name,
  'checked_at': _iso(c.checkedAt),
  'amount': c.amount,
  'deleted_at': null,
};

final dailyChecksTable = SyncTable(
  remote: 'daily_checks',
  onConflict: 'user_id,day,item',
  entity: kEntityDailyChecks,
  pendingRows: (db) async {
    final rows = await (db.select(
      db.dailyChecks,
    )..where((r) => r.pendingSync.equals(true))).get();
    return [for (final c in rows) _checkRow(c)];
  },
  clearPending: (db, sent) async {
    for (final row in sent) {
      final item = CheckItem.values.byName(row['item'] as String);
      final day = row['day'] as String;
      final local =
          await (db.select(db.dailyChecks)
                ..where((r) => r.day.equals(day) & r.item.equalsValue(item)))
              .getSingleOrNull();
      if (local == null || !_sameRow(_checkRow(local), row)) continue;
      await (db.update(db.dailyChecks)
            ..where((r) => r.day.equals(day) & r.item.equalsValue(item)))
          .write(const DailyChecksCompanion(pendingSync: Value(false)));
    }
  },
  pendingCount: (db) async =>
      (await (db.select(
        db.dailyChecks,
      )..where((r) => r.pendingSync.equals(true))).get()).length,
  applyPulled: (db, rows) async {
    var applied = 0;
    var removed = 0;
    for (final row in rows) {
      final day = row['day'] as String;
      final item = CheckItem.values.byName(row['item'] as String);
      final local = await (db.select(db.dailyChecks)
            ..where((r) => r.day.equals(day) & r.item.equalsValue(item)))
          .getSingleOrNull();
      if (local != null && local.pendingSync) continue;
      if (row['deleted_at'] != null) {
        if (local != null) {
          await (db.delete(db.dailyChecks)
                ..where((r) => r.day.equals(day) & r.item.equalsValue(item)))
              .go();
          removed++;
        }
        continue;
      }
      await db
          .into(db.dailyChecks)
          .insertOnConflictUpdate(
            DailyChecksCompanion.insert(
              day: day,
              item: item,
              checkedAt: _local(row['checked_at']),
              amount: Value(_num(row['amount'])),
              pendingSync: const Value(false),
            ),
          );
      applied++;
    }
    return (applied, removed);
  },
);

// ---------------------------------------------------------------------------
// 身體基本資料（一個人一列）
// ---------------------------------------------------------------------------

Map<String, dynamic> _profileRow(Profile p) => {
  'sex': p.sex.name,
  'birth_year': p.birthYear,
  'height_cm': p.heightCm,
  'activity': p.activity.name,
  'weight_kg': p.weightKg,
  'tdee_kcal': p.tdeeKcal,
  'energy_mode': p.energyMode.name,
};

final bodyProfileTable = SyncTable(
  remote: 'body_profiles',
  onConflict: 'user_id',
  entity: '',
  pendingRows: (db) async {
    final p = await (db.select(
      db.profiles,
    )..where((r) => r.pendingSync.equals(true))).getSingleOrNull();
    if (p == null) return const [];
    return [_profileRow(p)];
  },
  clearPending: (db, sent) async {
    if (sent.isEmpty) return;
    final local = await db.select(db.profiles).getSingleOrNull();
    if (local == null || !_sameRow(_profileRow(local), sent.single)) return;
    await db
        .update(db.profiles)
        .write(const ProfilesCompanion(pendingSync: Value(false)));
  },
  pendingCount: (db) async =>
      (await (db.select(
        db.profiles,
      )..where((r) => r.pendingSync.equals(true))).get()).length,
  applyPulled: (db, rows) async {
    if (rows.isEmpty) return (0, 0);
    final row = rows.last;
    final local = await db.select(db.profiles).getSingleOrNull();
    if (local != null && local.pendingSync) return (0, 0);
    await db
        .into(db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: const Value(1),
            sex: Sex.values.byName(row['sex'] as String),
            birthYear: row['birth_year'] as int,
            heightCm: _num(row['height_cm'])!,
            activity: ActivityLevel.values.byName(row['activity'] as String),
            weightKg: _num(row['weight_kg'])!,
            tdeeKcal: _num(row['tdee_kcal'])!,
            energyMode: Value(
              EnergyMode.values.byName(row['energy_mode'] as String),
            ),
            updatedAt: _local(row['updated_at']),
            pendingSync: const Value(false),
          ),
        );
    return (1, 0);
  },
);

/// 兩張健康資料快取只上傳。正本在 Apple 健康 / Health Connect，
/// 下拉回本機的列會被下一次健康資料整理覆蓋，而且 `fromThisApp` 可能
/// 跟著跑到沒寫過它的裝置上，那台就會以為自己刪得掉 Apple 健康裡的紀錄。
/// 放到伺服器上只為了家人看得到。
///
/// 沒有 pendingSync 欄位，改用 Settings 裡的 syncedAt 游標判斷哪些要送。
const kBodyMetricsPushCursor = 'syncPushedBodyMetrics';
const kDailyActivityPushCursor = 'syncPushedDailyActivity';

/// 雙向同步的表，順序就是同步的順序。
final syncTables = <SyncTable>[
  foodEntriesTable,
  phasesTable,
  extraBurnsTable,
  dailyChecksTable,
  bodyProfileTable,
];
