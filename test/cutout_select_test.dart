import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/cutout/cutout_page.dart';
import 'package:pico_snap/cutout/subject_segmenter.dart';

/// 白底上左右兩個色塊（兩個「人」）。
Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r)
    ..drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = const Color(0xFFFFFFFF))
    ..drawRect(const Rect.fromLTWH(20, 20, 60, 60), Paint()..color = const Color(0xFFE0302C))
    ..drawRect(const Rect.fromLTWH(120, 20, 60, 60), Paint()..color = const Color(0xFF2C60E0));
  final img = await r.endRecording().toImage(200, 100);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Uint8List _box(int x0, int y0, int x1, int y1, int w, int h) {
  final m = Uint8List(w * h);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      m[y * w + x] = 255;
    }
  }
  return m;
}

void main() {
  test('placeSubjects：框內遮罩放回整張，大的排前面，雜點丟掉', () {
    const w = 100, h = 50;
    final small = Uint8List(10 * 10)..fillRange(0, 100, 255);
    final big = Uint8List(30 * 30)..fillRange(0, 900, 255);
    final speck = Uint8List(2 * 2)..fillRange(0, 4, 255);
    final out = placeSubjects([
      (x: 5, y: 5, w: 10, h: 10, mask: small),
      (x: 60, y: 10, w: 30, h: 30, mask: big),
      (x: 0, y: 0, w: 2, h: 2, mask: speck),
    ], w, h);
    expect(out, hasLength(2));
    expect(out[0][20 * w + 70], 255, reason: '大的在前');
    expect(out[1][8 * w + 8], 255);
    expect(out[1][20 * w + 70], 0);
  });

  test('splitSubjects：分開的兩塊拆成兩個主體', () {
    const w = 100, h = 50;
    final fg = _box(5, 5, 30, 40, w, h);
    final other = _box(60, 5, 90, 30, w, h);
    for (var i = 0; i < fg.length; i++) {
      if (other[i] > 0) fg[i] = 255;
    }
    final parts = splitSubjects(fg, w, h);
    expect(parts, hasLength(2));
    expect(parts[0][20 * w + 10], 255);
    expect(parts[0][20 * w + 70], 0);
    expect(parts[1][20 * w + 70], 255);
  });

  testWidgets('選主體：AI 找到兩個，點一下只留一個；預覽可以拿掉白邊', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const channel = MethodChannel('picosnap/subject');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'subjects') return null;
      final a = call.arguments as Map;
      final w = a['width'] as int, h = a['height'] as int;
      return [
        {'x': 0, 'y': 0, 'w': w, 'h': h, 'mask': _box(20, 20, 80, 80, w, h)},
        {'x': 0, 'y': 0, 'w': w, 'h': h, 'mask': _box(120, 20, 180, 80, w, h)},
      ];
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final photo = (await t.runAsync(_photo))!;
    Uint8List? result;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
      onPressed: () async => result = await CutoutPage.open(context, photo),
      child: const Text('open'),
    ))))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 200 && find.textContaining('找到 2 個主體').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(find.textContaining('找到 2 個主體'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2), reason: '一開始兩個都選');

    // 點掉右邊那個（徽章上的勾）
    await t.tap(find.byIcon(Icons.check_rounded).last);
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2), reason: '沒選的顯示編號（另一個是步驟 2）');

    // 直接到預覽，選「無」白邊再做成貼紙
    await t.tap(find.text('預覽'));
    for (var i = 0; i < 40; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.tap(find.text('無'));
    for (var i = 0; i < 40; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.tap(find.text('做成貼紙'));
    for (var i = 0; i < 200 && result == null; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 600));
    expect(result, isNotNull);
    final codec = (await t.runAsync(() => ui.instantiateImageCodec(result!)))!;
    final img = (await t.runAsync(codec.getNextFrame))!.image;
    // 只有左邊那塊（60×60），沒有白邊，外面一圈透明的 1 像素
    expect(img.width, inInclusiveRange(60, 64));
    expect(img.height, inInclusiveRange(60, 64));
  });

  testWidgets('黏在一起的主體：畫一條線切開，再點掉一個', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const channel = MethodChannel('picosnap/subject');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'subjects') return null;
      final a = call.arguments as Map;
      final w = a['width'] as int, h = a['height'] as int;
      // One subject covering both blocks and the bridge between them.
      final m = _box(20, 20, 180, 80, w, h);
      return [{'x': 0, 'y': 0, 'w': w, 'h': h, 'mask': m}];
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: CutoutPage(photo: photo)));
    for (var i = 0; i < 200 && find.textContaining('找到主體了').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Draw a vertical line through the middle of the photo.
    final box = t.getRect(find.byType(RawImage).last);
    final g = await t.startGesture(Offset(box.center.dx, box.top + 2));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset(box.center.dx, box.top + 2 + (box.height - 4) * i / 10));
      await t.pump();
    }
    await g.up();
    for (var i = 0; i < 100 && find.textContaining('切開了').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(find.textContaining('切開了'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    await t.tap(find.byIcon(Icons.check_rounded).last);
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
