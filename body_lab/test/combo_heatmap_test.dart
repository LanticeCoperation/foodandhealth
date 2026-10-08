import 'package:body_lab/analysis/combo_heatmap.dart';
import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:flutter_test/flutter_test.dart';

DayTotals food(double kcal, double protein) => DayTotals(
  kcal: kcal,
  proteinG: protein,
  carbsG: 0,
  fatG: 0,
  missingKcal: 0,
);

WeekSample week({
  double? kcal,
  double? proteinPerKg,
  int creatineDays = 0,
  double? fat,
  double? lean,
}) => WeekSample(
  start: DateTime(2026, 1, 1),
  end: DateTime(2026, 1, 7),
  foodDays: 7,
  creatineDays: creatineDays,
  kcal: kcal,
  proteinPerKg: proteinPerKg,
  fatMassChange: fat,
  leanMassChange: lean,
);

void main() {
  group('weeklySamples', () {
    // 9/9～10/13 共 35 天 = 5 週；每天量體重（每天 -0.1 kg、體脂 20%）
    final from = DateTime(2026, 9, 9);
    final to = DateTime(2026, 10, 13);
    final days = [for (var d = from; !d.isAfter(to); d = addDays(d, 1)) d];
    final metrics = [
      for (final (i, d) in days.indexed)
        BodyMetric(
          date: d,
          measuredAt: d,
          weightKg: 80 - i * 0.1,
          bodyFatPercent: 20,
        ),
    ];
    // 最後一週每天都有紀錄、吃肌酸；倒數第二週只有 3 天紀錄
    final last = days.sublist(28);
    final secondLast = days.sublist(21, 24);
    final ds = buildDataset(
      from: from,
      to: to,
      metrics: metrics,
      food: {
        for (final d in last) d: food(2000, 156),
        for (final d in secondLast) d: food(2500, 100),
      },
      checks: {
        for (final d in last) d: {CheckItem.creatine},
      },
    );
    final samples = weeklySamples(ds);

    test('從最新一天往回切 7 天，由舊到新', () {
      expect(samples, hasLength(5));
      expect(samples.last.end, to);
      expect(samples.last.start, DateTime(2026, 10, 7));
      expect(samples.first.start, from);
    });

    test('紀錄 4 天以上才算平均攝取；蛋白質換算 g/kg', () {
      final s = samples.last;
      expect(s.foodDays, 7);
      expect(s.kcal, 2000);
      // 週末 7 日平均體重 = 80 - 31×0.1 = 76.9
      expect(s.proteinPerKg, closeTo(156 / 76.9, 1e-9));
      expect(s.creatine, isTrue);

      expect(samples[3].foodDays, 3);
      expect(samples[3].kcal, isNull);
      expect(samples[3].creatine, isFalse);
    });

    test('週變化 = 週末 7 日平均 − 上週末 7 日平均；第一週沒有上週', () {
      expect(samples.first.weightChange, isNull);
      expect(samples.last.weightChange, closeTo(-0.7, 1e-9));
      expect(samples.last.fatMassChange, closeTo(-0.14, 1e-9));
    });
  });

  group('分組', () {
    test('蛋白質依 1.2 / 1.6 / 2.2 g/kg 分 4 組', () {
      final b = bucketsFor(HeatmapFactor.protein, const []);
      expect(b.labels, hasLength(4));
      expect(b.classify(week(proteinPerKg: 1.0)), 0);
      expect(b.classify(week(proteinPerKg: 1.6)), 2);
      expect(b.classify(week(proteinPerKg: 2.5)), 3);
      expect(b.classify(week()), isNull);
    });

    test('熱量用三分位數分低 / 中 / 高，資料不足時不分', () {
      final samples = [
        for (final k in <double>[1800, 1900, 2000, 2100, 2200, 2300])
          week(kcal: k),
      ];
      final b = bucketsFor(HeatmapFactor.kcal, samples);
      expect(b.labels, ['<1950', '1950–2150', '≥2150']);
      expect(b.classify(week(kcal: 1800)), 0);
      expect(b.classify(week(kcal: 2000)), 1);
      expect(b.classify(week(kcal: 2300)), 2);

      final few = bucketsFor(HeatmapFactor.kcal, [week(kcal: 2000)]);
      expect(few.labels, ['全部']);
    });

    test('肌酸一週 5 天以上算有', () {
      final b = bucketsFor(HeatmapFactor.creatine, const []);
      expect(b.classify(week(creatineDays: 4)), 0);
      expect(b.classify(week(creatineDays: 5)), 1);
    });
  });

  test('熱力圖：格子平均與樣本數、略過缺資料的週、好壞方向', () {
    final samples = [
      week(proteinPerKg: 2.0, creatineDays: 7, fat: -0.4, lean: 0.2),
      week(proteinPerKg: 2.0, creatineDays: 7, fat: -0.2, lean: 0.1),
      week(proteinPerKg: 1.0, creatineDays: 0, fat: 0.3, lean: -0.1),
      week(creatineDays: 7, fat: -1), // 沒有蛋白質資料
      week(proteinPerKg: 1.0), // 沒有結果
    ];
    final h = buildHeatmap(
      samples,
      x: HeatmapFactor.protein,
      y: HeatmapFactor.creatine,
      outcome: HeatmapOutcome.fatMass,
    );
    expect(h.total, 5);
    expect(h.used, 3);
    final good = h.cells[(2, 1)]!;
    expect(good.n, 2);
    expect(good.mean, closeTo(-0.3, 1e-9));
    expect(h.cells[(0, 0)]!.mean, 0.3);
    expect(h.cells.containsKey((3, 0)), isFalse);
    // 脂肪下降是好的：分數為正；上升為負
    expect(h.score(good), greaterThan(0));
    expect(h.score(h.cells[(0, 0)]!), closeTo(-1, 1e-9));

    final lean = buildHeatmap(
      samples,
      x: HeatmapFactor.creatine,
      y: HeatmapFactor.none,
      outcome: HeatmapOutcome.leanMass,
    );
    expect(lean.yLabels, ['全部']);
    expect(lean.score(lean.cells[(1, 0)]!), greaterThan(0));
  });
}
