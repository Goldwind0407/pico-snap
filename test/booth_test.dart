import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/booth_screen.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/services/my_works.dart';
import 'package:pico_snap/widgets/frames.dart';

import 'test_filters.dart';

Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 160, 120), Paint()..color = const Color(0xFFF08030));
  final img = await r.endRecording().toImage(160, 120);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<void> _phone(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pump();
}

/// The big countdown number (the small cell numbers below don't count).
Finder _count(String n) => find.byWidgetPredicate((w) => w is Text && w.data == n && (w.style?.fontSize ?? 0) > 60);

void main() {
  useTestFilters();

  test('取景框跟模板的照片格一樣比例', () {
    final drawn = drawnTemplates.first;
    expect(cellAspect(drawn, 0), closeTo(176 / 128, 1e-9));
    final art = stripTemplates.firstWhere((t) => t.art != null);
    final r = art.art!.cells[1], s = art.designSize;
    expect(cellAspect(art, 1), closeTo(r.width * s.width / (r.height * s.height), 1e-9));
    expect(shotCount(art), art.art!.cells.length);
    expect(shotCount(drawn), 4);
  });

  testWidgets('拍貼機：選模板 → 倒數 → 一張一張拍 → 挑濾鏡 → 存檔', (t) async {
    final photo = (await t.runAsync(_photo))!;
    var shots = 0;
    await _phone(t, BoothScreen(template: 1, shoot: () async {
      shots++;
      return photo;
    }));
    // 1. 選模板（從首頁帶進來的那個已經選好）、倒數秒數
    expect(find.text('開始拍照（4 張）'), findsOneWidget);
    await t.tap(find.text('3 秒'));
    await t.pump();
    await t.tap(find.text('開始拍照（4 張）'));
    await t.pump();
    // 2–4. 每張倒數 3、2、1 再拍，拍好的停一下，接著下一張
    expect(find.text('第 1 / 4 張'), findsOneWidget);
    expect(_count('3'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(_count('2'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(shots, 1);
    expect(find.text('拍好了 ♡'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text('第 2 / 4 張'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1500));
    }
    await t.pump(const Duration(milliseconds: 500));
    expect(shots, 4);
    // 5. 拍完才挑濾鏡，套在全部照片
    expect(find.text('挑濾鏡'), findsOneWidget);
    await t.tap(find.text('測試青橙'));
    await t.pump();
    final strip = t.widget<PhotoStrip>(find.byType(PhotoStrip));
    expect(strip.template, allStripTemplates[1]);
    expect(strip.photos, hasLength(4));
    expect(strip.filters.every((f) => f.id == 'test_teal'), isTrue);
    // 6. 完成：存圖，可選順便存影片（測試沒有相機畫面，所以不能選）
    await t.tap(find.text('下一步'));
    await t.pump();
    expect(find.text('拍好了！'), findsOneWidget);
    expect(find.text('完成！'), findsOneWidget);
    expect(find.text('存到相簿'), findsNothing, reason: '完成後才選要不要存到相簿');
    expect(find.text('這次沒有錄到畫面，只能存圖片'), findsOneWidget);
    expect(find.text('加貼紙裝飾'), findsOneWidget, reason: '不用先存一張沒裝飾的');
    // 返回回到挑濾鏡，不會直接離開
    await t.tap(find.byIcon(CupertinoIcons.back));
    await t.pump();
    expect(find.text('挑濾鏡'), findsOneWidget);
  });

  testWidgets('拍到一半按返回會先確認', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BoothScreen(shoot: () async => photo))),
      child: const Text('go'),
    ))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('開始拍照'));
    await t.pump();
    await t.tap(find.byIcon(CupertinoIcons.back));
    await t.pumpAndSettle();
    expect(find.text('拍好的照片會不見喔。'), findsOneWidget);
    await t.tap(find.text('繼續'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(BoothScreen), findsOneWidget);
    await t.tap(find.byIcon(CupertinoIcons.back));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('離開'));
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.byType(BoothScreen), findsNothing);
  });

  testWidgets('拍貼機也能改從相簿選照片，進原本的編輯器', (t) async {
    await _phone(t, const BoothScreen(template: 2));
    await t.tap(find.text('從相簿選照片'));
    await t.pumpAndSettle();
    expect(t.widget<EditorScreen>(find.byType(EditorScreen)).template, 2);
  });

  testWidgets('拍貼機：只重拍其中一張，其他的留著', (t) async {
    final photos = <Uint8List>[];
    for (final c in [0xFFF08030, 0xFF30A0F0, 0xFF40C060, 0xFFC040C0, 0xFF202020]) {
      photos.add((await t.runAsync(() async {
        final r = ui.PictureRecorder();
        ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 160, 120), Paint()..color = Color(c));
        final img = await r.endRecording().toImage(160, 120);
        return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      }))!);
    }
    var shots = 0;
    await _phone(t, BoothScreen(template: 1, shoot: () async => photos[shots++]));
    await t.tap(find.text('3 秒'));
    await t.pump();
    await t.tap(find.text('開始拍照（4 張）'));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1500));
    }
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('挑濾鏡'), findsOneWidget);
    List<ImageProvider?> strip() => t.widget<PhotoStrip>(find.byType(PhotoStrip)).photos;
    final before = strip();

    await t.tap(find.text('重拍'));
    await t.pumpAndSettle();
    await t.tap(find.text('第 2 張'));
    await t.pump();
    expect(find.text('重拍第 2 張'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1500));
    await t.pump(const Duration(milliseconds: 500));
    expect(shots, 5, reason: '只多拍一張');
    expect(find.text('挑濾鏡'), findsOneWidget, reason: '拍完直接回到挑濾鏡');
    final after = strip();
    expect(after[0], before[0]);
    expect(after[1], isNot(before[1]), reason: '第 2 張換成新拍的');
    expect([after[2], after[3]], [before[2], before[3]]);
  });

  testWidgets('拍貼機：重拍一張時按返回，回到原本的照片', (t) async {
    final photo = (await t.runAsync(_photo))!;
    var shots = 0;
    await _phone(t, BoothScreen(template: 1, shoot: () async {
      shots++;
      return photo;
    }));
    await t.tap(find.text('3 秒'));
    await t.pump();
    await t.tap(find.text('開始拍照（4 張）'));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1500));
    }
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('重拍'));
    await t.pumpAndSettle();
    await t.tap(find.text('第 3 張'));
    await t.pump();
    await t.tap(find.byIcon(CupertinoIcons.back));
    await t.pump();
    await t.pump(const Duration(seconds: 4));
    expect(find.text('挑濾鏡'), findsOneWidget);
    expect(shots, 4, reason: '倒數中取消，沒有拍');
  });

  testWidgets('拍貼機：還沒存就能加貼紙裝飾，直接開在貼紙', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, BoothScreen(template: 1, shoot: () async => photo));
    await t.tap(find.text('3 秒'));
    await t.pump();
    await t.tap(find.text('開始拍照（4 張）'));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1500));
    }
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('下一步'));
    await t.pump();
    await t.tap(find.text('加貼紙裝飾'));
    await t.pumpAndSettle();
    final editor = t.widget<EditorScreen>(find.byType(EditorScreen));
    expect(editor.photos, hasLength(4));
    expect(editor.decorate, isTrue);
    expect(editor.saved, isFalse);
  });

  testWidgets('拍貼機：完成！收進作品集，接著可以存到相簿或再拍一組', (t) async {
    MyWorks.reset();
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, BoothScreen(template: 1, shoot: () async => photo));
    await t.tap(find.text('3 秒'));
    await t.pump();
    await t.tap(find.text('開始拍照（4 張）'));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1500));
    }
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('下一步'));
    await t.pump();
    await t.tap(find.text('完成！'));
    for (var i = 0; i < 100 && find.text('再拍一組').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect(MyWorks.works.single.kind, WorkKind.fourCut);
    expect(find.text('收進作品集了'), findsOneWidget);
    expect(find.text('存到相簿'), findsOneWidget);
    expect(find.text('再拍一組'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });
}
