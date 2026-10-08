import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/data/body_repository.dart';
import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/data/profile_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/screens/food_screen.dart';
import 'package:body_lab/screens/phases_screen.dart';
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
  late FoodRepository food;
  late PhaseRepository phases;
  late DatasetRepository dataset;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    food = FoodRepository(db);
    phases = PhaseRepository(db);
    dataset = DatasetRepository(
      db,
      BodyRepository(db, _NoSource()),
      food,
      CheckRepository(db),
      phases,
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

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  testWidgets('建立階段 → 卡片顯示進度與執行率 → 詳情頁', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhasesScreen(
            phases: phases,
            dataset: dataset,
            profile: ProfileRepository(db),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('還沒有實驗階段'), findsOneWidget);

    await tester.tap(find.text('新增階段'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, '名稱'), '高蛋白');
    await tester.enterText(
      find.widgetWithText(TextFormField, '每日熱量目標'),
      '2000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '每日蛋白質目標'),
      '150',
    );
    await tester.tap(find.text('儲存'));
    await settle(tester);

    expect(find.text('高蛋白'), findsOneWidget);
    expect(find.text('進行中'), findsOneWidget);
    expect(find.text('第 1 / 28 天'), findsOneWidget);
    expect(find.text('熱量 2000±10% 達標 0/1 天'), findsOneWidget);

    await tester.runAsync(
      () => food.add(
        FoodEntriesCompanion.insert(
          eatenAt: DateTime.now(),
          meal: MealType.lunch,
          name: '雞胸便當',
          kcal: const Value(2100),
          proteinG: const Value(160),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('熱量 2000±10% 達標 1/1 天'), findsOneWidget);
    expect(find.text('蛋白質 ≥150g 達標 1/1 天'), findsOneWidget);

    await tester.tap(find.text('高蛋白'));
    await settle(tester);
    expect(find.byType(LineChart), findsNWidgets(2)); // 身體 + 攝取
    await tester.scrollUntilVisible(find.text('階段期間'), 300);
    await settle(tester);
    expect(find.text('階段期間'), findsOneWidget);

    await close(tester);
  });

  testWidgets('飲食頁顯示當天階段的目標', (tester) async {
    usePhoneSize(tester);
    final today = dateOnly(DateTime.now());
    await tester.runAsync(
      () => phases.save(
        PhasesCompanion.insert(
          name: '減脂',
          startDay: dayKey(today),
          endDay: dayKey(addDays(today, 27)),
          targetKcal: const Value(1800),
          targetProteinG: const Value(140),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FoodScreen(
          repository: food,
          templates: TemplateRepository(db),
          checks: CheckRepository(db),
          phases: phases,
          profile: ProfileRepository(db),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('階段：減脂'), findsOneWidget);
    expect(find.text('0 / 1800 kcal'), findsOneWidget);
    expect(find.text('0 / 140 g'), findsOneWidget);

    await close(tester);
  });
}
