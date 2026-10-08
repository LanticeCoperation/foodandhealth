import 'package:flutter/material.dart';

import 'analysis/daily_dataset.dart';
import 'data/body_repository.dart';
import 'data/check_repository.dart';
import 'data/database.dart';
import 'data/food_repository.dart';
import 'data/template_repository.dart';
import 'screens/body_screen.dart';
import 'screens/food_screen.dart';
import 'screens/trend_screen.dart';
import 'services/health_service.dart';

void main() {
  runApp(BodyLabApp(services: AppServices(AppDatabase(), HealthService())));
}

/// App 共用的資料庫、健康資料與 repository。
class AppServices {
  AppServices(this.db, this.health)
    : body = BodyRepository(db, health),
      food = FoodRepository(db),
      templates = TemplateRepository(db),
      checks = CheckRepository(db) {
    dataset = DatasetRepository(db, body, food, checks);
  }

  final AppDatabase db;
  final HealthService health;
  final BodyRepository body;
  final FoodRepository food;
  final TemplateRepository templates;
  final CheckRepository checks;
  late final DatasetRepository dataset;
}

class BodyLabApp extends StatelessWidget {
  const BodyLabApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Body Lab',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
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
      BodyScreen(health: s.health, repository: s.body),
      FoodScreen(repository: s.food, templates: s.templates, checks: s.checks),
      TrendScreen(dataset: s.dataset),
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
        ],
      ),
    );
  }
}
