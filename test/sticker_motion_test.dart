import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/sticker_book.dart';
import 'package:pico_snap/widgets/sticker_book_view.dart';
import 'package:pico_snap/widgets/sticker_item.dart';
import 'package:pico_snap/widgets/sticker_motion.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: SizedBox(width: 360, height: 500, child: child)))),
);

void main() {
  testWidgets('curl pins the attached face and reveals a reflected paper back', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(home: Center(child: RepaintBoundary(key: key,
      child: const SizedBox.square(dimension: 160, child: StickerLift(amount: .45,
        child: ColoredBox(color: Color(0xFFFF0000)))),
    ))));
    await t.pump();
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      try {
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        List<int> at(int x, int y) => [for (var c = 0; c < 4; c++) rgba.getUint8((y * 160 + x) * 4 + c)];
        expect(at(15, 145), [255, 0, 0, 255], reason: 'Attached artwork must stay exactly in place');
        expect(at(145, 15)[3], 0, reason: 'The peeled corner must uncover the backing');
        final back = at(75, 85);
        expect(back[1], greaterThan(180), reason: 'Folded-over artwork becomes the pale adhesive face');
        expect(back[3], 255);
      } finally {
        image.dispose();
      }
    });
  });

  testWidgets('peeling commits once after the lift, even on repeated taps', (t) async {
    var picks = 0;
    await t.pumpWidget(host(PeelableSticker(
      onPick: () => picks++, child: const SizedBox.square(dimension: 100, child: FlutterLogo()),
    )));
    await t.tap(find.byType(PeelableSticker));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(picks, 0);
    expect(t.widget<StickerLift>(find.byType(StickerLift)).amount, greaterThan(0));
    await t.tap(find.byType(PeelableSticker));
    await t.pump(const Duration(milliseconds: 400));
    expect(picks, 0, reason: 'Keep the visible paper curl before committing the pick');
    await t.pumpAndSettle();
    expect(picks, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('closing during a peel cancels the pending addition', (t) async {
    var picks = 0;
    await t.pumpWidget(host(PeelableSticker(onPick: () => picks++, child: const FlutterLogo())));
    await t.tap(find.byType(PeelableSticker));
    await t.pump(const Duration(milliseconds: 120));
    await t.pumpWidget(host(const SizedBox()));
    await t.pumpAndSettle();
    expect(picks, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('reduced motion picks immediately without a lift', (t) async {
    var picks = 0;
    await t.pumpWidget(host(PeelableSticker(onPick: () => picks++, child: const FlutterLogo()), reduceMotion: true));
    await t.tap(find.byType(PeelableSticker));
    expect(picks, 1);
    await t.pump();
    expect(t.widget<StickerLift>(find.byType(StickerLift)).amount, 0);
  });

  testWidgets('built-in book peels before adding and ignores a second tap', (t) async {
    customStickers.clear();
    mySheets.clear();
    final picks = <String>[];
    await t.pumpWidget(host(StickerBookView(onPick: (id, _) => picks.add(id))));
    await t.pumpAndSettle();
    final sheet = stickerBooks.first;
    final image = find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == sheet.sheet);
    final bounds = t.getRect(image);
    final sticker = sheet.stickers.first;
    final point = bounds.topLeft + Offset(sticker.rect.center.dx * bounds.width, sticker.rect.center.dy * bounds.height);
    await t.tapAt(point);
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    expect(picks, isEmpty);
    await t.tapAt(point);
    await t.pumpAndSettle();
    expect(picks, [sticker.asset]);
    expect(t.takeException(), isNull);
  });

  testWidgets('capture renders a settled sticker during its landing animation', (t) async {
    Widget canvas({bool capture = false}) => host(Stack(children: [StickerItem(
      key: const ValueKey('sticker'),
      data: const StickerData(sticker: 'text:Hi', center: Offset(.5, .5)), canvas: const Size(360, 500),
      selected: !capture, animatePlacement: true, animationsEnabled: !capture,
      onSelect: () {}, onDelete: () {}, onFlip: () {}, onEditStart: () {}, onChanged: (_) {}, toLocal: (p) => p,
    )]));
    await t.pumpWidget(canvas());
    await t.pump(const Duration(milliseconds: 90));
    expect(t.widget<StickerLanding>(find.byType(StickerLanding)).progress, lessThan(1));
    await t.pumpWidget(canvas(capture: true));
    expect(t.widget<StickerLanding>(find.byType(StickerLanding)).progress, 1);
    await t.pumpWidget(canvas());
    expect(t.widget<StickerLanding>(find.byType(StickerLanding)).progress, 1,
      reason: 'Finishing capture must not bring back an interrupted fold');
    expect(t.takeException(), isNull);
    await t.pumpAndSettle();
  });
}
