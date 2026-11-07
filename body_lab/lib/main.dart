import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads/analysis_banner_ad.dart';

import 'analysis/daily_dataset.dart';
import 'data/activity_repository.dart';
import 'data/backup_service.dart';
import 'data/body_repository.dart';
import 'data/check_repository.dart';
import 'data/extra_burn_repository.dart';
import 'data/database.dart';
import 'data/food_repository.dart';
import 'data/phase_repository.dart';
import 'data/profile_repository.dart';
import 'data/settings_repository.dart';
import 'data/template_repository.dart';
import 'dev/demo_data_menu.dart';
import 'screens/body_screen.dart';
import 'screens/food_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quick_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/trend_screen.dart';
import 'services/catalog_updater.dart';
import 'services/health_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'services/sync_config.dart';
import 'services/sync_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/app_update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kAdsEnabled) MobileAds.instance.initialize();
  // 有設定同步伺服器才初始化。supabase_flutter 負責把登入的 session 存到
  // 裝置上，沒有它的話 App 一關掉就要重新登入。
  if (SyncConfig.configured) {
    await Supabase.initialize(
      url: SyncConfig.url,
      publishableKey: SyncConfig.publishableKey,
    );
  }
  runApp(
    BodyLabApp(
      services: AppServices(AppDatabase(), HealthService()),
      analysisBanner: kAdsEnabled ? const AnalysisBannerAd() : null,
    ),
  );
}

/// App 共用的資料庫、健康資料與 repository。
class AppServices {
  AppServices(this.db, this.health, {CatalogUpdater? catalog})
    : catalog = catalog ?? CatalogUpdater(db),
      body = BodyRepository(db, health),
      food = FoodRepository(db),
      templates = TemplateRepository(db),
      checks = CheckRepository(db),
      phases = PhaseRepository(db),
      profile = ProfileRepository(db),
      activity = ActivityRepository(db, health),
      backup = BackupService(db),
      extraBurns = ExtraBurnRepository(db),
      settings = SettingsRepository(db),
      sync = SyncController(db) {
    dataset = DatasetRepository(
      db,
      body,
      food,
      checks,
      phases,
      activity: activity,
      extraBurns: extraBurns,
    );
  }

  final AppDatabase db;
  final HealthService health;

  /// 零碎設定（Gemini API key、同步的歸屬與游標）。
  final SettingsRepository settings;

  /// 跨裝置同步。沒帶 --dart-define 的伺服器設定時 available 是 false，
  /// 設定頁不會出現同步區塊，App 行為跟加同步之前一樣。
  final SyncController sync;

  /// 預設一鍵項目目錄：啟動時套用內建的，再從 GitHub 抓更新。
  final CatalogUpdater catalog;
  final BodyRepository body;
  final FoodRepository food;
  final TemplateRepository templates;
  final CheckRepository checks;
  final PhaseRepository phases;
  final ProfileRepository profile;
  final ActivityRepository activity;
  final BackupService backup;
  final ExtraBurnRepository extraBurns;
  late final DatasetRepository dataset;
}

/// 介面全是繁體中文，固定用 zh-Hant-TW（日期 / 時間選擇器、星期、上午下午）。
const kAppLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
  countryCode: 'TW',
);

class BodyLabApp extends StatelessWidget {
  const BodyLabApp({super.key, required this.services, this.analysisBanner});

  final AppServices services;

  /// 分析頁底部的廣告；只有 main() 會傳，測試不載入廣告外掛。
  final Widget? analysisBanner;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Body Lab',
      locale: kAppLocale,
      supportedLocales: const [kAppLocale, Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: UpdateChecker(
        child: _HomeShell(services: services, analysisBanner: analysisBanner),
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.services, this.analysisBanner});

  final AppServices services;
  final Widget? analysisBanner;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late final List<Widget> _pages;

  /// 啟動與回到前景時各試一次同步。
  ///
  /// 伺服器在家裡的 NAS 上，人不在家時一定連不到——那是正常狀況，
  /// [SyncController.autoSync] 會安靜地把變更留在本機排隊，回到家再送。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.services.sync.autoSync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.services.sync.available) {
      unawaited(widget.services.sync.autoSync());
    }
    final s = widget.services;
    _pages = [
      BodyScreen(
        health: s.health,
        repository: s.body,
        activity: s.activity,
        food: s.food,
        phases: s.phases,
        profile: s.profile,
        extraActions: [
          ProfileButton(
            profile: s.profile,
            body: s.body,
            backup: s.backup,
            settings: s.settings,
            sync: s.sync.available ? s.sync : null,
          ),
          if (kDebugMode)
            DemoDataMenu(
              db: s.db,
              body: s.body,
              food: s.food,
              templates: s.templates,
              checks: s.checks,
              phases: s.phases,
              profile: s.profile,
              activity: s.activity,
              extraBurns: s.extraBurns,
            ),
        ],
      ),
      FoodScreen(
        repository: s.food,
        settings: s.settings,
        checks: s.checks,
        phases: s.phases,
        profile: s.profile,
        activity: s.activity,
        extraBurns: s.extraBurns,
      ),
      QuickScreen(templates: s.templates, food: s.food, updater: s.catalog),
      TrendScreen(dataset: s.dataset, profile: s.profile),
      AnalysisScreen(
        phases: s.phases,
        dataset: s.dataset,
        profile: s.profile,
        bottomBanner: widget.analysisBanner,
      ),
    ];
    _updateCatalog();
  }

  /// 啟動時先套用 App 內建的預設項目目錄，再背景從 GitHub 抓較新的版本；
  /// 有變動時提示一下。沒網路就靜靜跳過。
  Future<void> _updateCatalog() async {
    final updater = widget.services.catalog;
    try {
      await updater.applyBundled();
    } catch (e, st) {
      debugPrint('[catalog] 內建目錄套用失敗：$e\n$st');
    }
    final outcome = await updater.fetchAndApply();
    if (!mounted) return;
    if (outcome case CatalogUpdated(:final result) when result.changed) {
      final parts = [
        if (result.added > 0) '新增 ${result.added} 個',
        if (result.updated > 0) '更新 ${result.updated} 個',
      ];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('預設項目已更新：${parts.join('、')}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_weight_outlined),
            selectedIcon: Icon(Icons.monitor_weight),
            label: '身體',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '紀錄',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: '快速',
          ),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '趨勢'),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: '分析',
          ),
        ],
      ),
    );
  }
}
