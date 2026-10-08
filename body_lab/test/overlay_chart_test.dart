import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/analysis/overlay_chart.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

BodyMetric metric(int day, double kg, {double bf = 20}) => BodyMetric(
  date: DateTime(2026, 10, day),
  measuredAt: DateTime(2026, 10, day, 7),
  weightKg: kg,
  bodyFatPercent: bf,
  leanMassKg: kg * (1 - bf / 100),
);

DayTotals totals(double kcal, double protein) => DayTotals(
  kcal: kcal,
  proteinG: protein,
  carbsG: 0,
  fatG: 0,
  missingKcal: 0,
);

void main() {
  // 10/1～10/10；10/4 沒量、10/5 沒飲食紀錄
  final ds = buildDataset(
    from: DateTime(2026, 10, 1),
    to: DateTime(2026, 10, 10),
    metrics: [
      for (final d in [1, 2, 3, 5, 6, 7, 8, 9, 10]) metric(d, 80.0 - d * 0.1),
    ],
    food: {
      for (final d in [1, 2, 3, 4, 6, 7, 8, 9, 10])
        DateTime(2026, 10, d): totals(2000 + d * 10, 150),
    },
    checks: {
      DateTime(2026, 10, 2): {CheckItem.creatine},
      DateTime(2026, 10, 3): {CheckItem.creatine},
    },
  );

  test('dataset 每天一筆；沒量的天仍有 7 日平均', () {
    expect(ds.days, hasLength(10));
    final d4 = ds.days[3];
    expect(d4.metric, isNull);
    expect(d4.average!.windowCount, 3);
    expect(d4.average!.weight, closeTo((79.9 + 79.8 + 79.7) / 3, 1e-9));
    expect(ds.days[4].food, isNull);
  });

  test('左軸是相對起點的變化，三條線從 0 開始', () {
    final o = buildOverlay(
      ds,
      series: BodySeries.values.toSet(),
      intake: IntakeSeries.kcal,
    );
    for (final s in BodySeries.values) {
      expect(o.lines[s]!.first.y, 0);
      expect(o.lines[s], hasLength(10));
    }
    expect(o.baselines[BodySeries.weight], closeTo(79.9, 1e-9));
    // 體重一直下降，最後一天的平均低於起點
    expect(o.lines[BodySeries.weight]!.last.y, lessThan(0));
    // 實際量測點 9 個（10/4 沒量）
    expect(o.weightDots, hasLength(9));
    expect(o.minY, lessThanOrEqualTo(-0.5));
    expect(o.maxY, greaterThanOrEqualTo(0.5));
  });

  test('攝取量沒紀錄的天斷線，右軸取整並可來回換算', () {
    final o = buildOverlay(
      ds,
      series: {BodySeries.weight},
      intake: IntakeSeries.kcal,
    );
    expect(o.intake[4], FlSpot.nullSpot);
    expect(o.intake[0].y, 2010);
    expect(o.intakeMax, 2500); // 2100 × 1.1 = 2310 → 取整到 500
    expect(o.yToIntake(o.intakeToY(1234)), closeTo(1234, 1e-9));
    expect(o.creatineX, [1, 2]);
  });

  test('只選部分線時其他線不出現', () {
    final o = buildOverlay(
      ds,
      series: {BodySeries.fatMass},
      intake: IntakeSeries.none,
    );
    expect(o.lines.keys, [BodySeries.fatMass]);
    expect(o.weightDots, isEmpty);
    expect(o.hasIntakeData, isFalse);
  });

  test('區間摘要', () {
    final s = summarize(ds.days);
    expect(s.totalDays, 10);
    expect(s.weighDays, 9);
    expect(s.foodDays, 9);
    expect(s.creatineDays, 2);
    expect(s.weightChange, lessThan(0));
    expect(s.avgProteinG, 150);
  });
}
