import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/services/photo_save_service.dart';
import 'package:pico_snap/widgets/doodle.dart';
import 'package:pico_snap/widgets/instant_print.dart';
import 'package:sensors_plus/sensors_plus.dart';

Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 120, 120), Paint()..color = const Color(0xFF3080F0));
  final img = await r.endRecording().toImage(120, 120);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  test('顯影：一開始是一片淡灰藍的空白，最後是原本的照片', () {
    expect(developFilter(0), const ColorFilter.matrix([0, 0, 0, 0, 196, 0, 0, 0, 0, 202, 0, 0, 0, 0, 206, 0, 0, 0, 1, 0]));
    expect(developFilter(1), const ColorFilter.matrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]));
    expect(developFilter(.5), isNot(developFilter(1)), reason: '中途還沒完全顯影');
  });

  testWidgets('沒有相機：顯示說明；從相簿選 → 出片 → 顯影 → 存檔、做成拼貼', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    // 測試裡沒有相機外掛
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty())));
    for (var i = 0; i < 40 && find.textContaining('從相簿選照片').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump();
    }
    expect(find.textContaining('從相簿選照片'), findsOneWidget);
    await t.tap(find.text('做成拼貼'));
    await t.pump();
    expect(find.text('先拍一張，再做成拼貼'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));

    await t.tap(find.text('從相簿'));
    await t.pump();
    expect(find.text('出片中…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1400));
    expect(find.byType(InstantPrint), findsOneWidget, reason: '相片正從出片口出來');
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text('顯影中…'), findsOneWidget);

    // 輕點跳過顯影
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.byType(InstantPrint));
    await t.pumpAndSettle();
    expect(find.text('存到相簿'), findsOneWidget);
    expect(find.text('再拍一張'), findsOneWidget);

    // 沒有自動印日期；按「手寫」直接在相片上寫
    final caption = find.byKey(const ValueKey('instant-caption'));
    expect(find.descendant(of: caption, matching: find.byType(Text)), findsNothing, reason: '白邊一開始是空的');
    expect(find.byType(DoodleInput), findsNothing);
    final small = t.getRect(find.byType(InstantPrint)).width;
    await t.tap(find.text('手寫'));
    await t.pumpAndSettle();
    expect(find.byType(DoodleInput), findsOneWidget, reason: '整張相片都可以寫');
    expect(t.getRect(find.byType(InstantPrint)).width, greaterThan(small * 1.2), reason: '寫字時相片放大');
    expect(find.text('存到相簿'), findsNothing, reason: '寫字時下方換成筆的工具');
    final printRect = t.getRect(find.byType(InstantPrint));
    final g = await t.startGesture(printRect.center - Offset(printRect.width * .3, 0));
    for (var i = 1; i <= 8; i++) {
      await g.moveBy(Offset(printRect.width * .07, 2));
      await t.pump();
    }
    await g.up();
    await t.tap(find.text('寫好了'));
    await t.pumpAndSettle();
    expect(find.byType(DoodleInput), findsNothing);
    expect(t.getRect(find.byType(InstantPrint)).width, closeTo(small, 1), reason: '寫好縮回原本大小');
    List<Stroke> written() => t.widget<InstantPrint>(find.byType(InstantPrint)).handwriting;
    expect(written(), hasLength(1));
    expect(written().single.points.length, greaterThan(4));
    expect(written().single.color, FilmStock.white.pen, reason: '白底片預設黑筆');

    // 存檔：測試裡沒有相簿外掛，會顯示錯誤但不會當掉
    await t.tap(find.text('存到相簿'));
    for (var i = 0; i < 60 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect(find.byType(SnackBar), findsOneWidget);

    await t.tap(find.text('再拍一張'));
    await t.pumpAndSettle();
    expect(find.text('1'), findsOneWidget, reason: '左下角有一張拍好的');
    await t.tap(find.text('做成拼貼'));
    await t.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    final editor = t.widget<EditorScreen>(find.byType(EditorScreen));
    expect(editor.photos, hasLength(1));
    expect(editor.captions, [''], reason: '手寫的那張不放範例文字');
    expect(editor.handwriting.single, hasLength(1));
    expect(find.byType(InstantPrint), findsNWidgets(4), reason: '拼貼也是同一種底片');
    expect(find.byWidgetPredicate((w) => w is InstantPrint && w.handwriting.isNotEmpty), findsOneWidget, reason: '手寫帶到拼貼');
  });

  testWidgets('顯影約 20 秒；搖手機會加快', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    final motion = StreamController<UserAccelerometerEvent>.broadcast();
    addTearDown(motion.close);
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo, motion: motion.stream)));
    await t.pump();
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 3000)); // 出片
    expect(find.text('顯影中…'), findsOneWidget);

    // 不搖：10 秒後還在顯影
    await t.pump(const Duration(seconds: 10));
    expect(find.text('顯影中…'), findsOneWidget);
    final before = t.widget<InstantPrint>(find.byType(InstantPrint)).develop;
    expect(before, closeTo(.5, .05));

    // 輕輕晃不算；用力搖幾下就顯影完
    motion.add(UserAccelerometerEvent(1, 1, 1, DateTime.now()));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).develop, closeTo(before, .02));
    for (var i = 0; i < 20; i++) {
      motion.add(UserAccelerometerEvent(i.isEven ? 20 : -20, 3, 0, DateTime.now()));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 95)));
    }
    await t.pumpAndSettle();
    expect(find.text('存到相簿'), findsOneWidget, reason: '搖完已經顯影好了');
  });

  group('焦段', () {
    CameraDescription cam(String name, CameraLensDirection d, [CameraLensType t = CameraLensType.unknown]) =>
        CameraDescription(name: name, lensDirection: d, sensorOrientation: 90, lensType: t);
    List<String> labels(List<LensChoice> l) => [for (final c in l) c.label];

    test('iPhone：每顆實體鏡頭各自一個選項，前鏡頭不混進來', () {
      final cams = [
        cam('wide', CameraLensDirection.back, CameraLensType.wide),
        cam('front', CameraLensDirection.front, CameraLensType.wide),
        cam('tele', CameraLensDirection.back, CameraLensType.telephoto),
        cam('ultra', CameraLensDirection.back, CameraLensType.ultraWide),
      ];
      final l = lensChoices(cams, CameraLensDirection.back);
      expect(labels(l), ['0.5×', '1×', '長焦']);
      expect([for (final c in l) c.camera.name], ['ultra', 'wide', 'tele']);
      expect(l.every((c) => c.zoom == 1), isTrue, reason: '換鏡頭，不是數位放大');
      expect(mainCamera(cams, CameraLensDirection.back)!.name, 'wide');
      expect(labels(lensChoices(cams, CameraLensDirection.front)), ['1×']);
    });

    test('Android：主鏡頭能縮到 1 以下就是超廣角', () {
      final cams = [cam('0', CameraLensDirection.back), cam('1', CameraLensDirection.front)];
      final l = lensChoices(cams, CameraLensDirection.back, minZoom: .6);
      expect(labels(l), ['0.6×', '1×']);
      expect(l.first.camera.name, '0');
      expect(l.first.zoom, .6);
      expect(labels(lensChoices(cams, CameraLensDirection.back)), ['1×'], reason: '沒有超廣角就不顯示');
      expect(labels(lensChoices(cams, CameraLensDirection.back, minZoom: .5)), ['0.5×', '1×']);
    });
  });

  testWidgets('出片到一半離開：馬達的震動計時器跟著停，不會一直震', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty())));
    for (var i = 0; i < 40 && find.textContaining('從相簿選照片').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump();
    }
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('出片中…'), findsOneWidget);
    // 換掉整個頁面（像按返回離開）
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pump(const Duration(seconds: 3));
    // 計時器還在的話，測試結束時 flutter_test 會報「Timer is still pending」
  });

  testWidgets('從相簿連按兩下只開一次', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    final picked = Completer<Uint8List?>();
    var opened = 0;
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () {
      opened++;
      return picked.future;
    }, motion: const Stream.empty())));
    for (var i = 0; i < 40 && find.textContaining('從相簿選照片').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump();
    }
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.tap(find.text('從相簿'));
    await t.pump();
    expect(opened, 1);
    picked.complete(photo);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('出片中…'), findsOneWidget);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pump(const Duration(seconds: 3));
  });

  test('連續存檔：同一秒存好幾張，檔名都不一樣', () {
    final names = [for (var i = 0; i < 20; i++) PhotoSaveService.nextName()];
    expect(names.toSet(), hasLength(20));
    expect(names.first, startsWith('pico_snap_'));
  });
}
