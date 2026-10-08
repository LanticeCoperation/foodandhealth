import 'dart:async';

import 'package:drift/drift.dart';

import '../data/activity_repository.dart';
import '../data/body_repository.dart';
import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/phase_repository.dart';
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
    this.phase,
    this.activeKcal,
  });

  final DateTime date;

  /// 當天有量體重才有。
  final BodyMetric? metric;

  /// 往前 7 天的平均（當天沒量也可能有）。
  final RollingAverage? average;

  /// 當天有飲食紀錄才有。
  final DayTotals? food;

  final Set<CheckItem> checks;

  /// 當天所屬的實驗階段。
  final Phase? phase;

  /// 當天手錶記錄的活動消耗（kcal）。
  final double? activeKcal;
}

/// 連續日期的每日資料，由舊到新，每天都有一筆。
class DailyDataset {
  const DailyDataset(this.days);

  final List<DayRecord> days;

  DateTime? get from => days.isEmpty ? null : days.first.date;
  DateTime? get to => days.isEmpty ? null : days.last.date;

  /// 只保留 [from]～[to] 的天。
  DailyDataset slice(DateTime from, DateTime to) => DailyDataset([
    for (final d in days)
      if (!d.date.isBefore(from) && !d.date.isAfter(to)) d,
  ]);
}

/// 所有階段，加上從最早階段前 7 天到今天的 dataset（沒有階段時為 null）。
typedef PhaseOverview = ({List<Phase> phases, DailyDataset? dataset});

/// [metrics] 應包含 [from] 之前 6 天的資料，最舊幾天的 7 日平均才會完整。
DailyDataset buildDataset({
  required DateTime from,
  required DateTime to,
  required List<BodyMetric> metrics,
  required Map<DateTime, DayTotals> food,
  required Map<DateTime, Set<CheckItem>> checks,
  List<Phase> phases = const [],
  Map<DateTime, double> activity = const {},
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
        phase: phases.where((p) => p.contains(d)).firstOrNull,
        activeKcal: activity[d],
      ),
  ]);
}

class DatasetRepository {
  DatasetRepository(
    this._db,
    this._body,
    this._food,
    this._checks,
    this._phases, {
    this.activity,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BodyRepository _body;
  final FoodRepository _food;
  final CheckRepository _checks;
  final PhaseRepository _phases;

  /// 每日活動消耗（沒有時每日消耗退回固定 TDEE）。
  final ActivityRepository? activity;
  final DateTime Function() _clock;

  DateTime get today => dateOnly(_clock());

  /// 最近 [days] 天（含今天）。
  Future<DailyDataset> load(int days) =>
      loadRange(addDays(today, -(days - 1)), today);

  /// [from]～[to]（含頭尾）。
  Future<DailyDataset> loadRange(DateTime from, DateTime to) async {
    final (metrics, food, checks, phases, active) = await (
      _body.since(addDays(from, -(kMovingAverageDays - 1))),
      _food.dailyTotalsSince(from),
      _checks.since(from),
      _phases.all(),
      activity?.since(from) ?? Future.value(<DateTime, double>{}),
    ).wait;
    return buildDataset(
      from: from,
      to: to,
      metrics: metrics,
      food: food,
      checks: checks,
      phases: phases,
      activity: active,
    );
  }

  /// 最近 [days] 天；任何相關資料表變動就重新計算。
  Stream<DailyDataset> watch(int days) => _watch(() => load(days));

  Stream<DailyDataset> watchRange(DateTime from, DateTime to) =>
      _watch(() => loadRange(from, to));

  /// 從最早一筆資料（身體、飲食或打勾）到今天；沒有任何資料時是空的。
  Future<DailyDataset> loadAll() async {
    final first = await _earliestDay();
    if (first == null) return const DailyDataset([]);
    return loadRange(first.isAfter(today) ? today : first, today);
  }

  Stream<DailyDataset> watchAll() => _watch(loadAll);

  Future<DateTime?> _earliestDay() async {
    final body = _db.dailyBodyMetrics.day.min();
    final food = _db.foodEntries.eatenAt.min();
    final check = _db.dailyChecks.day.min();
    final (b, f, c) = await (
      (_db.selectOnly(_db.dailyBodyMetrics)..addColumns([body])).getSingle(),
      (_db.selectOnly(_db.foodEntries)..addColumns([food])).getSingle(),
      (_db.selectOnly(_db.dailyChecks)..addColumns([check])).getSingle(),
    ).wait;
    final candidates = [
      if (b.read(body) case final key?) parseDayKey(key),
      if (f.read(food) case final t?) dateOnly(t),
      if (c.read(check) case final key?) parseDayKey(key),
    ]..sort();
    return candidates.firstOrNull;
  }

  Stream<PhaseOverview> watchPhaseOverview() => _watch(() async {
    final phases = await _phases.all();
    if (phases.isEmpty) return (phases: phases, dataset: null);
    final earliest = phases
        .map((p) => p.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final from = addDays(earliest, -kMovingAverageDays);
    final to = from.isAfter(today) ? from : today;
    return (phases: phases, dataset: await loadRange(from, to));
  });

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    final updates = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.dailyBodyMetrics,
        _db.foodEntries,
        _db.dailyChecks,
        _db.phases,
        _db.dailyActivity,
      ]),
    );
    await for (final _ in updates) {
      yield await load();
    }
  }
}
