import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
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

  testWidgets('新增一筆後出現在列表與總量，滑動刪除可復原', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FoodScreen(repository: FoodRepository(db))),
    );
    await settle(tester);
    expect(find.text('這天還沒有紀錄，按 + 新增。'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, '名稱'), '蛋白粉');
    await tester.enterText(find.widgetWithText(TextFormField, '份量'), '2');
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '120');
    await tester.enterText(find.widgetWithText(TextFormField, '蛋白質'), '24');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    expect(find.text('蛋白粉 ×2'), findsOneWidget);
    expect(find.text('240 kcal'), findsWidgets);
    expect(find.text('240'), findsOneWidget); // 熱量總計
    expect(find.text('48'), findsOneWidget); // 蛋白質總計

    await tester.drag(find.text('蛋白粉 ×2'), const Offset(-500, 0));
    await settle(tester);
    expect(find.text('蛋白粉 ×2'), findsNothing);
    expect(find.text('已刪除「蛋白粉」'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.text('蛋白粉 ×2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
