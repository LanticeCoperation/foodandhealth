import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;

import '../data/body_repository.dart';
import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../models/body_metric.dart';
import '../utils/dates.dart';
import '../utils/trend.dart';

/// 分析用的單日資料：身體組成、7 日平均、飲食總量、打勾。
class DayRecord {
  const DayRecord({
    required this.date,
    this.metric,
    this.average,
    this.food,
    this.checks = const {},
  });

  final DateTime date;

  /// 當天有量體重才有。
  final BodyMetric? metric;

  /// 往前 7 天的平均（當天沒量也可能有）。
  final RollingAverage? average;

  /// 當天有飲食紀錄才有。
  final DayTotals? food;

  final Set<CheckItem> checks;
}

/// 連續日期的每日資料，由舊到新，每天都有一筆。
class DailyDataset {
  const DailyDataset(this.days);

  final List<DayRecord> days;

  DateTime? get from => days.isEmpty ? null : days.first.date;
  DateTime? get to => days.isEmpty ? null : days.last.date;
}

/// [metrics] 應包含 [from] 之前 6 天的資料，最舊幾天的 7 日平均才會完整。
DailyDataset buildDataset({
  required DateTime from,
  required DateTime to,
  required List<BodyMetric> metrics,
  required Map<DateTime, DayTotals> food,
  required Map<DateTime, Set<CheckItem>> checks,
}) {
  final byDay = {for (final m in metrics) m.date: m};
  final averages = rollingAverages(metrics, from: from, to: to);
  return DailyDataset([
    for (var d = from; !d.isAfter(to); d = addDays(d, 1))
      DayRecord(
        date: d,
        metric: byDay[d],
        average: averages[d],
        food: food[d],
        checks: checks[d] ?? const {},
      ),
  ]);
}

class DatasetRepository {
  DatasetRepository(
    this._db,
    this._body,
    this._food,
    this._checks, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BodyRepository _body;
  final FoodRepository _food;
  final CheckRepository _checks;
  final DateTime Function() _clock;

  /// 最近 [days] 天（含今天）。
  Future<DailyDataset> load(int days) async {
    final to = dateOnly(_clock());
    final from = addDays(to, -(days - 1));
    final results = await Future.wait([
      _body.since(addDays(from, -(kMovingAverageDays - 1))),
      _food.dailyTotalsSince(from),
      _checks.since(from),
    ]);
    return buildDataset(
      from: from,
      to: to,
      metrics: results[0] as List<BodyMetric>,
      food: results[1] as Map<DateTime, DayTotals>,
      checks: results[2] as Map<DateTime, Set<CheckItem>>,
    );
  }

  /// 任何相關資料表變動就重新計算。
  Stream<DailyDataset> watch(int days) async* {
    yield await load(days);
    final updates = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.dailyBodyMetrics,
        _db.foodEntries,
        _db.dailyChecks,
      ]),
    );
    await for (final _ in updates) {
      yield await load(days);
    }
  }
}
