import '../services/catalog_updater.dart';
import 'database.dart';

/// 使用者自己申請、貼進設定頁的 Gemini API key。
const kGeminiApiKeySettingKey = 'geminiApiKey';

/// 同步伺服器的位址與金鑰，由使用者在設定頁填。
///
/// 刻意不內嵌進 App：位址一旦編進 .ipa / .apk，任何人解壓縮就看得到
/// 伺服器在哪。放在設定裡的話，發出去的檔案不含任何關於位置的資訊，
/// 換伺服器也不用重發版。
const kSyncUrlSettingKey = 'syncUrl';
const kSyncKeySettingKey = 'syncKey';

/// 讀寫 [Settings] 這張零碎設定表。
///
/// key 不會跟著備份匯出（[BackupService.export] 不含 settings），
/// 匯入時也只清掉目錄版本那一筆，見 [clearCatalogVersion]。
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> _get(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    final value = row?.value.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _set(String key, String? value) async {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      await (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();
      return;
    }
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: v));
  }

  Future<String?> geminiApiKey() => _get(kGeminiApiKeySettingKey);

  Future<void> setGeminiApiKey(String? value) =>
      _set(kGeminiApiKeySettingKey, value);

  Future<String?> syncUrl() => _get(kSyncUrlSettingKey);
  Future<String?> syncKey() => _get(kSyncKeySettingKey);

  /// 兩個一起設；任一個空的就等於關閉同步。
  Future<void> setSyncServer(String? url, String? key) async {
    await _set(kSyncUrlSettingKey, url);
    await _set(kSyncKeySettingKey, key);
  }

  /// 忘掉已套用的目錄版本，下次啟動重新套用預設項目目錄。
  /// 只刪這一筆，別的設定（例如 API key）要留著。
  Future<void> clearCatalogVersion() => (_db.delete(
    _db.settings,
  )..where((s) => s.key.equals(kCatalogVersionKey))).go();
}
