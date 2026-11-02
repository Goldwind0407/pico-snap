import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/lut_files.dart';
import 'package:pico_snap/widgets/filter_thumbs.dart';
import 'package:pico_snap/widgets/frames.dart';

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(300, 200);
  } finally {
    picture.dispose();
  }
}

class _DelayedImage extends ImageProvider<_DelayedImage> {
  final Future<ui.Image> image;
  const _DelayedImage(this.image);

  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _DelayedImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          image.then((image) => ImageInfo(image: image)));
}

void main() {
  test('softening reuses buffers without mixing colour channels or alpha', () {
    const w = 5, h = 3;
    final source = Uint8List.fromList([
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) ...[x * 40, y * 70, (x + y) * 25, 120 + x],
    ]);
    final result = Uint8List.fromList(source);
    finishFilm(result, source, w, h, soften: .8);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final offset = (y * w + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          var sum = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final sx = (x + dx).clamp(0, w - 1);
              final sy = (y + dy).clamp(0, h - 1);
              sum += source[(sy * w + sx) * 4 + channel];
            }
          }
          final expected = (source[offset + channel] +
                  (sum / 9 - source[offset + channel]) * .8 * .55)
              .round();
          expect(result[offset + channel], closeTo(expected, 1));
        }
        expect(result[offset + 3], source[offset + 3]);
      }
    }
  });

  testWidgets('lookup loading shares one job and does not append duplicates',
      (t) async {
    await t.runAsync(() async {
      final first = LutFiles.load();
      expect(LutFiles.load(), same(first));
      await first;
    });
    final ids = photoFilters.map((f) => f.id).toList();
    expect(ids.where((id) => id.startsWith('lut:')), isNotEmpty);
    expect(ids.toSet().length, ids.length);
    await t.runAsync(() => LutFiles.load());
    expect(photoFilters.map((f) => f.id), ids);
  });

  test('filters with the same ID keep their own lookup data', () async {
    final warm = PhotoFilter('same', 'Warm', const Grade(temp: 1));
    final cool = PhotoFilter('same', 'Cool', const Grade(temp: -1));
    await Future.wait([warm.prepare(), cool.prepare()]);
    final pixel = Uint8List.fromList([120, 120, 120, 255]);
    expect(applyLut(pixel, warm.lut, lutSize),
        isNot(applyLut(pixel, cool.lut, lutSize)));
    expect(warm.matrix, isNot(cool.matrix));
  });

  testWidgets('capture waits for the replacement hidden by gapless playback',
      (t) async {
    final old = _DelayedImage(Future.value((await t.runAsync(_image))!));
    final pending = Completer<ui.Image>();
    final next = _DelayedImage(pending.future);
    final key = GlobalKey();
    Widget scene(ImageProvider image) => MaterialApp(
            home: SizedBox(
          key: key,
          child: Image(image: image, gaplessPlayback: true),
        ));
    await t.pumpWidget(scene(old));
    await t.pumpAndSettle();
    await t.pumpWidget(scene(next));
    var ready = false;
    final wait =
        waitForPhotoImages(key.currentContext!).then((_) => ready = true);
    await t.pump();
    expect(ready, isFalse);
    pending.complete((await t.runAsync(_image))!);
    await t.runAsync(() => wait);
    expect(ready, isTrue);
  });

  testWidgets('export decodes the source at export size and restores preview',
      (t) async {
    final bytes = (await t.runAsync(() async {
      final image = await _image();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    final source = MemoryImage(bytes);
    final preview = ResizeImage(source,
        width: 80,
        height: 80,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false);
    final key = GlobalKey<PhotoCaptureState>();
    await t.pumpWidget(MaterialApp(
        home: PhotoCapture(
      key: key,
      child: FittedPhoto(image: preview),
    )));
    key.currentState!.setExportSide(240);
    await t.pump();
    final image = t.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(image.imageProvider, same(source));
    expect(image.width, 240);
    expect(image.height, 240);
    expect(image.policy, ResizeImagePolicy.fit);
    expect(image.allowUpscaling, isFalse);
    key.currentState!.setExportSide(null);
    await t.pump();
    expect(t.widget<Image>(find.byType(Image)).image, same(preview));
  });

  testWidgets('filter thumbnails update when lookup files arrive', (t) async {
    final photo = _DelayedImage(Future.value((await t.runAsync(_image))!));
    const added = PhotoFilter('late', 'Later filter', Grade.none);
    addTearDown(() => photoFilters.remove(added));
    await t.pumpWidget(MaterialApp(
        home: SizedBox(
      height: 90,
      child: FilterThumbs(image: photo, selected: 'none', onPick: (_) {}),
    )));
    photoFilters.insert(1, added);
    LutFiles.changes.value++;
    await t.pump();
    expect(find.text('Later filter'), findsOneWidget);
  });
}
