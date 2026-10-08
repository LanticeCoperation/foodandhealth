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

/// 實驗階段（v3）：一段期間固定改變某些做法（例如高蛋白 + 肌酸），看身體組成怎麼變。
class Phases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// 當地日期 yyyy-MM-dd，含頭含尾。
  TextColumn get startDay => text()();
  TextColumn get endDay => text()();

  /// 這階段改變了什麼、預期會怎樣。
  TextColumn get hypothesis => text().nullable()();

  /// 每日目標；熱量 ±10% 算達標，蛋白質達到即算。
  RealColumn get targetKcal => real().nullable()();
  RealColumn get targetProteinG => real().nullable()();

  /// 這階段是否每天吃肌酸。
  BoolColumn get creatine => boolean().withDefault(const Constant(false))();

  /// 結束後的心得。
  TextColumn get conclusion => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

enum Sex {
  male('男'),
  female('女');

  const Sex(this.label);
  final String label;
}

/// 活動量係數（TDEE = 基礎代謝 × 係數）。
enum ActivityLevel {
  sedentary('久坐', 1.2, '幾乎不運動、坐辦公室'),
  light('輕度', 1.375, '每週運動 1–3 天'),
  moderate('中度', 1.55, '每週運動 3–5 天'),
  high('高度', 1.725, '每週運動 6–7 天'),
  athlete('非常高', 1.9, '勞力工作或一天兩練');

  const ActivityLevel(this.label, this.factor, this.description);
  final String label;
  final double factor;
  final String description;
}

/// 每日消耗怎麼算。
enum EnergyMode {
  /// 基礎代謝 + 當天手錶記錄的活動消耗（沒有手錶資料的天用固定 TDEE）。
  watch('Apple Watch 活動消耗'),

  /// 固定 TDEE（基礎代謝 × 活動量係數）。
  fixed('固定 TDEE');

  const EnergyMode(this.label);
  final String label;
}

/// 每日活動消耗快取（v5），來自 Apple 健康 / Health Connect 的活動能量（已依來源去重）。
@DataClassName('DailyActivityRow')
class DailyActivity extends Table {
  /// 當地日期 yyyy-MM-dd。
  TextColumn get day => text()();
  RealColumn get activeKcal => real()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {day};
}

/// 自訂消耗（v6）：手錶沒記錄到的活動（例如沒戴錶的運動），加進當天的每日消耗。
class ExtraBurns extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 當地日期 yyyy-MM-dd。
  TextColumn get day => text()();
  RealColumn get kcal => real()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 個人資料（v4），只有一列（id = 1）。TDEE 算好後固定存下來，
/// 不隨每天體重變動；體重變化大時再到個人資料頁重算。
class Profiles extends Table {
  IntColumn get id => integer()();
  TextColumn get sex => textEnum<Sex>()();
  IntColumn get birthYear => integer()();
  RealColumn get heightCm => real()();
  TextColumn get activity => textEnum<ActivityLevel>()();

  /// 計算 TDEE 時用的體重。
  RealColumn get weightKg => real()();

  /// 固定的每日總消耗（kcal），可手動調整。
  RealColumn get tdeeKcal => real()();

  /// 每日消耗的算法（v5）。
  TextColumn get energyMode =>
      textEnum<EnergyMode>().withDefault(const Constant('watch'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    DailyBodyMetrics,
    FoodEntries,
    MealTemplates,
    DailyChecks,
    Phases,
    Profiles,
    DailyActivity,
    ExtraBurns,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 不傳 [executor] 時使用 App 文件目錄下的 body_lab.sqlite；測試可傳記憶體資料庫。
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'body_lab'));

  @override
  int get schemaVersion => 6;

  // 改 schema 的流程：schemaVersion +1 → dart run build_runner build →
  // dart run drift_dev make-migrations → 在 stepByStep 補上 fromNToN+1。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaultTemplates();
    },
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.mealTemplates);
        await m.createTable(schema.dailyChecks);
        await m.addColumn(schema.foodEntries, schema.foodEntries.templateId);
        await seedDefaultTemplates();
      },
      from2To3: (m, schema) async {
        await m.createTable(schema.phases);
      },
      from3To4: (m, schema) async {
        await m.createTable(schema.profiles);
      },
      from4To5: (m, schema) async {
        await m.createTable(schema.dailyActivity);
        await m.addColumn(schema.profiles, schema.profiles.energyMode);
      },
      from5To6: (m, schema) async {
        await m.createTable(schema.extraBurns);
      },
    ),
  );

  /// 預設釘選「蛋白粉」範本，數值可在範本管理修改。
  /// 用 SQL 寫死，避免之後 schema 再變時舊的 migration 跟著變。
  Future<void> seedDefaultTemplates() => customStatement(
    "INSERT INTO meal_templates "
    "(name, default_servings, kcal, protein_g, carbs_g, fat_g, pinned) "
    "VALUES ('蛋白粉（1 匙）', 1, 60, 12, 1.5, 0.75, 1)",
  );

  /// 清空所有資料，回到剛安裝的狀態（保留預設範本）。
  Future<void> clearAllData() => transaction(() async {
    for (final table in allTables) {
      await delete(table).go();
    }
    await seedDefaultTemplates();
  });
}

extension FoodEntryTotals on FoodEntry {
  double? get totalKcal => kcal == null ? null : kcal! * servings;
  double? get totalProteinG => proteinG == null ? null : proteinG! * servings;
  double? get totalCarbsG => carbsG == null ? null : carbsG! * servings;
  double? get totalFatG => fatG == null ? null : fatG! * servings;
}
