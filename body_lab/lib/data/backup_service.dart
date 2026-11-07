import 'dart:convert';

import 'package:drift/drift.dart';

import '../utils/uuid.dart';
import 'database.dart';
import 'settings_repository.dart';

/// 備份檔格式版本；改了內容結構就 +1，並在 [BackupService.restore] 處理舊版。
///
/// - 1：飲食、一鍵項目、打勾、階段、個人資料
/// - 2：加入自訂消耗（extraBurns）；讀 1 版時視為沒有
/// - 3：飲食紀錄帶 syncId / pendingSync；讀 2 版以下時現場補 syncId
const int kBackupFormat = 3;

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
    this.extraBurns = 0,
  });

  final int foodEntries;
  final int templates;
  final int checks;
  final int phases;
  final bool hasProfile;
  final int extraBurns;

  @override
  String toString() =>
      '飲食 $foodEntries 筆、一鍵項目 $templates 個、打勾 $checks 天、'
      '階段 $phases 個${extraBurns > 0 ? '、自訂消耗 $extraBurns 筆' : ''}'
      '${hasProfile ? '、個人資料' : ''}';
}

/// 使用者自己輸入的資料備份成 JSON：飲食、一鍵項目、每日打勾、實驗階段、個人資料、自訂消耗。
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
    final extra = await _db.select(_db.extraBurns).get();
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
      'extraBurns': [for (final e in extra) e.toJson()],
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
      extraBurns: list('extraBurns').length,
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
    final List<ExtraBurn> extra;
    try {
      // v12 之前的備份沒有 syncId / pendingSync。現場補一組新的 syncId，
      // 並標成待上傳——還原回來的就是這台的資料，本來就該送上去。
      // 上傳是以 syncId 為鍵的 upsert，所以同一筆重複送不會產生重複列。
      food = [
        for (final e in list('foodEntries'))
          FoodEntry.fromJson({
            'syncId': newUuidV4(),
            ...e,
            // 放在 spread 之後：格式 3 的備份可能帶 false，
            // 但還原回來的資料在這台就是待上傳（upsert 冪等，重送無害），
            // 而且伺服器有可能是重建過的。
            'pendingSync': true,
          }),
      ];
      // v11 之前的備份沒有 sourceKey / customized
      templates = [
        for (final t in list('mealTemplates'))
          MealTemplate.fromJson({'sourceKey': null, 'customized': false, ...t}),
      ];
      checks = list('dailyChecks').map(DailyCheck.fromJson).toList();
      phases = list('phases').map(Phase.fromJson).toList();
      final p = json['profile'];
      profile = p == null ? null : Profile.fromJson(p as Map<String, dynamic>);
      extra = list('extraBurns').map(ExtraBurn.fromJson).toList();
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
        _db.extraBurns,
      ]) {
        await _db.delete(table).go();
      }
      // 忘掉記住的目錄版本，下次啟動重新套用預設項目目錄。
      // 只清這一筆：別的設定（例如 Gemini API key）要留著。
      await SettingsRepository(_db).clearCatalogVersion();
      await _db.batch((b) {
        b.insertAll(_db.mealTemplates, templates);
        b.insertAll(_db.foodEntries, food);
        // 還原回來的 syncId 若還掛著刪除待辦，會在下次同步時被當成已刪除。
        b.deleteWhere(
          _db.pendingDeletes,
          (r) => r.syncId.isIn([for (final e in food) e.syncId].nonNulls),
        );
        b.insertAll(_db.dailyChecks, checks);
        b.insertAll(_db.phases, phases);
        if (profile != null) b.insert(_db.profiles, profile);
        b.insertAll(_db.extraBurns, extra);
      });
      // v9 之前的備份沒有雞蛋、牛奶等預設項目，補上（已有同名就跳過）
      final schema = json['schemaVersion'];
      if (schema is! int || schema < 9) await _db.seedBasicTemplates();
      // v11 之前的備份沒有 customized / sourceKey，照升級的規則補
      if (schema is! int || schema < 11) await _db.adoptLegacyTemplates();
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
