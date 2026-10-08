import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart' show FlSpot;

import '../data/database.dart';
import 'daily_dataset.dart';

/// 7 日平均至少要有幾天飲食紀錄才畫（避免一兩天的資料讓線亂跳）。
const int kMinFoodDaysForAverage = 3;

/// 攝取圖：熱量（左軸 kcal）與蛋白質、脂肪（右軸 g）同時顯示，各有每日值與 7 日平均；
/// 底部標出有吃肌酸的天。
/// x 是第幾天（0 = 區間第一天）；沒紀錄的天不畫點。
class IntakeChartData {
  const IntakeChartData({
    required this.days,
    required this.kcal,
    required this.kcalAvg,
    required this.protein,
    required this.proteinAvg,
    required this.fat,
    required this.fatAvg,
    required this.creatineX,
    required this.expenditure,
    required this.kcalMax,
    required this.kcalStep,
    required this.proteinMax,
  });

  final List<DateTime> days;
  final List<FlSpot> kcal;
  final List<FlSpot> kcalAvg;
  final List<FlSpot> protein;
  final List<FlSpot> proteinAvg;

  /// 飲食脂肪（g，選填，有填的天才有）。
  final List<FlSpot> fat;
  final List<FlSpot> fatAvg;

  /// 有吃肌酸的天。
  final List<double> creatineX;

  /// 每日總消耗（kcal）；沒有個人資料時是空的。
  final List<FlSpot> expenditure;

  /// 左軸上限與刻度間距（kcal）。
  final double kcalMax;
  final double kcalStep;

  /// 右軸上限（g），刻度和左軸對齊，每格是整數。
  final double proteinMax;

  /// 公克（蛋白質、脂肪）換算到左軸座標。
  double gramsToY(double g) => g / proteinMax * kcalMax;
  double yToGrams(double y) => y / kcalMax * proteinMax;

  bool get isEmpty => kcal.isEmpty && protein.isEmpty;
}

IntakeChartData buildIntakeChart(
  DailyDataset ds, {
  double? Function(DayRecord)? expenditureOf,
}) {
  final days = ds.days;

  List<FlSpot> daily(double? Function(DayRecord) f) => [
    for (final (i, d) in days.indexed)
      if (f(d) case final v?) FlSpot(i.toDouble(), v),
  ];

  // 往前 7 天（含當天）有紀錄的天的平均
  List<FlSpot> trailing(double? Function(DayRecord) f) {
    final out = <FlSpot>[];
    for (var i = 0; i < days.length; i++) {
      final window = [for (var j = math.max(0, i - 6); j <= i; j++) f(days[j])]
          .whereType<double>()
          .toList();
      if (window.length < kMinFoodDaysForAverage) continue;
      out.add(
        FlSpot(i.toDouble(), window.reduce((a, b) => a + b) / window.length),
      );
    }
    return out;
  }

  double? kcalOf(DayRecord d) => d.food?.kcal;
  // 有紀錄但沒填蛋白質 / 脂肪的天不算 0，當作沒有資料
  double? proteinOf(DayRecord d) =>
      d.food == null || d.food!.proteinG == 0 ? null : d.food!.proteinG;
  double? fatOf(DayRecord d) =>
      d.food == null || d.food!.fatG == 0 ? null : d.food!.fatG;

  final kcal = daily(kcalOf);
  final protein = daily(proteinOf);
  final fat = daily(fatOf);
  final expenditure = expenditureOf == null
      ? const <FlSpot>[]
      : daily((d) => expenditureOf(d));

  // 左軸：500 一格，上限取整
  const step = 500.0;
  final kcalPeak = [
    ...kcal,
    ...expenditure,
  ].map((s) => s.y).fold(0.0, math.max);
  final kcalMax = math.max(step * 2, (kcalPeak * 1.08 / step).ceil() * step);
  final ticks = kcalMax / step;

  // 右軸：每格是 10 的倍數，和左軸刻度對齊
  final proteinPeak = [...protein, ...fat].map((s) => s.y).fold(0.0, math.max);
  final perTick = math.max(
    10.0,
    (proteinPeak * 1.1 / ticks / 10).ceil() * 10.0,
  );

  return IntakeChartData(
    days: [for (final d in days) d.date],
    kcal: kcal,
    kcalAvg: trailing(kcalOf),
    protein: protein,
    proteinAvg: trailing(proteinOf),
    fat: fat,
    fatAvg: trailing(fatOf),
    creatineX: [
      for (final (i, d) in days.indexed)
        if (d.checks.contains(CheckItem.creatine)) i.toDouble(),
    ],
    expenditure: expenditure,
    kcalMax: kcalMax,
    kcalStep: step,
    proteinMax: perTick * ticks,
  );
}
