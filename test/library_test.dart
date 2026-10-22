import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/library_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/services/my_library.dart';
import 'package:pico_snap/template_maker_screen.dart';
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
    customTemplates.clear();
  });

  Future<void> phone(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: home));
    await t.pumpAndSettle();
  }

  testWidgets('我的素材：刪除貼紙要先確認', (t) async {
    final a = MyLibrary.addSticker(_tinyPng);
    final b = MyLibrary.addSticker(_tinyPng);
    expect(a, isNot(b));
    await phone(t, const LibraryScreen());
    expect(find.text('照片去背'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));

    await t.tap(find.byIcon(Icons.close_rounded).first);
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(customStickers, hasLength(2));

    await t.tap(find.byIcon(Icons.close_rounded).first);
    await t.pumpAndSettle();
    await t.tap(find.text('刪除'));
    await t.pumpAndSettle();
    expect(customStickers, hasLength(1));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('設計模板：選項會存進模板，模板頁可以刪除', (t) async {
    final sticker = MyLibrary.addSticker(_tinyPng);
    // 從「我的素材」的模板頁進去，儲存後回到那一頁
    await phone(t, const LibraryScreen());
    await t.tap(find.text('模板'));
    await t.pumpAndSettle();
    await t.tap(find.text('新增模板'));
    await t.pumpAndSettle();
    expect(find.byType(TemplateMakerScreen), findsOneWidget);
    for (final label in ['貓掌', '雲朵', '大標題']) {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await t.pumpAndSettle();
    }
    await t.enterText(find.byType(TextField), 'BEST DAY');
    final mine = find.byWidgetPredicate((w) => w is StickerVisual && w.sticker == sticker);
    await t.ensureVisible(mine);
    await t.tap(mine);
    await t.pumpAndSettle();
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(customTemplates, hasLength(1));
    final c = customTemplates.single;
    expect([c.pattern, c.cellShape, c.footer, c.caption, c.stickers], [FramePattern.paws, CellShape.cloud, FooterStyle.title, 'BEST DAY', [sticker]]);
    // 存檔格式來回一次不變
    expect(CustomTemplate.fromJson(c.toJson()).toJson(), c.toJson());

    expect(find.byType(TemplateMakerScreen), findsNothing);
    expect(find.byType(PhotoStrip), findsOneWidget);
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pumpAndSettle();
    await t.tap(find.text('刪除'));
    await t.pumpAndSettle();
    expect(customTemplates, isEmpty);
  });

  testWidgets('編輯器只能使用我的素材，不能新增或刪除', (t) async {
    final sticker = MyLibrary.addSticker(_tinyPng);
    MyLibrary.addTemplate(const CustomTemplate(id: 't1', caption: 'mine!', frame: Color(0xFFB9C9AE)));
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

    // 貼紙：「我的」只能貼，沒有新增、刪除
    await t.tap(find.text('貼紙').last);
    await t.pumpAndSettle();
    await t.tap(find.text('📷 我的'));
    await t.pumpAndSettle();
    expect(find.text('照片去背'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await t.tap(find.byWidgetPredicate((w) => w is StickerVisual && w.sticker == sticker));
    await t.pumpAndSettle();
    expect(find.byType(StickerItem), findsOneWidget);
  });

  testWidgets('編輯器：還沒有自己的貼紙時顯示說明', (t) async {
    await phone(t, const EditorScreen());
    await t.tap(find.text('貼紙').last);
    await t.pumpAndSettle();
    await t.tap(find.text('📷 我的'));
    await t.pumpAndSettle();
    expect(find.textContaining('到首頁的「我的」'), findsOneWidget);
  });
}
