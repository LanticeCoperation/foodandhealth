import 'package:flutter/material.dart';

import 'screens/body_screen.dart';
import 'services/health_service.dart';

void main() {
  runApp(BodyLabApp(service: HealthService()));
}

class BodyLabApp extends StatelessWidget {
  const BodyLabApp({super.key, required this.service});

  final HealthService service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Body Lab',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: BodyScreen(service: service),
    );
  }
}
