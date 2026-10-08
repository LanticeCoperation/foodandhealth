import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

FoodEntriesCompanion entry(
  DateTime at,
  String name, {
  double servings = 1,
  double? kcal,
  double? protein,
}) => FoodEntriesCompanion.insert(
  eatenAt: at,
  meal: MealType.lunch,
  name: name,
  servings: Value(servings),
  kcal: Value(kcal),
  proteinG: Value(protein),
);

void main() {
  late AppDatabase db;
  late FoodRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = FoodRepository(db);
  });

  tearDown(() => db.close());

  test('watchDay 只包含當天 00:00 到隔天 00:00，依時間排序', () async {
    await repo.add(entry(DateTime(2026, 10, 8, 12, 30), '雞腿便當'));
    await repo.add(entry(DateTime(2026, 10, 8, 0, 0), '宵夜'));
    await repo.add(entry(DateTime(2026, 10, 7, 23, 59), '前一天'));
    await repo.add(entry(DateTime(2026, 10, 9, 0, 0), '隔天'));

    final day = await repo.watchDay(DateTime(2026, 10, 8, 15)).first;
    expect(day.map((e) => e.name), ['宵夜', '雞腿便當']);
  });

  test('新增、修改、刪除、復原', () async {
    final id = await repo.add(entry(DateTime(2026, 10, 8, 8), '蛋餅'));
    var e = (await repo.watchDay(DateTime(2026, 10, 8)).first).single;
    expect(e.id, id);
    expect(e.servings, 1);
    expect(e.meal, MealType.lunch);

    await repo.save(e.copyWith(name: '起司蛋餅', meal: MealType.breakfast));
    e = (await repo.watchDay(DateTime(2026, 10, 8)).first).single;
    expect(e.name, '起司蛋餅');
    expect(e.meal, MealType.breakfast);

    await repo.delete(id);
    expect(await repo.watchDay(DateTime(2026, 10, 8)).first, isEmpty);

    await repo.restore(e);
    e = (await repo.watchDay(DateTime(2026, 10, 8)).first).single;
    expect((e.id, e.name), (id, '起司蛋餅'));
  });

  test('總量 = 每份 × 份量倍率，沒填熱量的筆數另外記', () async {
    await repo.add(
      entry(DateTime(2026, 10, 8, 12), '便當', kcal: 800, protein: 30),
    );
    await repo.add(
      entry(
        DateTime(2026, 10, 8, 15),
        '蛋白粉',
        servings: 2,
        kcal: 120,
        protein: 24,
      ),
    );
    await repo.add(entry(DateTime(2026, 10, 8, 19), '朋友請的'));

    final entries = await repo.watchDay(DateTime(2026, 10, 8)).first;
    final totals = DayTotals.of(entries);
    expect(totals.kcal, 1040);
    expect(totals.proteinG, 78);
    expect(totals.carbsG, 0);
    expect(totals.missingKcal, 1);
    expect(entries[1].totalKcal, 240);
    expect(entries[2].totalKcal, isNull);
  });
}
