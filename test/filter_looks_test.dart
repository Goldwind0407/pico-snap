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
    expect(filterById('lut:fuji_classic_neg_raw').name, '濃烈負片');
    expect(filterById('lut:fuji_classic_neg_raw').table, isNull, reason: '自己的配方，不是相機廠的檔案');
    expect(filterById('lut:retro_soft').table, isNull);
  });

  test('strong negative: hard but not burnt, cyan-green shadows, deep reds, dark cyan greens', () {
    final filter = filterById('lut:fuji_classic_neg_raw');
    expect(filter.grain, greaterThan(0));
    var previous = rgb(filter, [0, 0, 0]);
    expect(previous[1], greaterThan(previous[0]), reason: '暗部偏青綠');
    expect(previous[2], greaterThan(previous[0]));
    for (var v = 1; v <= 255; v++) {
      final current = rgb(filter, [v, v, v]);
      for (var c = 0; c < 3; c++) {
        expect(current[c] - previous[c], inInclusiveRange(0, 4), reason: '灰階不能跳色或反轉');
      }
      previous = current;
    }
    expect(previous.every((v) => v < 255), isTrue, reason: '白色留一點奶油感');
    // Harder than the photo: the mid tones are steeper than a straight line.
    expect(rgb(filter, [170, 170, 170])[1] - rgb(filter, [85, 85, 85])[1], greaterThan(95));
    for (final skin in [[220, 164, 140], [160, 106, 80], [85, 56, 43]]) {
      final out = rgb(filter, skin);
      expect(out[0], greaterThan(out[1]));
      expect(out[1], greaterThan(out[2]));
      expect(out.every((v) => v > 0 && v < 250), isTrue, reason: '膚色不能燒白');
    }
    final red = rgb(filter, [190, 55, 45]);
    expect(red[0], lessThan(190), reason: '紅色變深而不是變亮');
    expect(red[0] - red[1], greaterThan(110), reason: '但還是濃');
    final foliage = rgb(filter, [70, 130, 65]), plain = [70, 130, 65];
    expect(foliage[1], lessThan(plain[1]), reason: '綠色變深');
    expect(foliage[2] - foliage[0], greaterThan(plain[2] - plain[0]), reason: '綠色往青偏');
  });

  test('film density and tone-dependent colour', () {
    const vivid = Grade(density: 1), drain = Grade(shadowDesat: 1, highlightDesat: 1);
    final (r, g, b) = vivid.apply(1, 0, 0);
    expect(r, closeTo(.5, 1e-6), reason: '最鮮豔的顏色最深');
    expect([g, b], [0, 0]);
    final (gr, gg, gb) = vivid.apply(.5, .5, .5);
    expect([gr, gg, gb], everyElement(closeTo(.5, 1e-6)), reason: '灰色不變');
    final (dr, dg, db) = drain.apply(.12, .02, .02);
    expect(dr - dg, lessThan(.03), reason: '最暗的地方沒什麼顏色');
    final (hr, hg, hb) = drain.apply(1, .9, .9);
    expect(hr - hg, lessThan(.02), reason: '最亮的地方也是');
    final (mr, mg, mb) = drain.apply(.7, .4, .4);
    expect(mr - mg, greaterThan(.25), reason: '顏色留在中間調');
    expect([db, hb, mb], everyElement(isNonNegative));
  });

  test('film presets enable grain while clean looks stay clean', () {
    for (final id in ['instant_golden', 'instant_cool', 'lut:fuji_classic_neg_raw', 'lut:teal_amber_street', 'lut:retro_soft']) {
      expect(filterById(id).grain, greaterThan(0), reason: id);
    }
    expect(filterById('none').grain, 0);
    expect(filterById('korean_cream').grain, 0);
  });

  test('instant looks retain skin and smooth tonal separation', () {
    for (final id in ['instant_golden', 'instant_cool']) {
      final filter = filterById(id);
      expect(filter.id, id, reason: 'Saved instant IDs must not fall back to original');
      var previous = rgb(filter, [0, 0, 0]);
      for (var v = 1; v <= 255; v++) {
        final current = rgb(filter, [v, v, v]);
        for (var c = 0; c < 3; c++) {
          expect(current[c] - previous[c], inInclusiveRange(0, 3),
            reason: '$id must not reverse or posterize the grey ramp');
        }
        previous = current;
      }
      for (final skin in [[220, 164, 140], [160, 106, 80], [85, 56, 43]]) {
        final out = rgb(filter, skin);
        expect(out[0], greaterThan(out[1]));
        expect(out[1], greaterThan(out[2]));
        expect(out.every((v) => v > 0 && v < 250), isTrue);
      }
      final high = rgb(filter, [220, 220, 220]);
      final white = rgb(filter, [255, 255, 255]);
      for (var c = 0; c < 3; c++) {
        expect(white[c] - high[c], greaterThan(10), reason: 'Retain highlight texture');
      }
      expect(white.every((v) => v < 255), isTrue);
    }
  });

  test('instant warm and cool looks have distinct split tones', () {
    final golden = filterById('instant_golden');
    final cool = filterById('instant_cool');
    final goldenBlack = rgb(golden, [0, 0, 0]);
    expect(goldenBlack[1] - goldenBlack[0], greaterThan(5));
    expect(goldenBlack[2] - goldenBlack[0], greaterThan(5));
    final warmMid = rgb(golden, [128, 128, 128]);
    final coolMid = rgb(cool, [128, 128, 128]);
    expect(warmMid[0] - warmMid[2], greaterThan(5));
    expect(coolMid[2] - coolMid[0], greaterThan(5));
    expect(warmMid[0] - warmMid[2] - (coolMid[0] - coolMid[2]), greaterThan(15));
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
