import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';

Uint8List grey(int side) => Uint8List.fromList([
  for (var i = 0; i < side * side; i++) ...[128, 128, 128, 255],
]);

// Measure grain after the same box reduction used when a full photo is
// viewed at phone size. Per-pixel white noise vanishes under this reduction.
double phoneGrain(Uint8List pixels, int side) {
  const output = 256;
  final step = side ~/ output;
  var energy = 0.0;
  for (var y = 0; y < output; y++) {
    for (var x = 0; x < output; x++) {
      var sum = 0.0;
      for (var dy = 0; dy < step; dy++) {
        for (var dx = 0; dx < step; dx++) {
          sum += pixels[((y * step + dy) * side + x * step + dx) * 4] - 128;
        }
      }
      energy += math.pow(sum / (step * step), 2);
    }
  }
  return math.sqrt(energy / (output * output));
}

void main() {
  test('grain remains visible at phone size across preview and export resolutions', () {
    final strengths = <double>[];
    for (final side in [512, 2048]) {
      final pixels = grey(side);
      finishFilm(pixels, pixels, side, side, grain: .4);
      final strength = phoneGrain(pixels, side);
      expect(strength, greaterThan(2.5), reason: '$side px grain should survive reduction to 256 px');
      strengths.add(strength);
    }
    expect(strengths.last / strengths.first, inInclusiveRange(.75, 1.25));
  });

  test('grain is deterministic, monochrome and preserves transparent pixels', () {
    final source = grey(32);
    source.setRange(0, 4, [10, 20, 30, 0]);
    source[7] = 96;
    final first = Uint8List.fromList(source), second = Uint8List.fromList(source);
    finishFilm(first, source, 32, 32, grain: .4);
    finishFilm(second, source, 32, 32, grain: .4);
    expect(first, orderedEquals(second));
    expect(first.sublist(0, 4), [10, 20, 30, 0]);
    for (var i = 4; i < first.length; i += 4) {
      expect(first[i], first[i + 1]);
      expect(first[i + 1], first[i + 2]);
      expect(first[i + 3], source[i + 3]);
    }
    final clean = Uint8List.fromList(source);
    finishFilm(clean, source, 32, 32);
    expect(clean, orderedEquals(source));
  });
}
