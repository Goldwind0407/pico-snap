import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/models.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/widgets/instant_print.dart';

/// Applies a 4×5 matrix to one colour, like the GPU does.
List<int> _apply(List<double> m, List<int> rgb) => [
  for (var i = 0; i < 3; i++)
    (m[i * 5] * rgb[0] + m[i * 5 + 1] * rgb[1] + m[i * 5 + 2] * rgb[2] + m[i * 5 + 4]).round().clamp(0, 255),
];

Future<Uint8List> _photo() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 120, 90), Paint()..color = const Color(0xFF3080F0));
  final img = await r.endRecording().toImage(120, 90);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  test('原圖不改顏色；每款濾鏡都有改', () {
    expect(_apply(photoFilters.first.matrix, [120, 80, 200]), [120, 80, 200]);
    for (final f in photoFilters.skip(1)) {
      expect(_apply(f.matrix, [120, 80, 200]), isNot([120, 80, 200]), reason: f.name);
    }
    expect(photoFilters.map((f) => f.id).toSet(), hasLength(photoFilters.length), reason: 'id 不重複');
  });

  test('青橙：暗部偏青、亮部偏橙；黑茶接近灰階', () {
    final to = filterById('teal_orange').matrix;
    final dark = _apply(to, [40, 40, 40]), light = _apply(to, [220, 220, 220]);
    expect(dark[2], greaterThan(dark[0]), reason: '暗部藍多於紅');
    expect(light[0], greaterThan(light[2]), reason: '亮部紅多於藍');
    final tea = _apply(filterById('dark_tea').matrix, [230, 40, 40]);
    expect((tea[0] - tea[1]).abs(), lessThan(70), reason: '顏色被壓得很淡');
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
