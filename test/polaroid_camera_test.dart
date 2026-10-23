import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/widgets/frames.dart';
import 'package:sensors_plus/sensors_plus.dart';

Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 120, 120), Paint()..color = const Color(0xFF3080F0));
  final img = await r.endRecording().toImage(120, 120);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  test('顯影：一開始是一片深色，最後是原本的照片', () {
    expect(developFilter(0), const ColorFilter.matrix([0, 0, 0, 0, 52, 0, 0, 0, 0, 56, 0, 0, 0, 0, 50, 0, 0, 0, 1, 0]));
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

    // 在白邊寫字
    final caption = find.descendant(of: find.byType(InstantPrint), matching: find.byType(Text));
    await t.tap(caption);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'cheese!');
    await t.tap(find.text('好'));
    await t.pumpAndSettle();
    expect(find.text('cheese!'), findsWidgets);

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
    expect(editor.captions, ['cheese!']);
    expect(find.byType(PolaroidCard), findsNWidgets(4));
    expect(find.text('cheese!'), findsOneWidget);
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
}
