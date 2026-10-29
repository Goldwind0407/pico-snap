import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/booth_screen.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/home_screen.dart';
import 'package:pico_snap/library_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/services/my_library.dart';
import 'package:pico_snap/widgets/frames.dart';
import 'package:pico_snap/widgets/instant_print.dart';
import 'package:pico_snap/widgets/sticker_item.dart';

/// A wide photo (3:2), so it can be moved sideways in a squarish window.
Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 150, 100), Paint()..color = const Color(0xFF3080F0));
  final img = await r.endRecording().toImage(150, 100);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<void> _phone(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

/// Lets the photo decode so its size is known.
Future<void> _settleImages(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

void main() {
  setUp(() {
    customStickers.clear();
    customTemplates.clear();
  });

  testWidgets('照片：點有照片的格子可以拖曳移動、置中、移除', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, EditorScreen(mode: EditorMode.polaroid, photos: [photo]));
    await _settleImages(t);
    InstantPrint first() => t.widget<InstantPrint>(find.byType(InstantPrint).first);
    // The selected print is drawn last; the first print is the one with the photo.
    final withPhoto = find.byWidgetPredicate((w) => w is InstantPrint && w.image != null);
    expect(withPhoto, findsOneWidget);
    expect(first().image, isNull, reason: '照片在第 1 張，畫在最後面（選取中）');

    await t.tap(find.descendant(of: withPhoto, matching: find.byType(FittedPhoto)));
    await t.pumpAndSettle();
    expect(find.text('換照片'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);

    await t.drag(find.descendant(of: withPhoto, matching: find.byType(FittedPhoto)), const Offset(30, 0));
    await t.pumpAndSettle();
    final moved = t.widget<InstantPrint>(withPhoto).fit;
    expect(moved.align.x, lessThan(0), reason: '往右拖，看到照片左邊');

    await t.tap(find.text('置中'));
    await t.pumpAndSettle();
    expect(t.widget<InstantPrint>(withPhoto).fit.align, Alignment.center);

    await t.tap(find.text('移除'));
    await t.pumpAndSettle();
    expect(withPhoto, findsNothing);
    expect(find.text('換照片'), findsNothing, reason: '回到原本的工具');
  });

  testWidgets('拍立得拼貼：可以換成黑底片', (t) async {
    await _phone(t, const EditorScreen(mode: EditorMode.polaroid));
    expect(find.byWidgetPredicate((w) => w is InstantPrint && w.film == FilmStock.white), findsNWidgets(4));
    await t.tap(find.text('黑底片'));
    await t.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is InstantPrint && w.film == FilmStock.black), findsNWidgets(4));
  });

  testWidgets('相機：選黑底片拍出來就是黑底片，做成拼貼也帶過去', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty()));
    await t.tap(find.text('黑底片'));
    await t.pump();
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).film, FilmStock.black);
    await t.tap(find.byType(InstantPrint));
    await t.pumpAndSettle();
    await t.tap(find.text('再拍一張'));
    await t.pumpAndSettle();
    await t.tap(find.text('做成拼貼'));
    await t.pumpAndSettle();
    expect(t.widget<EditorScreen>(find.byType(EditorScreen)).films, [FilmStock.black]);
  });

  testWidgets('相機：下次打開還是上次選的底片', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty()));
    await t.tap(find.text('黑底片'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty()));
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).film, FilmStock.black);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('插畫模板：文字變成可以拖曳的貼紙', (t) async {
    final art = allStripTemplates.indexWhere((s) => s.art != null);
    await _phone(t, EditorScreen(template: art));
    await t.tap(find.text('文字'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '好開心');
    await t.tap(find.text('加上去'));
    await t.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is TextSticker && w.text == '好開心'), findsOneWidget);
    expect(find.byType(StickerItem), findsOneWidget);
  });

  testWidgets('首頁：「我的」是分頁，返回鍵先回首頁', (t) async {
    await _phone(t, const HomeScreen());
    await t.tap(find.text('我的'));
    await t.pumpAndSettle();
    expect(find.text('我的素材'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing, reason: '分頁裡沒有返回箭頭');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget, reason: '回到首頁分頁');
  });

  testWidgets('我的素材：點模板直接用它拍四格', (t) async {
    MyLibrary.addTemplate(const CustomTemplate(id: 't1', caption: 'mine!', frame: Color(0xFFB9C9AE)));
    await _phone(t, const LibraryScreen());
    await t.tap(find.text('模板'));
    await t.pumpAndSettle();
    await t.tap(find.byType(PhotoStrip));
    await t.pumpAndSettle();
    expect(t.widget<BoothScreen>(find.byType(BoothScreen)).template, stripTemplates.length);
    expect(find.text('mine!'), findsWidgets);
  });
}
