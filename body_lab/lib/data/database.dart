import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'database.steps.dart';

part 'database.g.dart';

/// 健康資料快取：每天一列，內容同 [BodyMetric]。
@DataClassName('DailyBodyMetricRow')
class DailyBodyMetrics extends Table {
  /// 當地日期 yyyy-MM-dd。
  TextColumn get day => text()();
  DateTimeColumn get measuredAt => dateTime()();
  RealColumn get weightKg => real()();
  RealColumn get bodyFatPercent => real().nullable()();
  RealColumn get leanMassKg => real().nullable()();
  BoolColumn get leanMassEstimated =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {day};
}

/// 存成文字，之後調整順序或新增值都不會弄亂舊資料。
enum MealType {
  breakfast('早餐'),
  lunch('午餐'),
  dinner('晚餐'),
  snack('點心');

  const MealType(this.label);
  final String label;

  /// 依時間猜餐別。
  static MealType forTime(DateTime t) {
    final h = t.hour;
    if (h < 10) return breakfast;
    if (h < 14) return lunch;
    if (h >= 17 && h < 21) return dinner;
    return snack;
  }
}

/// 飲食紀錄。營養素都是「每份」的值，實際攝取 = 每份 × [servings]。
@TableIndex(name: 'food_entries_eaten_at', columns: {#eatenAt})
class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get eatenAt => dateTime()();
  TextColumn get meal => textEnum<MealType>()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  RealColumn get servings => real().withDefault(const Constant(1.0))();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  TextColumn get note => text().nullable()();

  /// 從範本加入時記錄來源範本（v2）。營養素仍複製一份，之後改範本不影響舊紀錄。
  IntColumn get templateId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 餐點範本（v2）：常吃的外食 / 補充品，營養素是「每份」的值。
class MealTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// 預設餐別；null 表示依加入時間判斷。
  TextColumn get meal => textEnum<MealType>().nullable()();
  RealColumn get defaultServings => real().withDefault(const Constant(1.0))();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get fatG => real().nullable()();

  /// 釘選的範本顯示在飲食頁頂端，一鍵 +1。
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// 刪除只做封存，舊紀錄的 templateId 仍有效。
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 每日打勾項目，存成文字。
enum CheckItem {
  creatine('肌酸');

  const CheckItem(this.label);
  final String label;
}

/// 每日打勾（v2）：有紀錄 = 當天有做。
class DailyChecks extends Table {
  /// 當地日期 yyyy-MM-dd。
  TextColumn get day => text()();
  TextColumn get item => textEnum<CheckItem>()();
  DateTimeColumn get checkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {day, item};
}

@DriftDatabase(
  tables: [DailyBodyMetrics, FoodEntries, MealTemplates, DailyChecks],
)
class AppDatabase extends _$AppDatabase {
  /// 不傳 [executor] 時使用 App 文件目錄下的 body_lab.sqlite；測試可傳記憶體資料庫。
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'body_lab'));

  @override
  int get schemaVersion => 2;

  // 改 schema 的流程：schemaVersion +1 → dart run build_runner build →
  // dart run drift_dev make-migrations → 在 stepByStep 補上 fromNToN+1。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaultTemplates();
    },
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.mealTemplates);
        await m.createTable(schema.dailyChecks);
        await m.addColumn(schema.foodEntries, schema.foodEntries.templateId);
        await _seedDefaultTemplates();
      },
    ),
  );

  /// 預設釘選「蛋白粉」範本，數值可在範本管理修改。
  /// 用 SQL 寫死，避免之後 schema 再變時舊的 migration 跟著變。
  Future<void> _seedDefaultTemplates() => customStatement(
    "INSERT INTO meal_templates "
    "(name, default_servings, kcal, protein_g, carbs_g, fat_g, pinned) "
    "VALUES ('蛋白粉（1 匙）', 1, 120, 24, 3, 1.5, 1)",
  );
}

extension FoodEntryTotals on FoodEntry {
  double? get totalKcal => kcal == null ? null : kcal! * servings;
  double? get totalProteinG => proteinG == null ? null : proteinG! * servings;
  double? get totalCarbsG => carbsG == null ? null : carbsG! * servings;
  double? get totalFatG => fatG == null ? null : fatG! * servings;
}
