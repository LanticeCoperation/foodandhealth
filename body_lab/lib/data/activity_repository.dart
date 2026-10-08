import 'package:drift/drift.dart';

import '../services/health_service.dart';
import '../utils/dates.dart';
import 'database.dart';

/// 每日活動消耗：畫面讀本地快取，[sync] 從健康資料更新。
class ActivityRepository {
  ActivityRepository(this._db, this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final ActivitySource _source;
  final DateTime Function() _clock;

  /// 快取是空的時候，第一次同步抓幾天。
  static const int initialDays = 90;

  /// 之後從快取最後一天往前重抓幾天（今天的消耗會一直增加、手錶可能晚同步）。
  static const int overlapDays = 3;

  /// [day] 的活動消耗；沒有資料時是 null。
  Stream<double?> watchDay(DateTime day) {
    final t = _db.dailyActivity;
    return (_db.select(t)..where((r) => r.day.equals(dayKey(day))))
        .watchSingleOrNull()
        .map((r) => r?.activeKcal);
  }

  /// [from] 之後每天的活動消耗，key 是當地日期 00:00。
  Future<Map<DateTime, double>> since(DateTime from) async {
    final t = _db.dailyActivity;
    final rows = await (_db.select(
      t,
    )..where((r) => r.day.isBiggerOrEqualValue(dayKey(from)))).get();
    return {for (final r in rows) parseDayKey(r.day): r.activeKcal};
  }

  /// 從健康資料同步，回傳讀到的天數。
  Future<int> sync() async {
    final today = dateOnly(_clock());
    final t = _db.dailyActivity;
    final maxDay = t.day.max();
    final row = await (_db.selectOnly(t)..addColumns([maxDay])).getSingle();
    final latest = row.read(maxDay);
    final start = latest == null
        ? addDays(today, -(initialDays - 1))
        : addDays(
            parseDayKey(latest).isAfter(today) ? today : parseDayKey(latest),
            -overlapDays,
          );

    final data = await _source.fetchDailyActiveEnergy(start);
    await replaceFrom(start, data);
    return data.length;
  }

  /// 以 [data] 取代 [start] 之後的快取。[data] 是空的時候不動快取
  /// （iOS 被拒絕讀取時只會拿到空資料，和沒戴手錶分不出來）。
  Future<void> replaceFrom(DateTime start, Map<DateTime, double> data) async {
    if (data.isEmpty) return;
    final t = _db.dailyActivity;
    final syncedAt = _clock();
    await _db.transaction(() async {
      await (_db.delete(
        t,
      )..where((r) => r.day.isBiggerOrEqualValue(dayKey(start)))).go();
      await _db.batch((b) {
        b.insertAllOnConflictUpdate(t, [
          for (final MapEntry(key: day, value: kcal) in data.entries)
            DailyActivityCompanion.insert(
              day: dayKey(day),
              activeKcal: kcal,
              syncedAt: syncedAt,
            ),
        ]);
      });
    });
  }
}
