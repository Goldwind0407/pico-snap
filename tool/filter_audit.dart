// Run: flutter test tool/filter_audit.dart --dart-define=AUDIT_LABEL=before
// Writes a contact sheet and colour probes using the app's actual CPU pipeline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/lut_files.dart';

const _probes = <String, List<int>>{
  'black': [0, 0, 0], 'shadow': [40, 40, 40], 'grey': [128, 128, 128],
  'highlight': [220, 220, 220], 'white': [255, 255, 255],
  'skin_light': [220, 164, 140], 'skin_medium': [160, 106, 80],
  'skin_dark': [85, 56, 43], 'foliage': [70, 130, 65],
  'sky': [100, 165, 210], 'red': [190, 55, 45], 'yellow': [220, 185, 65],
};

Future<ui.Image> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    done.complete(info.image.clone());
    info.dispose();
  }, onError: (Object e, StackTrace? stack) {
    stream.removeListener(listener);
    done.completeError(e, stack);
  });
  stream.addListener(listener);
  return done.future;
}

void _text(Canvas canvas, String label, double x, double y, {double size = 16}) {
  final painter = TextPainter(textDirection: TextDirection.ltr,
    text: TextSpan(text: label, style: TextStyle(fontFamily: 'Nunito', fontSize: size, color: Colors.black)));
  painter.layout(maxWidth: 380);
  painter.paint(canvas, Offset(x, y));
  painter.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render all installed filter looks', () async {
    final font = FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito-500.ttf'));
    await font.load();
    await LutFiles.load();
    const label = String.fromEnvironment('AUDIT_LABEL', defaultValue: 'current');
    final dir = await Directory('build/filter_audit').create(recursive: true);
    final record = ui.PictureRecorder();
    final canvas = Canvas(record);
    const tileW = 400, tileH = 375, columns = 3;
    final rows = (photoFilters.length / columns).ceil();
    canvas.drawColor(const Color(0xFFF3F3F3), BlendMode.src);
    final report = <String, Object>{};
    for (final (index, filter) in photoFilters.indexed) {
      await filter.prepare();
      final dx = (index % columns) * tileW.toDouble();
      final dy = (index ~/ columns) * tileH.toDouble();
      canvas.save();
      canvas.translate(dx, dy);
      canvas.drawRect(const Rect.fromLTWH(5, 5, 390, 365), Paint()..color = Colors.white);
      _text(canvas, '${index + 1}. ${filter.id}', 15, 12);
      for (final (i, asset) in ['girl1.jpg', 'duo.jpg'].indexed) {
        final image = await _resolve(filtered(AssetImage('assets/samples/$asset'), filter, maxSide: 400));
        final box = Rect.fromLTWH(15 + i * 190, 45, 180, 195);
        final fit = applyBoxFit(BoxFit.contain, Size(image.width.toDouble(), image.height.toDouble()), box.size);
        final dst = Alignment.center.inscribe(fit.destination, box);
        canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), dst,
          Paint()..filterQuality = FilterQuality.medium);
        if (filter.vignette > 0) {
          canvas.drawRect(dst, Paint()..shader = RadialGradient(radius: .85,
            colors: [Colors.transparent, Colors.black.withValues(alpha: filter.vignette)], stops: const [.52, 1]).createShader(dst));
        }
        image.dispose();
      }
      final probes = <String, List<int>>{};
      for (final (i, entry) in _probes.entries.indexed) {
        final p = applyLut(Uint8List.fromList([...entry.value, 255]), filter.lut, lutSize).sublist(0, 3);
        probes[entry.key] = p;
        final x = 15 + (i % 6) * 62.0, y = 250 + (i ~/ 6) * 37.0;
        canvas.drawRect(Rect.fromLTWH(x, y, 60, 28), Paint()..color = Color.fromARGB(255, p[0], p[1], p[2]));
      }
      final ramp = <List<int>>[];
      for (var i = 0; i < 256; i++) {
        final p = applyLut(Uint8List.fromList([i, i, i, 255]), filter.lut, lutSize).sublist(0, 3);
        ramp.add(p);
        canvas.drawRect(Rect.fromLTWH(15 + i * 370 / 256, 331, 370 / 256 + .1, 24),
          Paint()..color = Color.fromARGB(255, p[0], p[1], p[2]));
      }
      report[filter.id] = {'name': filter.name, 'probes': probes, 'greyRamp': ramp,
        'grain': filter.grain, 'soften': filter.soften, 'halation': filter.halation};
      canvas.restore();
    }
    final picture = record.endRecording();
    final sheet = await picture.toImage(columns * tileW, rows * tileH);
    try {
      final png = (await sheet.toByteData(format: ui.ImageByteFormat.png))!;
      await File('${dir.path}/$label.png').writeAsBytes(png.buffer.asUint8List());
      await File('${dir.path}/$label.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    } finally {
      sheet.dispose();
      picture.dispose();
    }
  });
}
