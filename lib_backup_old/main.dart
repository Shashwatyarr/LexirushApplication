// lib/main.dart

import 'package:flutter/material.dart';
import 'features/auth/screens/player_login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LexiRush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const PlayerLoginScreen(),
    );
  }
}