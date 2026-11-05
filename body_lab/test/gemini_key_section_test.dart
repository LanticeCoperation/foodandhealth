import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/settings_repository.dart';
import 'package:body_lab/widgets/gemini_key_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GeminiKeySection(settings: settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('還沒設定：欄位是空的，沒有清除按鈕', (tester) async {
    await show(tester);

    expect(find.text('已設定'), findsNothing);
    expect(find.text('清除'), findsNothing);
  });

  testWidgets('輸入後儲存：存進設定並顯示已設定', (tester) async {
    await show(tester);

    await tester.enterText(find.byType(TextField), 'AIza-test');
    await tester.tap(find.text('儲存 API key'));
    await tester.pumpAndSettle();

    expect(await settings.geminiApiKey(), 'AIza-test');
    expect(find.text('已設定'), findsOneWidget);
  });

  testWidgets('已設定過：一開啟就顯示已設定，但不顯示 key 本身', (tester) async {
    await settings.setGeminiApiKey('AIza-secret');
    await show(tester);

    expect(find.text('已設定'), findsOneWidget);
    expect(find.text('AIza-secret'), findsNothing);
  });

  testWidgets('清除：設定被刪掉', (tester) async {
    await settings.setGeminiApiKey('AIza-secret');
    await show(tester);

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(await settings.geminiApiKey(), isNull);
    expect(find.text('已設定'), findsNothing);
  });
}
