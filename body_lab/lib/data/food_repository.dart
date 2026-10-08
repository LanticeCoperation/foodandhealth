import 'package:drift/drift.dart';

import '../utils/dates.dart';
import 'database.dart';

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
  Future<Map<DateTime, DayTotals>> dailyTotalsSince(DateTime from) async {
    final t = _db.foodEntries;
    final rows = await (_db.select(
      t,
    )..where((r) => r.eatenAt.isBiggerOrEqualValue(dateOnly(from)))).get();
    final byDay = <DateTime, List<FoodEntry>>{};
    for (final e in rows) {
      byDay.putIfAbsent(dateOnly(e.eatenAt), () => []).add(e);
    }
    return byDay.map((day, entries) => MapEntry(day, DayTotals.of(entries)));
  }

  Future<int> add(FoodEntriesCompanion entry) =>
      _db.into(_db.foodEntries).insert(entry);

  /// 以 id 覆蓋整筆（[entry] 需含 id 與所有欄位）。
  Future<void> save(Insertable<FoodEntry> entry) =>
      _db.update(_db.foodEntries).replace(entry);

  Future<void> delete(int id) =>
      (_db.delete(_db.foodEntries)..where((r) => r.id.equals(id))).go();

  /// 復原刪除：用原本的 id 放回去。
  Future<void> restore(FoodEntry entry) =>
      _db.into(_db.foodEntries).insert(entry);
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
