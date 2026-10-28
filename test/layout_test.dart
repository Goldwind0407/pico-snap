import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/booth_screen.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/home_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/widgets/frames.dart';
import 'package:pico_snap/widgets/sticker_item.dart';

void main() {
  const sizes = [Size(360, 740), Size(390, 844), Size(430, 932)];
  Future<void> pump(WidgetTester t, Size s, Widget w) async {
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(home: w));
    await t.pumpAndSettle();
  }

  for (final s in sizes) {
    testWidgets('home $s', (t) async {
      await pump(t, s, const HomeScreen());
      await t.drag(find.byType(ListView).first, const Offset(0, -900));
      await t.pumpAndSettle();
    });
    testWidgets('diary $s', (t) async {
      await pump(t, s, const HomeScreen());
      await t.tap(find.text('日記'));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).last, const Offset(0, -900));
      await t.pumpAndSettle();
    });
    testWidgets('booth $s', (t) async {
      await pump(t, s, const BoothScreen());
      for (final c in stripCategories) {
        await t.tap(find.text(c));
        await t.pumpAndSettle();
      }
    });
    for (final m in EditorMode.values) {
      testWidgets('editor $m $s', (t) async {
        await pump(t, s, EditorScreen(mode: m));
        for (final label in ['模板', '版面', '底紋', '去背', '文字', '畫筆', '橡皮擦', '貼紙']) {
          final f = find.text(label);
          if (f.evaluate().isEmpty) continue;
          await t.tap(f.last);
          await t.pumpAndSettle();
        }
        // Every sticker pack, then add a hand-drawn sticker from the first one.
        // Chips may be scrolled off narrow screens; scroll each into view first.
        final chips = find.ancestor(of: find.text('📷 我的'), matching: find.byType(Scrollable));
        for (final p in [...stickerPacks.reversed, stickerPacks.first]) {
          final chip = find.text('${p.$1} ${p.$2}');
          await t.dragUntilVisible(chip, chips, Offset(p == stickerPacks.first ? 120 : -120, 0));
          await t.tap(chip);
          await t.pumpAndSettle();
        }
        await t.pumpAndSettle();
        await t.tap(find.byType(StickerVisual).first);
        await t.pumpAndSettle();
        expect(find.byType(StickerItem), findsOneWidget);
        await t.drag(find.byType(StickerItem), const Offset(30, 20));
        await t.pumpAndSettle();
        await t.drag(find.byIcon(Icons.open_in_full_rounded), const Offset(25, 25));
        await t.pumpAndSettle();
        // Tap the flip handle: the sticker is mirrored left to right.
        bool mirrored() => find.byWidgetPredicate((w) => w is Transform && w.transform.storage[0] == -1).evaluate().isNotEmpty;
        expect(mirrored(), isFalse);
        await t.tap(find.byIcon(Icons.flip_rounded));
        await t.pumpAndSettle();
        expect(mirrored(), isTrue);
        await t.tap(find.byIcon(Icons.undo_rounded));
        await t.pumpAndSettle();
        await t.tap(find.byType(StickerItem));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.delete_outline_rounded));
        await t.pumpAndSettle();
        expect(find.byType(StickerItem), findsNothing);
        if (m == EditorMode.polaroid) {
          await t.tap(find.text('版面'));
          await t.pumpAndSettle();
          for (final f in ['9:16', '1:1', '4:5']) {
            await t.tap(find.text(f));
            await t.pumpAndSettle();
          }
        }
      });
    }
  }
}
