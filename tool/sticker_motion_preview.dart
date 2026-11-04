// flutter test tool/sticker_motion_preview.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/widgets/sticker_motion.dart';

void main() {
  testWidgets('render the paper lift and landing stages', (t) async {
    t.view.physicalSize = const Size(1440, 300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    const sticker = AssetImage('assets/sticker_sheets/cool_01.webp');
    await t.runAsync(() async {
      final font = FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito-500.ttf'));
      await font.load();
    });
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return RepaintBoundary(key: key, child: ColoredBox(color: const Color(0xFFF6F0E7), child: Row(
        children: [
          for (final (label, amount, landing) in [
            ('1. Attached', 0.0, false), ('2. Corner curls', .25, false),
            ('3. Adhesive back', .48, false), ('4. Peel away', .72, false),
            ('5. Roll onto canvas', .45, true), ('6. Fully attached', 1.0, true),
          ]) Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 190, height: 215, child: Center(child: SizedBox(width: 130, height: 170,
              child: landing
                ? StickerLanding(progress: amount, child: const Image(image: sticker))
                : StickerLift(amount: amount, child: const Image(image: sticker)),
            ))),
            Text(label, style: const TextStyle(fontFamily: 'Nunito', fontSize: 16, color: Colors.black, decoration: TextDecoration.none)),
          ])),
        ],
      )));
    })));
    await t.runAsync(() => precacheImage(sticker, key.currentContext!));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/sticker_preview').create(recursive: true);
        await File('build/sticker_preview/motion.png').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  });
}
