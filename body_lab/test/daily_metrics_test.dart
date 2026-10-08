import 'package:body_lab/services/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

BodySample w(DateTime t, double v) => BodySample(BodySampleType.weight, t, v);
BodySample bf(DateTime t, double v) => BodySample(BodySampleType.bodyFat, t, v);
BodySample lean(DateTime t, double v) =>
    BodySample(BodySampleType.leanMass, t, v);

void main() {
  test('每種數值各取當天最早一筆', () {
    final metrics = buildDailyMetrics([
      w(DateTime(2026, 10, 1, 21, 0), 73.0),
      w(DateTime(2026, 10, 1, 7, 5), 72.0),
      bf(DateTime(2026, 10, 1, 22, 0), 21.0),
      bf(DateTime(2026, 10, 1, 7, 5), 20.0),
      lean(DateTime(2026, 10, 1, 7, 5), 57.5),
    ]);

    expect(metrics, hasLength(1));
    final m = metrics.single;
    expect(m.date, DateTime(2026, 10, 1));
    expect(m.measuredAt, DateTime(2026, 10, 1, 7, 5));
    expect(m.weightKg, 72.0);
    expect(m.bodyFatPercent, 20.0);
    expect(m.leanMassKg, 57.5);
    expect(m.leanMassEstimated, isFalse);
    expect(m.fatMassKg, closeTo(14.4, 1e-9));
  });

  test('沒有除脂體重時由體重與體脂推算並標記', () {
    final m = buildDailyMetrics([
      w(DateTime(2026, 10, 2, 7), 80.0),
      bf(DateTime(2026, 10, 2, 7), 25.0),
    ]).single;

    expect(m.leanMassKg, closeTo(60.0, 1e-9));
    expect(m.leanMassEstimated, isTrue);
    expect(m.fatMassKg, closeTo(20.0, 1e-9));
  });

  test('只有體重時體脂相關欄位為 null', () {
    final m = buildDailyMetrics([w(DateTime(2026, 10, 3, 7), 70.0)]).single;
    expect(m.bodyFatPercent, isNull);
    expect(m.leanMassKg, isNull);
    expect(m.fatMassKg, isNull);
  });

  test('沒有體重的日子略過，結果依日期由舊到新', () {
    final metrics = buildDailyMetrics([
      w(DateTime(2026, 10, 5, 7), 71.0),
      bf(DateTime(2026, 10, 4, 7), 20.0),
      w(DateTime(2026, 10, 3, 7), 72.0),
    ]);
    expect(metrics.map((m) => m.date), [
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 5),
    ]);
  });

  test('當天體重是 Body Lab 寫入的才標記 fromThisApp', () {
    final metrics = buildDailyMetrics([
      BodySample(
        BodySampleType.weight,
        DateTime(2026, 10, 8, 8, 40),
        73.9,
        fromThisApp: true,
      ),
      w(DateTime(2026, 10, 9, 7), 73.5), // 體脂計
    ]);
    expect(metrics.map((m) => m.fromThisApp), [true, false]);
  });
}
