import 'package:drift/drift.dart';

import 'database.dart';

/// 預設一鍵項目目錄（assets/food_templates.json，同一份也放在 GitHub 供更新）。
///
/// ```json
/// { "version": 1, "items": [ { "key": "egg", "name": "雞蛋（1 顆）",
///   "servings": 1, "kcal": 75, "protein": 7, "carbs": 1, "fat": 5, "pinned": true } ] }
/// ```
class TemplateCatalog {
  const TemplateCatalog({required this.version, required this.items});

  /// 每次改內容就 +1；App 只套用比上次更新的版本。
  final int version;
  final List<CatalogItem> items;

  /// 解析 JSON；格式錯誤（缺欄位、key 重複）丟 [FormatException]。
  factory TemplateCatalog.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) throw const FormatException('缺少 version');
    final raw = json['items'];
    if (raw is! List) throw const FormatException('缺少 items');
    final items = [
      for (final e in raw)
        CatalogItem.fromJson(
          e is Map<String, dynamic>
              ? e
              : throw const FormatException('items 必須是物件'),
        ),
    ];
    final keys = <String>{};
    for (final i in items) {
      if (!keys.add(i.key)) throw FormatException('key 重複：${i.key}');
    }
    return TemplateCatalog(version: version, items: items);
  }
}

class CatalogItem {
  const CatalogItem({
    required this.key,
    required this.name,
    required this.servings,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.pinned = true,
  });

  final String key;
  final String name;
  final double servings;
  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;

  /// 新增時是否置頂；已存在的項目不改置頂狀態。
  final bool pinned;

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final name = json['name'];
    final kcal = json['kcal'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('項目缺少 key');
    }
    if (name is! String || name.isEmpty) {
      throw FormatException('項目 $key 缺少 name');
    }
    if (kcal is! num) throw FormatException('項目 $key 缺少 kcal');
    double? optional(String field) {
      final v = json[field];
      if (v == null) return null;
      if (v is! num) throw FormatException('項目 $key 的 $field 不是數字');
      return v.toDouble();
    }

    return CatalogItem(
      key: key,
      name: name,
      servings: optional('servings') ?? 1,
      kcal: kcal.toDouble(),
      protein: optional('protein'),
      carbs: optional('carbs'),
      fat: optional('fat'),
      pinned: json['pinned'] as bool? ?? true,
    );
  }

  /// 目錄決定的欄位（不含置頂、封存、使用次數）。
  MealTemplatesCompanion toCompanion() => MealTemplatesCompanion(
    name: Value(name),
    defaultServings: Value(servings),
    kcal: Value(kcal),
    proteinG: Value(protein),
    carbsG: Value(carbs),
    fatG: Value(fat),
    sourceKey: Value(key),
  );
}

/// [applyCatalog] 的結果。
class CatalogApplyResult {
  const CatalogApplyResult({required this.added, required this.updated});

  final int added;
  final int updated;

  bool get changed => added > 0 || updated > 0;
}

/// 把目錄合併進資料庫：
///
/// - key 不存在：新增（置頂依目錄）。
/// - key 存在、未封存、使用者沒改過：名稱 / 份量 / 營養素更新成目錄的值。
/// - 使用者改過（customized）或已封存：不動，也不會重新加回來。
/// - 舊資料（v11 之前種下的預設項目）沒有 key：同名、沒 key、沒改過的那一筆接上 key，
///   視為更新，不重複新增。
///
/// 重複套用同一份目錄不會有任何變動。
Future<CatalogApplyResult> applyCatalog(
  AppDatabase db,
  TemplateCatalog catalog,
) {
  return db.transaction(() async {
    final t = db.mealTemplates;
    final existing = await db.select(t).get();
    final byKey = {
      for (final row in existing)
        if (row.sourceKey != null) row.sourceKey!: row,
    };
    var added = 0;
    var updated = 0;

    for (final item in catalog.items) {
      var row = byKey[item.key];
      row ??= existing
          .where(
            (r) =>
                r.sourceKey == null &&
                !r.customized &&
                !r.archived &&
                r.name == item.name,
          )
          .firstOrNull;

      if (row == null) {
        await db
            .into(t)
            .insert(item.toCompanion().copyWith(pinned: Value(item.pinned)));
        added++;
        continue;
      }
      if (row.customized || row.archived) continue;
      if (_sameAsCatalog(row, item)) continue;
      await (db.update(
        t,
      )..where((r) => r.id.equals(row!.id))).write(item.toCompanion());
      updated++;
    }
    return CatalogApplyResult(added: added, updated: updated);
  });
}

bool _sameAsCatalog(MealTemplate row, CatalogItem item) =>
    row.sourceKey == item.key &&
    row.name == item.name &&
    row.defaultServings == item.servings &&
    row.kcal == item.kcal &&
    row.proteinG == item.protein &&
    row.carbsG == item.carbs &&
    row.fatG == item.fat;
