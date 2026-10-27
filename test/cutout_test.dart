import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/cutout/cutout_page.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/models.dart';


/// 白底上一個紅色圓（測試用的照片）。
Future<Uint8List> _circlePhoto() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(const Rect.fromLTWH(0, 0, 200, 160), Paint()..color = const Color(0xFFFFFFFF))
    ..drawCircle(const Offset(100, 80), 45, Paint()..color = const Color(0xFFE0302C));
  final image = await recorder.endRecording().toImage(200, 160);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

Future<(int, int, Uint8List)> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final out = (image.width, image.height, data!.buffer.asUint8List());
  image.dispose();
  return out;
}

void main() {
  group('bakeSticker', () {
    // 20×20 的方塊主體在 100×100 的照片中間
    const w = 100, h = 100;
    final rgba = Uint8List(w * h * 4);
    final mask = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        rgba.setAll(i * 4, [10, 20, 200, 255]);
        if (x >= 40 && x < 60 && y >= 40 && y < 60) mask[i] = 255;
      }
    }
    final out = bakeSticker((rgba: rgba, mask: mask, w: w, h: h));
    // 描邊 = max(4, 100 × 2.2%) = 4 像素
    const r = 4;

    test('裁到主體加上描邊', () {
      expect(out.w, inInclusiveRange(20 + 2 * r, 20 + 2 * (r + 1)));
      expect(out.h, out.w);
    });

    test('主體顏色不變、描邊是白色、外面透明', () {
      int at(int x, int y, int c) => out.rgba[(y * out.w + x) * 4 + c];
      final c = out.w ~/ 2;
      expect([at(c, c, 0), at(c, c, 1), at(c, c, 2), at(c, c, 3)], [10, 20, 200, 255], reason: '主體');
      final edge = (out.w - 20) ~/ 2 - 2; // 主體左邊 2 格，在描邊裡
      expect([at(edge, c, 0), at(edge, c, 3)], [255, 255], reason: '白色描邊');
      expect(at(0, 0, 3), 0, reason: '角落在描邊外，透明');
    });
  });

  testWidgets('去背頁：AI 不能用時自動改用手動去背，完成後回傳貼紙 PNG', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photo = (await tester.runAsync(_circlePhoto))!;
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
      onPressed: () async => result = await CutoutPage.open(context, photo),
      child: const Text('open'),
    ))))));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // page transition

    // 解碼、GrabCut 都在背景跑：等到狀態列說改用了手動去背
    for (var i = 0; i < 200 && find.textContaining('改用手動去背').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('AI 這次認不出來，改用手動去背'), findsOneWidget);

    await tester.tap(find.text('完成'));
    for (var i = 0; i < 200 && result == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 600)); // pop transition
    expect(result, isNotNull);

    // 圓的直徑 90，加上兩邊白色描邊，背景（白色）沒有被留下來
    final (w, h, rgba) = (await tester.runAsync(() => _decode(result!)))!;
    expect(w, inInclusiveRange(90, 130));
    expect(h, inInclusiveRange(90, 130));
    final c = (h ~/ 2 * w + w ~/ 2) * 4;
    expect(rgba[c], greaterThan(200), reason: '中間是紅色');
    expect(rgba[c + 1], lessThan(80), reason: '中間是紅色');
    expect(rgba[3], 0, reason: '角落透明');
  });

  testWidgets('儲存：還沒放照片時不讓存', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen(mode: EditorMode.polaroid)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pump();
    expect(find.text('先放一張照片再儲存喔'), findsOneWidget);
    expect(find.text('同時存「製作過程」縮時影片'), findsNothing);
  });

  testWidgets('編輯過還沒存：按返回會先問；沒編輯就直接離開', (tester) async {
    final photo = (await tester.runAsync(_circlePhoto))!;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditorScreen(mode: EditorMode.polaroid))),
      child: const Text('open'),
    ))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 沒編輯：直接離開
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('要離開嗎？'), findsOneWidget);
    await tester.tap(find.text('繼續編輯'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget, reason: '選繼續編輯就留下來');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('離開'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(photo, isNotEmpty);
  });

  testWidgets('儲存：沒有相簿外掛時顯示錯誤訊息，不會當掉', (tester) async {
    final photo = (await tester.runAsync(_circlePhoto))!;
    await tester.pumpWidget(MaterialApp(home: EditorScreen(mode: EditorMode.polaroid, photos: [photo])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('同時存「製作過程」縮時影片'), findsOneWidget);
    await tester.tap(find.text('存到相簿').last);
    for (var i = 0; i < 100 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('儲存'), findsOneWidget, reason: '按鈕恢復原狀');
  });
}
