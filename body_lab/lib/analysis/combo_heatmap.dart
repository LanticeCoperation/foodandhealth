import 'dart:math' as math;

import '../data/database.dart';
import '../utils/dates.dart';
import 'daily_dataset.dart';

/// 一週至少幾天有飲食紀錄，平均攝取才算數。
const int kMinFoodDaysPerWeek = 4;

/// 一週至少幾天有吃肌酸，才算「有」。
const int kCreatineDaysPerWeek = 5;

/// 7 日平均的視窗內至少要有幾次量測，週變化才算數。
const int kMinWeighInsForAverage = 3;

/// 格子裡少於這個樣本數時淡化顯示。
const int kMinSamplesPerCell = 2;

/// 一週（7 天、不重疊）的因子與結果。
class WeekSample {
  const WeekSample({
    required this.start,
    required this.end,
    required this.foodDays,
    required this.creatineDays,
    this.kcal,
    this.proteinPerKg,
    this.phase,
    this.weightChange,
    this.fatMassChange,
    this.leanMassChange,
  });

  final DateTime start;
  final DateTime end;
  final int foodDays;
  final int creatineDays;

  /// 有紀錄天的平均；紀錄少於 [kMinFoodDaysPerWeek] 天時為 null。
  final double? kcal;

  /// 平均蛋白質 ÷ 週末 7 日平均體重。
  final double? proteinPerKg;

  /// 這週有 4 天以上屬於的階段。
  final Phase? phase;

  /// 週末的 7 日平均 − 前一週末的 7 日平均（kg / 週）。
  final double? weightChange;
  final double? fatMassChange;
  final double? leanMassChange;

  bool get creatine => creatineDays >= kCreatineDaysPerWeek;
}

/// 從最新一天往回切成不重疊的 7 天區塊，由舊到新。
List<WeekSample> weeklySamples(DailyDataset ds) {
  final days = ds.days;
  final byDate = {for (final d in days) d.date: d};
  final samples = <WeekSample>[];

  double? avg(Iterable<double?> values) {
    final v = values.whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  double? change(
    DateTime end,
    DateTime prevEnd,
    double? Function(DayRecord) f,
  ) {
    final a = byDate[end];
    final b = byDate[prevEnd];
    if (a == null || b == null) return null;
    if ((a.average?.windowCount ?? 0) < kMinWeighInsForAverage ||
        (b.average?.windowCount ?? 0) < kMinWeighInsForAverage) {
      return null;
    }
    final va = f(a);
    final vb = f(b);
    return va == null || vb == null ? null : va - vb;
  }

  for (var end = ds.to; end != null; end = addDays(end, -7)) {
    final start = addDays(end, -6);
    if (start.isBefore(ds.from!)) break;
    final week = [
      for (var d = start; !d.isAfter(end); d = addDays(d, 1)) byDate[d]!,
    ];
    final foodDays = week.where((d) => d.food != null).toList();
    final enoughFood = foodDays.length >= kMinFoodDaysPerWeek;
    final kcal = enoughFood ? avg(foodDays.map((d) => d.food!.kcal)) : null;
    final protein = enoughFood
        ? avg(foodDays.map((d) => d.food!.proteinG))
        : null;
    final weight = byDate[end]?.average?.weight;

    final phaseDays = <int, int>{};
    for (final d in week) {
      if (d.phase != null) {
        phaseDays[d.phase!.id] = (phaseDays[d.phase!.id] ?? 0) + 1;
      }
    }
    final mainPhase = phaseDays.entries
        .where((e) => e.value >= 4)
        .map((e) => week.firstWhere((d) => d.phase?.id == e.key).phase)
        .firstOrNull;

    final prevEnd = addDays(start, -1);
    samples.add(
      WeekSample(
        start: start,
        end: end,
        foodDays: foodDays.length,
        creatineDays: week
            .where((d) => d.checks.contains(CheckItem.creatine))
            .length,
        kcal: kcal,
        proteinPerKg: protein == null || weight == null
            ? null
            : protein / weight,
        phase: mainPhase,
        weightChange: change(end, prevEnd, (d) => d.average?.weight),
        fatMassChange: change(end, prevEnd, (d) => d.average?.fatMass),
        leanMassChange: change(end, prevEnd, (d) => d.average?.leanMass),
      ),
    );
  }
  return samples.reversed.toList();
}

enum HeatmapOutcome {
  weight('體重', higherIsBetter: false),
  fatMass('脂肪重', higherIsBetter: false),
  leanMass('除脂體重', higherIsBetter: true);

  const HeatmapOutcome(this.label, {required this.higherIsBetter});
  final String label;
  final bool higherIsBetter;

  double? of(WeekSample s) => switch (this) {
    weight => s.weightChange,
    fatMass => s.fatMassChange,
    leanMass => s.leanMassChange,
  };
}

enum HeatmapFactor {
  kcal('熱量'),
  protein('蛋白質 g/kg'),
  creatine('肌酸'),
  phase('階段'),
  none('不分');

  const HeatmapFactor(this.label);
  final String label;
}

/// 因子的分組：依序的標籤，以及把樣本分到第幾組（null = 無法分組，略過）。
class FactorBuckets {
  const FactorBuckets(this.labels, this.classify);

  final List<String> labels;
  final int? Function(WeekSample) classify;
}

/// 蛋白質 g/kg 的分界。
const List<double> kProteinCuts = [1.2, 1.6, 2.2];

/// 有固定 TDEE 時，熱量依每日赤字分組的分界（kcal）。
const double kDeficitCut = 500;

FactorBuckets bucketsFor(
  HeatmapFactor f,
  List<WeekSample> samples, {
  double? tdee,
}) {
  switch (f) {
    case HeatmapFactor.none:
      return FactorBuckets(const ['全部'], (_) => 0);

    case HeatmapFactor.creatine:
      return FactorBuckets(const ['無肌酸', '有肌酸'], (s) => s.creatine ? 1 : 0);

    case HeatmapFactor.protein:
      final c = kProteinCuts;
      return FactorBuckets(
        ['<${c[0]}', '${c[0]}–${c[1]}', '${c[1]}–${c[2]}', '≥${c[2]}'],
        (s) {
          final v = s.proteinPerKg;
          if (v == null) return null;
          return c.where((cut) => v >= cut).length;
        },
      );

    case HeatmapFactor.phase:
      final phases = <int, Phase>{
        for (final s in samples)
          if (s.phase != null) s.phase!.id: s.phase!,
      }.values.toList()..sort((a, b) => a.startDay.compareTo(b.startDay));
      return FactorBuckets(
        ['無階段', for (final p in phases) p.name],
        (s) => s.phase == null
            ? 0
            : phases.indexWhere((p) => p.id == s.phase!.id) + 1,
      );

    case HeatmapFactor.kcal when tdee != null:
      final cut = kDeficitCut.round();
      return FactorBuckets(['赤字 >$cut', '赤字 0–$cut', '盈餘'], (s) {
        final v = s.kcal;
        if (v == null) return null;
        final balance = v - tdee;
        return balance < -kDeficitCut ? 0 : (balance < 0 ? 1 : 2);
      });

    case HeatmapFactor.kcal:
      // 沒有 TDEE 時用自己資料的三分位數分低 / 中 / 高。
      final values = samples.map((s) => s.kcal).whereType<double>().toList()
        ..sort();
      if (values.length < 3) {
        return FactorBuckets(const ['全部'], (s) => s.kcal == null ? null : 0);
      }
      double roundTo50(double v) => (v / 50).round() * 50;
      final lo = roundTo50(_quantile(values, 1 / 3));
      final hi = roundTo50(_quantile(values, 2 / 3));
      if (lo >= hi) {
        return FactorBuckets(const ['全部'], (s) => s.kcal == null ? null : 0);
      }
      return FactorBuckets(
        ['<${lo.round()}', '${lo.round()}–${hi.round()}', '≥${hi.round()}'],
        (s) {
          final v = s.kcal;
          if (v == null) return null;
          return v < lo ? 0 : (v < hi ? 1 : 2);
        },
      );
  }
}

double _quantile(List<double> sorted, double q) {
  final pos = (sorted.length - 1) * q;
  final i = pos.floor();
  final j = math.min(i + 1, sorted.length - 1);
  return sorted[i] + (sorted[j] - sorted[i]) * (pos - i);
}

class HeatmapCell {
  const HeatmapCell(this.mean, this.n);
  final double mean;
  final int n;
}

class Heatmap {
  const Heatmap({
    required this.xLabels,
    required this.yLabels,
    required this.cells,
    required this.outcome,
    required this.used,
    required this.total,
  });

  final List<String> xLabels;
  final List<String> yLabels;

  /// key 是 (x, y)；沒有樣本的格子不在裡面。
  final Map<(int, int), HeatmapCell> cells;
  final HeatmapOutcome outcome;

  /// 有結果且兩個因子都能分組的週數 / 全部週數。
  final int used;
  final int total;

  double get maxAbs =>
      cells.values.map((c) => c.mean.abs()).fold(0.0, math.max);

  /// -1（最差）～ 1（最好），依結果方向調整正負。
  double score(HeatmapCell c) {
    final m = maxAbs;
    if (m == 0) return 0;
    final v = c.mean / m;
    return outcome.higherIsBetter ? v : -v;
  }
}

Heatmap buildHeatmap(
  List<WeekSample> samples, {
  required HeatmapFactor x,
  required HeatmapFactor y,
  required HeatmapOutcome outcome,
  double? tdee,
}) {
  final bx = bucketsFor(x, samples, tdee: tdee);
  final by = bucketsFor(y, samples, tdee: tdee);
  final sums = <(int, int), (double, int)>{};
  var used = 0;

  for (final s in samples) {
    final v = outcome.of(s);
    final ix = bx.classify(s);
    final iy = by.classify(s);
    if (v == null || ix == null || iy == null) continue;
    used++;
    final (sum, n) = sums[(ix, iy)] ?? (0.0, 0);
    sums[(ix, iy)] = (sum + v, n + 1);
  }

  return Heatmap(
    xLabels: bx.labels,
    yLabels: by.labels,
    cells: sums.map((k, v) => MapEntry(k, HeatmapCell(v.$1 / v.$2, v.$2))),
    outcome: outcome,
    used: used,
    total: samples.length,
  );
}
