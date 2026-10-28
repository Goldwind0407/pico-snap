import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'lut_files.dart';
import 'services/my_library.dart';
import 'services/my_works.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([MyLibrary.load(), MyWorks.load()]);
  runApp(const PicoSnapApp());
  // Filters from lookup files join the list a moment later.
  LutFiles.load();
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
