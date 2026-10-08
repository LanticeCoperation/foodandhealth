import 'package:body_lab/data/database.dart';
import 'package:body_lab/main.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('四個頁籤都能打開', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    // 測試環境沒有健康資料外掛，同步會失敗並顯示提示，不影響其他頁。
    await tester.pumpWidget(
      BodyLabApp(services: AppServices(db, HealthService())),
    );

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await settle();
    expect(find.text('身體組成'), findsOneWidget);

    await tester.tap(find.text('紀錄'));
    await settle();
    expect(find.widgetWithText(ActionChip, '蛋白粉（1 匙）'), findsOneWidget);

    await tester.tap(find.text('趨勢'));
    await settle();
    expect(find.text('攝取'), findsOneWidget);

    await tester.tap(find.text('分析'));
    await settle();
    expect(find.textContaining('還沒有實驗階段'), findsOneWidget);
    await tester.tap(find.text('組合分析'));
    await settle();
    expect(find.text('還沒有完整的一週資料。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
