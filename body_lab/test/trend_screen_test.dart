import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/data/body_repository.dart';
import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/screens/trend_screen.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
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

  testWidgets('有資料時畫出疊加圖與摘要，可切換區間', (tester) async {
    usePhoneSize(tester);
    final body = BodyRepository(db, _NoSource());
    final food = FoodRepository(db);
    final checks = CheckRepository(db);
    final today = dateOnly(DateTime.now());

    await tester.runAsync(() async {
      final start = addDays(today, -20);
      await body.replaceFrom(start, [
        for (var i = 0; i <= 20; i++)
          BodyMetric(
            date: addDays(start, i),
            measuredAt: addDays(start, i).add(const Duration(hours: 7)),
            weightKg: 80 - i * 0.05,
            bodyFatPercent: 20,
            leanMassKg: (80 - i * 0.05) * 0.8,
          ),
      ]);
      for (var i = 0; i < 10; i++) {
        await food.add(
          FoodEntriesCompanion.insert(
            eatenAt: addDays(today, -i).add(const Duration(hours: 12)),
            meal: MealType.lunch,
            name: '便當',
            kcal: const Value(2000),
            proteinG: const Value(140),
          ),
        );
      }
      await checks.set(today, CheckItem.creatine, true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TrendScreen(
          dataset: DatasetRepository(
            db,
            body,
            food,
            checks,
            PhaseRepository(db),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('最近 30 天'), findsOneWidget);
    expect(find.text('2000 kcal'), findsOneWidget); // 平均熱量
    expect(find.text('21 / 30 天'), findsOneWidget); // 有量體重
    expect(find.text('1 / 30 天'), findsOneWidget); // 肌酸

    await tester.tap(find.text('90 天'));
    await settle(tester);
    expect(find.text('最近 90 天'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
