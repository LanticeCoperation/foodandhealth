import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
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
    expect(find.textContaining('這天還沒有紀錄'), findsOneWidget);

    await tester.tap(find.text('記錄'));
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
    await tester.tap(find.text('記錄'));
    await settle(tester);
    await tester.tap(find.text('晚餐'));
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '700');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('700 kcal'), findsNWidgets(2));

    // 沒填熱量不能存
    await tester.tap(find.text('記錄'));
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
    expect(find.text('48 g'), findsOneWidget); // 蛋白質總計 24 × 2
    expect(find.text('已加入「蛋白粉（1 匙）」'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('已加入「蛋白粉（1 匙）」'), findsNothing);

    // 肌酸打勾
    final creatine = find.widgetWithText(FilterChip, '肌酸');
    expect(tester.widget<FilterChip>(creatine).selected, isFalse);
    await tester.tap(creatine);
    await settle(tester);
    expect(tester.widget<FilterChip>(creatine).selected, isTrue);

    await close(tester);
  });
}
