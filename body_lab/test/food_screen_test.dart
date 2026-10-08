import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:body_lab/screens/food_screen.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  testWidgets('自訂輸入一筆後出現在列表與總量，滑動刪除可復原', (tester) async {
    await open(tester);
    expect(find.text('這天還沒有紀錄，按 + 新增。'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add).last);
    await settle(tester);
    await tester.tap(find.text('自訂輸入'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, '名稱'), '鮭魚飯糰');
    await tester.enterText(find.widgetWithText(TextFormField, '份量'), '2');
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '200');
    await tester.enterText(find.widgetWithText(TextFormField, '蛋白質'), '8');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    expect(find.text('鮭魚飯糰 ×2'), findsOneWidget);
    expect(find.text('400 kcal'), findsWidgets);
    expect(find.text('400'), findsOneWidget); // 熱量總計
    expect(find.text('16'), findsOneWidget); // 蛋白質總計

    await tester.drag(find.text('鮭魚飯糰 ×2'), const Offset(-500, 0));
    await settle(tester);
    expect(find.text('鮭魚飯糰 ×2'), findsNothing);
    expect(find.text('已刪除「鮭魚飯糰」'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.text('鮭魚飯糰 ×2'), findsOneWidget);

    await close(tester);
  });

  testWidgets('從範本加入、蛋白粉一鍵 +1、肌酸打勾', (tester) async {
    await open(tester);

    // 預設的蛋白粉範本釘選在快速列
    final powderChip = find.widgetWithText(ActionChip, '蛋白粉（1 匙）');
    expect(powderChip, findsOneWidget);

    // 從快速新增面板選範本，份量 ×2
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.text('蛋白粉（1 匙）').last);
    await settle(tester);
    await tester.tap(find.text('×2'));
    await settle(tester);
    await tester.tap(find.textContaining('加入 · 240 kcal'));
    await settle(tester);
    expect(find.text('蛋白粉（1 匙） ×2'), findsOneWidget);
    expect(find.text('蛋白粉（1 匙） · 2'), findsOneWidget);

    // 一鍵 +1
    await tester.tap(find.text('蛋白粉（1 匙） · 2'));
    await settle(tester);
    expect(find.text('蛋白粉（1 匙） · 3'), findsOneWidget);
    expect(find.text('72'), findsOneWidget); // 蛋白質總計 24 × 3

    // 肌酸打勾
    final creatine = find.widgetWithText(FilterChip, '肌酸');
    expect(tester.widget<FilterChip>(creatine).selected, isFalse);
    await tester.tap(creatine);
    await settle(tester);
    expect(tester.widget<FilterChip>(creatine).selected, isTrue);

    await close(tester);
  });
}
