import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'analysis/daily_dataset.dart';
import 'data/body_repository.dart';
import 'data/check_repository.dart';
import 'data/database.dart';
import 'data/food_repository.dart';
import 'data/phase_repository.dart';
import 'data/profile_repository.dart';
import 'data/template_repository.dart';
import 'dev/demo_data_menu.dart';
import 'screens/body_screen.dart';
import 'screens/food_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/trend_screen.dart';
import 'services/health_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(BodyLabApp(services: AppServices(AppDatabase(), HealthService())));
}

/// App 共用的資料庫、健康資料與 repository。
class AppServices {
  AppServices(this.db, this.health)
    : body = BodyRepository(db, health),
      food = FoodRepository(db),
      templates = TemplateRepository(db),
      checks = CheckRepository(db),
      phases = PhaseRepository(db),
      profile = ProfileRepository(db) {
    dataset = DatasetRepository(db, body, food, checks, phases);
  }

  final AppDatabase db;
  final HealthService health;
  final BodyRepository body;
  final FoodRepository food;
  final TemplateRepository templates;
  final CheckRepository checks;
  final PhaseRepository phases;
  final ProfileRepository profile;
  late final DatasetRepository dataset;
}

/// 介面全是繁體中文，固定用 zh-Hant-TW（日期 / 時間選擇器、星期、上午下午）。
const kAppLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
  countryCode: 'TW',
);

class BodyLabApp extends StatelessWidget {
  const BodyLabApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Body Lab',
      locale: kAppLocale,
      supportedLocales: const [kAppLocale, Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: _HomeShell(services: services),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.services});

  final AppServices services;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    final s = widget.services;
    _pages = [
      BodyScreen(
        health: s.health,
        repository: s.body,
        extraActions: [
          ProfileButton(profile: s.profile, body: s.body),
          if (kDebugMode)
            DemoDataMenu(
              db: s.db,
              body: s.body,
              food: s.food,
              templates: s.templates,
              checks: s.checks,
              phases: s.phases,
              profile: s.profile,
            ),
        ],
      ),
      FoodScreen(
        repository: s.food,
        templates: s.templates,
        checks: s.checks,
        phases: s.phases,
        profile: s.profile,
      ),
      TrendScreen(dataset: s.dataset),
      AnalysisScreen(phases: s.phases, dataset: s.dataset, profile: s.profile),
    ];
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
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: '飲食',
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
