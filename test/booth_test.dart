import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/booth_screen.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/widgets/frames.dart';

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
  test('取景框跟模板的照片格一樣比例', () {
    final drawn = stripTemplates.firstWhere((t) => t.art == null);
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
    await t.tap(find.text('青橙'));
    await t.pump();
    final strip = t.widget<PhotoStrip>(find.byType(PhotoStrip));
    expect(strip.template, allStripTemplates[1]);
    expect(strip.photos, hasLength(4));
    expect(strip.filters.every((f) => f.id == 'teal_orange'), isTrue);
    // 6. 完成：存圖，可選順便存影片（測試沒有相機畫面，所以不能選）
    await t.tap(find.text('下一步'));
    await t.pump();
    expect(find.text('完成！'), findsOneWidget);
    expect(find.text('存到相簿'), findsOneWidget);
    expect(find.text('這次沒有錄到畫面，只能存圖片'), findsOneWidget);
    // 返回回到挑濾鏡，不會直接離開
    await t.tap(find.byIcon(Icons.arrow_back_rounded));
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
    await t.tap(find.byIcon(Icons.arrow_back_rounded));
    await t.pumpAndSettle();
    expect(find.text('拍好的照片會不見喔。'), findsOneWidget);
    await t.tap(find.text('繼續'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(BoothScreen), findsOneWidget);
    await t.tap(find.byIcon(Icons.arrow_back_rounded));
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
}
