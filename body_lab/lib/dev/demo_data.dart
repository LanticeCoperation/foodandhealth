import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;

import '../data/body_repository.dart';
import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/phase_repository.dart';
import '../data/template_repository.dart';
import '../models/body_metric.dart';
import '../utils/dates.dart';

/// 示範資料共幾天（12 週）。
const int kDemoDays = 84;

/// 一個時期的設定：每天的脂肪 / 除脂變化、要吃的餐、是否吃肌酸。
class _Period {
  const _Period({
    required this.fatPerDay,
    required this.leanPerDay,
    required this.meals,
    required this.creatine,
  });

  final double fatPerDay;
  final double leanPerDay;

  /// （範本名稱, 份量, 幾點吃）
  final List<(String, double, int)> meals;
  final bool creatine;
}

const _templates = <(String, MealType?, double, double, double, double)>[
  // 名稱, 餐別, 熱量, 蛋白質, 碳水, 脂肪（每份）
  ('蛋餅', MealType.breakfast, 350, 12, 40, 15),
  ('奶茶', null, 250, 5, 40, 8),
  ('無糖豆漿', MealType.breakfast, 130, 12, 6, 6),
  ('茶葉蛋', null, 75, 7, 1, 5),
  ('雞腿便當', MealType.lunch, 850, 35, 100, 32),
  ('牛肉麵', null, 700, 35, 80, 25),
  ('雞胸沙拉', null, 350, 40, 15, 14),
  ('地瓜', MealType.snack, 200, 3, 45, 0.5),
  ('香蕉', MealType.snack, 100, 1, 25, 0.3),
  ('餅乾', MealType.snack, 200, 3, 28, 9),
];

const _maintenance = _Period(
  fatPerDay: 0.006,
  leanPerDay: 0,
  creatine: false,
  meals: [
    ('蛋餅', 1, 8),
    ('奶茶', 1, 8),
    ('雞腿便當', 1, 12),
    ('牛肉麵', 1, 19),
    ('餅乾', 1, 15),
  ],
);

const _highProtein = _Period(
  fatPerDay: -0.035,
  leanPerDay: 0.015,
  creatine: true,
  meals: [
    ('無糖豆漿', 1, 7),
    ('茶葉蛋', 2, 7),
    ('雞腿便當', 1, 12),
    ('蛋白粉（1 匙）', 2, 16),
    ('雞胸沙拉', 1, 19),
    ('地瓜', 1, 15),
  ],
);

const _cut = _Period(
  fatPerDay: -0.07,
  leanPerDay: -0.005,
  creatine: true,
  meals: [
    ('無糖豆漿', 1, 7),
    ('茶葉蛋', 2, 7),
    ('雞胸沙拉', 1, 12),
    ('蛋白粉（1 匙）', 2, 16),
    ('雞腿便當', 0.8, 19),
    ('香蕉', 1, 15),
  ],
);

/// 清空資料後產生 12 週擬真資料（固定亂數種子，每次結果相同），
/// 讓沒有健康資料的模擬器也能看到所有畫面。只在 debug 版提供。
///
/// - 第 1～4 週「維持期」：約 2350 kcal、蛋白質約 90 g，脂肪微升
/// - 第 5～8 週「高蛋白 + 肌酸」：約 2000 kcal、蛋白質約 150 g、肌酸；
///   脂肪下降、除脂上升，開始吃肌酸時水分 +0.6 kg
/// - 第 9 週空檔，第 10 週起「減脂」（進行中）：約 1650 kcal，脂肪下降較快
Future<void> seedDemoData({
  required AppDatabase db,
  required BodyRepository body,
  required TemplateRepository templates,
  required CheckRepository checks,
  required PhaseRepository phases,
  DateTime? today,
}) async {
  final end = dateOnly(today ?? DateTime.now());
  final start = addDays(end, -(kDemoDays - 1));
  final random = math.Random(42);

  double gaussian() {
    // Box–Muller
    final u = 1 - random.nextDouble();
    final v = random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  await db.clearAllData();

  for (final (name, meal, kcal, protein, carbs, fat) in _templates) {
    await templates.add(
      MealTemplatesCompanion.insert(
        name: name,
        meal: Value(meal),
        kcal: Value(kcal),
        proteinG: Value(protein),
        carbsG: Value(carbs),
        fatG: Value(fat),
      ),
    );
  }
  final byName = {
    for (final t in await templates.watchTemplates().first) t.name: t,
  };

  // 階段：第 1～4 週、第 5～8 週、第 10 週起 28 天（進行中）
  Future<void> phase(
    String name,
    int fromDay,
    int days, {
    String? hypothesis,
    double? kcal,
    double? protein,
    bool creatine = false,
    String? conclusion,
  }) => phases.save(
    PhasesCompanion.insert(
      name: name,
      startDay: dayKey(addDays(start, fromDay)),
      endDay: dayKey(addDays(start, fromDay + days - 1)),
      hypothesis: Value(hypothesis),
      targetKcal: Value(kcal),
      targetProteinG: Value(protein),
      creatine: Value(creatine),
      conclusion: Value(conclusion),
    ),
  );

  await phase(
    '維持期',
    0,
    28,
    hypothesis: '照平常吃，當作基準線',
    kcal: 2350,
    protein: 90,
    conclusion: '體重幾乎不動，脂肪微升',
  );
  await phase(
    '高蛋白 + 肌酸',
    28,
    28,
    hypothesis: '蛋白質提高到 150 g、每天肌酸，除脂體重會上升',
    kcal: 2000,
    protein: 150,
    creatine: true,
    conclusion: '前一週水分上升，之後脂肪穩定下降',
  );
  await phase(
    '減脂',
    63,
    28,
    hypothesis: '熱量降到 1650，看除脂體重能不能守住',
    kcal: 1650,
    protein: 150,
    creatine: true,
  );

  _Period periodOf(int day) =>
      day < 28 ? _maintenance : (day < 63 ? _highProtein : _cut);

  var fat = 16.0;
  var lean = 60.0;
  var water = 0.0;
  final metrics = <BodyMetric>[];

  for (var i = 0; i < kDemoDays; i++) {
    final day = addDays(start, i);
    final p = periodOf(i);
    fat += p.fatPerDay + gaussian() * 0.01;
    lean += p.leanPerDay + gaussian() * 0.01;

    // 開始吃肌酸的前 5 天水分逐漸增加 0.6 kg，之後維持
    final creatineWater = i < 28 ? 0.0 : math.min(0.6, (i - 27) * 0.12);
    // 偶爾吃太鹹，隔天水分暴增
    water = random.nextDouble() < 0.06 ? 1.0 + random.nextDouble() * 0.4 : 0;
    final weight = fat + lean + creatineWater + water + gaussian() * 0.25;

    if (random.nextDouble() > 0.1) {
      // 體脂計 BIA 量測誤差約 ±0.6%；除脂體重由 App 推算
      final bf = (fat / (fat + lean)) * 100 + gaussian() * 0.6;
      metrics.add(
        BodyMetric(
          date: day,
          measuredAt: day.add(Duration(hours: 7, minutes: random.nextInt(40))),
          weightKg: double.parse(weight.toStringAsFixed(1)),
          bodyFatPercent: double.parse(bf.toStringAsFixed(1)),
          leanMassKg: double.parse(
            (weight * (1 - bf / 100)).toStringAsFixed(1),
          ),
          leanMassEstimated: true,
        ),
      );
    }

    if (random.nextDouble() > 0.15) {
      for (final (name, servings, hour) in p.meals) {
        // 少數幾餐份量有變化
        final s = random.nextDouble() < 0.2
            ? servings * (random.nextBool() ? 1.5 : 0.5)
            : servings;
        await templates.addEntryFromTemplate(
          byName[name]!,
          eatenAt: day.add(Duration(hours: hour, minutes: random.nextInt(50))),
          servings: s,
        );
      }
    }

    if (p.creatine && random.nextDouble() > 0.1) {
      await checks.set(day, CheckItem.creatine, true);
    }
  }

  await body.replaceFrom(start, metrics);
}
