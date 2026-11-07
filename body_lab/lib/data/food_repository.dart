import 'package:drift/drift.dart';

import '../utils/dates.dart';
import 'database.dart';
import 'sync_entities.dart';

class FoodRepository {
  FoodRepository(this._db);

  final AppDatabase _db;

  /// 某一天（當地時間 00:00 到隔天 00:00）的飲食紀錄，依時間排序。
  Stream<List<FoodEntry>> watchDay(DateTime day) {
    final start = dateOnly(day);
    final end = addDays(start, 1);
    final t = _db.foodEntries;
    final query = _db.select(t)
      ..where(
        (r) =>
            r.eatenAt.isBiggerOrEqualValue(start) &
            r.eatenAt.isSmallerThanValue(end),
      )
      ..orderBy([
        (r) => OrderingTerm.asc(r.eatenAt),
        (r) => OrderingTerm.asc(r.id),
      ]);
    return query.watch();
  }

  /// [from] 之後每天的攝取總量；沒有紀錄的天不會出現。key 是當地日期 00:00。
  Future<Map<DateTime, DayTotals>> dailyTotalsSince(DateTime from) async =>
      _byDay(await _sinceQuery(from).get());

  /// 同 [dailyTotalsSince]，飲食紀錄有變動時會重新發出。
  Stream<Map<DateTime, DayTotals>> watchDailyTotalsSince(DateTime from) =>
      _sinceQuery(from).watch().map(_byDay);

  SimpleSelectStatement<$FoodEntriesTable, FoodEntry> _sinceQuery(
    DateTime from,
  ) =>
      _db.select(_db.foodEntries)
        ..where((r) => r.eatenAt.isBiggerOrEqualValue(dateOnly(from)));

  static Map<DateTime, DayTotals> _byDay(List<FoodEntry> rows) {
    final byDay = <DateTime, List<FoodEntry>>{};
    for (final e in rows) {
      byDay.putIfAbsent(dateOnly(e.eatenAt), () => []).add(e);
    }
    return byDay.map((day, entries) => MapEntry(day, DayTotals.of(entries)));
  }

  /// syncId 由 [FoodEntries.syncId] 的 clientDefault 自動帶入，呼叫端不用管。
  Future<int> add(FoodEntriesCompanion entry) =>
      _db.into(_db.foodEntries).insert(entry);

  /// 以 id 覆蓋整筆（[entry] 需含 id 與所有欄位）。
  ///
  /// 一定要重新標成待上傳：呼叫端通常是拿既有的列改幾個欄位再存回來，
  /// 那筆的 pendingSync 可能是上次同步完留下的 false。
  Future<void> save(Insertable<FoodEntry> entry) async {
    await _db.update(_db.foodEntries).replace(entry);
    final row = entry.toColumns(false);
    final id = row['id'];
    if (id is Variable) {
      await (_db.update(_db.foodEntries)
            ..where((r) => r.id.equals(id.value as int)))
          .write(const FoodEntriesCompanion(pendingSync: Value(true)));
    }
  }

  /// 本機硬刪除，另外在待辦表記下 syncId，之後通知伺服器。
  ///
  /// 本機不做軟刪除：那會讓每一個讀飲食紀錄的查詢都得記得濾掉墓碑。
  Future<void> delete(int id) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.foodEntries,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      final syncId = row?.syncId;
      if (syncId != null) {
        await _db
            .into(_db.pendingDeletes)
            .insertOnConflictUpdate(
              PendingDeletesCompanion.insert(
                entity: const Value(kEntityFoodEntries),
                syncId: syncId,
              ),
            );
      }
      await (_db.delete(_db.foodEntries)..where((r) => r.id.equals(id))).go();
    });
  }

  /// 復原刪除：用原本的 id 放回去，並取消那筆刪除待辦。
  ///
  /// 一定要標成待上傳：如果刪除已經送出去了，伺服器上有墓碑，
  /// 不重新上傳的話另一台會一直看到「已刪除」。
  Future<void> restore(FoodEntry entry) async {
    await _db.transaction(() async {
      await _db
          .into(_db.foodEntries)
          .insert(entry.copyWith(pendingSync: true));
      final syncId = entry.syncId;
      if (syncId != null) {
        await (_db.delete(_db.pendingDeletes)..where(
              (r) =>
                  r.entity.equals(kEntityFoodEntries) &
                  r.syncId.equals(syncId),
            ))
            .go();
      }
    });
  }
}

/// 一天的攝取總量；沒填的營養素當 0 計算，[missingKcal] 記錄有幾筆沒填熱量。
class DayTotals {
  const DayTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.missingKcal,
  });

  factory DayTotals.of(Iterable<FoodEntry> entries) {
    double sum(double? Function(FoodEntry) f) =>
        entries.fold(0, (acc, e) => acc + (f(e) ?? 0));
    return DayTotals(
      kcal: sum((e) => e.totalKcal),
      proteinG: sum((e) => e.totalProteinG),
      carbsG: sum((e) => e.totalCarbsG),
      fatG: sum((e) => e.totalFatG),
      missingKcal: entries.where((e) => e.kcal == null).length,
    );
  }

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final int missingKcal;
}
