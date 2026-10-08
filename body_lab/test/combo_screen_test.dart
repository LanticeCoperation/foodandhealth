import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/data/body_repository.dart';
import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/data/profile_repository.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/screens/combo_screen.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSource implements BodyMetricsSource {
  @override
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start) async => [];
}

/// 手機尺寸（360 × 780 dp），確認窄螢幕不會溢出。
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('6 週資料：高蛋白 + 肌酸的週脂肪下降較多', (tester) async {
    usePhoneSize(tester);
    final body = BodyRepository(db, _NoSource());
    final food = FoodRepository(db);
    final checks = CheckRepository(db);
    final today = dateOnly(DateTime.now());
    final start = addDays(today, -41); // 42 天 = 6 週

    // 前 3 週：蛋白質 80 g、沒肌酸、脂肪每天 +0.01
    // 後 3 週：蛋白質 160 g、肌酸、脂肪每天 -0.03
    await tester.runAsync(() async {
      var fat = 16.0;
      final metrics = <BodyMetric>[];
      for (var i = 0; i < 42; i++) {
        final d = addDays(start, i);
        final late = i >= 21;
        fat += late ? -0.03 : 0.01;
        const lean = 60.0;
        metrics.add(
          BodyMetric(
            date: d,
            measuredAt: d,
            weightKg: fat + lean,
            bodyFatPercent: fat / (fat + lean) * 100,
            leanMassKg: lean,
          ),
        );
        await food.add(
          FoodEntriesCompanion.insert(
            eatenAt: d.add(const Duration(hours: 12)),
            meal: MealType.lunch,
            name: late ? '雞胸' : '麵',
            kcal: const Value(2000),
            proteinG: Value(late ? 160 : 80),
          ),
        );
        if (late) await checks.set(d, CheckItem.creatine, true);
      }
      await body.replaceFrom(start, metrics);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComboScreen(
            dataset: DatasetRepository(
              db,
              body,
              food,
              checks,
              PhaseRepository(db),
            ),
            profile: ProfileRepository(db),
          ),
        ),
      ),
    );
    await settle(tester);

    // 預設：橫軸蛋白質 g/kg、縱軸肌酸、結果脂肪重
    expect(find.textContaining('共 6 週，可用 5 週'), findsOneWidget);
    // 80 g / 76 kg ≈ 1.05 → <1.2；160 g / 75 kg ≈ 2.1 → 1.6–2.2
    expect(find.text('+0.07'), findsOneWidget); // 無肌酸、低蛋白：每週 +0.07
    // 有肌酸、高蛋白：第 4 週的上週末平均還在上升期，只降 0.09；
    // 第 5、6 週各降 0.21 → 平均 (-0.09 - 0.21 - 0.21) / 3 = -0.17
    expect(find.text('-0.17'), findsOneWidget);
    expect(find.text('n=2'), findsOneWidget);
    expect(find.text('n=3'), findsOneWidget);

    await tester.tap(find.text('除脂體重'));
    await settle(tester);
    expect(find.textContaining('0.00'), findsNWidgets(2)); // 除脂體重不變

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
