import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:body_lab/screens/quick_screen.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: QuickScreen(
          templates: TemplateRepository(db),
          food: FoodRepository(db),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  /// 「蛋白粉（1 匙）」那一列的 +1 按鈕。
  Finder plusOne(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
    matching: find.byTooltip('+1'),
  );

  testWidgets('按 +1 記一份到今天，顯示今天已幾份，可復原', (tester) async {
    await open(tester);

    expect(find.text('蛋白粉（1 匙）'), findsOneWidget);
    await tester.tap(plusOne('蛋白粉（1 匙）'));
    await settle(tester);
    expect(find.text('已加入「蛋白粉（1 匙）」'), findsOneWidget);
    expect(find.text('今天 1 份'), findsOneWidget);

    await tester.tap(plusOne('蛋白粉（1 匙）'));
    await settle(tester);
    expect(find.text('今天 2 份'), findsOneWidget);

    // 復原最後一次
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.text('今天 1 份'), findsOneWidget);

    await tester.runAsync(() async {
      final entries = await FoodRepository(db).watchDay(DateTime.now()).first;
      expect(entries.single.name, '蛋白粉（1 匙）');
      expect(entries.single.kcal, 60);
    });

    await close(tester);
  });

  testWidgets('新增項目後出現在列表；點列可編輯', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('新增項目'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, '名稱'), '水煮蛋');
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '75');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('水煮蛋'), findsOneWidget);

    await tester.tap(find.text('水煮蛋'));
    await settle(tester);
    expect(find.text('編輯項目'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '名稱'), '茶葉蛋');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('茶葉蛋'), findsOneWidget);
    expect(find.text('水煮蛋'), findsNothing);

    await close(tester);
  });
}
