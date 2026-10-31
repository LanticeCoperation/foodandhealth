import 'dart:convert';
import 'dart:io';

import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/template_catalog.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

TemplateCatalog catalog(int version, List<Map<String, Object?>> items) =>
    TemplateCatalog.fromJson({'version': version, 'items': items});

Map<String, Object?> item(
  String key,
  String name, {
  double kcal = 100,
  double protein = 10,
  double carbs = 5,
  double fat = 2,
  double servings = 1,
  bool pinned = true,
}) => {
  'key': key,
  'name': name,
  'servings': servings,
  'kcal': kcal,
  'protein': protein,
  'carbs': carbs,
  'fat': fat,
  'pinned': pinned,
};

void main() {
  group('解析', () {
    test('讀出版本與項目', () {
      final c = catalog(3, [item('egg', '雞蛋', kcal: 75)]);
      expect(c.version, 3);
      expect(c.items.single.key, 'egg');
      expect(c.items.single.name, '雞蛋');
      expect(c.items.single.kcal, 75);
      expect(c.items.single.pinned, isTrue);
    });

    test('缺 key、名稱或熱量就拒絕', () {
      expect(
        () => catalog(1, [
          {'name': '雞蛋', 'kcal': 75},
        ]),
        throwsFormatException,
      );
      expect(
        () => catalog(1, [
          {'key': 'egg', 'kcal': 75},
        ]),
        throwsFormatException,
      );
      expect(
        () => catalog(1, [
          {'key': 'egg', 'name': '雞蛋'},
        ]),
        throwsFormatException,
      );
      expect(
        () => TemplateCatalog.fromJson({'items': []}),
        throwsFormatException,
      );
    });

    test('key 重複就拒絕', () {
      expect(
        () => catalog(1, [item('egg', '雞蛋'), item('egg', '雞蛋 2')]),
        throwsFormatException,
      );
    });

    test('內建的 assets/food_templates.json 合法', () {
      final text = File('assets/food_templates.json').readAsStringSync();
      final c = TemplateCatalog.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
      expect(c.version, greaterThanOrEqualTo(1));
      expect(c.items.map((i) => i.key).toSet().length, c.items.length);
      expect(c.items.any((i) => i.name == '蛋白粉（1 匙）'), isTrue);
    });
  });

  group('套用到資料庫', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<List<MealTemplate>> all() => db.select(db.mealTemplates).get();

    test('新 key 新增；再套一次什麼都不做', () async {
      // 新資料庫已有 7 個用 SQL 種下的預設項目，先清掉只看目錄行為
      await db.delete(db.mealTemplates).go();
      final c = catalog(1, [item('egg', '雞蛋', kcal: 75), item('milk', '牛奶')]);

      final r1 = await applyCatalog(db, c);
      expect((r1.added, r1.updated), (2, 0));
      final rows = await all();
      expect(rows.map((t) => t.sourceKey), containsAll(['egg', 'milk']));
      expect(rows.firstWhere((t) => t.sourceKey == 'egg').kcal, 75);
      expect(rows.every((t) => t.pinned), isTrue);

      final r2 = await applyCatalog(db, c);
      expect((r2.added, r2.updated), (0, 0));
      expect((await all()).length, 2);
    });

    test('已存在且沒改過的項目依目錄更新；改過的不動', () async {
      await db.delete(db.mealTemplates).go();
      await applyCatalog(
        db,
        catalog(1, [item('egg', '雞蛋', kcal: 75), item('milk', '牛奶', kcal: 60)]),
      );
      final milk = (await all()).firstWhere((t) => t.sourceKey == 'milk');
      await (db.update(
        db.mealTemplates,
      )..where((t) => t.id.equals(milk.id))).write(
        const MealTemplatesCompanion(kcal: Value(999), customized: Value(true)),
      );

      final r = await applyCatalog(
        db,
        catalog(2, [
          item('egg', '雞蛋（1 顆）', kcal: 80),
          item('milk', '牛奶（100 ml）', kcal: 63),
        ]),
      );
      expect((r.added, r.updated), (0, 1));
      final rows = await all();
      final egg = rows.firstWhere((t) => t.sourceKey == 'egg');
      expect(egg.name, '雞蛋（1 顆）');
      expect(egg.kcal, 80);
      final milk2 = rows.firstWhere((t) => t.sourceKey == 'milk');
      expect(milk2.name, '牛奶');
      expect(milk2.kcal, 999);
    });

    test('封存過的不更新也不重新加回來；置頂狀態與使用次數不被目錄覆蓋', () async {
      await db.delete(db.mealTemplates).go();
      await applyCatalog(
        db,
        catalog(1, [item('egg', '雞蛋'), item('milk', '牛奶')]),
      );
      final rows = await all();
      final egg = rows.firstWhere((t) => t.sourceKey == 'egg');
      final milk = rows.firstWhere((t) => t.sourceKey == 'milk');
      await (db.update(db.mealTemplates)..where((t) => t.id.equals(egg.id)))
          .write(const MealTemplatesCompanion(archived: Value(true)));
      await (db.update(
        db.mealTemplates,
      )..where((t) => t.id.equals(milk.id))).write(
        const MealTemplatesCompanion(pinned: Value(false), useCount: Value(5)),
      );

      final r = await applyCatalog(
        db,
        catalog(2, [item('egg', '雞蛋 v2'), item('milk', '牛奶 v2')]),
      );
      expect((r.added, r.updated), (0, 1));
      final after = await all();
      expect(after.length, 2);
      final egg2 = after.firstWhere((t) => t.sourceKey == 'egg');
      expect(egg2.archived, isTrue);
      expect(egg2.name, '雞蛋');
      final milk2 = after.firstWhere((t) => t.sourceKey == 'milk');
      expect(milk2.name, '牛奶 v2');
      expect(milk2.pinned, isFalse);
      expect(milk2.useCount, 5);
    });

    test('舊資料沒有 key 的同名項目會接上 key，不會重複新增', () async {
      // 新資料庫用 SQL 種下的 7 個預設項目都沒有 sourceKey
      final before = await all();
      expect(before.every((t) => t.sourceKey == null), isTrue);
      expect(before.length, 7);

      final r = await applyCatalog(
        db,
        catalog(1, [
          item('protein_powder', '蛋白粉（1 匙）', kcal: 60),
          item('egg', '雞蛋（1 顆）', kcal: 75),
          item('new_item', '新項目'),
        ]),
      );
      expect((r.added, r.updated), (1, 2));
      final rows = await all();
      expect(rows.length, 8);
      expect(
        rows.firstWhere((t) => t.name == '蛋白粉（1 匙）').sourceKey,
        'protein_powder',
      );
      expect(rows.where((t) => t.name == '雞蛋（1 顆）').length, 1);
    });

    test('使用者自建的同名項目（customized）不會被接上 key', () async {
      await db.delete(db.mealTemplates).go();
      await db
          .into(db.mealTemplates)
          .insert(
            MealTemplatesCompanion.insert(
              name: '雞蛋',
              kcal: const Value(70),
              customized: const Value(true),
            ),
          );
      final r = await applyCatalog(
        db,
        catalog(1, [item('egg', '雞蛋', kcal: 75)]),
      );
      expect((r.added, r.updated), (1, 0));
      final rows = await all();
      expect(rows.length, 2);
      expect(rows.firstWhere((t) => t.sourceKey == null).kcal, 70);
    });
  });
}
