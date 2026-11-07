import 'package:body_lab/data/database.dart';
import 'package:body_lab/main.dart';
import 'package:body_lab/services/catalog_updater.dart';
import 'package:body_lab/services/sync_config.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_health.dart';

/// 在模擬器上對真的自架 Supabase 跑一次完整流程。
///
/// 這支要證明的是純 Dart 的 sync_live_test 證明不了的那一段：
/// App 跑在 Android 上真的連得到伺服器——明文 HTTP 的放行、10.0.2.2
/// 這個宿主位址、整包外掛堆疊都對。
///
/// 前置：本機 stack 在跑，而且 infra/supabase/scripts/admin.sh 建好了
/// dad@example.com / mom@example.com 並加進同一個家庭。
///
/// ```
/// flutter test integration_test/sync_flow_test.dart -d emulator-5554 \
///   --dart-define=SUPABASE_URL=http://10.0.2.2:8000 \
///   --dart-define=SUPABASE_KEY=<publishable key>
/// ```
///
/// 所有真的網路 I/O 都要包在 [WidgetTester.runAsync] 裡。
/// testWidgets 預設跑在假的非同步時鐘上，直接 await HTTP 會卡住不動。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 整合測試不會走 App 的 main()，所以要自己初始化一次。
  // 少了這步，SyncController 取 Supabase.instance.client 會炸在
  // AppServices 的建構子裡。
  setUpAll(() async {
    await Supabase.initialize(
      url: SyncConfig.url,
      publishableKey: SyncConfig.publishableKey,
    );
  });

  const dad = 'dad@example.com';
  const mom = 'mom@example.com';
  const password = 'DemoPass-1234';

  testWidgets('Android 上：登入 → 記一餐 → 上傳 → 家人讀得到 → 家人頁畫得出來', (
    tester,
  ) async {
    expect(
      SyncConfig.configured,
      isTrue,
      reason: '這支測試要帶 --dart-define 的 SUPABASE_URL / SUPABASE_KEY',
    );

    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final services = AppServices(
      db,
      FakeHealthService(),
      catalog: CatalogUpdater(
        db,
        fetchRemote: () async => throw Exception('整合測試不連網'),
      ),
    );
    expect(services.sync.available, isTrue);

    await tester.runAsync(() async {
      await services.sync.signIn(dad, password);
      expect(
        services.sync.signedIn,
        isTrue,
        reason: services.sync.lastMessage ?? '登入失敗',
      );

      final localId = await services.food.add(
        FoodEntriesCompanion.insert(
          eatenAt: DateTime.now(),
          meal: MealType.lunch,
          name: 'EmulatorLunch',
          kcal: const Value(640),
          proteinG: const Value(42),
        ),
      );
      await services.sync.syncNow();
      expect(
        services.sync.lastMessage,
        isNot(contains('失敗')),
        reason: services.sync.lastMessage,
      );

      // 用這次寫入的那一列的 syncId 查，不要用名稱也不要假設只有一列——
      // 這個帳號在伺服器上還留著前幾次跑的資料，登入時會被拉回來。
      final syncId =
          (await (db.select(db.foodEntries)
                    ..where((r) => r.id.equals(localId)))
                  .getSingle())
              .syncId;
      expect(syncId, isNotNull);

      // 換家人的帳號從伺服器讀
      final asMom = SupabaseClient(SyncConfig.url, SyncConfig.publishableKey);
      await asMom.auth.signInWithPassword(email: mom, password: password);
      final seen = await asMom
          .from('food_entries')
          .select('sync_id,name')
          .eq('sync_id', syncId!);
      expect(seen, hasLength(1), reason: '家人應該讀得到阿爸這次記的那一筆');
      expect(seen.single['name'], 'EmulatorLunch');
      await asMom.dispose();
    });

    // App 的家人頁也要真的畫得出來
    await tester.pumpWidget(BodyLabApp(services: services));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('身體組成'), findsWidgets);

    await tester.tap(find.byIcon(Icons.person_outline).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 同步區塊在設定頁的下半部，要先捲過去才畫得出來
    await tester.scrollUntilVisible(
      find.text('跨裝置同步'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('跨裝置同步'), findsOneWidget);

    await tester.tap(find.text('家人'));
    // 家人頁要打一次伺服器
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('阿爸（我）'), findsOneWidget);
    expect(find.text('阿母'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
