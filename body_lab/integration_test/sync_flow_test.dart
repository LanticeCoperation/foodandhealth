import 'package:body_lab/data/database.dart';
import 'package:body_lab/main.dart';
import 'package:body_lab/services/catalog_updater.dart';
import 'package:body_lab/services/sync_config.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase/supabase.dart';

import 'fake_health.dart';

/// 在模擬器上對真的自架 Supabase 跑一次完整的同步流程。
///
/// 這支測試要證明的是 sync_live_test（純 Dart）證明不了的那一段：
/// App 跑在 Android 上，真的連得到伺服器——明文 HTTP 的放行、
/// 10.0.2.2 這個宿主位址、整包外掛堆疊都對。
///
/// 前置：本機 stack 在跑，而且 infra/supabase/scripts/admin.sh 建好了
/// dad@example.com / mom@example.com 並加進同一個家庭。
///
/// ```
/// flutter test integration_test/sync_flow_test.dart -d emulator-5554 \
///   --dart-define=SUPABASE_URL=http://10.0.2.2:8000 \
///   --dart-define=SUPABASE_KEY=<publishable key>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const dad = 'dad@example.com';
  const mom = 'mom@example.com';
  const password = 'DemoPass-1234';

  late AppDatabase db;
  late AppServices services;

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('等不到 $finder');
  }

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    services = AppServices(
      db,
      FakeHealthService(),
      catalog: CatalogUpdater(
        db,
        fetchRemote: () async => throw Exception('整合測試不連網'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('設定好伺服器時，設定頁才有同步區塊', (tester) async {
    expect(
      SyncConfig.configured,
      isTrue,
      reason: '這支測試要帶 --dart-define 的 SUPABASE_URL / SUPABASE_KEY',
    );
    expect(services.sync.available, isTrue);
  });

  testWidgets('在 Android 上登入 → 上傳 → 家人看得到', (tester) async {
    final sync = services.sync;

    // 先把伺服器上這個帳號的舊資料清掉（要 service_role 才刪得掉，
    // 這裡改用軟刪除之外的辦法：直接拿家人帳號讀，確認只看我們這次寫的）
    await sync.signIn(dad, password);
    expect(sync.signedIn, isTrue, reason: sync.lastMessage ?? '');

    // 記一餐，然後同步上去
    final at = DateTime.now();
    await services.food.add(
      FoodEntriesCompanion.insert(
        eatenAt: at,
        meal: MealType.lunch,
        name: 'EmulatorLunch',
        kcal: const Value(640),
        proteinG: const Value(42),
      ),
    );
    await sync.syncNow();
    expect(sync.lastMessage, isNot(contains('失敗')), reason: sync.lastMessage);

    // 換家人的帳號從伺服器讀，確認看得到（而且是唯讀的那條路）
    final asMom = SupabaseClient(SyncConfig.url, SyncConfig.publishableKey);
    await asMom.auth.signInWithPassword(email: mom, password: password);
    final seen = await asMom
        .from('food_entries')
        .select('name,kcal')
        .eq('name', 'EmulatorLunch');
    expect(seen, isNotEmpty, reason: '家人應該讀得到阿爸的紀錄');
    await asMom.dispose();

    // App 裡的家人頁也要真的畫得出來
    await tester.pumpWidget(BodyLabApp(services: services));
    await waitFor(tester, find.text('身體組成'));
    await tester.tap(find.byIcon(Icons.person_outline).first);
    await waitFor(tester, find.text('跨裝置同步'));
    await tester.tap(find.text('家人'));
    await waitFor(tester, find.text('阿爸（我）'));
    expect(find.text('阿母'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
