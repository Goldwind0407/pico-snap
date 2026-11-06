import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/library_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/services/my_library.dart';
import 'package:pico_snap/template_maker_screen.dart';
import 'package:pico_snap/theme.dart';
import 'package:pico_snap/widgets/frames.dart';
import 'package:pico_snap/widgets/sticker_item.dart';

/// 1×1 的透明 PNG：當作使用者自己做的貼紙。
final _tinyPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  setUp(() {
    customStickers.clear();
    mySheets.clear();
    stickerNames.clear();
    customTemplates.clear();
  });

  Future<void> phone(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: home));
    await t.pumpAndSettle();
  }

  Finder visual(String id) => find.byWidgetPredicate((w) => w is StickerVisual && w.sticker == id);

  testWidgets('我的素材：長按選貼紙，刪除要先確認', (t) async {
    final a = MyLibrary.addSticker(_tinyPng);
    final b = MyLibrary.addSticker(_tinyPng);
    expect(a, isNot(b));
    await phone(t, const LibraryScreen());
    expect(find.text('照片去背'), findsOneWidget);
    expect(find.text(unsortedSheet), findsOneWidget, reason: '還沒分類的貼紙放在未分類');

    await t.longPress(visual(a));
    await t.pumpAndSettle();
    expect(find.text('已選 1 張'), findsOneWidget);
    await t.tap(find.byTooltip('刪除'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(customStickers, hasLength(2));

    await t.tap(find.byTooltip('刪除'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(GlassDialog), matching: find.text('刪除')));
    await t.pumpAndSettle();
    expect(customStickers.keys, [b]);
    expect(find.text('已選 1 張'), findsNothing);
  });

  testWidgets('我的素材：一次選很多張移到同一張貼紙紙，取名字、搜尋', (t) async {
    final a = MyLibrary.addSticker(_tinyPng);
    final b = MyLibrary.addSticker(_tinyPng);
    final c = MyLibrary.addSticker(_tinyPng);
    final cats = MyLibrary.addSheet('我家貓咪');
    MyLibrary.renameSticker(c, '早餐');
    await phone(t, const LibraryScreen());

    // 長按一張開始選，之後點一下就加選
    await t.longPress(visual(a));
    await t.pumpAndSettle();
    await t.tap(visual(b));
    await t.pumpAndSettle();
    expect(find.text('已選 2 張'), findsOneWidget);
    await t.tap(find.byTooltip('移到貼紙紙'));
    await t.pumpAndSettle();
    await t.tap(find.text('我家貓咪').last);
    await t.pumpAndSettle();
    expect(mySheets.single.id, cats);
    expect(mySheets.single.stickers, [a, b]);
    expect(shownSheets.map((s) => s.name), ['我家貓咪', unsortedSheet]);

    // 單選一張可以取名字
    await t.longPress(visual(a));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('取名字'));
    await t.pumpAndSettle();
    await t.enterText(find.descendant(of: find.byType(GlassDialog), matching: find.byType(TextField)), '橘貓');
    await t.tap(find.text('好'));
    await t.pumpAndSettle();
    expect(stickerNames[a], '橘貓');

    // 搜尋貼紙名或貼紙紙名
    await t.enterText(find.byType(TextField), '早餐');
    await t.pumpAndSettle();
    expect(visual(c), findsOneWidget);
    expect(visual(a), findsNothing);
    await t.enterText(find.byType(TextField), '貓咪');
    await t.pumpAndSettle();
    expect(visual(a), findsOneWidget);
    expect(visual(b), findsOneWidget);
    expect(visual(c), findsNothing);
  });

  testWidgets('設計模板：每種圖案都列出來、都畫得出來，換了就存進模板', (t) async {
    await phone(t, const TemplateMakerScreen());
    await t.tap(find.text('圖案'));
    await t.pumpAndSettle();
    for (final label in ['無', '點點', '貓掌', '碎紙花', '條紋', '格紋', '愛心', '星星', '小花', '棋盤格', '波浪']) {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: label);
    }
    expect(t.widget<PhotoStrip>(find.byType(PhotoStrip)).template.pattern, FramePattern.waves);
    expect(_listed(), FramePattern.values.length, reason: '每一種都可以選');
  });

  testWidgets('設計模板：照片格可以四格一起換，也可以每格不同（點預覽的格子選）', (t) async {
    await phone(t, const TemplateMakerScreen());
    await t.tap(find.text('照片格'));
    await t.pumpAndSettle();
    await t.tap(find.text('雲朵'));
    await t.pumpAndSettle();
    StripTemplate strip() => t.widget<PhotoStrip>(find.byType(PhotoStrip)).template;
    expect([for (var i = 0; i < 4; i++) strip().shapeOf(i)], List.filled(4, CellShape.cloud));
    await t.tap(find.descendant(of: find.byType(Row), matching: find.text('2')).first);
    await t.pumpAndSettle();
    await t.tap(find.text('愛心'));
    await t.pumpAndSettle();
    // 點預覽的第 4 格，換成星星
    final cells = find.descendant(of: find.byType(PhotoStrip), matching: find.byType(ClipPath));
    await t.tap(cells.at(3));
    await t.pumpAndSettle();
    await t.tap(find.text('星星'));
    await t.pumpAndSettle();
    expect([for (var i = 0; i < 4; i++) strip().shapeOf(i)], [CellShape.cloud, CellShape.heart, CellShape.cloud, CellShape.star]);
    expect(t.takeException(), isNull);
  });

  test('每格的形狀存檔讀回來一樣；舊的只有一個形狀的模板讀成四格一樣（拿掉的波浪變成雲朵）', () {
    final c = CustomTemplate(id: 'a', frame: const Color(0xFFF9CACB), cellShapes: const [CellShape.heart, CellShape.star, CellShape.rounded, CellShape.cloud]);
    expect(CustomTemplate.fromJson(c.toJson()).cellShapes, c.cellShapes);
    final old = c.toJson()..remove('cellShapes')..['cellShape'] = 'wavy';
    expect(CustomTemplate.fromJson(old).cellShapes, List.filled(4, CellShape.cloud), reason: '拿掉的波浪變成雲朵');
  });

  testWidgets('設計模板：選項會存進模板，模板頁可以刪除', (t) async {
    final sticker = MyLibrary.addSticker(_tinyPng);
    // 從「我的素材」的模板頁進去，儲存後回到那一頁
    await phone(t, const LibraryScreen());
    await t.tap(find.text('模板'));
    await t.pumpAndSettle();
    await t.tap(find.text('做第一個模板'));
    await t.pumpAndSettle();
    expect(find.byType(TemplateMakerScreen), findsOneWidget);
    Future<void> tab(String label) async {
      await t.tap(find.descendant(of: find.byType(TemplateMakerScreen), matching: find.text(label)).last);
      await t.pumpAndSettle();
    }
    await tab('圖案');
    await tab('貓掌');
    await tab('照片格');
    await tab('雲朵');
    await tab('文字');
    await tab('大標題');
    await t.enterText(find.byType(TextField), 'BEST DAY');
    await tab('貼紙');
    // 有自己的貼紙時，貼紙本先翻到自己的那一頁
    await t.tap(visual(sticker).last);
    await t.pumpAndSettle();
    // 貼紙直接在預覽上：拖一下、翻轉
    expect(find.byType(StickerItem), findsOneWidget);
    await t.drag(find.byType(StickerItem), const Offset(20, 30));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_left_right_square));
    await t.pumpAndSettle();
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(customTemplates, hasLength(1));
    final c = customTemplates.single;
    expect([c.pattern, c.cellShape, c.footer, c.caption], [FramePattern.paws, CellShape.cloud, FooterStyle.title, 'BEST DAY']);
    expect(c.stickers.single.sticker, sticker);
    expect(c.stickers.single.flipped, isTrue);
    expect(c.template.decos.single.flipped, isTrue, reason: '印在模板上也是翻轉的');
    // 存檔格式來回一次不變
    expect(CustomTemplate.fromJson(c.toJson()).toJson(), c.toJson());

    expect(find.byType(TemplateMakerScreen), findsNothing);
    expect(find.byType(PhotoStrip), findsOneWidget);

    // 按 ✎ 修改：改成條紋，存回同一個模板
    await t.tap(find.byIcon(CupertinoIcons.pencil));
    await t.pumpAndSettle();
    expect(find.text('修改模板'), findsOneWidget);
    await tab('圖案');
    await tab('條紋');
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(customTemplates.single.pattern, FramePattern.stripes);
    expect(customTemplates.single.id, c.id);
    await t.tap(find.byIcon(CupertinoIcons.xmark));
    await t.pumpAndSettle();
    await t.tap(find.text('刪除'));
    await t.pumpAndSettle();
    expect(customTemplates, isEmpty);
  });

  testWidgets('編輯器只能使用我的素材，不能新增或刪除', (t) async {
    final sticker = MyLibrary.addSticker(_tinyPng);
    MyLibrary.addTemplate(CustomTemplate(id: 't1', caption: 'mine!', frame: Color(0xFFB9C9AE)));
    await phone(t, const EditorScreen());

    // 模板：多一個「我的」分類，選了之後可以改文字（不是印好字的插畫模板）
    await t.tap(find.text(myCategory));
    await t.pumpAndSettle();
    await t.tap(find.byType(PhotoStrip).last);
    await t.pumpAndSettle();
    expect(find.text('mine!'), findsWidgets);
    await t.tap(find.text('文字'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // 貼紙：自己的貼紙紙在貼紙本最前面，只能貼，沒有新增、刪除
    await t.tap(find.text('貼紙').last);
    await t.pumpAndSettle();
    expect(find.text('📷 我的'), findsOneWidget, reason: '沒分類的自己的貼紙，在貼紙本叫「我的」');
    expect(find.text('照片去背'), findsNothing);
    expect(find.byTooltip('刪除'), findsNothing);
    await t.tap(visual(sticker));
    await t.pumpAndSettle();
    expect(find.byType(StickerItem), findsOneWidget);
  });

  testWidgets('編輯器：還沒有自己的貼紙時顯示說明', (t) async {
    await phone(t, const EditorScreen());
    await t.tap(find.text('貼紙').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('📷 我的'));
    await t.pumpAndSettle();
    await t.tap(find.text('📷 我的'));
    await t.pumpAndSettle();
    expect(find.textContaining('到首頁下方的「素材」'), findsOneWidget);
  });

  test('舊格式的模板（固定位置的貼紙）還讀得到', () {
    final old = CustomTemplate.fromJson({
      'id': 'x', 'caption': 'hi', 'frame': 0xFFF9CACB, 'frame2': null,
      'pattern': 'dots', 'cellShape': 'square', 'footer': 'caption', 'stickers': ['assets/stickers/bunny.png'],
    });
    expect(old.stickers.single.sticker, 'assets/stickers/bunny.png');
    expect((old.template.decos.single.center - const Offset(26, 26)).distance, lessThan(.001));
    expect(old.template.decos.single.size, closeTo(40, .01));
  });
}

int _listed() => find.descendant(of: find.byType(Wrap), matching: find.byType(GestureDetector)).evaluate().length;
