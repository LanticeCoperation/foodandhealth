import 'dart:async';

import 'package:drift/drift.dart';

import '../models/body_metric.dart';
import '../services/health_service.dart';
import '../utils/dates.dart';
import 'database.dart';

/// 身體組成：畫面讀本地快取，[sync] 再從健康資料更新快取。
class BodyRepository {
  BodyRepository(this._db, this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BodyMetricsSource _source;
  final DateTime Function() _clock;

  /// 快取是空的時候，第一次同步抓幾天。
  static const int initialDays = 90;

  /// 之後每次同步，從快取最後一天再往前重抓幾天（體脂計晚寫入、使用者刪改資料）。
  static const int overlapDays = 14;

  Stream<List<BodyMetric>> watchSince(DateTime from) =>
      _sinceQuery(from).watch().map((rows) => rows.map(_toMetric).toList());

  Future<List<BodyMetric>> since(DateTime from) async =>
      (await _sinceQuery(from).get()).map(_toMetric).toList();

  SimpleSelectStatement<$DailyBodyMetricsTable, DailyBodyMetricRow> _sinceQuery(
    DateTime from,
  ) {
    final t = _db.dailyBodyMetrics;
    return _db.select(t)
      ..where((r) => r.day.isBiggerOrEqualValue(dayKey(from)))
      ..orderBy([(r) => OrderingTerm.asc(r.day)]);
  }

  /// 從健康資料同步到快取，回傳讀到的天數。
  Future<int> sync() async {
    final today = dateOnly(_clock());
    final latest = await _latestCachedDay();
    final start = latest == null
        ? addDays(today, -(initialDays - 1))
        : addDays(latest.isAfter(today) ? today : latest, -overlapDays);

    final metrics = await _source.fetchDailyMetrics(start);
    await replaceFrom(start, metrics);
    return metrics.length;
  }

  /// 以 [metrics] 取代 [start] 之後的快取，健康 App 裡刪掉的天也會一起消失。
  ///
  /// [metrics] 是空的時候不動快取：iOS 被拒絕讀取時 HealthKit 只會回傳空資料，
  /// 和「真的沒資料」分不出來，寧可保留舊快取。
  Future<void> replaceFrom(DateTime start, List<BodyMetric> metrics) async {
    if (metrics.isEmpty) return;
    final t = _db.dailyBodyMetrics;
    final syncedAt = _clock();

    await _db.transaction(() async {
      await (_db.delete(
        t,
      )..where((r) => r.day.isBiggerOrEqualValue(dayKey(start)))).go();
      await _db.batch((b) {
        b.insertAllOnConflictUpdate(t, [
          for (final m in metrics)
            DailyBodyMetricsCompanion.insert(
              day: dayKey(m.date),
              measuredAt: m.measuredAt,
              weightKg: m.weightKg,
              bodyFatPercent: Value(m.bodyFatPercent),
              leanMassKg: Value(m.leanMassKg),
              leanMassEstimated: Value(m.leanMassEstimated),
              syncedAt: syncedAt,
            ),
        ]);
      });
    });
  }

  Future<DateTime?> _latestCachedDay() async {
    final t = _db.dailyBodyMetrics;
    final maxDay = t.day.max();
    final row = await (_db.selectOnly(t)..addColumns([maxDay])).getSingle();
    final key = row.read(maxDay);
    return key == null ? null : parseDayKey(key);
  }

  static BodyMetric _toMetric(DailyBodyMetricRow r) => BodyMetric(
    date: parseDayKey(r.day),
    measuredAt: r.measuredAt,
    weightKg: r.weightKg,
    bodyFatPercent: r.bodyFatPercent,
    leanMassKg: r.leanMassKg,
    leanMassEstimated: r.leanMassEstimated,
  );
}
