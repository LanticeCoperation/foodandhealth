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
  group('同步欄位', _syncTests);
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

  test('watchDailyTotalsSince 依天加總，新增紀錄後重新發出', () async {
    final stream = repo.watchDailyTotalsSince(DateTime(2026, 10, 8));
    await repo.add(entry(DateTime(2026, 10, 7, 20), '前一天', kcal: 999));
    await repo.add(
      entry(DateTime(2026, 10, 8, 8), '早餐', kcal: 400, protein: 30),
    );
    await repo.add(
      entry(DateTime(2026, 10, 8, 12), '午餐', servings: 2, kcal: 300),
    );

    final totals = await stream.firstWhere(
      (m) => m[DateTime(2026, 10, 8)]?.kcal == 1000,
    );
    expect(totals.keys, [DateTime(2026, 10, 8)]);
    expect(totals[DateTime(2026, 10, 8)]!.proteinG, 30);
  });
}

void _syncTests() {
  late AppDatabase db;
  late FoodRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = FoodRepository(db);
  });
  tearDown(() => db.close());

  Future<FoodEntry> only() => db.select(db.foodEntries).getSingle();

  test('新增的紀錄自動拿到 RFC 4122 v4 的 syncId，並標成待上傳', () async {
    await repo.add(entry(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    final row = await only();
    expect(
      row.syncId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(row.pendingSync, isTrue);
  });

  test('兩筆的 syncId 不會相同', () async {
    await repo.add(entry(DateTime(2026, 11, 7, 12), 'A'));
    await repo.add(entry(DateTime(2026, 11, 7, 13), 'B'));
    final rows = await db.select(db.foodEntries).get();
    expect(rows.map((r) => r.syncId).toSet(), hasLength(2));
  });

  test('編輯走畫面那條路（copyWith().toCompanion(true)）不會換掉 syncId', () async {
    await repo.add(entry(DateTime(2026, 11, 7, 12), '午餐', kcal: 600));
    final before = await only();
    // 模擬同步完成
    await db
        .update(db.foodEntries)
        .write(const FoodEntriesCompanion(pendingSync: Value(false)));

    final edited = (await only()).copyWith(kcal: const Value(800));
    await repo.save(edited.toCompanion(true));

    final after = await only();
    expect(after.syncId, before.syncId, reason: '換了 syncId 另一台會看成新的一筆');
    expect(after.kcal, 800);
    expect(after.pendingSync, isTrue, reason: '改過就要重新上傳');
  });

  test('刪除會把 syncId 記進待辦表；復原則取消待辦', () async {
    await repo.add(entry(DateTime(2026, 11, 7, 12), '午餐'));
    final row = await only();

    await repo.delete(row.id);
    expect(await db.select(db.foodEntries).get(), isEmpty);
    final pending = await db.select(db.pendingDeletes).getSingle();
    expect(pending.syncId, row.syncId);

    await repo.restore(row);
    expect(await db.select(db.pendingDeletes).get(), isEmpty);
    expect((await only()).syncId, row.syncId);
  });
}
