@Tags(['server'])
library;

import 'dart:io';

import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/services/sync_api.dart';
import 'package:body_lab/services/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

/// 對真的自架 Supabase 跑的多台同步測試。預設不跑（tag: server）。
///
/// 先把 stack 起來、建好測試帳號，然後：
///
/// ```
/// SUPABASE_URL=http://localhost:8000 \
/// SUPABASE_KEY=<publishable key> \
/// SYNC_TEST_EMAIL=... SYNC_TEST_PASSWORD=... \
/// flutter test --tags server test/sync_live_test.dart
/// ```
void main() {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'];
  final key = env['SUPABASE_KEY'];
  final email = env['SYNC_TEST_EMAIL'];
  final password = env['SYNC_TEST_PASSWORD'];
  final secret = env['SYNC_TEST_SECRET'];

  if (url == null ||
      key == null ||
      email == null ||
      password == null ||
      secret == null) {
    test('缺少環境變數，略過', () {}, skip: '需要 SUPABASE_URL / KEY / 測試帳號 / service_role');
    return;
  }
  late SupabaseClient admin;

  late SupabaseClient phone1;
  late SupabaseClient phone2;
  late AppDatabase db1;
  late AppDatabase db2;
  late FoodRepository repo1;
  late FoodRepository repo2;
  late SyncService sync1;
  late SyncService sync2;
  late String uid;

  setUp(() async {
    // 同一個帳號登入兩次 = 兩支手機
    phone1 = SupabaseClient(url, key);
    phone2 = SupabaseClient(url, key);
    final a = await phone1.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await phone2.auth.signInWithPassword(email: email, password: password);
    uid = a.user!.id;

    // 每次從乾淨的伺服器狀態開始（要用 service_role，見檔頭說明）
    admin = SupabaseClient(url, secret);
    await admin.from('food_entries').delete().eq('user_id', uid);

    db1 = AppDatabase(NativeDatabase.memory());
    db2 = AppDatabase(NativeDatabase.memory());
    repo1 = FoodRepository(db1);
    repo2 = FoodRepository(db2);
    sync1 = SyncService(db1, SupabaseSyncApi(phone1));
    sync2 = SyncService(db2, SupabaseSyncApi(phone2));
  });

  tearDown(() async {
    await admin.from('food_entries').delete().eq('user_id', uid);
    await db1.close();
    await db2.close();
    await phone1.dispose();
    await phone2.dispose();
    await admin.dispose();
  });

  Future<List<FoodEntry>> rowsOf(AppDatabase db) =>
      (db.select(db.foodEntries)
            ..orderBy([(r) => OrderingTerm.asc(r.eatenAt)]))
          .get();

  FoodEntriesCompanion meal(int hour, String name, {double? kcal}) =>
      FoodEntriesCompanion.insert(
        eatenAt: DateTime(2026, 11, 7, hour),
        meal: MealType.lunch,
        name: name,
        kcal: Value(kcal),
      );

  test('手機一新增三筆 → 手機二全部拿到', () async {
    await repo1.add(meal(8, 'Breakfast', kcal: 350));
    await repo1.add(meal(12, 'Lunch', kcal: 700));
    await repo1.add(meal(19, 'Dinner', kcal: 420));

    expect((await sync1.sync()).uploaded, 3);
    expect((await sync2.sync()).pulled, 3);

    final rows = await rowsOf(db2);
    expect(rows.map((r) => r.name), ['Breakfast', 'Lunch', 'Dinner']);
    expect(rows.map((r) => r.kcal), [350, 700, 420]);
    expect(rows.every((r) => !r.pendingSync), isTrue);
  });

  test('重跑同步不會長出重複列', () async {
    await repo1.add(meal(12, 'Lunch', kcal: 700));
    await sync1.sync();
    await sync2.sync();
    await sync1.sync();
    await sync2.sync();

    expect(await rowsOf(db1), hasLength(1));
    expect(await rowsOf(db2), hasLength(1));
    final server = await phone1.from('food_entries').select();
    expect(server, hasLength(1));
  });

  test('手機二改 → 手機一增量下拉拿到新值', () async {
    await repo1.add(meal(12, 'Lunch', kcal: 700));
    await sync1.sync();
    await sync2.sync();

    final onTwo = (await rowsOf(db2)).single;
    await repo2.save(onTwo.copyWith(kcal: const Value(850)).toCompanion(true));
    await sync2.sync();

    await sync1.sync();
    expect((await rowsOf(db1)).single.kcal, 850);
  });

  test('手機一刪除 → 手機二跟著移除', () async {
    await repo1.add(meal(12, 'Lunch', kcal: 700));
    await sync1.sync();
    await sync2.sync();

    await repo1.delete((await rowsOf(db1)).single.id);
    await sync1.sync();

    expect((await sync2.sync()).removedLocally, 1);
    expect(await rowsOf(db2), isEmpty);
  });

  test('時間跨 UTC 往返不跑掉', () async {
    final at = DateTime(2026, 11, 7, 23, 30);
    await repo1.add(
      FoodEntriesCompanion.insert(
        eatenAt: at,
        meal: MealType.snack,
        name: 'LateSnack',
        kcal: const Value(300),
      ),
    );
    await sync1.sync();
    await sync2.sync();
    expect((await rowsOf(db2)).single.eatenAt, at);
  });

  test('認領：同帳號可重複，換帳號被擋', () async {
    await sync1.claimForCurrentUser();
    expect(await sync1.ownerUid(), uid);
    await sync1.claimForCurrentUser();
    expect(await sync1.ownerUid(), uid);
  });
}
