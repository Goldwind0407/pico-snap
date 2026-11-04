import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
    mySheets.clear();
    stickerNames.clear();
    customTemplates.clear();
  });

  testWidgets('照片：點有照片的格子可以拖曳移動、置中、移除', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, EditorScreen(key: UniqueKey(), mode: EditorMode.polaroid, photos: [photo]));
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

  testWidgets('相機：底片分系列，切到三麗鷗只看到三麗鷗的底片', (t) async {
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => null, motion: const Stream.empty()));
    expect(find.text('凱蒂貓'), findsNothing, reason: '一開始是基本');
    await t.tap(find.text('三麗鷗'));
    await t.pump();
    expect(find.text('白底片'), findsNothing);
    await t.tap(find.text('凱蒂貓'));
    await t.pump();
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).film, FilmStock.sanrioKitty);
    // Back to 白底片: the screen remembers the last film for the next tests.
    await t.tap(find.text('基本'));
    await t.pump();
    await t.tap(find.text('白底片'));
    await t.pump();
    for (final g in FilmStock.series) {
      expect(FilmStock.values.where((f) => f.group == g), isNotEmpty, reason: g);
    }
    expect(FilmStock.values.every((f) => FilmStock.series.contains(f.group)), isTrue);
  });

  testWidgets('相機：選黑底片拍出來就是黑底片；機身顏色在設定裡換', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty()));
    await t.tap(find.text('黑底片'));
    await t.pump();
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).film, FilmStock.black, reason: '選的底片放大給你看');
    await t.tap(find.byTooltip('設定'));
    await t.pumpAndSettle();
    expect(find.text('相機顏色'), findsOneWidget);
    await t.tap(find.text('薄荷'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(195, 60));
    await t.pumpAndSettle();
    await t.tap(find.text('開始拍照'));
    await t.pump();
    expect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/instant/camera_mint.png'), findsOneWidget);
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).film, FilmStock.black);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('相機：下次打開還是上次選的底片', (t) async {
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty()));
    await t.tap(find.text('黑底片'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await _phone(t, PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty()));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).film, FilmStock.black);
    await t.tap(find.text('開始拍照'));
    await t.pump();
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
    expect(find.byWidgetPredicate((w) => w is TextSticker && w.words.text == '好開心'), findsOneWidget);
    expect(find.byType(StickerItem), findsOneWidget);
  });

  testWidgets('文字貼紙：選字型和顏色再加上去；選中的字也能改樣式', (t) async {
    await _phone(t, const EditorScreen(mode: EditorMode.polaroid));
    await t.tap(find.text('文字').last);
    await t.pumpAndSettle();
    expect(find.text('相片上的字'), findsOneWidget);
    await t.tap(find.text('文字貼紙'));
    await t.pumpAndSettle();
    await t.tap(find.byWidgetPredicate((w) => w is TextSticker && w.words.text == '描邊'));
    final dot = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == textColors[1] && (w.decoration! as BoxDecoration).shape == BoxShape.circle);
    await t.tap(dot);
    await t.pump();
    await t.enterText(find.byType(TextField), '好開心');
    await t.tap(find.text('加上去'));
    await t.pumpAndSettle();
    TypedWords words() => t.widget<TextSticker>(find.byWidgetPredicate((w) => w is TextSticker && w.words.text == '好開心')).words;
    expect(words().look, TextLook.outline);
    expect(words().color, textColors[1]);
    // 剛加上去的是選中的：換成手寫，它跟著換
    await t.tap(find.byWidgetPredicate((w) => w is TextSticker && w.words.text == '手寫'));
    await t.pumpAndSettle();
    expect(words().look, TextLook.hand);
    expect(TypedWords.parse('text:舊的字')!.text, '舊的字', reason: '以前存的文字貼紙還讀得到');
    expect(TypedWords.parse(const TypedWords('a:b', look: TextLook.round).id)!.text, 'a:b');
  });

  testWidgets('寬螢幕（摺疊機打開、平板）：編輯器的工具在作品旁邊，首頁玩法排成一排；摺回去又變回上下', (t) async {
    t.view.physicalSize = const Size(820, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: EditorScreen(mode: EditorMode.polaroid)));
    await t.pumpAndSettle();
    final canvas = t.getRect(find.byType(InstantPrint).first);
    final tabs = t.getRect(find.text('版面'));
    expect(tabs.left, greaterThan(canvas.right), reason: '工具在右邊');
    // 摺回去：同一個畫面變窄，工具回到下面，作品還在
    await t.tap(find.text('黑底片'));
    await t.pumpAndSettle();
    t.view.physicalSize = const Size(390, 844);
    await t.pumpAndSettle();
    expect(t.getRect(find.text('版面')).top, greaterThan(t.getRect(find.byType(InstantPrint).first).bottom));
    expect(find.byWidgetPredicate((w) => w is InstantPrint && w.film == FilmStock.black), findsNWidgets(4), reason: '改過的還在');

    t.view.physicalSize = const Size(820, 900);
    await t.pumpWidget(const MaterialApp(home: HomeScreen()));
    await t.pumpAndSettle();
    final four = t.getRect(find.text('四格拍貼').first), sticker = t.getRect(find.text('貼紙裝飾').first);
    expect(sticker.top, closeTo(four.top, 1), reason: '四張卡片同一排');
  });

  testWidgets('首頁：「素材」是分頁，返回鍵先回首頁；沒有還沒開放的商店', (t) async {
    await _phone(t, const HomeScreen());
    expect(find.text('商店'), findsNothing);
    await t.tap(find.text('素材'));
    await t.pumpAndSettle();
    expect(find.text('我的素材'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.back), findsNothing, reason: '分頁裡沒有返回箭頭');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget, reason: '回到首頁分頁');
  });

  testWidgets('首頁：相機按鈕和「開始製作」都先選一種玩法', (t) async {
    await _phone(t, const HomeScreen());
    await t.tap(find.byIcon(CupertinoIcons.camera_fill));
    await t.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    for (final mode in ['四格拍貼', '拍立得', '拍立得拼貼', '貼紙裝飾']) {
      expect(find.descendant(of: sheet, matching: find.text(mode)), findsOneWidget);
    }
    await t.tap(find.descendant(of: sheet, matching: find.text('貼紙裝飾')));
    await t.pumpAndSettle();
    expect(t.widget<EditorScreen>(find.byType(EditorScreen)).mode, EditorMode.sticker);
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('開始製作'));
    await t.pumpAndSettle();
    expect(find.text('像拍貼機，倒數連拍 4 張'), findsOneWidget);
  });

  testWidgets('我的素材：還沒有貼紙、模板時，有說明和「做第一個」', (t) async {
    await _phone(t, const LibraryScreen());
    expect(find.text('還沒有自己的貼紙'), findsOneWidget);
    expect(find.text('做第一張貼紙'), findsOneWidget);
    await t.tap(find.text('模板'));
    await t.pumpAndSettle();
    expect(find.text('做第一個模板'), findsOneWidget);
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

  testWidgets('換底紋、背景這類設定也算修改：返回時會問', (t) async {
    await _phone(t, Builder(builder: (context) => TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditorScreen(mode: EditorMode.sticker))),
      child: const Text('open'),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final nav = t.state<NavigatorState>(find.byType(Navigator));

    // 只是點工具、沒有改東西：直接離開
    await t.tap(find.text('底紋'));
    await t.pumpAndSettle();
    nav.maybePop();
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('底紋'));
    await t.pumpAndSettle();
    await t.tap(find.text(ginghamPatterns[2].name));
    await t.pumpAndSettle();
    nav.maybePop();
    await t.pumpAndSettle();
    expect(find.text('還沒儲存的作品會不見喔。'), findsOneWidget);
  });

  testWidgets('空白作品先引導選照片；有照片之後就不再擋著', (t) async {
    await _phone(t, const EditorScreen(mode: EditorMode.sticker));
    expect(find.text('先選一張照片'), findsOneWidget);
    await _phone(t, EditorScreen(key: UniqueKey(), mode: EditorMode.fourCut, template: 0));
    expect(find.text('選照片（一次可以選 4 張）'), findsOneWidget);
    final photo = (await t.runAsync(_photo))!;
    await _phone(t, EditorScreen(key: UniqueKey(), mode: EditorMode.polaroid, photos: [photo]));
    expect(find.textContaining('選照片'), findsNothing);
  });
}
