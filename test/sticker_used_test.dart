import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/sticker_book.dart';
import 'package:pico_snap/widgets/sticker_book_view.dart';

void main() {
  testWidgets('貼紙本：同一個作品裡，貼過的貼紙從紙上不見；拿掉之後又回來', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final picked = <String>[];
    late StateSetter refresh;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      refresh = setState;
      return StickerBookView(onPick: (id, _) => setState(() => picked.add(id)), used: picked.toSet());
    }))));
    final sheet = stickerBooks.first;
    await t.tap(find.text(sheet.label));
    await t.pumpAndSettle();
    final k = sheet.stickers.first;
    Future<void> tapSticker() async {
      final page = t.getRect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == sheet.sheet));
      await t.tapAt(Offset(page.left + k.rect.center.dx * page.width, page.top + k.rect.center.dy * page.height));
      await t.pumpAndSettle();
    }

    await tapSticker();
    expect(picked, [k.asset]);
    // Its spot is bare backing now, and tapping it does nothing.
    expect(find.byType(ColorFiltered), findsOneWidget);
    await tapSticker();
    expect(picked, [k.asset], reason: '一張貼紙在同一個作品只能用一次');

    // Taken off the piece (or a new piece): the sticker is back on the sheet.
    refresh(picked.clear);
    await t.pump();
    expect(find.byType(ColorFiltered), findsNothing);
    await tapSticker();
    expect(picked, [k.asset]);
  });
}
