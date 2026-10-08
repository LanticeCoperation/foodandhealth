import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart' show FlSpot;

import '../data/database.dart';
import 'daily_dataset.dart';

enum BodySeries {
  weight('體重', 'kg'),
  bodyFatPercent('體脂率', '%'),
  fatMass('脂肪重', 'kg'),
  leanMass('除脂體重', 'kg');

  const BodySeries(this.label, this.unit);
  final String label;

  /// 體脂率畫的是百分點的變化，和 kg 放在同一個左軸。
  final String unit;

  double? averageOf(DayRecord d) => switch (this) {
    weight => d.average?.weight,
    bodyFatPercent => d.average?.bodyFatPercent,
    fatMass => d.average?.fatMass,
    leanMass => d.average?.leanMass,
  };
}

enum IntakeSeries {
  none('不顯示', ''),
  kcal('熱量', 'kcal'),
  protein('蛋白質', 'g');

  const IntakeSeries(this.label, this.unit);
  final String label;
  final String unit;

  double? valueOf(DayRecord d) => switch (this) {
    none => null,
    kcal => d.food?.kcal,
    protein => d.food?.proteinG,
  };

  /// 右軸最大值取整的單位。
  double get roundTo => this == protein ? 50 : 500;
}

/// 疊加圖資料。x 是第幾天（0 = 區間第一天）。
///
/// 左軸：身體組成 7 日平均相對區間起點的變化（Δkg），三條線同一尺度，
/// 看得出體重變化來自脂肪還是除脂體重。
/// 右軸：攝取量原始值，畫圖時用 [intakeToY] 換算到左軸座標，
/// 只佔圖表下方 [intakeBand] 的高度，避免蓋住身體組成的線。
class OverlayData {
  static const double intakeBand = 0.45;

  const OverlayData({
    required this.days,
    required this.lines,
    required this.baselines,
    required this.weightDots,
    required this.intake,
    required this.creatineX,
    this.expenditure = const [],
    this.phaseSpans = const [],
    required this.minY,
    required this.maxY,
    required this.intakeMax,
  });

  final List<DateTime> days;
  final Map<BodySeries, List<FlSpot>> lines;

  /// 各線的起點絕對值（kg），tooltip 用來還原。
  final Map<BodySeries, double> baselines;

  /// 每天實際量到的體重（Δkg）。
  final List<FlSpot> weightDots;

  /// 攝取量原始值；沒紀錄的天是 [FlSpot.nullSpot]，線會斷開。
  final List<FlSpot> intake;

  /// 有吃肌酸的天。
  final List<double> creatineX;

  /// 每日總消耗原始值（kcal），只在攝取顯示熱量時有。
  final List<FlSpot> expenditure;

  /// 實驗階段在圖上的範圍（x 前後各延伸半天，色塊才會蓋滿整天）。
  final List<({Phase phase, double x1, double x2})> phaseSpans;

  final double minY;
  final double maxY;
  final double intakeMax;

  double intakeToY(double v) =>
      minY + v / intakeMax * (maxY - minY) * intakeBand;
  double yToIntake(double y) =>
      (y - minY) / ((maxY - minY) * intakeBand) * intakeMax;

  /// 肌酸標記的高度：貼近底部但不被裁掉。
  double get markerY => minY + (maxY - minY) * 0.02;

  bool get hasBodyData => lines.values.any((l) => l.isNotEmpty);
  bool get hasIntakeData => intake.any((s) => s != FlSpot.nullSpot);
}

/// [expenditureOf] 給每天的總消耗（kcal）；攝取顯示熱量時畫成虛線對照。
OverlayData buildOverlay(
  DailyDataset ds, {
  required Set<BodySeries> series,
  required IntakeSeries intake,
  double? Function(DayRecord)? expenditureOf,
}) {
  final days = ds.days;
  final lines = <BodySeries, List<FlSpot>>{};
  final baselines = <BodySeries, double>{};
  final ys = <double>[];

  for (final s in BodySeries.values.where(series.contains)) {
    final first = days.map(s.averageOf).whereType<double>().firstOrNull;
    final spots = <FlSpot>[];
    if (first != null) {
      baselines[s] = first;
      for (final (i, d) in days.indexed) {
        final v = s.averageOf(d);
        if (v != null) spots.add(FlSpot(i.toDouble(), v - first));
      }
    }
    lines[s] = spots;
    ys.addAll(spots.map((p) => p.y));
  }

  final weightDots = <FlSpot>[];
  final weightBase = baselines[BodySeries.weight];
  if (weightBase != null) {
    for (final (i, d) in days.indexed) {
      final m = d.metric;
      if (m != null) {
        weightDots.add(FlSpot(i.toDouble(), m.weightKg - weightBase));
      }
    }
    ys.addAll(weightDots.map((p) => p.y));
  }

  final intakeSpots = [
    for (final (i, d) in days.indexed)
      switch (intake.valueOf(d)) {
        final v? => FlSpot(i.toDouble(), v),
        null => FlSpot.nullSpot,
      },
  ];
  final expenditure = intake == IntakeSeries.kcal && expenditureOf != null
      ? [
          for (final (i, d) in days.indexed)
            if (expenditureOf(d) case final v?) FlSpot(i.toDouble(), v),
        ]
      : const <FlSpot>[];
  final intakeValues = [
    ...intakeSpots.where((s) => s != FlSpot.nullSpot).map((s) => s.y),
    ...expenditure.map((s) => s.y),
  ];
  final rawMax = intakeValues.fold<double>(0, math.max);
  final intakeMax = rawMax == 0
      ? intake.roundTo
      : (rawMax * 1.1 / intake.roundTo).ceilToDouble() * intake.roundTo;

  // 左軸至少 ±0.5 kg，取 0.5 的倍數。
  final lo = ys.fold<double>(-0.5, math.min);
  final hi = ys.fold<double>(0.5, math.max);

  return OverlayData(
    days: [for (final d in days) d.date],
    lines: lines,
    baselines: baselines,
    weightDots: weightDots,
    intake: intakeSpots,
    creatineX: [
      for (final (i, d) in days.indexed)
        if (d.checks.contains(CheckItem.creatine)) i.toDouble(),
    ],
    expenditure: expenditure,
    phaseSpans: _phaseSpans(days),
    minY: (lo * 2).floorToDouble() / 2,
    maxY: (hi * 2).ceilToDouble() / 2,
    intakeMax: intakeMax,
  );
}

List<({Phase phase, double x1, double x2})> _phaseSpans(List<DayRecord> days) {
  final spans = <({Phase phase, double x1, double x2})>[];
  for (final (i, d) in days.indexed) {
    final p = d.phase;
    if (p == null) continue;
    final last = spans.lastOrNull;
    if (last != null && last.phase.id == p.id && last.x2 == i - 0.5) {
      spans[spans.length - 1] = (phase: p, x1: last.x1, x2: i + 0.5);
    } else {
      spans.add((phase: p, x1: i - 0.5, x2: i + 0.5));
    }
  }
  return spans;
}

/// 區間摘要：身體組成變化（最後一天平均 − 第一天平均）與平均攝取。
class RangeSummary {
  const RangeSummary({
    required this.totalDays,
    required this.weighDays,
    required this.foodDays,
    required this.creatineDays,
    this.weightChange,
    this.bodyFatChange,
    this.fatMassChange,
    this.leanMassChange,
    this.avgKcal,
    this.avgProteinG,
    this.avgFatG,
    this.avgBalance,
  });

  final int totalDays;
  final int weighDays;
  final int foodDays;
  final int creatineDays;
  final double? weightChange;

  /// 體脂率變化（百分點）。
  final double? bodyFatChange;
  final double? fatMassChange;
  final double? leanMassChange;

  /// 只平均有飲食紀錄的天。
  final double? avgKcal;
  final double? avgProteinG;

  /// 只平均有填脂肪的天。
  final double? avgFatG;

  /// 有飲食紀錄的天，平均（攝取 − 消耗）；負數是赤字。
  final double? avgBalance;
}

RangeSummary summarize(
  Iterable<DayRecord> days, {
  double? Function(DayRecord)? expenditureOf,
}) {
  final list = days.toList();

  double? change(BodySeries s) {
    final values = list.map(s.averageOf).whereType<double>();
    if (values.length < 2) return null;
    return values.last - values.first;
  }

  final food = list.map((d) => d.food).whereType<Object>().length;
  double? avg(double? Function(DayRecord) f) {
    final values = list.map(f).whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  return RangeSummary(
    totalDays: list.length,
    weighDays: list.where((d) => d.metric != null).length,
    foodDays: food,
    creatineDays: list
        .where((d) => d.checks.contains(CheckItem.creatine))
        .length,
    weightChange: change(BodySeries.weight),
    bodyFatChange: change(BodySeries.bodyFatPercent),
    fatMassChange: change(BodySeries.fatMass),
    leanMassChange: change(BodySeries.leanMass),
    avgKcal: avg((d) => d.food?.kcal),
    avgProteinG: avg((d) => d.food?.proteinG),
    avgFatG: avg(
      (d) => d.food == null || d.food!.fatG == 0 ? null : d.food!.fatG,
    ),
    avgBalance: expenditureOf == null
        ? null
        : avg((d) {
            final e = expenditureOf(d);
            return d.food == null || e == null ? null : d.food!.kcal - e;
          }),
  );
}
