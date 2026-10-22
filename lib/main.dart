import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'services/my_library.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MyLibrary.load();
  runApp(const PicoSnapApp());
}

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
