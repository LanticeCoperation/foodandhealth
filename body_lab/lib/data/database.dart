import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [DailyBodyMetrics, FoodEntries])
class AppDatabase extends _$AppDatabase {
  /// 不傳 [executor] 時使用 App 文件目錄下的 body_lab.sqlite；測試可傳記憶體資料庫。
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'body_lab'));

  @override
  int get schemaVersion => 1;

  // 之後改 schema：schemaVersion +1，並在這裡加 onUpgrade。
  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());
}

extension FoodEntryTotals on FoodEntry {
  double? get totalKcal => kcal == null ? null : kcal! * servings;
  double? get totalProteinG => proteinG == null ? null : proteinG! * servings;
  double? get totalCarbsG => carbsG == null ? null : carbsG! * servings;
  double? get totalFatG => fatG == null ? null : fatG! * servings;
}
