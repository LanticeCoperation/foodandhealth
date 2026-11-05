import 'package:body_lab/data/database.dart';
import 'package:body_lab/screens/food_entry_sheet.dart';
import 'package:body_lab/services/food_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    AskFoodAi? askAi,
    void Function(FoodEntriesCompanion?)? onResult,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final r = await showFoodEntrySheet(
                    context,
                    defaultTime: DateTime(2026, 11, 5, 12),
                    askAi: askAi,
                  );
                  onResult?.call(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String label) => tester
      .widget<TextFormField>(find.widgetWithText(TextFormField, label))
      .controller!
      .text;

  testWidgets('沒給 askAi：不顯示 AI 按鈕', (tester) async {
    await open(tester);
    expect(find.byTooltip('用 AI 估熱量'), findsNothing);
  });

  testWidgets('查詢成功：熱量、蛋白質、脂肪自動填入', (tester) async {
    await open(
      tester,
      askAi: (_) async =>
          const FoodNutrition(kcal: 620, proteinG: 18.5, fatG: 22),
    );

    await tester.tap(find.byTooltip('用 AI 估熱量'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '一碗滷肉飯');
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();

    expect(textOf(tester, '熱量'), '620');
    expect(textOf(tester, '蛋白質（選填）'), '18.5');
    expect(textOf(tester, '脂肪（選填）'), '22');
  });

  testWidgets('只回熱量：蛋白質、脂肪維持空白', (tester) async {
    await open(tester, askAi: (_) async => const FoodNutrition(kcal: 90));

    await tester.tap(find.byTooltip('用 AI 估熱量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '一顆蘋果');
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();

    expect(textOf(tester, '熱量'), '90');
    expect(textOf(tester, '蛋白質（選填）'), '');
    expect(textOf(tester, '脂肪（選填）'), '');
  });

  testWidgets('查詢失敗：顯示錯誤訊息，欄位不動', (tester) async {
    await open(
      tester,
      askAi: (_) async => throw const FoodAiException('今天的免費額度用完了，等一下再試。'),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '500');
    await tester.tap(find.byTooltip('用 AI 估熱量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '一碗飯');
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();

    expect(find.text('今天的免費額度用完了，等一下再試。'), findsOneWidget);
    expect(textOf(tester, '熱量'), '500');
  });

  testWidgets('其他例外：也顯示訊息，不會整個當掉', (tester) async {
    await open(tester, askAi: (_) async => throw StateError('boom'));

    await tester.tap(find.byTooltip('用 AI 估熱量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '一碗飯');
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();

    expect(find.textContaining('查詢失敗'), findsOneWidget);
  });

  testWidgets('AI 查詢不會自動存檔，仍要按儲存', (tester) async {
    await open(tester, askAi: (_) async => const FoodNutrition(kcal: 300));

    await tester.tap(find.byTooltip('用 AI 估熱量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '一份蛋餅');
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();

    // 查完還留在表單上，沒有被關掉
    expect(find.text('新增飲食'), findsOneWidget);
    expect(find.text('儲存'), findsOneWidget);
  });

  testWidgets('備註會一起存進去；沒填就是 null', (tester) async {
    FoodEntriesCompanion? saved;
    await open(tester, onResult: (r) => saved = r);

    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '400');
    await tester.enterText(
      find.widgetWithText(TextFormField, '備註（選填）'),
      '  半碗飯  ',
    );
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(saved!.note.value, '半碗飯');

    await open(tester, onResult: (r) => saved = r);
    await tester.enterText(find.widgetWithText(TextFormField, '熱量'), '400');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(saved!.note.value, isNull);
  });

  testWidgets('AI 查詢會把備註一起帶入', (tester) async {
    String? asked;
    await open(
      tester,
      askAi: (d) async {
        asked = d;
        return const FoodNutrition(kcal: 300);
      },
    );

    await tester.enterText(find.widgetWithText(TextFormField, '備註（選填）'), '少糖');
    await tester.tap(find.byTooltip('用 AI 估熱量'));
    await tester.pumpAndSettle();
    expect(find.textContaining('會一併參考備註：少糖'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '珍珠奶茶');
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();

    expect(asked, '珍珠奶茶（備註：少糖）');
  });

  testWidgets('按右上角 ✕ 關閉表單，不會存任何東西', (tester) async {
    var called = false;
    FoodEntriesCompanion? saved;
    await open(
      tester,
      onResult: (r) {
        called = true;
        saved = r;
      },
    );

    await tester.tap(find.byTooltip('關閉'));
    await tester.pumpAndSettle();

    expect(find.text('新增飲食'), findsNothing);
    expect(called, isTrue);
    expect(saved, isNull);
  });
}
