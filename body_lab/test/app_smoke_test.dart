import 'package:body_lab/data/database.dart';
import 'package:body_lab/main.dart';
import 'package:body_lab/services/catalog_updater.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('五個頁籤都能打開', (tester) async {
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
    // 啟動時套用內建目錄，再從遠端抓到較新版本：提示新增的項目
    final updater = CatalogUpdater(
      db,
      loadBundled: () async => '{"version": 1, "items": []}',
      fetchRemote: () async => '{"version": 2, "items": [{"key": "yogurt", "name": "無糖優格", "kcal": 60}]}',
    );
    await tester.pumpWidget(
      BodyLabApp(services: AppServices(db, HealthService(), catalog: updater)),
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
    expect(find.text('預設項目已更新：新增 1 個'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle();

    await tester.tap(find.text('紀錄'));
    await settle();
    expect(find.widgetWithText(ActionChip, '運動'), findsOneWidget);

    await tester.tap(find.text('快速'));
    await settle();
    expect(find.text('蛋白粉（1 匙）'), findsOneWidget);
    expect(find.text('無糖優格'), findsOneWidget);
    expect(find.byTooltip('+1'), findsWidgets);

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
