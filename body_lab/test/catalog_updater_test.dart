import 'dart:convert';

import 'package:body_lab/data/database.dart';
import 'package:body_lab/services/catalog_updater.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String catalogJson(int version, List<String> names) => jsonEncode({
  'version': version,
  'items': [
    for (final n in names) {'key': n, 'name': n, 'kcal': 100, 'protein': 5},
  ],
});

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.delete(db.mealTemplates).go();
  });
  tearDown(() => db.close());

  Future<int> count() async => (await db.select(db.mealTemplates).get()).length;

  test('內建目錄啟動時套用並記住版本', () async {
    final updater = CatalogUpdater(
      db,
      loadBundled: () async => catalogJson(1, ['a', 'b']),
      fetchRemote: () async => throw Exception('沒網路'),
    );
    final r = await updater.applyBundled();
    expect(r.added, 2);
    expect(await updater.appliedVersion(), 1);

    // 再套一次不變
    expect((await updater.applyBundled()).changed, isFalse);
    expect(await count(), 2);
  });

  test('遠端版本較新才合併，並更新記住的版本', () async {
    var remote = catalogJson(1, ['a', 'b']);
    final updater = CatalogUpdater(
      db,
      loadBundled: () async => catalogJson(1, ['a', 'b']),
      fetchRemote: () async => remote,
    );
    await updater.applyBundled();

    expect(await updater.fetchAndApply(), const CatalogUpToDate());

    remote = catalogJson(2, ['a', 'b', 'c']);
    final outcome = await updater.fetchAndApply();
    expect(outcome, isA<CatalogUpdated>());
    expect((outcome as CatalogUpdated).result.added, 1);
    expect(await updater.appliedVersion(), 2);
    expect(await count(), 3);

    // 已經是 2 了，再抓一次是最新
    expect(await updater.fetchAndApply(), const CatalogUpToDate());
  });

  test('遠端比記住的版本舊時不套用', () async {
    final updater = CatalogUpdater(
      db,
      loadBundled: () async => catalogJson(5, ['a']),
      fetchRemote: () async => catalogJson(3, ['a', 'old']),
    );
    await updater.applyBundled();
    expect(await updater.fetchAndApply(), const CatalogUpToDate());
    expect(await count(), 1);
  });

  test('抓不到或格式錯誤回報失敗，資料不動', () async {
    final updater = CatalogUpdater(
      db,
      loadBundled: () async => catalogJson(1, ['a']),
      fetchRemote: () async => throw Exception('timeout'),
    );
    await updater.applyBundled();
    expect(await updater.fetchAndApply(), isA<CatalogFailed>());

    final bad = CatalogUpdater(
      db,
      loadBundled: () async => catalogJson(1, ['a']),
      fetchRemote: () async => '{"version": 2, "items": [{"name": "x"}]}',
    );
    expect(await bad.fetchAndApply(), isA<CatalogFailed>());
    expect(await bad.appliedVersion(), 1);
    expect(await count(), 1);
  });
}
