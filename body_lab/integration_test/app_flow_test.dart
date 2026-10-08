import 'package:body_lab/data/database.dart';
import 'package:body_lab/main.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_health.dart';

/// 在模擬器 / 實機上跑完整的 App，走過主要使用流程。
///
///   flutter test integration_test -d <裝置 id>
///
/// 健康資料用 [FakeHealthService]，資料庫用記憶體，不會動到裝置上的真實資料。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppServices services;

  Future<void> launch(WidgetTester tester, FakeHealthService health) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    services = AppServices(db, health);
    await tester.pumpWidget(BodyLabApp(services: services));
    await waitFor(tester, find.text('身體組成'));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }

  testWidgets('身體：手動記錄體重 → 顯示在列表 → 刪除', (tester) async {
    final yesterday = addDays(dateOnly(DateTime.now()), -1);
    await launch(
      tester,
      FakeHealthService(
        samples: [
          // 體脂計寫入的紀錄，Body Lab 不能刪
          BodySample(
            BodySampleType.weight,
            yesterday.add(const Duration(hours: 7)),
            75.2,
          ),
          BodySample(
            BodySampleType.bodyFat,
            yesterday.add(const Duration(hours: 7)),
            20.0,
          ),
        ],
      ),
    );
    await waitFor(tester, find.text('75.2'));

    await tester.tap(find.text('記錄體重'));
    await waitFor(tester, find.widgetWithText(TextFormField, '體重'));
    await tester.enterText(find.widgetWithText(TextFormField, '體重'), '74.3');
    await tester.enterText(
      find.widgetWithText(TextFormField, '體脂率（選填）'),
      '18.4',
    );
    await tester.tap(find.text('儲存'));

    await waitFor(tester, find.text('已記錄 74.3 kg、體脂 18.4%'));
    await waitFor(tester, find.text('74.3'));
    expect(find.text('手動'), findsOneWidget);
    expect(find.text('18.4%'), findsOneWidget);

    // 體脂計的紀錄只能說明，不能刪
    await tester.tap(find.text('75.2'));
    await waitFor(tester, find.textContaining('Body Lab 不能刪除'));
    expect(find.text('刪除這筆'), findsNothing);
    await dismissSheet(tester);

    // 手動記錄的可以刪
    await tester.tap(find.text('74.3'));
    await waitFor(tester, find.text('刪除這筆'));
    await tester.tap(find.text('刪除這筆'));
    await waitFor(tester, find.text('刪除這筆體重？'));
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));

    await waitFor(tester, find.text('已刪除'));
    await waitGone(tester, find.text('74.3'));
    expect(find.text('75.2'), findsOneWidget);

    await close(tester);
  });

  testWidgets('紀錄：記一餐 → 編輯 → 刪除並復原；蛋白粉與運動', (tester) async {
    await launch(tester, FakeHealthService());
    await tester.tap(find.text('紀錄'));
    await waitFor(tester, find.textContaining('這天還沒有飲食紀錄'));

    // 記一餐
    await tester.tap(find.text('記一餐'));
    await waitFor(tester, find.widgetWithText(TextFormField, '熱量'));
    await tester.tap(find.text('午餐'));
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '650');
    await tester.enterText(find.widgetWithText(TextFormField, '蛋白質（選填）'), '35');
    await tester.tap(find.text('儲存'));
    await waitFor(tester, find.text('650 kcal'));
    expect(find.textContaining('蛋白質 35 g'), findsOneWidget);

    // 點那筆編輯成 700
    await tester.tap(find.text('650 kcal').last);
    await waitFor(tester, find.text('編輯飲食'));
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '700');
    await tester.tap(find.text('儲存'));
    await waitFor(tester, find.text('700 kcal'));
    expect(find.text('650 kcal'), findsNothing);

    // 編輯表單裡刪除，再復原
    await tester.tap(find.text('700 kcal').last);
    await waitFor(tester, find.text('刪除這筆'));
    await tester.tap(find.text('刪除這筆'));
    await waitFor(tester, find.textContaining('已刪除 午餐'));
    expect(find.text('700 kcal'), findsNothing);
    await tester.tap(find.text('復原'));
    await waitFor(tester, find.text('700 kcal'));

    // 蛋白粉一鍵加入
    await tester.tap(find.widgetWithText(ActionChip, '蛋白粉（1 匙）'));
    await waitFor(tester, find.text('蛋白粉（1 匙） · 1'));

    // 運動
    await tester.tap(find.widgetWithText(ActionChip, '運動'));
    await waitFor(tester, find.widgetWithText(TextFormField, '消耗'));
    await tester.enterText(find.widgetWithText(TextFormField, '消耗'), '300');
    await tester.enterText(find.widgetWithText(TextFormField, '備註（選填）'), '游泳');
    await tester.tap(find.text('加入'));
    await waitFor(tester, find.text('游泳'));
    await dismissSheet(tester);
    await waitFor(tester, find.widgetWithText(ActionChip, '運動 · 300 kcal'));

    await close(tester);
  });

  testWidgets('分析：建立階段 → 紀錄頁顯示階段目標', (tester) async {
    await launch(tester, FakeHealthService());
    await tester.tap(find.text('分析'));
    await waitFor(tester, find.textContaining('還沒有實驗階段'));

    await tester.tap(find.text('新增階段'));
    await waitFor(tester, find.widgetWithText(TextFormField, '名稱'));
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
    await waitFor(tester, find.text('高蛋白'));
    expect(find.text('進行中'), findsOneWidget);
    expect(find.text('第 1 / 28 天'), findsOneWidget);

    await tester.tap(find.text('紀錄'));
    await waitFor(tester, find.text('階段：高蛋白'));
    expect(find.text('0 / 2000 kcal'), findsOneWidget);
    expect(find.text('0 / 150 g'), findsOneWidget);

    await close(tester);
  });

  testWidgets('趨勢：從健康資料同步的體重與飲食畫成圖表與摘要', (tester) async {
    final today = dateOnly(DateTime.now());
    await launch(
      tester,
      FakeHealthService(
        samples: [
          for (var i = 0; i <= 20; i++) ...[
            BodySample(
              BodySampleType.weight,
              addDays(today, -i).add(const Duration(hours: 7)),
              79 + i * 0.05,
            ),
            BodySample(
              BodySampleType.bodyFat,
              addDays(today, -i).add(const Duration(hours: 7)),
              20,
            ),
          ],
        ],
      ),
    );
    for (var i = 0; i < 10; i++) {
      await services.food.add(
        FoodEntriesCompanion.insert(
          eatenAt: addDays(today, -i).add(const Duration(hours: 12)),
          meal: MealType.lunch,
          name: '便當',
          kcal: const Value(2000),
          proteinG: const Value(140),
        ),
      );
    }

    await tester.tap(find.text('趨勢'));
    await waitFor(tester, find.byType(LineChart));
    expect(find.text('攝取'), findsOneWidget);

    await scrollTo(tester, find.text('有吃肌酸'));
    expect(find.text('最近 30 天'), findsOneWidget);
    expect(find.text('2000 kcal'), findsOneWidget); // 平均熱量
    expect(find.text('21 / 30 天'), findsOneWidget); // 有量體重

    await close(tester);
  });

  testWidgets('個人資料：填寫後儲存 TDEE', (tester) async {
    await launch(tester, FakeHealthService());
    await tester.tap(find.byTooltip('個人資料與設定'));
    await waitFor(tester, find.widgetWithText(TextFormField, '年齡'));

    await tester.tap(find.text('男'));
    await tester.enterText(find.widgetWithText(TextFormField, '年齡'), '30');
    await tester.enterText(find.widgetWithText(TextFormField, '身高'), '175');
    await tester.enterText(find.widgetWithText(TextFormField, '體重'), '72');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(tester, find.textContaining('基礎代謝'));

    final save = find.widgetWithText(FilledButton, '儲存');
    await scrollTo(tester, save);
    await tester.tap(save);
    await waitFor(tester, find.text('身體組成'));

    // 再打開，上方顯示已存的設定
    await tester.tap(find.byTooltip('個人資料與設定'));
    await waitFor(tester, find.textContaining('以 72.0 kg 計算'));

    await close(tester);
  });
}

/// 等到 [finder] 出現。真機上資料庫查詢與動畫要真的花時間，
/// 而轉圈動畫不會停，所以不用 pumpAndSettle，改成輪詢。
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('等不到：$finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // 再給動畫一點時間跑完，避免點到還在滑入的元件
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

Future<void> waitGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('一直還在：$finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// 點表單外的遮罩關閉底部面板。
Future<void> dismissSheet(WidgetTester tester) async {
  final barrier = find.byType(ModalBarrier).last;
  await tester.tapAt(tester.getTopLeft(barrier) + const Offset(20, 120));
  await waitGone(tester, find.byType(BottomSheet));
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await waitFor(tester, finder);
}
