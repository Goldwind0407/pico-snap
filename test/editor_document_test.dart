import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_document.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/services/editor_drafts.dart';
import 'package:pico_snap/services/my_works.dart';
import 'package:pico_snap/widgets/backdrop.dart';
import 'package:pico_snap/widgets/doodle.dart';
import 'package:pico_snap/widgets/page_texture.dart';
import 'package:pico_snap/widgets/frames.dart';
import 'package:pico_snap/widgets/instant_print.dart';
import 'package:pico_snap/widgets/sticker_book_view.dart';

EditorDocument document({List<Stroke> strokes = const []}) => EditorDocument(
      mode: EditorMode.polaroid,
      photos: [
        Uint8List.fromList([1, 2, 3]),
        null,
        null,
        null
      ],
      fits: const [
        PhotoFit(2, Alignment(.2, -.3)),
        PhotoFit(),
        PhotoFit(),
        PhotoFit()
      ],
      films: List.filled(4, FilmStock.white),
      filters: List.filled(4, 'original'),
      captions: ['a', 'b', 'c', 'd'],
      stickers: const [],
      strokes: strokes,
      handwriting: [strokes],
      templateKey: EditorDocument.keyForTemplate(0),
      format: 2,
      pattern: 1,
      backdrop: 0,
      bubble: 'hello',
      stripCaption: 'caption',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('checkpoints isolate growing brush paths', () {
    final stroke = Stroke(
        points: [const Offset(.1, .2)],
        color: Colors.red,
        width: 3,
        style: PenStyle.pen);
    final snapshot = document(strokes: [stroke]);
    stroke.points.add(const Offset(.8, .9));
    expect(snapshot.strokes.single.points, [const Offset(.1, .2)]);
    expect(snapshot.handwriting.single.single.points.length, 1);
  });

  test('draft survives reload and overwrites metadata without rewriting photos',
      () async {
    final dir = await Directory.systemTemp.createTemp('pico_draft_test_');
    try {
      await EditorDrafts.load(directory: dir);
      final id = EditorDrafts.newId();
      final d = document();
      expect(await EditorDrafts.save(id, d), isTrue);
      expect(await EditorDrafts.save(id, d), isTrue);
      expect(
          await dir
              .list(recursive: true)
              .where((f) => f.path.endsWith('.bin'))
              .length,
          1);
      await EditorDrafts.load(directory: dir);
      expect(EditorDrafts.entries.single.id, id);
      final restored = await EditorDrafts.read(id);
      expect(restored.photos.first, d.photos.first);
      expect(restored.toJson(['photo', null, null, null], null),
          d.toJson(['photo', null, null, null], null));
      await EditorDrafts.remove(id);
      expect(EditorDrafts.entries, isEmpty);
      expect(await dir.list().isEmpty, isTrue);
    } finally {
      EditorDrafts.reset();
      await dir.delete(recursive: true);
    }
  });

  test('a collage draft keeps moved prints, its own background photo and the page look', () async {
    final dir = await Directory.systemTemp.createTemp('pico_draft_test_');
    try {
      await EditorDrafts.load(directory: dir);
      final id = EditorDrafts.newId();
      final back = Uint8List.fromList([9, 8, 7]);
      final d = EditorDocument(
        mode: EditorMode.polaroid, photos: const [], fits: const [], films: const [], filters: const [], captions: const [],
        stickers: const [], strokes: const [], handwriting: const [], templateKey: EditorDocument.keyForTemplate(0),
        format: 0, pattern: 0, backdrop: 3, bubble: '',
        places: [null, (center: const Offset(.3, .4), width: .5, angle: .2)],
        backdropPattern: BackdropPattern.photo, backdropPhoto: back, backdropBlur: false,
        texture: PageTexture.leak, textureStrength: .4,
      );
      expect(d.photos.length, 6, reason: '拼貼補滿 6 張');
      expect(await EditorDrafts.save(id, d), isTrue);
      final restored = await EditorDrafts.read(id);
      expect(restored.places[1], (center: const Offset(.3, .4), width: .5, angle: .2));
      expect(restored.places[0], isNull);
      expect(restored.backdropPhoto, back);
      expect(restored.backdropBlur, isFalse);
      expect(restored.backdropPattern, BackdropPattern.photo);
      expect(restored.texture, PageTexture.leak);
      expect(restored.textureStrength, .4);
    } finally {
      EditorDrafts.reset();
      await dir.delete(recursive: true);
    }
  });

  test('gallery exports original bytes and supports legacy previews', () async {
    MyWorks.reset();
    final preview = Uint8List.fromList([1, 2]);
    final original = Uint8List.fromList([3, 4, 5]);
    final full =
        await MyWorks.add(preview, WorkKind.collage, original: original);
    final legacy = await MyWorks.add(preview, WorkKind.collage);
    expect(full.hasOriginal, isTrue);
    expect(await full.exportBytes(), original);
    expect(legacy.hasOriginal, isFalse);
    expect(await legacy.exportBytes(), preview);
  });

  testWidgets('caption undo and redo restore the whole visible document',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        const MaterialApp(home: EditorScreen(mode: EditorMode.polaroid)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文字').last);
    await tester.pumpAndSettle();
    List<String> captions() => tester
        .widgetList<InstantPrint>(find.byType(InstantPrint))
        .map((p) => p.caption)
        .toList();
    final before = captions();
    await tester.enterText(find.byType(TextField).first, 'edited caption');
    await tester.pumpAndSettle();
    expect(captions(), contains('edited caption'));
    await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
    await tester.pumpAndSettle();
    expect(captions(), unorderedEquals(before));
    await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_right));
    await tester.pumpAndSettle();
    expect(captions(), contains('edited caption'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('已經存到相簿的作品拿來裝飾，什麼都沒改就離開，不會變成草稿', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('pico_draft_saved_')))!;
    await tester.runAsync(() => EditorDrafts.load(directory: dir));
    addTearDown(() {
      EditorDrafts.reset();
      dir.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(
        photos: [Uint8List.fromList([1, 2, 3])], decorate: true, saved: true)));
    await tester.pump();
    expect(find.byType(StickerBookView), findsOneWidget, reason: '直接開在貼紙');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(EditorDrafts.entries, isEmpty);
  });
}
