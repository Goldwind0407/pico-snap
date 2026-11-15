import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'lut_files.dart';
import 'services/my_library.dart';
import 'services/my_works.dart';
import 'services/editor_drafts.dart';
import 'services/app_sounds.dart';
import 'theme.dart';
import 'widgets/launch_intro.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The handwritten Chinese font's licence, for the app's licence page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['辰宇落雁體 ChenYuluoyan'], await rootBundle.loadString('assets/fonts/ChenYuluoyan-OFL.txt'));
  });
  final ready = Future.wait([MyLibrary.load(), MyWorks.load(), EditorDrafts.load(), AppSounds.shared.initialize()]);
  runApp(PicoSnapApp(ready: ready));
  // Filters from lookup files join the list a moment later.
  LutFiles.load();
}

class PicoSnapApp extends StatelessWidget {
  final Future<void>? ready;
  /// The studio's opening animation over the app as it loads (off in tests).
  final bool intro;
  const PicoSnapApp({super.key, this.ready, this.intro = true});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '快趣拍',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (context, child) => LaunchIntro(enabled: intro, child: child!),
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
