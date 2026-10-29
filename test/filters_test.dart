import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/live_filter.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/widgets/instant_print.dart';

import 'test_filters.dart';

/// Grades one 0–255 colour with [f]'s full grade.
List<int> _apply(PhotoFilter f, List<int> rgb) {
  final (r, g, b) = f.grade.apply(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}

double _sat(List<int> c) {
  final mx = c.reduce((a, b) => a > b ? a : b), mn = c.reduce((a, b) => a < b ? a : b);
  return mx == 0 ? 0 : (mx - mn) / mx;
}

Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 120, 90), Paint()..color = const Color(0xFF3080F0));
  final img = await r.endRecording().toImage(120, 90);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  useTestFilters();

  test('原圖不改顏色；有調色的濾鏡會改', () {
    expect(_apply(photoFilters.first, [120, 80, 200]), [120, 80, 200]);
    expect(photoFilters.first.isNone, isTrue);
    for (final f in [tealFilter, fadedFilter]) {
      expect(_apply(f, [120, 80, 200]), isNot([120, 80, 200]), reason: f.name);
    }
    expect(photoFilters.map((f) => f.id).toSet(), hasLength(photoFilters.length), reason: 'id 不重複');
  });

  test('分離色調：暗部偏青、亮部偏橙', () {
    final dark = _apply(tealFilter, [40, 40, 40]), light = _apply(tealFilter, [220, 220, 220]);
    expect(dark[2], greaterThan(dark[0]), reason: '暗部藍多於紅');
    expect(light[0], greaterThan(light[2]), reason: '亮部紅多於藍');
    const mono = PhotoFilter('mono', '單色', Grade(saturation: 0));
    expect(_sat(_apply(mono, [220, 80, 140])), lessThan(.02), reason: '飽和度 0 就是黑白');
  });

  test('褪色感：黑色點被拉起來，純黑變成帶灰', () {
    final black = _apply(fadedFilter, [0, 0, 0]);
    expect(black.reduce((a, b) => a < b ? a : b), greaterThan(10));
  });

  test('HSL 只動特定顏色：綠色往青色推，灰色不變色', () {
    final green = _apply(tealFilter, [60, 160, 60]);
    expect(green[2], greaterThan(60 + 20), reason: '綠色帶青（藍增加）');
    const hslOnly = PhotoFilter('hsl', 'HSL', Grade(hsl: {Hue.green: Hsl(hue: 55, sat: -.35)}));
    final grey = _apply(hslOnly, [128, 128, 128]);
    expect((grey[0] - grey[2]).abs(), lessThan(2), reason: '灰色沒有被染色');
  });

  test('LUT 和直接算的結果一致', () {
    final f = fadedFilter;
    final rgba = Uint8List.fromList([10, 200, 90, 255, 250, 30, 140, 128]);
    final out = applyLut(rgba, f.lut, 33);
    for (var i = 0; i < 2; i++) {
      final direct = _apply(f, [rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]]);
      for (var c = 0; c < 3; c++) {
        expect((out[i * 4 + c] - direct[c]).abs(), lessThanOrEqualTo(4));
      }
      expect(out[i * 4 + 3], rgba[i * 4 + 3], reason: '透明度不變');
    }
  });

  testWidgets('編輯器：選濾鏡只套在選取的照片，可以套用到全部', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: EditorScreen(mode: EditorMode.polaroid, photos: [photo, photo])));
    await t.pumpAndSettle();
    await t.tap(find.text('濾鏡'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('測試褪色'), 200, scrollable: find.byWidget(t.widget(find.ancestor(of: find.text('原圖'), matching: find.byType(Scrollable)).first)));
    await t.ensureVisible(find.text('測試褪色'));
    await t.pumpAndSettle();
    await t.tap(find.text('測試褪色'));
    await t.pumpAndSettle();
    List<String?> ids() => [for (final e in find.byType(InstantPrint).evaluate()) (e.widget as InstantPrint).filter?.id];
    expect(ids().where((id) => id == 'test_faded'), hasLength(1));
    await t.tap(find.text('套用到全部照片'));
    await t.pumpAndSettle();
    expect(ids().every((id) => id == 'test_faded'), isTrue);
    expect(find.text('已套用到全部'), findsOneWidget);
  });

  testWidgets('相機：選的濾鏡會印在相片上，也帶到拼貼', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty())));
    await t.pump();
    await t.scrollUntilVisible(find.text('測試青橙'), 200, scrollable: find.byWidget(t.widget(find.ancestor(of: find.text('原圖'), matching: find.byType(Scrollable)).first)));
    await t.tap(find.text('測試青橙'));
    await t.pump();
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).filter?.id, 'test_teal');
    await t.tap(find.byType(InstantPrint));
    await t.pumpAndSettle();
    await t.tap(find.text('再拍一張'));
    await t.pumpAndSettle();
    await t.tap(find.text('做成拼貼'));
    await t.pumpAndSettle();
    expect(t.widget<EditorScreen>(find.byType(EditorScreen)).filters.single.id, 'test_teal');
  });

  testWidgets('相機：拍完一張回來，濾鏡列停在原本的位置', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty())));
    await t.pump();
    final row = find.byWidget(t.widget(find.ancestor(of: find.text('原圖'), matching: find.byType(Scrollable)).first));
    await t.scrollUntilVisible(find.text('測試褪色'), 200, scrollable: row);
    await t.tap(find.text('測試褪色'));
    await t.pump();
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.byType(InstantPrint));
    await t.pumpAndSettle();
    await t.tap(find.text('再拍一張'));
    await t.pumpAndSettle();
    expect(find.text('測試褪色').hitTestable(), findsOneWidget, reason: '選中的濾鏡還在畫面上');
  });

  group('底片處理', () {
    // 64×64 dark grey with a white 8×8 light in the middle.
    const w = 64, h = 64;
    Uint8List scene() {
      final p = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final light = x >= 28 && x < 36 && y >= 28 && y < 36;
          p[i] = p[i + 1] = p[i + 2] = light ? 255 : 40;
          p[i + 3] = 255;
        }
      }
      return p;
    }

    test('高光光暈：亮點旁邊泛橙紅，遠處不變', () {
      final src = scene(), out = Uint8List.fromList(src);
      finishFilm(out, src, w, h, halation: .8);
      int at(int x, int y, int c) => out[(y * w + x) * 4 + c];
      expect(at(38, 32, 0), greaterThan(60), reason: '旁邊變亮');
      expect(at(38, 32, 0), greaterThan(at(38, 32, 2) + 15), reason: '偏紅橙');
      expect(at(2, 2, 0), lessThan(46), reason: '遠處不受影響');
    });

    test('動態顆粒：中間調最明顯，純黑幾乎沒有', () {
      double spread(int v) {
        final p = Uint8List(w * h * 4);
        for (var i = 0; i < p.length; i += 4) {
          p[i] = p[i + 1] = p[i + 2] = v;
          p[i + 3] = 255;
        }
        finishFilm(p, Uint8List.fromList(p), w, h, grain: .5);
        var d = 0.0;
        for (var i = 0; i < p.length; i += 4) {
          d += (p[i] - v).abs();
        }
        return d / (w * h);
      }

      expect(spread(128), greaterThan(spread(6) * 2.5));
      expect(spread(128), greaterThan(spread(250) * 2.5));
    });

    test('柔化：邊緣變柔，但整體亮度不變', () {
      final src = scene(), out = Uint8List.fromList(src);
      finishFilm(out, src, w, h, soften: 1);
      expect(out[(32 * w + 27) * 4], greaterThan(40), reason: '亮點邊緣往外柔開');
      expect(out[(32 * w + 32) * 4], greaterThan(200), reason: '亮點本身還是亮的');
    });
  });

  test('即時取景的 LUT 貼圖：x = 藍 × 33 + 紅，y = 綠', () {
    final f = tealFilter;
    const n = 33;
    final px = FilmShader.lutPixels(f.lut, n);
    expect(px.length, n * n * n * 4);
    for (final (r, g, b) in [(0, 0, 0), (32, 0, 0), (0, 32, 0), (0, 0, 32), (5, 17, 29), (32, 32, 32)]) {
      final o = (g * n * n + b * n + r) * 4, s = ((r * n + g) * n + b) * 3;
      for (var k = 0; k < 3; k++) {
        expect(px[o + k], (f.lut[s + k] * 255).round().clamp(0, 255), reason: '($r,$g,$b)');
      }
    }
  });

  testWidgets('即時取景：沒有 GPU 濾鏡時退回顏色矩陣，不會壞掉', (t) async {
    await t.pumpWidget(MaterialApp(home: FilterLayer(filter: tealFilter, child: const SizedBox.expand(child: ColoredBox(color: Colors.white)))));
    await t.pump();
    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}
