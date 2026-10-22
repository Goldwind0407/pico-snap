import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'theme.dart';

void main() => runApp(const PicoSnapApp());

class PicoSnapApp extends StatelessWidget {
  const PicoSnapApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PICO SNAP',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: coral),
      fontFamily: 'Nunito',
    ),
    home: const HomeScreen(),
  );
}
