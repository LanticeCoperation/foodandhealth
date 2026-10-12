import 'package:body_lab/data/body_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/screens/body_screen.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:body_lab/theme/app_theme.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('每天的卡片顯示當天攝取熱量、蛋白質、脂肪總量', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final today = dateOnly(DateTime.now());
    final yesterday = addDays(today, -1);
    await tester.runAsync(() async {
      for (final day in [today, yesterday]) {
        await db
            .into(db.dailyBodyMetrics)
            .insert(
              DailyBodyMetricsCompanion.insert(
                day: dayKey(day),
                measuredAt: day.add(const Duration(hours: 7)),
                weightKg: 70,
                syncedAt: DateTime.now(),
              ),
            );
      }
      final food = FoodRepository(db);
      await food.add(
        FoodEntriesCompanion.insert(
          eatenAt: today.add(const Duration(hours: 8)),
          meal: MealType.breakfast,
          name: '早餐',
          kcal: const Value(500),
          proteinG: const Value(40),
          fatG: const Value(15.4),
        ),
      );
      await food.add(
        FoodEntriesCompanion.insert(
          eatenAt: today.add(const Duration(hours: 12)),
          meal: MealType.lunch,
          name: '午餐',
          kcal: const Value(700),
          proteinG: const Value(35),
        ),
      );
    });

    // 測試環境沒有健康資料外掛，同步會失敗，畫面顯示快取。
    final health = HealthService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: BodyScreen(
          health: health,
          repository: BodyRepository(db, health),
          food: FoodRepository(db),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('1200 kcal'), findsOneWidget);
    expect(find.text('75 g'), findsOneWidget);
    expect(find.text('15 g'), findsOneWidget);
    // 只有今天有飲食紀錄，昨天的卡片不顯示攝取列
    expect(find.text('攝取熱量'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
