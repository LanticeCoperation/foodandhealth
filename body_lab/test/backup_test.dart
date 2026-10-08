import 'dart:convert';

import 'package:body_lab/data/backup_service.dart';
import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/extra_burn_repository.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/data/profile_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 這個測試本來就同時開兩個資料庫（來源與目標）
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase source;
  late AppDatabase target;

  setUp(() {
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<void> seed(AppDatabase db) async {
    final templates = TemplateRepository(db);
    final powder = (await templates.watchPinned().first).single;
    await templates.addEntryFromTemplate(
      powder,
      eatenAt: DateTime(2026, 10, 8, 16),
      servings: 2,
    );
    await FoodRepository(db).add(
      FoodEntriesCompanion.insert(
        eatenAt: DateTime(2026, 10, 8, 12, 30),
        meal: MealType.lunch,
        name: MealType.lunch.label,
        kcal: const Value(650),
        proteinG: const Value(35),
        fatG: const Value(20),
      ),
    );
    await CheckRepository(db)
        .set(DateTime(2026, 10, 8), CheckItem.creatine, true);
    await PhaseRepository(db).save(
      PhasesCompanion.insert(
        name: '減脂',
        startDay: '2026-10-01',
        endDay: '2026-10-28',
        targetKcal: const Value(1800),
        creatine: const Value(true),
      ),
    );
    await ExtraBurnRepository(db).add(DateTime(2026, 10, 8), 350, note: '爬山');
    await ProfileRepository(db).save(
      sex: Sex.male,
      birthYear: 1991,
      heightCm: 175,
      activity: ActivityLevel.light,
      weightKg: 76,
      tdeeKcal: 2320,
    );
  }

  test('匯出後匯入到另一個資料庫，內容完全相同', () async {
    await seed(source);
    final json = await BackupService(source).exportJson();

    // 目標資料庫原本有別的資料，匯入後要被取代
    await FoodRepository(target).add(
      FoodEntriesCompanion.insert(
        eatenAt: DateTime(2026, 1, 1),
        meal: MealType.snack,
        name: '舊資料',
      ),
    );

    final counts = await BackupService(target)
        .restore(jsonDecode(json) as Map<String, dynamic>);
    expect(counts.foodEntries, 2);
    expect(counts.templates, 1);
    expect(counts.checks, 1);
    expect(counts.phases, 1);
    expect(counts.hasProfile, isTrue);
    expect(counts.extraBurns, 1);

    Future<List<dynamic>> rows(AppDatabase db) async => [
      await db.select(db.foodEntries).get(),
      await db.select(db.mealTemplates).get(),
      await db.select(db.dailyChecks).get(),
      await db.select(db.phases).get(),
      await db.select(db.profiles).get(),
      await db.select(db.extraBurns).get(),
    ];
    expect(await rows(target), await rows(source));
  });

  test('一鍵項目的 templateId 對應保留（今天的蛋白粉份數正確）', () async {
    await seed(source);
    final json = await BackupService(source).export();
    await BackupService(target)
        .restore(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

    final powder = (await TemplateRepository(
      target,
    ).watchPinned().first).single;
    final day = await FoodRepository(target)
        .watchDay(DateTime(2026, 10, 8))
        .first;
    final scoops = day
        .where((e) => e.templateId == powder.id)
        .fold<double>(0, (s, e) => s + e.servings);
    expect(scoops, 2);
  });

  test('不是本 App 的檔案、較新版本的格式都拒絕，且不動目前資料', () async {
    await seed(target);
    final service = BackupService(target);

    expect(
      () => service.restore({'app': 'other'}),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => service.restore({'app': 'body_lab', 'format': kBackupFormat + 1}),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => service.restore({
        'app': 'body_lab',
        'format': kBackupFormat,
        'foodEntries': [
          {'壞掉': true},
        ],
      }),
      throwsA(isA<BackupFormatException>()),
    );

    expect(await target.select(target.foodEntries).get(), hasLength(2));
    expect(await target.select(target.profiles).getSingleOrNull(), isNotNull);
  });

  test('讀得懂舊版（1 版）備份：沒有自訂消耗', () async {
    await seed(source);
    final json = await BackupService(source).export();
    json['format'] = 1;
    json.remove('extraBurns');
    final counts = await BackupService(target).restore(json);
    expect(counts.extraBurns, 0);
    expect(await target.select(target.extraBurns).get(), isEmpty);
    expect(await target.select(target.foodEntries).get(), hasLength(2));
  });

  test('inspect 只看內容不寫入', () async {
    await seed(source);
    final json = await BackupService(source).export();
    final counts = BackupService(target).inspect(json);
    expect(counts.toString(), '飲食 2 筆、一鍵項目 1 個、打勾 1 天、階段 1 個、自訂消耗 1 筆、個人資料');
    // target 只有預設的蛋白粉項目，沒有紀錄
    expect(await target.select(target.foodEntries).get(), isEmpty);
  });
}
