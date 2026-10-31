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

  test('新資料庫預設有釘選的蛋白粉、雞蛋、牛奶等範本', () async {
    final pinned = await templates.watchPinned().first;
    expect(pinned.map((t) => t.name), [
      '蛋白粉（1 匙）',
      '雞蛋（1 顆）',
      '牛奶（100 ml）',
      '豆漿（100 ml）',
      '麥片（20 g）',
      '大麥克（去醬）',
      '麥克雞塊（4 塊）',
    ]);
    expect(pinned.first.proteinG, 12);
  });

  test('清空資料後預設範本只有一份', () async {
    await db.clearAllData();
    final pinned = await templates.watchPinned().first;
    expect(pinned, hasLength(7));
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

    // 預設範本都釘選，排在前面；只看自己加的
    Future<List<String>> names() async => [
      for (final t in await templates.watchTemplates().first)
        if (!t.pinned) t.name,
    ];
    expect((await templates.watchTemplates().first).first.pinned, isTrue);
    expect(await names(), ['B', 'A']);

    await templates.archive(bId);
    expect(await names(), ['A']);

    await templates.unarchive(bId);
    expect(await names(), contains('B'));
  });

  test('使用者從表單編輯過的範本標記 customized；置頂 / 封存不算', () async {
    final id = await templates.add(template('A', kcal: 100));
    Future<MealTemplate> row() async =>
        (await templates.watchTemplates(query: 'A').first).single;
    expect((await row()).customized, isFalse);

    await templates.setPinned(id, true);
    await templates.archive(id);
    await templates.unarchive(id);
    expect((await row()).customized, isFalse);

    await templates.edit(id, const MealTemplatesCompanion(kcal: Value(120)));
    final edited = await row();
    expect(edited.kcal, 120);
    expect(edited.customized, isTrue);
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

  test('肌酸劑量：預設 5 g、指定劑量、之後沿用上次', () async {
    final checks = CheckRepository(db);
    final d1 = DateTime(2026, 10, 1);
    final d2 = DateTime(2026, 10, 2);
    final d3 = DateTime(2026, 10, 3);

    expect(await checks.nextAmount(CheckItem.creatine), 5);
    await checks.set(d1, CheckItem.creatine, true);
    expect(await checks.watchDayAmounts(d1).first, {CheckItem.creatine: 5.0});

    await checks.set(d2, CheckItem.creatine, true, amount: 3);
    await checks.set(d3, CheckItem.creatine, true);
    expect(await checks.watchDayAmounts(d3).first, {CheckItem.creatine: 3.0});

    // 改劑量是覆蓋同一天
    await checks.set(d3, CheckItem.creatine, true, amount: 10);
    expect(await checks.watchDayAmounts(d3).first, {CheckItem.creatine: 10.0});
    expect(await checks.since(d1), hasLength(3));
  });
}
