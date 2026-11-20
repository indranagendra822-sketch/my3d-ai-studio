import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const My3DAIStudioApp());
}

class My3DAIStudioApp extends StatelessWidget {
  const My3DAIStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My3D AI Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
