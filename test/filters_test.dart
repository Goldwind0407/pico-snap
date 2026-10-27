import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/widgets/instant_print.dart';

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
  test('原圖不改顏色；每款濾鏡都有改', () {
    expect(_apply(photoFilters.first, [120, 80, 200]), [120, 80, 200]);
    for (final f in photoFilters.skip(1)) {
      expect(_apply(f, [120, 80, 200]), isNot([120, 80, 200]), reason: f.name);
    }
    expect(photoFilters.map((f) => f.id).toSet(), hasLength(photoFilters.length), reason: 'id 不重複');
  });

  test('青橙：暗部偏青、亮部偏橙；黑茶接近灰階', () {
    final to = filterById('teal_orange');
    final dark = _apply(to, [40, 40, 40]), light = _apply(to, [220, 220, 220]);
    expect(dark[2], greaterThan(dark[0]), reason: '暗部藍多於紅');
    expect(light[0], greaterThan(light[2]), reason: '亮部紅多於藍');
    expect(_sat(_apply(filterById('dark_tea'), [200, 60, 60])), lessThan(.45), reason: '顏色被壓得很淡');
  });

  test('褪色感：黑色點被拉起來，純黑變成帶灰', () {
    for (final id in ['cool_grey', 'matte', 'warm_film', 'vintage_brown']) {
      final black = _apply(filterById(id), [0, 0, 0]);
      expect(black.reduce((a, b) => a < b ? a : b), greaterThan(10), reason: id);
    }
  });

  test('膚色通透：千禧通透、清透野餐的膚色變亮、不更黃', () {
    const skin = [224, 172, 140];
    for (final id in ['y2k_clear', 'picnic', 'flash_blue']) {
      final out = _apply(filterById(id), skin);
      final l0 = skin[0] + skin[1] + skin[2], l1 = out[0] + out[1] + out[2];
      expect(l1, greaterThan(l0), reason: '$id 變亮');
      expect(_sat(out), lessThanOrEqualTo(_sat(skin) + .02), reason: '$id 不更飽和');
    }
  });

  test('HSL 只動特定顏色：青橙把綠色往青色推，灰色不變色', () {
    final to = filterById('teal_orange');
    final green = _apply(to, [60, 160, 60]);
    expect(green[2], greaterThan(60 + 20), reason: '綠色帶青（藍增加）');
    final grey = _apply(filterById('picnic'), [128, 128, 128]);
    expect((grey[0] - grey[2]).abs(), lessThan(6), reason: '灰色沒有被染色');
  });

  test('LUT 和直接算的結果一致', () {
    final f = filterById('warm_film');
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
    await t.scrollUntilVisible(find.text('漏光老照片'), 200, scrollable: find.byWidget(t.widget(find.ancestor(of: find.text('原圖'), matching: find.byType(Scrollable)).first)));
    await t.tap(find.text('漏光老照片'));
    await t.pumpAndSettle();
    List<String?> ids() => [for (final e in find.byType(InstantPrint).evaluate()) (e.widget as InstantPrint).filter?.id];
    expect(ids().where((id) => id == 'leak'), hasLength(1));
    await t.tap(find.text('套用到全部照片'));
    await t.pumpAndSettle();
    expect(ids().every((id) => id == 'leak'), isTrue);
    expect(find.text('已套用到全部'), findsOneWidget);
  });

  testWidgets('相機：選的濾鏡會印在相片上，也帶到拼貼', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photo = (await t.runAsync(_photo))!;
    await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo, motion: const Stream.empty())));
    await t.pump();
    await t.scrollUntilVisible(find.text('千禧通透'), 200, scrollable: find.byWidget(t.widget(find.ancestor(of: find.text('原圖'), matching: find.byType(Scrollable)).first)));
    await t.tap(find.text('千禧通透'));
    await t.pump();
    await t.tap(find.text('從相簿'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.widget<InstantPrint>(find.byType(InstantPrint)).filter?.id, 'y2k_clear');
    await t.tap(find.byType(InstantPrint));
    await t.pumpAndSettle();
    await t.tap(find.text('再拍一張'));
    await t.pumpAndSettle();
    await t.tap(find.text('做成拼貼'));
    await t.pumpAndSettle();
    expect(t.widget<EditorScreen>(find.byType(EditorScreen)).filters.single.id, 'y2k_clear');
  });
}
