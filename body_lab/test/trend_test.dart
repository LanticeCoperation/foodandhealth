import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/utils/trend.dart';
import 'package:flutter_test/flutter_test.dart';

BodyMetric day(int d, double kg, {double? bf}) => BodyMetric(
  date: DateTime(2026, 10, d),
  measuredAt: DateTime(2026, 10, d, 7),
  weightKg: kg,
  bodyFatPercent: bf,
);

void main() {
  test('7 日平均以日曆天計算，缺資料的天不算進去', () {
    // 10/1 ~ 10/10，缺 10/4
    final metrics = [
      for (final d in [1, 2, 3, 5, 6, 7, 8, 9, 10]) day(d, 70.0 + d),
    ];
    final trend = computeTrend(metrics);

    // 10/8 的視窗是 10/2 ~ 10/8，有 6 天資料
    final p = trend.firstWhere((t) => t.metric.date.day == 8);
    expect(p.windowCount, 6);
    expect(p.weightAvg, closeTo((72 + 73 + 75 + 76 + 77 + 78) / 6, 1e-9));

    // 10/1 只有自己
    expect(trend.first.windowCount, 1);
    expect(trend.first.weightAvg, 71.0);
  });

  test('輸入順序不影響結果，輸出由舊到新', () {
    final trend = computeTrend([day(3, 70), day(1, 71), day(2, 72)]);
    expect(trend.map((t) => t.metric.date.day), [1, 2, 3]);
    expect(trend.last.weightAvg, closeTo(71.0, 1e-9));
  });

  test('偏離 7 日平均超過 0.8 kg 標記為水分波動', () {
    final trend = computeTrend([
      day(1, 70.0),
      day(2, 70.0),
      day(3, 70.0),
      day(4, 72.0), // 平均 70.5，偏離 +1.5
      day(5, 70.6), // 平均 70.52，偏離 +0.08
    ]);
    expect(trend[3].isWaterOutlier, isTrue);
    expect(trend[3].weightDeviation, closeTo(1.5, 1e-9));
    expect(trend[4].isWaterOutlier, isFalse);
  });

  test('視窗資料少於 3 天時不判斷異常', () {
    final trend = computeTrend([day(1, 70.0), day(2, 75.0)]);
    expect(trend.last.isWaterOutlier, isFalse);
  });

  test('脂肪重平均只用有體脂的天', () {
    final trend = computeTrend([day(1, 80.0, bf: 25.0), day(2, 80.0)]);
    expect(trend.last.fatMassAvg, closeTo(20.0, 1e-9));
    expect(trend.last.leanMassAvg, isNull);
  });
}
