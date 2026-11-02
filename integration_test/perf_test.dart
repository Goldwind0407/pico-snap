import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:pico_snap/lut_files.dart';
import 'package:pico_snap/polaroid_camera_screen.dart';
import 'package:pico_snap/widgets/doodle.dart';
import 'package:pico_snap/widgets/instant_print.dart';

/// Every flow, with frame timings per step (flutter drive --profile).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final report = <String, dynamic>{};
  Future<void> watch(Future<void> Function() action, {required String reportKey}) async {
    final frames = <FrameTiming>[];
    void cb(List<FrameTiming> f) => frames.addAll(f);
    SchedulerBinding.instance.addTimingsCallback(cb);
    await action();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    SchedulerBinding.instance.removeTimingsCallback(cb);
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final f in frames) ms(f.buildDuration)]..sort();
    final raster = [for (final f in frames) ms(f.rasterDuration)]..sort();
    double p(List<double> l, double q) => l.isEmpty ? 0 : l[((l.length - 1) * q).round()];
    report[reportKey] = {
      'frames': frames.length,
      'build_p50': p(build, .5), 'build_p90': p(build, .9), 'build_max': p(build, 1),
      'raster_p50': p(raster, .5), 'raster_p90': p(raster, .9), 'raster_max': p(raster, 1),
      'janky(>16ms)': frames.where((f) => ms(f.buildDuration) > 16 || ms(f.rasterDuration) > 16).length,
    };
    debugPrint('PERF $reportKey ${report[reportKey]}');
  }

  Future<void> wait(WidgetTester t, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> until(WidgetTester t, Finder f, {int ms = 15000}) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (f.evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> scribble(WidgetTester t, Rect r, int strokes) async {
    for (var s = 0; s < strokes; s++) {
      final y = r.top + r.height * (.15 + .7 * (s % 10) / 10);
      final g = await t.startGesture(Offset(r.left + r.width * .15, y));
      for (var i = 0; i < 30; i++) {
        await g.moveBy(Offset(r.width * .7 / 30, (i.isEven ? 1 : -1) * r.height * .02));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('perf', (t) async {
    // A phone-sized photo, like one picked from the gallery.
    final photo = (await t.runAsync(() async {
      final r = ui.PictureRecorder();
      final c = ui.Canvas(r);
      final rnd = math.Random(1);
      c.drawRect(const Rect.fromLTWH(0, 0, 4000, 3000), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(4000, 3000), [const Color(0xFF8AB4F8), const Color(0xFFF6C26B)]));
      for (var i = 0; i < 400; i++) {
        c.drawCircle(Offset(rnd.nextDouble() * 4000, rnd.nextDouble() * 3000), rnd.nextDouble() * 200, Paint()..color = Color(0xFF000000 | rnd.nextInt(0xFFFFFF)).withValues(alpha: .5));
      }
      final img = await r.endRecording().toImage(4000, 3000);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;
    await LutFiles.load();
    await watch(() async {
      await t.pumpWidget(MaterialApp(home: PolaroidCameraScreen(pickPhoto: () async => photo)));
      await wait(t, 4000);
    }, reportKey: '1_open_polaroid');

    await t.tap(find.text('原圖').first);
    await wait(t, 1500);
    await watch(() async => wait(t, 3000), reportKey: '2a_idle_no_filter');
    await t.tap(find.text('日系街拍').first);
    await wait(t, 2500);
    await watch(() async => wait(t, 3000), reportKey: '2b_idle_film_filter');

    await watch(() async {
      await t.tap(find.text('從相簿'));
      await until(t, find.text('顯影中…'));
      await wait(t, 1500);
    }, reportKey: '4_shoot_eject');

    await watch(() async => wait(t, 3000), reportKey: '5_developing');

    debugPrint('DBG prints=${find.byType(InstantPrint, skipOffstage: false).evaluate().length} '
        'texts=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((d) => d != null).join('|')}');
    await t.tap(find.byType(InstantPrint));
    await until(t, find.text('在相片上手寫'));
    await wait(t, 800);

    await t.tap(find.text('在相片上手寫'));
    await wait(t, 800);
    final print = t.getRect(find.byType(InstantPrint));
    await watch(() => scribble(t, print, 25), reportKey: '6_polaroid_write');

    await t.tap(find.text('寫好了'));
    await wait(t, 800);
    await t.tap(find.text('再拍一張'));
    await wait(t, 1500);
    await watch(() async {
      await t.tap(find.text('做成拼貼'));
      await wait(t, 4000);
    }, reportKey: '7_open_editor');

    await watch(() async {
      await t.tap(find.text('濾鏡').last);
      await wait(t, 4000);
    }, reportKey: '8_editor_filters');

    await t.tap(find.text('畫筆').last);
    await wait(t, 800);
    final canvas = t.getRect(find.byType(DoodleInput).first);
    await watch(() => scribble(t, canvas, 25), reportKey: '9_editor_brush');
    binding.reportData = report;
  });
}
