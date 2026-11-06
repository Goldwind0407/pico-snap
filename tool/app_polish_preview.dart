// flutter test tool/app_polish_preview.dart
// Uses a local system Chinese font only for test screenshots. The app itself
// uses the device's system fallback and the fonts bundled in pubspec.yaml.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/home_screen.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/library_screen.dart';
import 'package:pico_snap/gallery_screen.dart';
import 'package:pico_snap/diary_screen.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/booth_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/theme.dart';

void main() {
  testWidgets('render the shared app styling across major screens', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    await t.runAsync(() async {
      for (final (family, asset) in [
        ('Nunito', 'assets/fonts/Nunito-500.ttf'), ('Nunito', 'assets/fonts/Nunito-800.ttf'),
        ('Caveat', 'assets/fonts/Caveat-600.ttf'), ('packages/cupertino_icons/CupertinoIcons', 'packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ('ChenYuluoyan', 'assets/fonts/ChenYuluoyan-2.0-Thin.ttf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) { await (FontLoader(family)..addFont(rootBundle.load(asset))).load(); }
      final chinese = File('C:/Windows/Fonts/msjh.ttc');
      if (await chinese.exists()) {
        // Flutter tests otherwise fall back to Ahem's solid square glyphs.
        for (final family in [...appFontFallback, 'Ahem']) {
          await (FontLoader(family)..addFont(chinese.readAsBytes().then((v) => ByteData.sublistView(v)))).load();
        }
      }
    });
    final photo = (await rootBundle.load('assets/samples/girl1.jpg')).buffer.asUint8List();
    final screens = <String, Widget>{
      'home': const HomeScreen(), 'library': const LibraryScreen(), 'gallery': const GalleryScreen(),
      'diary': const DiaryScreen(), 'editor': EditorScreen(mode: EditorMode.polaroid, photos: [photo]),
      'camera': const PolaroidCameraScreen(), 'booth': const BoothScreen(),
    };
    for (final entry in screens.entries) {
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RepaintBoundary(key: key, child: entry.value)));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: entry.key);
      await t.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        try {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          await Directory('build/app_polish').create(recursive: true);
          await File('build/app_polish/${entry.key}.png').writeAsBytes(png.buffer.asUint8List());
        } finally { image.dispose(); }
      });
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    }
    debugDisableShadows = oldShadows;
  });
}
