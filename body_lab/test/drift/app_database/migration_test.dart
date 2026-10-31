// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:body_lab/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v1 to v2 does not corrupt data', () async {
    // Add data to insert into the old database, and the expected rows after the
    // migration.
    // schema 快照用的是 SQL 原始值：DateTime 是 unix 秒、bool 是 0 / 1。
    int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    final measuredAt = unix(DateTime(2026, 10, 1, 7, 30));
    final syncedAt = unix(DateTime(2026, 10, 1, 8));
    final eatenAt = unix(DateTime(2026, 10, 1, 12));
    final createdAt = unix(DateTime(2026, 10, 1, 12, 5));

    final oldDailyBodyMetricsData = <v1.DailyBodyMetricsData>[
      v1.DailyBodyMetricsData(
        day: '2026-10-01',
        measuredAt: measuredAt,
        weightKg: 72,
        bodyFatPercent: 20,
        leanMassKg: 57.6,
        leanMassEstimated: 1,
        syncedAt: syncedAt,
      ),
    ];
    final expectedNewDailyBodyMetricsData = <v2.DailyBodyMetricsData>[
      v2.DailyBodyMetricsData(
        day: '2026-10-01',
        measuredAt: measuredAt,
        weightKg: 72,
        bodyFatPercent: 20,
        leanMassKg: 57.6,
        leanMassEstimated: 1,
        syncedAt: syncedAt,
      ),
    ];

    final oldFoodEntriesData = <v1.FoodEntriesData>[
      v1.FoodEntriesData(
        id: 1,
        eatenAt: eatenAt,
        meal: 'lunch',
        name: '雞腿便當',
        servings: 1,
        kcal: 800,
        createdAt: createdAt,
      ),
    ];
    final expectedNewFoodEntriesData = <v2.FoodEntriesData>[
      v2.FoodEntriesData(
        id: 1,
        eatenAt: eatenAt,
        meal: 'lunch',
        name: '雞腿便當',
        servings: 1,
        kcal: 800,
        createdAt: createdAt,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.dailyBodyMetrics, oldDailyBodyMetricsData);
        batch.insertAll(oldDb.foodEntries, oldFoodEntriesData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewDailyBodyMetricsData,
          await newDb.select(newDb.dailyBodyMetrics).get(),
        );
        expect(
          expectedNewFoodEntriesData,
          await newDb.select(newDb.foodEntries).get(),
        );
        final templates = await newDb.select(newDb.mealTemplates).get();
        expect(templates.map((t) => (t.name, t.pinned)), [('蛋白粉（1 匙）', 1)]);
      },
    );
  });

  test('v8 → v9 補上預設一鍵項目，已有同名的不重複', () async {
    final createdAt = DateTime(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;
    v8.MealTemplatesData old(int id, String name, int pinned) =>
        v8.MealTemplatesData(
          id: id,
          name: name,
          defaultServings: 1,
          pinned: pinned,
          archived: 0,
          useCount: 0,
          createdAt: createdAt,
        );

    await verifier.testWithDataIntegrity(
      oldVersion: 8,
      newVersion: 9,
      createOld: v8.DatabaseAtV8.new,
      createNew: v9.DatabaseAtV9.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.mealTemplates, [
          old(1, '蛋白粉（1 匙）', 1),
          // 使用者自己建過、沒釘選
          old(2, '雞蛋（1 顆）', 0),
        ]);
      },
      validateItems: (newDb) async {
        final templates = await newDb.select(newDb.mealTemplates).get();
        expect(templates.map((t) => (t.name, t.pinned)), [
          ('蛋白粉（1 匙）', 1),
          ('雞蛋（1 顆）', 0),
          ('牛奶（100 ml）', 1),
          ('豆漿（100 ml）', 1),
          ('麥片（20 g）', 1),
          ('大麥克（去醬）', 1),
          ('麥克雞塊（4 塊）', 1),
        ]);
      },
    );
  });

  test('v9 → v10 補回被舊備份蓋掉的預設一鍵項目', () async {
    final createdAt = DateTime(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;
    v9.MealTemplatesData old(int id, String name) => v9.MealTemplatesData(
      id: id,
      name: name,
      defaultServings: 1,
      pinned: 1,
      archived: 0,
      useCount: 0,
      createdAt: createdAt,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 9,
      newVersion: 10,
      createOld: v9.DatabaseAtV9.new,
      createNew: v10.DatabaseAtV10.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        // 匯入 v9 之前的備份後只剩蛋白粉和雞蛋
        batch.insertAll(oldDb.mealTemplates, [
          old(1, '蛋白粉（1 匙）'),
          old(2, '雞蛋（1 顆）'),
        ]);
      },
      validateItems: (newDb) async {
        final templates = await newDb.select(newDb.mealTemplates).get();
        expect(templates.map((t) => t.name), [
          '蛋白粉（1 匙）',
          '雞蛋（1 顆）',
          '牛奶（100 ml）',
          '豆漿（100 ml）',
          '麥片（20 g）',
          '大麥克（去醬）',
          '麥克雞塊（4 塊）',
        ]);
      },
    );
  });

  test('v10 → v11 舊版改過的預設項目標成 customized，沒改過的和使用者自建的分開', () async {
    final createdAt = DateTime(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;
    v10.MealTemplatesData old(
      int id,
      String name, {
      required double kcal,
      double? protein,
      double? carbs,
      double? fat,
    }) => v10.MealTemplatesData(
      id: id,
      name: name,
      defaultServings: 1,
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      pinned: 1,
      archived: 0,
      useCount: 0,
      createdAt: createdAt,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 10,
      newVersion: 11,
      createOld: v10.DatabaseAtV10.new,
      createNew: v11.DatabaseAtV11.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.mealTemplates, [
          // 使用者依包裝把蛋白粉改成 120 kcal
          old(1, '蛋白粉（1 匙）', kcal: 120, protein: 24, carbs: 3, fat: 1.5),
          // 雞蛋沒動
          old(2, '雞蛋（1 顆）', kcal: 75, protein: 7, carbs: 1, fat: 5),
          // 使用者自建
          old(3, '水煮蛋', kcal: 70),
        ]);
      },
      validateItems: (newDb) async {
        final rows = await newDb.select(newDb.mealTemplates).get();
        final byName = {for (final r in rows) r.name: r};
        expect(byName['蛋白粉（1 匙）']!.customized, 1);
        expect(byName['雞蛋（1 顆）']!.customized, 0);
        expect(byName['水煮蛋']!.customized, 1);
        // 預設項目（不管改沒改過）都接上目錄的 key，之後目錄套用才不會重複新增
        expect(byName['蛋白粉（1 匙）']!.sourceKey, 'protein_powder');
        expect(byName['雞蛋（1 顆）']!.sourceKey, 'egg');
        expect(byName['水煮蛋']!.sourceKey, null);
      },
    );
  });
}
