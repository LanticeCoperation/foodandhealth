import 'package:drift/drift.dart';

import 'database.dart';

/// 餐點範本：快速輸入外食與補充品。
class TemplateRepository {
  TemplateRepository(this._db);

  final AppDatabase _db;

  /// 未封存的範本：釘選優先，其次用得多、最近用過的。[query] 比對名稱。
  Stream<List<MealTemplate>> watchTemplates({String query = ''}) {
    final t = _db.mealTemplates;
    final q = query.trim();
    final select = _db.select(t)
      ..where((r) {
        final active = r.archived.equals(false);
        return q.isEmpty ? active : active & r.name.like('%$q%');
      })
      ..orderBy([
        (r) => OrderingTerm.desc(r.pinned),
        (r) => OrderingTerm.desc(r.useCount),
        (r) => OrderingTerm(expression: r.lastUsedAt, mode: OrderingMode.desc),
        (r) => OrderingTerm.asc(r.name),
      ]);
    return select.watch();
  }

  Stream<List<MealTemplate>> watchPinned() {
    final t = _db.mealTemplates;
    return (_db.select(t)
          ..where((r) => r.archived.equals(false) & r.pinned.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.id)]))
        .watch();
  }

  Future<int> add(MealTemplatesCompanion template) =>
      _db.into(_db.mealTemplates).insert(template);

  /// 只更新 [template] 有給值的欄位。
  Future<void> update(int id, MealTemplatesCompanion template) => (_db.update(
    _db.mealTemplates,
  )..where((r) => r.id.equals(id))).write(template);

  Future<void> setPinned(int id, bool pinned) =>
      update(id, MealTemplatesCompanion(pinned: Value(pinned)));

  /// 封存（從列表消失），舊紀錄仍保留 templateId。
  Future<void> archive(int id) =>
      update(id, const MealTemplatesCompanion(archived: Value(true)));

  Future<void> unarchive(int id) =>
      update(id, const MealTemplatesCompanion(archived: Value(false)));

  /// 依範本新增一筆飲食，營養素複製到紀錄上；同時更新使用次數。回傳新紀錄 id。
  Future<int> addEntryFromTemplate(
    MealTemplate template, {
    required DateTime eatenAt,
    double? servings,
    MealType? meal,
  }) {
    return _db.transaction(() async {
      final id = await _db
          .into(_db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              eatenAt: eatenAt,
              meal: meal ?? template.meal ?? MealType.forTime(eatenAt),
              name: template.name,
              servings: Value(servings ?? template.defaultServings),
              kcal: Value(template.kcal),
              proteinG: Value(template.proteinG),
              carbsG: Value(template.carbsG),
              fatG: Value(template.fatG),
              templateId: Value(template.id),
            ),
          );
      await _db.customUpdate(
        'UPDATE meal_templates SET use_count = use_count + 1, '
        'last_used_at = ? WHERE id = ?',
        variables: [Variable(DateTime.now()), Variable(template.id)],
        updates: {_db.mealTemplates},
      );
      return id;
    });
  }

  /// 把一筆飲食紀錄存成範本（份量倍率當作預設份量）。回傳範本 id。
  /// 已有的 [FoodEntry] 用 `toCompanion(true)` 轉過來。
  Future<int> addFromEntry(FoodEntriesCompanion e) => add(
    MealTemplatesCompanion.insert(
      name: e.name.value,
      meal: Value(e.meal.value),
      defaultServings: e.servings,
      kcal: e.kcal,
      proteinG: e.proteinG,
      carbsG: e.carbsG,
      fatG: e.fatG,
    ),
  );
}
