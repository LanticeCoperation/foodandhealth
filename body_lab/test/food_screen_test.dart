import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/extra_burn_repository.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/data/profile_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:body_lab/screens/food_screen.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手機尺寸（360 × 780 dp），確認窄螢幕不會溢出。
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  late AppDatabase db;

  setUp(() {
    // 測試結束時 stream 要同步關閉，否則 widget test 會抱怨有 timer 沒跑完。
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  // drift 的查詢在真實的事件迴圈完成，fake async 等不到；
  // 交替用 runAsync 讓查詢跑完、pump 推進動畫。不用 pumpAndSettle，
  // 因為等資料時的轉圈動畫永遠不會停。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScreen(
          repository: FoodRepository(db),
          templates: TemplateRepository(db),
          checks: CheckRepository(db),
          phases: PhaseRepository(db),
          profile: ProfileRepository(db),
          extraBurns: ExtraBurnRepository(db),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  testWidgets('選餐別、輸入熱量就能記錄；滑動刪除可復原', (tester) async {
    usePhoneSize(tester);
    await open(tester);
    expect(find.textContaining('這天還沒有飲食紀錄'), findsOneWidget);

    await tester.tap(find.text('記一餐'));
    await settle(tester);
    await tester.tap(find.text('午餐'));
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '650');
    await tester.enterText(find.widgetWithText(TextFormField, '蛋白質（選填）'), '35');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    // 總量卡片 + 午餐小計 + 那一筆
    expect(find.text('650 kcal'), findsNWidgets(3));
    expect(find.textContaining('蛋白質 35 g'), findsOneWidget);

    // 只輸入熱量也可以
    await tester.tap(find.text('記一餐'));
    await settle(tester);
    await tester.tap(find.text('晚餐'));
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '700');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('700 kcal'), findsNWidgets(2));

    // 沒填熱量不能存
    await tester.tap(find.text('記一餐'));
    await settle(tester);
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('請輸入熱量'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // 關閉表單
    await settle(tester);

    await tester.drag(find.text('700 kcal').last, const Offset(-500, 0));
    await settle(tester);
    expect(find.text('700 kcal'), findsNothing);
    expect(find.textContaining('已刪除 晚餐'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.text('700 kcal'), findsNWidgets(2));

    // 復原提示 4 秒後自動消失（不會卡在畫面上）
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('復原'), findsNothing);

    await close(tester);
  });

  testWidgets('蛋白粉一鍵 +1、肌酸打勾', (tester) async {
    usePhoneSize(tester);
    await open(tester);

    final powder = find.widgetWithText(ActionChip, '蛋白粉（1 匙）');
    expect(powder, findsOneWidget);
    await tester.tap(powder);
    await settle(tester);
    await tester.tap(find.text('蛋白粉（1 匙） · 1'));
    await settle(tester);
    expect(find.text('蛋白粉（1 匙） · 2'), findsOneWidget);
    expect(find.text('24 g'), findsOneWidget); // 蛋白質總計 12 × 2
    expect(find.text('已加入「蛋白粉（1 匙）」'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('已加入「蛋白粉（1 匙）」'), findsNothing);

    // 肌酸打勾：第一次預設 5 g
    final creatine = find.widgetWithText(FilterChip, '肌酸');
    expect(tester.widget<FilterChip>(creatine).selected, isFalse);
    await tester.tap(creatine);
    await settle(tester);
    final checked5 = find.widgetWithText(FilterChip, '肌酸 5g');
    expect(tester.widget<FilterChip>(checked5).selected, isTrue);

    // 長按改成 3 g
    await tester.longPress(checked5);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '3');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.widgetWithText(FilterChip, '肌酸 3g'), findsOneWidget);

    // 另一天打勾：沿用上次記下的 3 g
    await tester.tap(find.byTooltip('前一天'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilterChip, '肌酸'));
    await settle(tester);
    expect(find.widgetWithText(FilterChip, '肌酸 3g'), findsOneWidget);

    // 長按「取消今天的紀錄」
    await tester.longPress(find.widgetWithText(FilterChip, '肌酸 3g'));
    await settle(tester);
    await tester.tap(find.text('取消今天的紀錄'));
    await settle(tester);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '肌酸')).selected,
      isFalse,
    );

    await close(tester);
  });

  testWidgets('快速列的運動：加入後顯示當天總消耗', (tester) async {
    usePhoneSize(tester);
    await open(tester);

    final chip = find.widgetWithText(ActionChip, '運動');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await settle(tester);
    expect(
      find.text('運動 · ${DateTime.now().month}/${DateTime.now().day}'),
      findsOneWidget,
    );

    await tester.enterText(find.widgetWithText(TextFormField, '消耗'), '300');
    await tester.enterText(find.widgetWithText(TextFormField, '備註（選填）'), '游泳');
    await tester.tap(find.text('加入'));
    await settle(tester);
    expect(find.text('游泳'), findsOneWidget); // 面板裡列出剛加的

    // 點那筆 → 帶進表單 → 改成 450
    await tester.tap(find.text('游泳'));
    await settle(tester);
    expect(find.text('儲存修改'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '消耗'), '450');
    await tester.tap(find.text('儲存修改'));
    await settle(tester);
    expect(find.text('450 kcal'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget); // 回到新增模式

    await tester.tapAt(const Offset(10, 10)); // 關閉面板
    await settle(tester);
    expect(find.widgetWithText(ActionChip, '運動 · 450 kcal'), findsOneWidget);

    await close(tester);
  });

  testWidgets('點紀錄編輯熱量；編輯表單裡也能刪除並復原', (tester) async {
    usePhoneSize(tester);
    await open(tester);

    await tester.tap(find.text('記一餐'));
    await settle(tester);
    await tester.tap(find.text('午餐'));
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '600');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    // 點那筆 → 編輯成 650
    await tester.tap(find.text('600 kcal').last);
    await settle(tester);
    expect(find.text('編輯飲食'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '650');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('650 kcal'), findsWidgets);
    expect(find.text('600 kcal'), findsNothing);

    // 再點開 → 刪除
    await tester.tap(find.text('650 kcal').last);
    await settle(tester);
    await tester.tap(find.text('刪除這筆'));
    await settle(tester);
    expect(find.text('650 kcal'), findsNothing);
    expect(find.textContaining('已刪除 午餐'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.text('650 kcal'), findsWidgets);

    await close(tester);
  });
}
