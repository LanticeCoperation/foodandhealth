import 'package:flutter/material.dart';

import 'data/body_repository.dart';
import 'data/check_repository.dart';
import 'data/database.dart';
import 'data/food_repository.dart';
import 'data/template_repository.dart';
import 'screens/body_screen.dart';
import 'screens/food_screen.dart';
import 'services/health_service.dart';

void main() {
  final db = AppDatabase();
  final health = HealthService();
  runApp(
    BodyLabApp(
      health: health,
      bodyRepository: BodyRepository(db, health),
      foodRepository: FoodRepository(db),
      templateRepository: TemplateRepository(db),
      checkRepository: CheckRepository(db),
    ),
  );
}

class BodyLabApp extends StatelessWidget {
  const BodyLabApp({
    super.key,
    required this.health,
    required this.bodyRepository,
    required this.foodRepository,
    required this.templateRepository,
    required this.checkRepository,
  });

  final HealthService health;
  final BodyRepository bodyRepository;
  final FoodRepository foodRepository;
  final TemplateRepository templateRepository;
  final CheckRepository checkRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Body Lab',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: _HomeShell(
        body: BodyScreen(health: health, repository: bodyRepository),
        food: FoodScreen(
          repository: foodRepository,
          templates: templateRepository,
          checks: checkRepository,
        ),
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.body, required this.food});

  final Widget body;
  final Widget food;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: [widget.body, widget.food]),
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
        ],
      ),
    );
  }
}
