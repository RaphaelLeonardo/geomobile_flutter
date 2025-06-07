import 'package:flutter/material.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const GeomobileApp());
}

class GeomobileApp extends StatelessWidget {
  const GeomobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeomobileApp',
      theme: ThemeData(
        primaryColor: const Color(0xFF084783),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF084783),
          secondary: const Color(0xFF0083e2),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
