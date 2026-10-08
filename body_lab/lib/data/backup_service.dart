import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// 備份檔格式版本；改了內容結構就 +1，並在 [BackupService.restore] 處理舊版。
const int kBackupFormat = 1;

class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 匯入 / 匯出的筆數。
class BackupCounts {
  const BackupCounts({
    required this.foodEntries,
    required this.templates,
    required this.checks,
    required this.phases,
    required this.hasProfile,
  });

  final int foodEntries;
  final int templates;
  final int checks;
  final int phases;
  final bool hasProfile;

  @override
  String toString() =>
      '飲食 $foodEntries 筆、一鍵項目 $templates 個、打勾 $checks 天、'
      '階段 $phases 個${hasProfile ? '、個人資料' : ''}';
}

/// 使用者自己輸入的資料備份成 JSON：飲食、一鍵項目、每日打勾、實驗階段、個人資料。
///
/// 身體組成與活動消耗的快取不備份，正本在 Apple 健康，重新同步就會回來。
class BackupService {
  BackupService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> export() async {
    final food = await _db.select(_db.foodEntries).get();
    final templates = await _db.select(_db.mealTemplates).get();
    final checks = await _db.select(_db.dailyChecks).get();
    final phases = await _db.select(_db.phases).get();
    final profile = await _db.select(_db.profiles).getSingleOrNull();
    return {
      'app': 'body_lab',
      'format': kBackupFormat,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': _clock().toIso8601String(),
      'foodEntries': [for (final e in food) e.toJson()],
      'mealTemplates': [for (final t in templates) t.toJson()],
      'dailyChecks': [for (final c in checks) c.toJson()],
      'phases': [for (final p in phases) p.toJson()],
      'profile': profile?.toJson(),
    };
  }

  Future<String> exportJson() async =>
      const JsonEncoder.withIndent(' ').convert(await export());

  /// 先檢查格式，回傳裡面有幾筆（給確認對話框用），不寫入資料庫。
  BackupCounts inspect(Map<String, dynamic> json) {
    _checkHeader(json);
    List<dynamic> list(String key) => (json[key] as List?) ?? const [];
    return BackupCounts(
      foodEntries: list('foodEntries').length,
      templates: list('mealTemplates').length,
      checks: list('dailyChecks').length,
      phases: list('phases').length,
      hasProfile: json['profile'] != null,
    );
  }

  /// 用備份取代目前的飲食、一鍵項目、打勾、階段、個人資料（一個 transaction，失敗就全部不變）。
  Future<BackupCounts> restore(Map<String, dynamic> json) async {
    final counts = inspect(json);
    List<Map<String, dynamic>> list(String key) => [
      for (final e in (json[key] as List?) ?? const [])
        e as Map<String, dynamic>,
    ];

    final List<FoodEntry> food;
    final List<MealTemplate> templates;
    final List<DailyCheck> checks;
    final List<Phase> phases;
    final Profile? profile;
    try {
      food = list('foodEntries').map(FoodEntry.fromJson).toList();
      templates = list('mealTemplates').map(MealTemplate.fromJson).toList();
      checks = list('dailyChecks').map(DailyCheck.fromJson).toList();
      phases = list('phases').map(Phase.fromJson).toList();
      final p = json['profile'];
      profile = p == null ? null : Profile.fromJson(p as Map<String, dynamic>);
    } catch (e) {
      throw BackupFormatException('備份檔內容有誤：$e');
    }

    await _db.transaction(() async {
      for (final TableInfo<Table, dynamic> table in [
        _db.foodEntries,
        _db.mealTemplates,
        _db.dailyChecks,
        _db.phases,
        _db.profiles,
      ]) {
        await _db.delete(table).go();
      }
      await _db.batch((b) {
        b.insertAll(_db.mealTemplates, templates);
        b.insertAll(_db.foodEntries, food);
        b.insertAll(_db.dailyChecks, checks);
        b.insertAll(_db.phases, phases);
        if (profile != null) b.insert(_db.profiles, profile);
      });
    });
    return counts;
  }

  void _checkHeader(Map<String, dynamic> json) {
    if (json['app'] != 'body_lab') {
      throw BackupFormatException('這不是 Body Lab 的備份檔');
    }
    final format = json['format'];
    if (format is! int || format > kBackupFormat) {
      throw BackupFormatException('備份檔來自較新版本的 App，請先更新 App');
    }
  }
}
