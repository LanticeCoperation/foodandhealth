import 'package:body_lab/screens/body_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('體重必填、體脂率選填，回傳輸入的值', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    BodyEntry? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async =>
                    result = await showBodyEntrySheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 沒填體重不能存
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('請輸入 20–300'), findsOneWidget);

    // 體脂率超出範圍
    await tester.enterText(find.widgetWithText(TextFormField, '體重'), '74.3');
    await tester.enterText(find.widgetWithText(TextFormField, '體脂率（選填）'), '90');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('請輸入 2–70'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '體脂率（選填）'),
      '18.4',
    );
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(result!.weightKg, 74.3);
    expect(result!.bodyFatPercent, 18.4);
    expect(
      result!.time.difference(DateTime.now()).inMinutes.abs(),
      lessThan(2),
    );
  });
}
