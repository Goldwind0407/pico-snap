// flutter test tool/grain_audit.dart
// Compare the previous pixel-sized grain with the current photo-relative
// grain, rendering large processed photos at the size of a phone preview.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/lut_files.dart';

void oldGrain(Uint8List pixels, int w, int h, double amount) {
  double noise(int x, int y) {
    var hash = (x * 374761393 + y * 668265263) & 0x7fffffff;
    hash = ((hash ^ (hash >> 13)) * 1274126177) & 0x7fffffff;
    return (hash & 0xffff) / 32767.5 - 1;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final l = (.2126 * pixels[i] + .7152 * pixels[i + 1] + .0722 * pixels[i + 2]) / 255;
      final value = (noise(x, y) * .7 + noise(x >> 1, (y >> 1) + 9173) * .3) * amount * 30 * (.2 + 3.2 * l * (1 - l));
      for (var c = 0; c < 3; c++) { pixels[i + c] = (pixels[i + c] + value).round().clamp(0, 255); }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render grain before and after at phone size', () async {
    final font = FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito-500.ttf'));
    await font.load();
    await LutFiles.load();
    final bytes = await rootBundle.load('assets/samples/girl1.jpg');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(), targetWidth: 1600, allowUpscaling: true);
    final input = (await codec.getNextFrame()).image;
    codec.dispose();
    final w = input.width, h = input.height;
    final source = (await input.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    input.dispose();
    const previous = {'instant_golden': .28, 'instant_cool': .32, 'lut:teal_amber_street': .2,
      'lut:retro_soft': 0.0, 'lut:fuji_classic_neg_raw': 0.0};
    final recorder = ui.PictureRecorder(), images = <ui.Image>[];
    final canvas = Canvas(recorder)..drawColor(const Color(0xFFF5F2ED), BlendMode.src);
    var row = 0;
    for (final entry in previous.entries) {
      final filter = filterById(entry.key);
      final graded = applyLut(source, filter.lut, lutSize);
      finishFilm(graded, source, w, h, soften: filter.soften, halation: filter.halation, halationColor: filter.halationColor);
      for (var column = 0; column < 2; column++) {
        final pixels = Uint8List.fromList(graded);
        if (column == 0) {
          oldGrain(pixels, w, h, entry.value);
        } else {
          finishFilm(pixels, source, w, h, grain: filter.grain);
        }
        final done = Completer<ui.Image>();
        ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
        final image = await done.future;
        images.add(image);
        final painter = TextPainter(textDirection: TextDirection.ltr, text: TextSpan(
          text: '${column == 0 ? 'Before' : 'After'}: ${filter.id}',
          style: const TextStyle(fontFamily: 'Nunito', fontSize: 16, color: Colors.black)));
        painter.layout(maxWidth: 390);
        painter.paint(canvas, Offset(column * 400 + 10, row * 350 + 12));
        painter.dispose();
        final box = Rect.fromLTWH(column * 400 + 10, row * 350 + 42, 380, 298);
        final fit = applyBoxFit(BoxFit.contain, Size(w.toDouble(), h.toDouble()), box.size);
        canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Alignment.center.inscribe(fit.destination, box), Paint()..filterQuality = FilterQuality.medium);
      }
      row++;
    }
    final picture = recorder.endRecording();
    final sheet = await picture.toImage(800, row * 350);
    try {
      final png = (await sheet.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory('build/filter_audit').create(recursive: true);
      await File('build/filter_audit/grain_comparison.png').writeAsBytes(png.buffer.asUint8List());
    } finally {
      sheet.dispose(); picture.dispose();
      for (final image in images) { image.dispose(); }
    }
  });
}
