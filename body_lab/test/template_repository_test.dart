import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TemplateRepository templates;
  late FoodRepository food;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    templates = TemplateRepository(db);
    food = FoodRepository(db);
  });

  tearDown(() => db.close());

  MealTemplatesCompanion template(String name, {double? kcal}) =>
      MealTemplatesCompanion.insert(name: name, kcal: Value(kcal));

  test('新資料庫預設有釘選的蛋白粉範本', () async {
    final pinned = await templates.watchPinned().first;
    expect(pinned.single.name, '蛋白粉（1 匙）');
    expect(pinned.single.proteinG, 12);
  });

  test('從範本加入：複製營養素、記錄來源、使用次數 +1、改範本不影響舊紀錄', () async {
    final id = await templates.add(
      MealTemplatesCompanion.insert(
        name: '雞腿便當',
        meal: const Value(MealType.lunch),
        kcal: const Value(850),
        proteinG: const Value(35),
      ),
    );
    final t = (await templates.watchTemplates(query: '雞腿').first).single;

    await templates.addEntryFromTemplate(
      t,
      eatenAt: DateTime(2026, 10, 8, 19),
      servings: 1.5,
    );
    await templates.update(id, const MealTemplatesCompanion(kcal: Value(900)));

    final e = (await food.watchDay(DateTime(2026, 10, 8)).first).single;
    expect(e.name, '雞腿便當');
    expect(e.meal, MealType.lunch); // 範本的預設餐別優先於時間
    expect(e.servings, 1.5);
    expect(e.kcal, 850);
    expect(e.templateId, id);

    final updated = (await templates.watchTemplates(query: '雞腿').first).single;
    expect(updated.useCount, 1);
    expect(updated.lastUsedAt, isNotNull);
    expect(updated.kcal, 900);
  });

  test('範本沒有預設餐別時依時間判斷，沒給份量用預設份量', () async {
    await templates.add(
      MealTemplatesCompanion.insert(
        name: '茶葉蛋',
        defaultServings: const Value(2),
      ),
    );
    final t = (await templates.watchTemplates(query: '茶葉蛋').first).single;
    await templates.addEntryFromTemplate(
      t,
      eatenAt: DateTime(2026, 10, 8, 7, 30),
    );

    final e = (await food.watchDay(DateTime(2026, 10, 8)).first).single;
    expect(e.meal, MealType.breakfast);
    expect(e.servings, 2);
  });

  test('排序：釘選 > 使用次數；封存後消失、可還原', () async {
    await templates.add(template('A'));
    final bId = await templates.add(template('B'));
    final b = (await templates.watchTemplates(query: 'B').first).single;
    await templates.addEntryFromTemplate(b, eatenAt: DateTime(2026, 10, 8));

    var names = (await templates.watchTemplates().first).map((t) => t.name);
    expect(names, ['蛋白粉（1 匙）', 'B', 'A']);

    await templates.archive(bId);
    names = (await templates.watchTemplates().first).map((t) => t.name);
    expect(names, ['蛋白粉（1 匙）', 'A']);

    await templates.unarchive(bId);
    names = (await templates.watchTemplates().first).map((t) => t.name);
    expect(names, contains('B'));
  });

  test('飲食紀錄存成範本', () async {
    await food.add(
      FoodEntriesCompanion.insert(
        eatenAt: DateTime(2026, 10, 8, 12),
        meal: MealType.lunch,
        name: '牛肉麵',
        servings: const Value(1),
        kcal: const Value(700),
      ),
    );
    final e = (await food.watchDay(DateTime(2026, 10, 8)).first).single;
    await templates.addFromEntry(e.toCompanion(true));

    final t = (await templates.watchTemplates(query: '牛肉麵').first).single;
    expect((t.meal, t.kcal, t.defaultServings), (MealType.lunch, 700, 1));
  });

  test('每日打勾：勾選、重複勾選、取消、區間查詢', () async {
    final checks = CheckRepository(db);
    final day = DateTime(2026, 10, 8);

    await checks.set(day, CheckItem.creatine, true);
    await checks.set(day, CheckItem.creatine, true);
    expect(await checks.watchDay(day).first, {CheckItem.creatine});

    await checks.set(DateTime(2026, 10, 1), CheckItem.creatine, true);
    final range = await checks.since(DateTime(2026, 10, 2));
    expect(range.keys, [day]);

    await checks.set(day, CheckItem.creatine, false);
    expect(await checks.watchDay(day).first, isEmpty);
  });
}
