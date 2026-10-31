import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/template_catalog.dart';

/// GitHub 上的預設項目目錄（main 分支的 raw 檔）。
const kCatalogUrl =
    'https://raw.githubusercontent.com/LanticeCoperation/foodandhealth/main/body_lab/assets/food_templates.json';

const kCatalogAsset = 'assets/food_templates.json';

/// settings 表裡記住的「已套用的目錄版本」。
const kCatalogVersionKey = 'catalogVersion';

/// [CatalogUpdater.fetchAndApply] 的結果。
sealed class CatalogOutcome {
  const CatalogOutcome();
}

class CatalogUpdated extends CatalogOutcome {
  const CatalogUpdated(this.result);
  final CatalogApplyResult result;
}

class CatalogUpToDate extends CatalogOutcome {
  const CatalogUpToDate();

  @override
  bool operator ==(Object other) => other is CatalogUpToDate;

  @override
  int get hashCode => 0;
}

class CatalogFailed extends CatalogOutcome {
  const CatalogFailed(this.error);
  final Object error;
}

/// 預設一鍵項目目錄的更新：啟動時套用內建的 JSON，再從 GitHub 抓較新的版本合併。
class CatalogUpdater {
  CatalogUpdater(
    this._db, {
    Future<String> Function()? loadBundled,
    Future<String> Function()? fetchRemote,
  }) : _loadBundled = loadBundled ?? _loadAsset,
       _fetchRemote = fetchRemote ?? _fetchUrl;

  final AppDatabase _db;
  final Future<String> Function() _loadBundled;
  final Future<String> Function() _fetchRemote;

  static Future<String> _loadAsset() => rootBundle.loadString(kCatalogAsset);

  static Future<String> _fetchUrl() async {
    final response = await http
        .get(Uri.parse(kCatalogUrl))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'HTTP ${response.statusCode}',
        response.request?.url,
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  /// 上次套用的目錄版本；沒有是 0。
  Future<int> appliedVersion() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(kCatalogVersionKey))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _setAppliedVersion(int version) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: kCatalogVersionKey, value: '$version'),
      );

  /// 套用打包在 App 裡的目錄（每次啟動都做，重複套用不會有變動），
  /// 版本比記住的新時更新記住的版本。
  Future<CatalogApplyResult> applyBundled() async {
    final catalog = _parse(await _loadBundled());
    final result = await applyCatalog(_db, catalog);
    if (catalog.version > await appliedVersion()) {
      await _setAppliedVersion(catalog.version);
    }
    return result;
  }

  /// 從 GitHub 抓目錄，版本比記住的新才合併。網路或格式問題回傳 [CatalogFailed]。
  Future<CatalogOutcome> fetchAndApply() async {
    try {
      final catalog = _parse(await _fetchRemote());
      if (catalog.version <= await appliedVersion()) {
        return const CatalogUpToDate();
      }
      final result = await applyCatalog(_db, catalog);
      await _setAppliedVersion(catalog.version);
      return CatalogUpdated(result);
    } catch (e, st) {
      debugPrint('[catalog] 更新失敗：$e\n$st');
      return CatalogFailed(e);
    }
  }

  static TemplateCatalog _parse(String text) =>
      TemplateCatalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
}
