import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';

void main() {
  test('soft focus does not bleed hidden RGB into an opaque subject', () {
    final source = Uint8List.fromList([
      for (var i = 0; i < 25; i++)
        ...i == 12 ? [240, 10, 20, 255] : [0, 255, 255, 0],
    ]);
    final result = Uint8List.fromList(source);
    finishFilm(result, source, 5, 5, soften: 1);
    expect(result.sublist(48, 52), [240, 10, 20, 255]);
    for (var i = 3; i < source.length; i += 4) {
      expect(result[i], source[i]);
    }
  });

  test('halation samples small off-centre lights and preserves flat whites',
      () {
    const w = 16, h = 16;
    final white = Uint8List.fromList(List.filled(w * h * 4, 255));
    final flat = Uint8List.fromList(white);
    finishFilm(flat, white, w, h, halation: 1);
    expect(flat, white);
    final source = Uint8List.fromList([
      for (var i = 0; i < w * h; i++) ...[20, 20, 20, 255]
    ]);
    // None of these pixels lies at a quarter-resolution cell's centre.
    for (final p in [68, 69, 84, 85]) {
      source.setRange(p * 4, p * 4 + 3, [255, 255, 255]);
    }
    final glow = Uint8List.fromList(source);
    finishFilm(glow, source, w, h, halation: 1);
    expect(
        [
          for (var i = 0; i < glow.length; i += 4)
            if (source[i] == 20) glow[i]
        ].any((r) => r > 20),
        isTrue);
  });

  test('lookup interpolation preserves an identity cube including endpoints',
      () {
    final lut = Float32List.fromList([
      for (var r = 0; r < 2; r++)
        for (var g = 0; g < 2; g++)
          for (var b = 0; b < 2; b++) ...[
            r.toDouble(),
            g.toDouble(),
            b.toDouble()
          ]
    ]);
    final pixels = Uint8List.fromList([
      for (var i = 0; i < 256; i++) ...[i, 255 - i, (i * 71) % 256, i]
    ]);
    expect(applyLut(pixels, lut, 2), pixels);
    expect(() => applyLut(pixels, lut, 1), throwsArgumentError);
  });
}
