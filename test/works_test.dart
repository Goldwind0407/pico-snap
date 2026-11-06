import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_document.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/gallery_screen.dart';
import 'package:pico_snap/home_screen.dart';
import 'package:pico_snap/lut_files.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/services/editor_drafts.dart';
import 'package:pico_snap/services/my_works.dart';
import 'package:pico_snap/theme.dart';
import 'package:pico_snap/widgets/doodle.dart';
import 'package:pico_snap/widgets/frames.dart';

Future<Uint8List> _png() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 40, 60), Paint()..color = const Color(0xFFF47C6E));
  final img = await r.endRecording().toImage(40, 60);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<void> _phone(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

List<Stroke> _strokes(WidgetTester t) {
  final ink = find.byType(InkLayer);
  return ink.evaluate().isEmpty ? const [] : t.widget<InkLayer>(ink).strokes;
}

/// A finger stroke across the canvas, from [from] by [by] in small steps.
Future<void> _draw(WidgetTester t, Offset from, Offset by) async {
  final g = await t.startGesture(from);
  for (var i = 1; i <= 10; i++) {
    await g.moveTo(from + by * (i / 10));
    await t.pump();
  }
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  setUp(MyWorks.reset);

  test('作品集：新的在前面、可以刪、日記一天一句', () async {
    final png = await _png();
    final a = await MyWorks.add(png, WorkKind.fourCut, at: DateTime(2026, 10, 27, 15));
    final b = await MyWorks.add(png, WorkKind.instant, at: DateTime(2026, 10, 28, 9));
    expect(MyWorks.works.map((w) => w.id), [b.id, a.id]);
    expect(MyWorks.on(DateTime(2026, 10, 27)).single.id, a.id);

    await MyWorks.remove(a.id);
    expect(MyWorks.works.single.id, b.id);

    await MyWorks.setNote(DateTime(2026, 10, 28, 23), '  好開心  ');
    expect(MyWorks.noteOn(DateTime(2026, 10, 28)), '好開心');
    await MyWorks.setNote(DateTime(2026, 10, 28), ' ');
    expect(MyWorks.notes, isEmpty, reason: '空白就刪掉');
  });

  testWidgets('作品集：沒有作品時有說明；有作品可以篩選、打開、刪除', (t) async {
    await _phone(t, const GalleryScreen());
    expect(find.text('還沒有作品'), findsOneWidget);

    final png = (await t.runAsync(_png))!;
    await t.runAsync(() async {
      await MyWorks.add(png, WorkKind.fourCut);
      await MyWorks.add(png, WorkKind.sticker);
    });
    await t.pumpAndSettle();
    expect(find.byType(WorkTile), findsNWidgets(2));
    expect(find.text('2 件'), findsOneWidget);

    await t.tap(find.text('貼紙'));
    await t.pumpAndSettle();
    expect(find.byType(WorkTile), findsOneWidget);

    await t.tap(find.byType(WorkTile));
    await t.pumpAndSettle();
    expect(find.text('存預覽版'), findsOneWidget);
    await t.tap(find.text('刪除'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(GlassDialog), matching: find.text('刪除')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    expect(find.text('存預覽版'), findsNothing, reason: '最後一件刪掉就回到作品集');
    expect(MyWorks.works.single.kind, WorkKind.fourCut);
    expect(find.byType(WorkTile), findsOneWidget, reason: '只剩一種就不用篩選，顯示全部');
  });

  testWidgets('作品集：作品可以分享、再編輯、看影片', (t) async {
    final dir = (await t.runAsync(() => Directory.systemTemp.createTemp('pico_work_piece_')))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    final png = (await t.runAsync(_png))!;
    final piece = Directory('${dir.path}/piece');
    await t.runAsync(() => EditorDrafts.keep(EditorDocument.start(EditorMode.fourCut, photos: [png], filters: const []), piece));
    final work = Work(id: '1', kind: WorkKind.fourCut, created: DateTime(2026, 11, 4), bytes: png, piece: piece);
    await _phone(t, WorkViewer(works: [work, Work(id: '2', kind: WorkKind.instant, created: DateTime(2026, 11, 4), bytes: png)], initial: 1));
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('再編輯'), findsNothing, reason: '拍立得相機的作品沒有可以編輯的內容');
    expect(find.text('看影片'), findsNothing);
    await t.drag(find.byType(PageView), const Offset(400, 0));
    await t.pumpAndSettle();
    await t.runAsync(LutFiles.load);
    await t.tap(find.text('再編輯'));
    for (var i = 0; i < 20 && find.byType(EditorScreen).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pumpAndSettle();
    final editor = t.widget<EditorScreen>(find.byType(EditorScreen));
    expect(editor.draft!.photos.first, png);
    expect(editor.saved, isTrue, reason: '沒改就離開不會問、也不會留草稿');
  });

  testWidgets('首頁：底部「作品集」是分頁，「日記」可以寫今天的心情', (t) async {
    final png = (await t.runAsync(_png))!;
    await t.runAsync(() => MyWorks.add(png, WorkKind.fourCut));
    await _phone(t, const HomeScreen());

    await t.tap(find.text('作品集'));
    await t.pumpAndSettle();
    expect(find.byType(WorkTile), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.back), findsNothing, reason: '分頁裡沒有返回箭頭');

    await t.tap(find.text('日記'));
    await t.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    expect(find.text('這個月 1 件作品'), findsOneWidget);
    expect(find.text('1 件作品'), findsOneWidget, reason: '預設選今天');

    await t.tap(find.text('＋ 寫一句這天的心情'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '第一次拍貼 ♡');
    await t.tap(find.text('寫好了'));
    await t.pumpAndSettle();
    expect(find.text('第一次拍貼 ♡'), findsOneWidget);
    expect(MyWorks.noteOn(now), '第一次拍貼 ♡');

    await t.tap(find.byTooltip('下個月'));
    await t.pumpAndSettle();
    expect(find.text('這個月還沒有作品'), findsOneWidget);
    await t.tap(find.text('回到今天'));
    await t.pumpAndSettle();
    expect(find.text('這個月 1 件作品'), findsOneWidget);

    // Back on the 日記 tab goes to 首頁 first.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('畫筆：在作品上畫線、換螢光筆、橡皮擦擦掉、復原', (t) async {
    await _phone(t, const EditorScreen());
    await t.tap(find.text('畫筆'));
    await t.pumpAndSettle();
    final canvas = t.getRect(find.byType(PhotoStrip));
    final start = canvas.center - const Offset(40, 0);

    await _draw(t, start, const Offset(80, 0));
    expect(_strokes(t), hasLength(1));
    expect(_strokes(t).single.points.length, greaterThan(5));
    expect(_strokes(t).single.style, PenStyle.pen);

    await t.tap(find.text('螢光筆'));
    await t.pump();
    await _draw(t, canvas.center + const Offset(0, 120), const Offset(0, 40));
    expect(_strokes(t).map((s) => s.style), [PenStyle.pen, PenStyle.marker]);

    await t.tap(find.text('橡皮擦'));
    await t.pump();
    await _draw(t, canvas.center - const Offset(0, 30), const Offset(0, 60));
    expect(_strokes(t).map((s) => s.style), [PenStyle.marker], reason: '只擦掉碰到的那一條');

    await t.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
    await t.pumpAndSettle();
    expect(_strokes(t), hasLength(2), reason: '一次抹過只算一步');

    await t.tap(find.text('全部清掉'));
    await t.pumpAndSettle();
    expect(_strokes(t), isEmpty);
    await t.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
    await t.pumpAndSettle();
    expect(_strokes(t), hasLength(2));
  });

  testWidgets('畫筆：用筆畫有粗細；用過筆之後手掌不會畫；筆的側鍵是橡皮擦', (t) async {
    addTearDown(DoodleInput.forgetPen);
    await _phone(t, const EditorScreen());
    await t.tap(find.text('畫筆'));
    await t.pumpAndSettle();
    final c = t.getRect(find.byType(PhotoStrip)).center;
    Future<void> pen(int id, Offset from, Offset by, {List<double> pressure = const [.2, .5, .9], int buttons = kPrimaryButton}) async {
      t.binding.handlePointerEvent(PointerDownEvent(pointer: id, kind: PointerDeviceKind.stylus, position: from, pressure: pressure.first, pressureMin: 0, pressureMax: 1, buttons: buttons));
      for (var k = 1; k <= 8; k++) {
        t.binding.handlePointerEvent(PointerMoveEvent(pointer: id, kind: PointerDeviceKind.stylus, position: from + by * (k / 8),
          pressure: pressure[min(pressure.length - 1, k * pressure.length ~/ 9)], pressureMin: 0, pressureMax: 1, buttons: buttons));
        await t.pump(const Duration(milliseconds: 16));
      }
      t.binding.handlePointerEvent(PointerUpEvent(pointer: id, kind: PointerDeviceKind.stylus, position: from + by));
      await t.pump();
    }

    await pen(1, c - const Offset(40, 20), const Offset(80, 0));
    expect(_strokes(t), hasLength(1));
    final p = _strokes(t).single.pressures!;
    expect(p.first, lessThan(p.last), reason: '記下筆的壓力');
    expect(DoodleInput.penMode, isTrue);

    // 手掌（手指）碰到畫布：不畫
    await _draw(t, c + const Offset(-40, 60), const Offset(80, 0));
    expect(_strokes(t), hasLength(1), reason: '用筆的時候手掌不會畫出線');

    // 按著側鍵畫過去：擦掉
    await pen(2, c - const Offset(0, 50), const Offset(0, 60), buttons: kPrimaryButton | kSecondaryStylusButton);
    expect(_strokes(t), isEmpty);

    DoodleInput.forgetPen();
    await _draw(t, c + const Offset(-40, 60), const Offset(80, 0));
    expect(_strokes(t).single.pressures, isNull, reason: '沒在用筆了，手指又能畫');
  });

  testWidgets('畫筆：Apple Pencil 點兩下切換橡皮擦、再點兩下切回來', (t) async {
    await _phone(t, const EditorScreen());
    await t.tap(find.text('畫筆'));
    await t.pumpAndSettle();
    final c = t.getRect(find.byType(PhotoStrip)).center;
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t), hasLength(1));
    PencilTaps.debugTap('eraser');
    await t.pump();
    await _draw(t, c - const Offset(0, 30), const Offset(0, 60));
    expect(_strokes(t), isEmpty, reason: '點兩下變橡皮擦');
    PencilTaps.debugTap('eraser');
    await t.pump();
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t).single.style, PenStyle.pen, reason: '再點兩下回到畫筆');
  });

  testWidgets('畫筆：其他工具時不能畫，照片格還是點得到', (t) async {
    await _phone(t, const EditorScreen(mode: EditorMode.polaroid));
    expect(find.text('畫筆'), findsOneWidget, reason: '拼貼也有畫筆');
    expect(find.byType(DoodleInput), findsNothing);
    await t.tap(find.text('畫筆'));
    await t.pumpAndSettle();
    expect(find.byType(DoodleInput), findsOneWidget);
  });
}
