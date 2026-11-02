import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/lut_files.dart';

List<int> rgb(PhotoFilter filter, List<int> input) =>
    applyLut(Uint8List.fromList([...input, 255]), filter.lut, lutSize).sublist(0, 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LutFiles.load);

  test('all named looks load and saved negative ID keeps its new recipe', () {
    final ids = photoFilters.map((f) => f.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final entry in lutLooks.entries) {
      expect(filterById('lut:${entry.key}').name, entry.value.name);
    }
    expect(filterById('korean_cream').name, '韓系奶油');
    expect(filterById('lut:fuji_classic_neg_raw').table, isNull);
  });

  test('negative preserves skin colour and separates bright tones', () {
    final filter = filterById('lut:fuji_classic_neg_raw');
    for (final skin in [[220, 164, 140], [160, 106, 80], [85, 56, 43]]) {
      final out = rgb(filter, skin);
      expect(out[0], greaterThan(out[1]));
      expect(out[1], greaterThan(out[2]));
      expect(out.every((v) => v > 10 && v < 245), isTrue);
    }
    final shadow = rgb(filter, [40, 40, 40]);
    expect(shadow[1], lessThan(40), reason: '濃烈負片保留深陰影');
    final high = rgb(filter, [220, 220, 220]);
    final white = rgb(filter, [250, 250, 250]);
    for (var c = 0; c < 3; c++) {
      expect(white[c] - high[c], greaterThan(10));
    }
  });

  test('cream lifts shadows with warm whites and restrained saturation', () {
    final filter = filterById('korean_cream');
    final black = rgb(filter, [0, 0, 0]);
    expect(black.every((v) => v >= 10 && v <= 22), isTrue);
    final white = rgb(filter, [255, 255, 255]);
    expect(white[0], greaterThan(white[1]));
    expect(white[1], greaterThan(white[2]));
    expect(white[0] - white[2], lessThan(15), reason: '奶油白不應變成深黃');
    expect(white.every((v) => v < 255), isTrue);
    final skin = rgb(filter, [220, 164, 140]);
    expect(skin[0], greaterThan(skin[1]));
    expect(skin[1], greaterThan(skin[2]));
    expect(skin[0] - skin[2], lessThan(80));
    final foliage = rgb(filter, [70, 130, 65]);
    expect(foliage[1] - foliage[2], lessThan(65));
    var previous = rgb(filter, [0, 0, 0]);
    for (var v = 1; v <= 255; v++) {
      final current = rgb(filter, [v, v, v]);
      for (var c = 0; c < 3; c++) {
        expect(current[c], greaterThanOrEqualTo(previous[c]), reason: '灰階應平順且不反轉');
      }
      previous = current;
    }
  });
}
