import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/settings_repository.dart';
import 'package:body_lab/services/catalog_updater.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('沒設定過：回 null', () async {
    expect(await settings.geminiApiKey(), isNull);
  });

  test('存了之後讀得回來', () async {
    await settings.setGeminiApiKey('AIza-test');
    expect(await settings.geminiApiKey(), 'AIza-test');
  });

  test('前後空白會去掉', () async {
    await settings.setGeminiApiKey('  AIza-test  ');
    expect(await settings.geminiApiKey(), 'AIza-test');
  });

  test('存空字串等於清掉', () async {
    await settings.setGeminiApiKey('AIza-test');
    await settings.setGeminiApiKey('   ');
    expect(await settings.geminiApiKey(), isNull);
  });

  test('重複存：後面蓋掉前面，不會出現兩筆', () async {
    await settings.setGeminiApiKey('first');
    await settings.setGeminiApiKey('second');
    expect(await settings.geminiApiKey(), 'second');
    expect(await db.select(db.settings).get(), hasLength(1));
  });

  test('清掉目錄版本不會動到 API key', () async {
    await settings.setGeminiApiKey('AIza-test');
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: kCatalogVersionKey, value: '7'),
        );

    await settings.clearCatalogVersion();

    expect(await settings.geminiApiKey(), 'AIza-test');
    expect(await CatalogUpdater(db).appliedVersion(), 0);
  });
}
