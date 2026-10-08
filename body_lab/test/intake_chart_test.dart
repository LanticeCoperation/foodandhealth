import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/analysis/intake_chart.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:flutter_test/flutter_test.dart';

DayTotals food(double kcal, {double protein = 0, double fat = 0}) => DayTotals(
  kcal: kcal,
  proteinG: protein,
  carbsG: 0,
  fatG: fat,
  missingKcal: 0,
);

void main() {
  final from = DateTime(2026, 10, 1);
  // 10/1～10/10：10/1、10/2 有紀錄，10/3 沒有，之後每天都有
  final ds = buildDataset(
    from: from,
    to: DateTime(2026, 10, 10),
    metrics: const [],
    food: {
      for (final i in [0, 1, 3, 4, 5, 6, 7, 8, 9])
        addDays(from, i): food(
          2000 + i * 10,
          protein: i == 4 ? 0 : 150, // 10/5 沒填蛋白質
          fat: i >= 7 ? 60 : 0, // 只有最後三天有填脂肪
        ),
    },
    checks: {
      addDays(from, 2): {CheckItem.creatine},
      addDays(from, 9): {CheckItem.creatine},
    },
  );

  test('每日值只畫有紀錄的天；沒填蛋白質 / 脂肪不算 0', () {
    final c = buildIntakeChart(ds);
    expect(c.kcal.map((s) => s.x), [0, 1, 3, 4, 5, 6, 7, 8, 9]);
    expect(c.protein.map((s) => s.x), [0, 1, 3, 5, 6, 7, 8, 9]);
    expect(c.fat.map((s) => s.x), [7, 8, 9]);
    expect(c.creatineX, [2, 9]);
  });

  test('7 日平均：視窗內至少 3 天紀錄才畫', () {
    final c = buildIntakeChart(ds);
    // 10/1、10/2 只有 1、2 天；10/3 沒紀錄但視窗內只有 2 天；10/4 起有 3 天
    expect(c.kcalAvg.first.x, 3);
    expect(c.kcalAvg.first.y, closeTo((2000 + 2010 + 2030) / 3, 1e-9));
    // 脂肪只有最後三天，所以平均只有 10/10 一個點
    expect(c.fatAvg.map((s) => s.x), [9]);
    expect(c.fatAvg.single.y, 60);
  });

  test('左軸 500 一格；右軸刻度和左軸對齊且是 10 的倍數', () {
    final c = buildIntakeChart(ds);
    expect(c.kcalStep, 500);
    expect(c.kcalMax, 2500); // 2090 × 1.08 = 2257 → 2500
    final ticks = c.kcalMax / c.kcalStep;
    final perTick = c.proteinMax / ticks;
    expect(perTick % 10, 0);
    expect(c.proteinMax, greaterThanOrEqualTo(150 * 1.1));
    expect(c.yToGrams(c.gramsToY(123)), closeTo(123, 1e-9));
  });

  test('每日消耗放進左軸範圍', () {
    final c = buildIntakeChart(ds, expenditureOf: (_) => 2600);
    expect(c.expenditure, hasLength(10));
    expect(c.kcalMax, 3000); // 2600 × 1.08 = 2808 → 3000
  });
}
