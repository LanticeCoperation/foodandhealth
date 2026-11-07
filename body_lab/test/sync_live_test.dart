@Tags(['server'])
library;

import 'dart:io';

import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/extra_burn_repository.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/data/profile_repository.dart';
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
/// 收尾要清掉的伺服器表。
const _tables = [
  'food_entries',
  'phases',
  'extra_burns',
  'daily_checks',
  'body_profiles',
  'body_metrics',
  'daily_activity',
];

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
  late PhaseRepository repo1phase;
  late CheckRepository repo1check;
  late CheckRepository repo2check;
  late ExtraBurnRepository repo1burn;
  late ProfileRepository repo1profile;
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
    for (final t in _tables) {
      await admin.schema(kBodyLabSchema).from(t).delete().eq('user_id', uid);
    }

    db1 = AppDatabase(NativeDatabase.memory());
    db2 = AppDatabase(NativeDatabase.memory());
    repo1 = FoodRepository(db1);
    repo2 = FoodRepository(db2);
    repo1phase = PhaseRepository(db1);
    repo1check = CheckRepository(db1);
    repo2check = CheckRepository(db2);
    repo1burn = ExtraBurnRepository(db1);
    repo1profile = ProfileRepository(db1);
    sync1 = SyncService(db1, SupabaseSyncApi(phone1));
    sync2 = SyncService(db2, SupabaseSyncApi(phone2));
  });

  tearDown(() async {
    for (final t in _tables) {
      await admin.schema(kBodyLabSchema).from(t).delete().eq('user_id', uid);
    }
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
    final server = await phone1.schema(kBodyLabSchema).from('food_entries').select();
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


  test('階段：手機一新增 → 手機二拿到；刪除也會跟著', () async {
    await repo1phase.save(
      PhasesCompanion.insert(
        name: 'LiveTestPhase',
        startDay: '2026-11-01',
        endDay: '2026-11-28',
        targetKcal: const Value(2000),
        creatine: const Value(true),
      ),
    );
    expect((await sync1.sync()).uploaded, greaterThanOrEqualTo(1));
    await sync2.sync();
    final onTwo = await db2.select(db2.phases).getSingle();
    expect(onTwo.name, 'LiveTestPhase');
    expect(onTwo.targetKcal, 2000);
    expect(onTwo.creatine, isTrue);
    expect(onTwo.pendingSync, isFalse);

    await repo1phase.delete((await db1.select(db1.phases).getSingle()).id);
    await sync1.sync();
    await sync2.sync();
    expect(await db2.select(db2.phases).get(), isEmpty);
  });

  test('打勾（自然鍵）：兩台打同一天只會有一筆；取消會同步過去', () async {
    final day = DateTime(2026, 11, 7);
    await repo1check.set(day, CheckItem.creatine, true, amount: 5);
    await sync1.sync();
    await sync2.sync();
    expect(await db2.select(db2.dailyChecks).get(), hasLength(1));

    // 兩台各打一次，伺服器上還是一筆
    await repo2check.set(day, CheckItem.creatine, true, amount: 5);
    await sync2.sync();
    final server = await phone1.schema(kBodyLabSchema).from('daily_checks').select();
    expect(server, hasLength(1));

    await repo1check.set(day, CheckItem.creatine, false);
    await sync1.sync();
    await sync2.sync();
    expect(await db2.select(db2.dailyChecks).get(), isEmpty);
  });

  test('自訂消耗：新增會同步過去', () async {
    await repo1burn.add(DateTime(2026, 11, 7), 300, note: 'Hiking');
    await sync1.sync();
    await sync2.sync();
    final onTwo = await db2.select(db2.extraBurns).getSingle();
    expect(onTwo.kcal, 300);
    expect(onTwo.note, 'Hiking');
  });

  test('身體基本資料：一個人一列，後寫的贏', () async {
    await repo1profile.save(
      sex: Sex.male,
      birthYear: 1988,
      heightCm: 172,
      activity: ActivityLevel.moderate,
      weightKg: 74.5,
      tdeeKcal: 2400,
    );
    await sync1.sync();
    await sync2.sync();
    expect((await db2.select(db2.profiles).getSingle()).weightKg, 74.5);
    final server = await phone1.schema(kBodyLabSchema).from('body_profiles').select();
    expect(server, hasLength(1));
  });

  test('體重快取只上傳：家人讀得到，但不會被下拉回本機', () async {
    await db1
        .into(db1.dailyBodyMetrics)
        .insertOnConflictUpdate(
          DailyBodyMetricsCompanion.insert(
            day: '2026-11-07',
            measuredAt: DateTime(2026, 11, 7, 7),
            weightKg: 74.2,
            bodyFatPercent: const Value(18.5),
            syncedAt: DateTime.now(),
          ),
        );
    await sync1.sync();

    final server = await phone1.schema(kBodyLabSchema).from('body_metrics').select();
    expect(server, hasLength(1), reason: '要上傳給家人看');

    await sync2.sync();
    expect(
      await db2.select(db2.dailyBodyMetrics).get(),
      isEmpty,
      reason: '正本在 Apple 健康，不該被下拉回另一台的本機表',
    );
  });

  test('認領：同帳號可重複，換帳號被擋', () async {
    await sync1.claimForCurrentUser();
    expect(await sync1.ownerUid(), uid);
    await sync1.claimForCurrentUser();
    expect(await sync1.ownerUid(), uid);
  });
}
