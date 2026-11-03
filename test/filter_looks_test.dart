import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/lut_files.dart';

List<int> rgb(PhotoFilter filter, List<int> input) =>
    applyLut(Uint8List.fromList([...input, 255]), filter.lut, lutSize).sublist(0, 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LutFiles.load);

  test('all named looks load and saved IDs keep resolving', () {
    final ids = photoFilters.map((f) => f.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final entry in lutLooks.entries) {
      expect(filterById('lut:${entry.key}').name, entry.value.name);
    }
    expect(filterById('korean_cream').name, '韓系奶油');
    expect(filterById('lut:fuji_classic_neg_raw').table, isNotNull);
    expect(filterById('lut:retro_soft').table, isNull);
  });

  test('negative retains the original LUT and original film settings', () async {
    final filter = filterById('lut:fuji_classic_neg_raw');
    final source = parseCube(await rootBundle.loadString('assets/luts/fuji_classic_neg_raw.cube'));
    expect(filter.lut, orderedEquals(resampleLut(source.table, source.size, lutSize)));
    expect(filter.grain, 0);
    expect(filter.soften, 0);
  });

  test('retro has smooth neutral ramps, faded blacks and warm highlights', () {
    final filter = filterById('lut:retro_soft');
    var previous = rgb(filter, [0, 0, 0]);
    expect(previous.every((v) => v >= 18 && v <= 30), isTrue);
    for (var v = 1; v <= 255; v++) {
      final current = rgb(filter, [v, v, v]);
      for (var c = 0; c < 3; c++) {
        expect(current[c] - previous[c], inInclusiveRange(0, 2),
          reason: '灰階不能跳色或明暗反轉');
      }
      expect(current.reduce((a, b) => a > b ? a : b) -
          current.reduce((a, b) => a < b ? a : b), lessThan(14));
      previous = current;
    }
    expect(previous[0], greaterThan(previous[2]));
    expect(previous.every((v) => v < 250), isTrue);
    final skin = rgb(filter, [220, 164, 140]);
    expect(skin[0], greaterThan(skin[1]));
    expect(skin[1], greaterThan(skin[2]));
    expect(filter.soften, greaterThan(0));
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
