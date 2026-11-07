import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/settings_repository.dart';
import 'package:body_lab/screens/family_admin_screen.dart';
import 'package:body_lab/services/family_admin_api.dart';
import 'package:body_lab/services/sync_config.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 在模擬器上實際操作「家庭管理」畫面，打的是真的 edge function。
///
/// 要證明的是：App 裡只有管理密碼、沒有 service_role 金鑰，
/// 照樣能建帳號並加進家庭——而密碼錯的時候會被伺服器擋下來。
///
/// ```
/// flutter test integration_test/family_admin_test.dart -d emulator-5554 \
///   --dart-define=SUPABASE_URL=http://10.0.2.2:8000 \
///   --dart-define=SUPABASE_KEY=<publishable key> \
///   --dart-define=ADMIN_SECRET=<.env 裡的 ADMIN_SECRET> \
///   --dart-define=FAMILY_NAME=<現有的家庭名稱>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const adminSecret = String.fromEnvironment('ADMIN_SECRET');
  const familyName = String.fromEnvironment('FAMILY_NAME');

  late AppDatabase db;
  late FamilyAdminApi api;
  late SupabaseClient client;

  setUpAll(() async {
    await Supabase.initialize(
      url: SyncConfig.compiledUrl,
      publishableKey: SyncConfig.compiledKey,
    );
    client = Supabase.instance.client;
  });

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    api = FamilyAdminApi(client);
  });

  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FamilyAdminScreen(api: api)),
    );
    await tester.pumpAndSettle();
  }

  /// 把 ListView 捲到底，底部的結果才會被建出來。
  Future<void> scrollToBottom(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 4; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }
  /// 畫面上的動作會打網路，要包在 runAsync 裡，否則假時鐘會卡住。
  ///
  /// 兩個會害人的地方：
  ///
  /// - **按鈕要用具體型別找**。find.widgetWithText 比的是 runtimeType，
  ///   FilledButton / OutlinedButton 都比不到共同的父類別 ButtonStyleButton。
  /// - **結果在 ListView 底部，不捲下去就不會被建出來**，
  ///   find 當然也就找不到。所以每次輪詢都要往下捲。
  Future<void> tapAndWait(WidgetTester tester, String label) async {
    var target = find.widgetWithText(FilledButton, label);
    if (target.evaluate().isEmpty) {
      target = find.widgetWithText(OutlinedButton, label);
    }
    expect(target, findsOneWidget, reason: '找不到按鈕「$label」');
    // 實機上軟鍵盤會蓋住下半截畫面，剛打完字就點按鈕的話會點到鍵盤
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();

    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();
      await scrollToBottom(tester);
      final busy = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final done = find.byType(SelectableText).evaluate().isNotEmpty ||
          find.textContaining('不正確').evaluate().isNotEmpty ||
          find.textContaining('失敗').evaluate().isNotEmpty ||
          find.textContaining('請先').evaluate().isNotEmpty;
      if (!busy && done) return;
    }
    fail('等不到「$label」的結果');
  }







  testWidgets('伺服器位址存在設定裡就能用，不必編進程式', (tester) async {
    final settings = SettingsRepository(db);
    expect(await settings.syncUrl(), isNull);
    await settings.setSyncServer(SyncConfig.compiledUrl, SyncConfig.compiledKey);
    expect(await settings.syncUrl(), SyncConfig.compiledUrl);
    expect(await settings.syncKey(), SyncConfig.compiledKey);
  });

  testWidgets('管理密碼錯的時候，伺服器會擋下來', (tester) async {
    expect(adminSecret, isNotEmpty, reason: '這支測試要帶 --dart-define=ADMIN_SECRET');
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '管理密碼'),
      'definitely-not-the-secret',
    );
    await tapAndWait(tester, '看現況');

    expect(find.textContaining('管理密碼不正確'), findsOneWidget);
  });

  testWidgets('密碼對就看得到現況', (tester) async {
    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '管理密碼'),
      adminSecret,
    );
    await tapAndWait(tester, '看現況');

    expect(find.textContaining('--- 帳號 ---'), findsOneWidget);
    expect(find.textContaining('--- 家庭成員 ---'), findsOneWidget);
  });

  testWidgets('在 App 裡建家人：帳號、顯示名稱、家庭成員一次完成', (tester) async {
    expect(familyName, isNotEmpty, reason: '這支測試要帶 --dart-define=FAMILY_NAME');
    final email =
        'uitest-${DateTime.now().millisecondsSinceEpoch}@example.com';

    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '管理密碼'),
      adminSecret,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.enterText(find.widgetWithText(TextField, '顯示名稱'), '畫面測試');
    await tester.enterText(find.widgetWithText(TextField, '家庭名稱'), familyName);

    await tapAndWait(tester, '建立帳號');

    // 伺服器產生的密碼只回這一次，畫面要顯示出來
    expect(find.text('密碼（只會顯示這一次）'), findsOneWidget);
    expect(find.textContaining('畫面測試'), findsWidgets);
    expect(find.textContaining('加入'), findsOneWidget);

    // 收尾：把剛剛建的刪掉
    await tester.runAsync(() async {
      await api.removeMember(adminSecret, family: familyName, email: email);
    });
  });
}
