import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/services/sync_api.dart';
import 'package:body_lab/services/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 記憶體版的伺服器：行為照著 infra/supabase/migrations/0002 的規則——
/// 以 sync_id 為鍵 upsert、updated_at 一律由「伺服器」蓋掉、刪除是寫 deleted_at。
class FakeSyncApi implements SyncApi {
  FakeSyncApi(this.currentUserId);

  @override
  String? currentUserId;

  final Map<String, Map<String, dynamic>> rows = {};
  DateTime _clock = DateTime.utc(2026, 11, 7, 0, 0, 0);

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  @override
  Future<void> upsertFoodEntries(List<Map<String, dynamic>> incoming) async {
    for (final row in incoming) {
      final id = row['sync_id'] as String;
      rows[id] = {
        ...?rows[id],
        ...row,
        'user_id': currentUserId,
        'updated_at': _tick().toIso8601String(),
      };
    }
  }

  /// 一頁最多幾列（模擬伺服器的 PGRST_DB_MAX_ROWS）。測分頁時調小。
  int pageSize = 1000;

  @override
  Future<List<Map<String, dynamic>>> fetchFoodEntries({
    DateTime? since,
    int offset = 0,
    int limit = 500,
  }) async {
    final all =
        [
          for (final r in rows.values)
            if ((currentUserId == null || r['user_id'] == currentUserId) &&
                (since == null ||
                    !DateTime.parse(
                      r['updated_at'] as String,
                    ).isBefore(since)))
              Map<String, dynamic>.from(r),
        ]..sort((a, b) {
          final t = (a['updated_at'] as String).compareTo(
            b['updated_at'] as String,
          );
          return t != 0
              ? t
              : (a['sync_id'] as String).compareTo(b['sync_id'] as String);
        });
    final take = limit < pageSize ? limit : pageSize;
    if (offset >= all.length) return const [];
    final end = offset + take;
    return all.sublist(offset, end > all.length ? all.length : end);
  }

  @override
  Future<void> markDeleted(List<String> syncIds) async {
    for (final id in syncIds) {
      final row = rows[id];
      if (row == null) continue;
      row['deleted_at'] = _tick().toIso8601String();
      row['updated_at'] = _clock.toIso8601String();
    }
  }
}

FoodEntriesCompanion meal(DateTime at, String name, {double? kcal}) =>
    FoodEntriesCompanion.insert(
      eatenAt: at,
      meal: MealType.lunch,
      name: name,
      kcal: Value(kcal),
    );

void main() {
  const uid = 'user-a';
  late FakeSyncApi api;

  // 一台「手機」= 一個本機資料庫 + 一個 SyncService，共用同一個假伺服器
  late AppDatabase db1;
  late AppDatabase db2;
  late FoodRepository repo1;
  late FoodRepository repo2;
  late SyncService sync1;
  late SyncService sync2;

  setUp(() {
    api = FakeSyncApi(uid)..currentUserId = uid;
    db1 = AppDatabase(NativeDatabase.memory());
    db2 = AppDatabase(NativeDatabase.memory());
    repo1 = FoodRepository(db1);
    repo2 = FoodRepository(db2);
    sync1 = SyncService(db1, api);
    sync2 = SyncService(db2, api);
  });

  tearDown(() async {
    await db1.close();
    await db2.close();
  });

  Future<List<FoodEntry>> rowsOf(AppDatabase db) =>
      (db.select(db.foodEntries)..orderBy([
            (r) => OrderingTerm.asc(r.eatenAt),
          ]))
          .get();

  test('手機一新增 → 手機二下拉看得到，而且不會被排進上傳', () async {
    await repo1.add(meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    expect((await sync1.sync()).uploaded, 1);

    final result = await sync2.sync();
    expect(result.pulled, 1);

    final rows = await rowsOf(db2);
    expect(rows.single.name, '午餐');
    expect(rows.single.kcal, 600);
    expect(
      rows.single.pendingSync,
      isFalse,
      reason: '下拉寫入的列若標成待上傳，會被無限重傳',
    );
  });

  test('重複同步不會產生重複列', () async {
    await repo1.add(meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    await sync1.sync();
    await sync2.sync();
    await sync1.sync();
    await sync2.sync();

    expect(await rowsOf(db1), hasLength(1));
    expect(await rowsOf(db2), hasLength(1));
    expect(api.rows, hasLength(1));
  });

  test('本機還沒上傳的修改不會被下拉蓋掉', () async {
    await repo1.add(meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    await sync1.sync();
    await sync2.sync();

    // 手機二離線改了，還沒上傳
    final onTwo = (await rowsOf(db2)).single;
    await repo2.save(onTwo.copyWith(kcal: const Value(900)).toCompanion(true));

    // 此時手機一也改了並上傳
    final onOne = (await rowsOf(db1)).single;
    await repo1.save(onOne.copyWith(kcal: const Value(700)).toCompanion(true));
    await sync1.sync();

    // 手機二下拉：本機那筆有未上傳的修改，不能被蓋掉
    await sync2.sync();
    expect((await rowsOf(db2)).single.kcal, 900);
  });

  test('上傳期間又改了同一筆，不會被誤清成已同步', () async {
    await repo1.add(meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    final row = (await rowsOf(db1)).single;

    // 用一個會在 upsert 當下偷改本機資料的 api，模擬上傳途中使用者又編輯
    final racing = _RacingApi(api, () async {
      await repo1.save(row.copyWith(kcal: const Value(999)).toCompanion(true));
    });
    await SyncService(db1, racing).sync();

    final after = (await rowsOf(db1)).single;
    expect(after.kcal, 999);
    expect(
      after.pendingSync,
      isTrue,
      reason: '送出後才發生的修改還沒上傳，旗標不能清掉',
    );
  });

  test('手機一刪除 → 手機二跟著移除', () async {
    await repo1.add(meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    await sync1.sync();
    await sync2.sync();
    expect(await rowsOf(db2), hasLength(1));

    await repo1.delete((await rowsOf(db1)).single.id);
    final pushed = await sync1.sync();
    expect(pushed.deleted, 1);
    expect(await db1.select(db1.pendingDeletes).get(), isEmpty);

    final pulled = await sync2.sync();
    expect(pulled.removedLocally, 1);
    expect(await rowsOf(db2), isEmpty);
  });

  test('刪除後復原，會把伺服器上的墓碑救回來', () async {
    await repo1.add(meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    await sync1.sync();
    final row = (await rowsOf(db1)).single;

    await repo1.delete(row.id);
    await sync1.sync();
    expect(api.rows.values.single['deleted_at'], isNotNull);

    await repo1.restore(row);
    await sync1.sync();
    expect(
      api.rows.values.single['deleted_at'],
      isNull,
      reason: '不送 deleted_at:null 的話 merge-duplicates 會留著舊墓碑',
    );

    await sync2.sync();
    expect(await rowsOf(db2), hasLength(1));
  });

  test('時間跨時區往返不會跑掉', () async {
    final at = DateTime(2026, 11, 7, 23, 30);
    await repo1.add(meal(at, '宵夜', kcal: 300));
    await sync1.sync();
    await sync2.sync();
    expect((await rowsOf(db2)).single.eatenAt, at);
  });

  test('拉回來的紀錄 templateId 是 null（範本還沒同步）', () async {
    await repo1.add(
      meal(DateTime(2026, 11, 7, 12), '午餐', kcal: 600).copyWith(
        templateId: const Value(7),
      ),
    );
    await sync1.sync();
    await sync2.sync();
    expect((await rowsOf(db2)).single.templateId, null);
  });

  test('家人的資料不會寫進本機資料庫', () async {
    // 家人 B 上傳了一筆
    api.currentUserId = 'user-b';
    await api.upsertFoodEntries([
      {
        'sync_id': 'b-1',
        'eaten_at': DateTime.utc(2026, 11, 7, 10).toIso8601String(),
        'meal': 'breakfast',
        'name': '家人的早餐',
        'servings': 1,
        'kcal': 400,
        'created_at': DateTime.utc(2026, 11, 7, 10).toIso8601String(),
        'deleted_at': null,
      },
    ]);
    api.currentUserId = uid;

    await sync1.sync();
    expect(
      await rowsOf(db1),
      isEmpty,
      reason: '本機資料庫只放自己的；家人的資料要看時再去伺服器讀',
    );
  });

  test('超過一頁也要全部拉回來，游標不會把被截掉的列吃掉', () async {
    // 伺服器一頁只給 2 列，本機要靠翻頁才拿得齊
    api.pageSize = 2;
    for (var i = 0; i < 5; i++) {
      await repo1.add(meal(DateTime(2026, 11, 7, 8 + i), 'M$i', kcal: 100.0 + i));
    }
    expect((await sync1.sync()).uploaded, 5);

    expect((await sync2.sync()).pulled, 5, reason: '一頁 2 列也要翻到底');
    expect(await rowsOf(db2), hasLength(5));

    // 再同步一次：游標往回退 5 秒，所以剛剛那幾筆會被重抓——
    // 這是刻意的（見 kCursorSlack）。重點是重抓必須是冪等的，不能長出重複列。
    await sync2.sync();
    expect(await rowsOf(db2), hasLength(5));
    expect(
      (await rowsOf(db2)).map((r) => r.syncId).toSet(),
      hasLength(5),
      reason: '重抓不能產生重複列',
    );
  });

  group('認領', () {
    test('第一次登入寫下 ownerUid', () async {
      await sync1.claimForCurrentUser();
      expect(await sync1.ownerUid(), uid);
    });

    test('同一個帳號再登入一次沒事', () async {
      await sync1.claimForCurrentUser();
      await sync1.claimForCurrentUser();
      expect(await sync1.ownerUid(), uid);
    });

    test('換成別的帳號會擋下來', () async {
      await sync1.claimForCurrentUser();
      api.currentUserId = 'someone-else';
      expect(
        () => sync1.claimForCurrentUser(),
        throwsA(isA<WrongOwnerException>()),
      );
      expect(await sync1.ownerUid(), uid, reason: '擋下來就不能改掉歸屬');
    });
  });
}

/// upsert 當下插一段本機修改進去，模擬「上傳途中使用者又編輯」。
class _RacingApi implements SyncApi {
  _RacingApi(this._inner, this._duringUpsert);
  final SyncApi _inner;
  final Future<void> Function() _duringUpsert;

  @override
  String? get currentUserId => _inner.currentUserId;

  @override
  Future<void> upsertFoodEntries(List<Map<String, dynamic>> rows) async {
    await _inner.upsertFoodEntries(rows);
    await _duringUpsert();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFoodEntries({
    DateTime? since,
    int offset = 0,
    int limit = 500,
  }) => _inner.fetchFoodEntries(since: since, offset: offset, limit: limit);

  @override
  Future<void> markDeleted(List<String> syncIds) =>
      _inner.markDeleted(syncIds);
}
