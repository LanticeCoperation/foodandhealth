import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;

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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BodyRepository _body;
  final FoodRepository _food;
  final CheckRepository _checks;
  final PhaseRepository _phases;
  final DateTime Function() _clock;

  DateTime get today => dateOnly(_clock());

  /// 最近 [days] 天（含今天）。
  Future<DailyDataset> load(int days) =>
      loadRange(addDays(today, -(days - 1)), today);

  /// [from]～[to]（含頭尾）。
  Future<DailyDataset> loadRange(DateTime from, DateTime to) async {
    final (metrics, food, checks, phases) = await (
      _body.since(addDays(from, -(kMovingAverageDays - 1))),
      _food.dailyTotalsSince(from),
      _checks.since(from),
      _phases.all(),
    ).wait;
    return buildDataset(
      from: from,
      to: to,
      metrics: metrics,
      food: food,
      checks: checks,
      phases: phases,
    );
  }

  /// 最近 [days] 天；任何相關資料表變動就重新計算。
  Stream<DailyDataset> watch(int days) => _watch(() => load(days));

  Stream<DailyDataset> watchRange(DateTime from, DateTime to) =>
      _watch(() => loadRange(from, to));

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
      ]),
    );
    await for (final _ in updates) {
      yield await load();
    }
  }
}
