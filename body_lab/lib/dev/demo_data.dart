import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;

import '../data/activity_repository.dart';
import '../data/body_repository.dart';
import '../analysis/tdee.dart';
import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/phase_repository.dart';
import '../data/profile_repository.dart';
import '../data/template_repository.dart';
import '../models/body_metric.dart';
import '../utils/dates.dart';

/// 示範資料共幾天（12 週）。
const int kDemoDays = 84;

/// 一個時期的設定：每天的脂肪 / 除脂變化、每餐熱量與蛋白質、蛋白粉幾匙、是否吃肌酸。
class _Period {
  const _Period({
    required this.fatPerDay,
    required this.leanPerDay,
    required this.meals,
    required this.powderScoops,
    required this.creatine,
  });

  final double fatPerDay;
  final double leanPerDay;

  /// （餐別, 熱量, 蛋白質, 幾點吃）
  final List<(MealType, double, double, int)> meals;
  final int powderScoops;
  final bool creatine;
}

// 約 2350 kcal、蛋白質 90 g（TDEE 約 2320，略有盈餘）
const _maintenance = _Period(
  fatPerDay: 0.006,
  leanPerDay: 0,
  creatine: false,
  powderScoops: 0,
  meals: [
    (MealType.breakfast, 600, 17, 8),
    (MealType.lunch, 850, 35, 12),
    (MealType.snack, 200, 3, 15),
    (MealType.dinner, 700, 35, 19),
  ],
);

// 約 1920 kcal、蛋白質 150 g（含蛋白粉 2 匙）
const _highProtein = _Period(
  fatPerDay: -0.035,
  leanPerDay: 0.015,
  creatine: true,
  powderScoops: 2,
  meals: [
    (MealType.breakfast, 280, 26, 7),
    (MealType.lunch, 850, 35, 12),
    (MealType.snack, 200, 3, 15),
    (MealType.dinner, 350, 40, 19),
  ],
);

// 約 1650 kcal、蛋白質 145 g（含蛋白粉 2 匙）
const _cut = _Period(
  fatPerDay: -0.07,
  leanPerDay: -0.005,
  creatine: true,
  powderScoops: 2,
  meals: [
    (MealType.breakfast, 280, 26, 7),
    (MealType.lunch, 350, 40, 12),
    (MealType.snack, 100, 1, 15),
    (MealType.dinner, 680, 28, 19),
  ],
);

/// 清空資料後產生 12 週擬真資料（固定亂數種子，每次結果相同），
/// 讓沒有健康資料的模擬器也能看到所有畫面。只在 debug 版提供。
///
/// 飲食只有「餐別 + 熱量 + 蛋白質」，加上蛋白粉一鍵 +1；個人資料設為
/// 男性 35 歲、175 cm、輕度活動，固定 TDEE 約 2320 kcal；每日消耗用
/// Apple Watch 模式（活動消耗平常約 420 kcal，週一 / 三 / 五運動日多約 280）。
///
/// - 第 1～4 週「維持期」：約 2350 kcal、蛋白質約 90 g，脂肪微升
/// - 第 5～8 週「高蛋白 + 肌酸」：約 2000 kcal、蛋白質約 150 g、肌酸；
///   脂肪下降、除脂上升，開始吃肌酸時水分 +0.6 kg
/// - 第 9 週空檔，第 10 週起「減脂」（進行中）：約 1650 kcal，脂肪下降較快
Future<void> seedDemoData({
  required AppDatabase db,
  required BodyRepository body,
  required FoodRepository food,
  required TemplateRepository templates,
  required CheckRepository checks,
  required PhaseRepository phases,
  required ProfileRepository profile,
  required ActivityRepository activity,
  DateTime? today,
}) async {
  final end = dateOnly(today ?? DateTime.now());
  final start = addDays(end, -(kDemoDays - 1));
  final random = math.Random(42);
  // 活動消耗用獨立的亂數，不影響其他資料的序列
  final activityRandom = math.Random(7);

  double gaussian() {
    // Box–Muller
    final u = 1 - random.nextDouble();
    final v = random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  await db.clearAllData();

  // 清空後只剩預設的蛋白粉項目
  final powder = (await templates.watchPinned().first).single;

  const age = 35;
  const height = 175.0;
  const startWeight = 76.0;
  await profile.save(
    sex: Sex.male,
    birthYear: end.year - age,
    heightCm: height,
    activity: ActivityLevel.light,
    weightKg: startWeight,
    tdeeKcal: estimateTdee(
      sex: Sex.male,
      weightKg: startWeight,
      heightCm: height,
      age: age,
      activity: ActivityLevel.light,
    ),
  );

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
  final active = <DateTime, double>{};

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
      for (final (meal, kcal, protein, hour) in p.meals) {
        // 每餐熱量上下浮動約 15%，偶爾沒填蛋白質
        final factor = 1 + gaussian() * 0.15;
        await food.add(
          FoodEntriesCompanion.insert(
            eatenAt: day.add(
              Duration(hours: hour, minutes: random.nextInt(50)),
            ),
            meal: meal,
            name: meal.label,
            kcal: Value((kcal * factor / 10).roundToDouble() * 10),
            proteinG: Value(
              random.nextDouble() < 0.1
                  ? null
                  : (protein * factor).roundToDouble(),
            ),
          ),
        );
      }
      for (var k = 0; k < p.powderScoops; k++) {
        final at = day.add(Duration(hours: 16 + k * 4));
        await templates.addEntryFromTemplate(
          powder,
          eatenAt: at,
          meal: MealType.forTime(at),
        );
      }
    }

    // Apple Watch 活動消耗；約 5% 的天沒戴
    if (activityRandom.nextDouble() > 0.05) {
      final workout = const {1, 3, 5}.contains(day.weekday) ? 280 : 0;
      final noise = (activityRandom.nextDouble() - 0.5) * 240;
      active[day] = (420 + workout + noise).roundToDouble();
    }

    if (p.creatine && random.nextDouble() > 0.1) {
      await checks.set(day, CheckItem.creatine, true);
    }
  }

  await body.replaceFrom(start, metrics);
  await activity.replaceFrom(start, active);
}
