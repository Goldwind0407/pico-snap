import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'lut_files.dart';
import 'services/my_library.dart';
import 'services/my_works.dart';
import 'services/editor_drafts.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The handwritten Chinese font's licence, for the app's licence page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['辰宇落雁體 ChenYuluoyan'], await rootBundle.loadString('assets/fonts/ChenYuluoyan-OFL.txt'));
  });
  final ready = Future.wait([MyLibrary.load(), MyWorks.load(), EditorDrafts.load()]);
  runApp(PicoSnapApp(ready: ready));
  // Filters from lookup files join the list a moment later.
  LutFiles.load();
}

class PicoSnapApp extends StatelessWidget {
  final Future<void>? ready;
  const PicoSnapApp({super.key, this.ready});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '快趣拍',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: ready == null ? const HomeScreen() : FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done
          ? const HomeScreen()
          : const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('快趣拍', style: TextStyle(fontSize: 28, color: ink, fontWeight: FontWeight.w800)),
              SizedBox(height: 20), CircularProgressIndicator(color: coral),
            ]))),
    ),
  );
}
