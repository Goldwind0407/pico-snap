import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

enum PenStyle {
  pen(CupertinoIcons.pencil, '畫筆'),
  marker(CupertinoIcons.pencil_outline, '螢光筆'),
  outline(CupertinoIcons.scribble, '白邊筆'),
  eraser(CupertinoIcons.delete_left, '橡皮擦');

  final IconData icon;
  final String label;
  const PenStyle(this.icon, this.label);
}

const penColors = [
  ink, Colors.white, coral, Color(0xFFFF8FB1), Color(0xFFF7B267),
  Color(0xFFF7D77C), Color(0xFF9CC69B), Color(0xFF86BBD8), Color(0xFFB79CE0), Color(0xFF8B5E3C),
];

/// 細、中、粗：佔畫布寬度的比例，存成大圖時線條跟著放大。
const penWidths = [.008, .016, .028];

/// 畫在作品上的一筆。座標是畫布的比例（0–1），換尺寸也畫在一樣的地方。
class Stroke {
  /// 畫的時候一直加點；畫完就不再動。
  final List<Offset> points;
  final Color color;
  final double width;
  final PenStyle style;
  /// How hard a pen pressed at each point (0–1), drawn by a stylus; null
  /// for a finger.
  final List<double>? pressures;
  Stroke({required this.points, required this.color, required this.width, required this.style, this.pressures});

  /// How much wider than usual the line is where the pen pressed [i]'s way.
  double _press(int i) {
    final p = pressures;
    if (p == null || p.isEmpty) return 1;
    return .45 + 1.1 * p[min(i, p.length - 1)].clamp(0.0, 1.0);
  }

  // The marker drawing is costly to work out; keep it until the stroke grows
  // or the canvas changes size.
  ui.Picture? _felt;
  Size? _feltSize;
  int _feltLength = 0;

  Path _path(Size size) {
    final p = [for (final o in points) Offset(o.dx * size.width, o.dy * size.height)];
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    // A tap: a tiny line so the round cap draws a dot.
    if (p.length == 1) return path..lineTo(p.first.dx + .01, p.first.dy);
    // Smooth through the midpoints so fast strokes don't look jagged.
    for (var i = 1; i < p.length - 1; i++) {
      final mid = (p[i] + p[i + 1]) / 2;
      path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
    }
    return path..lineTo(p.last.dx, p.last.dy);
  }

  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    final w = width * size.width;
    Paint pen(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    switch (style) {
      case PenStyle.pen:
        if (_felt == null || _feltSize != size || _feltLength != points.length) {
          _felt?.dispose();
          final rec = ui.PictureRecorder();
          _paintFelt(Canvas(rec), size, w, pen);
          _felt = rec.endRecording();
          _feltSize = size;
          _feltLength = points.length;
        }
        canvas.drawPicture(_felt!);
      case PenStyle.eraser:
        canvas.drawPath(path, pen(color, w));
      case PenStyle.marker:
        canvas.drawPath(path, pen(color.withValues(alpha: .45), w * 2.4));
      case PenStyle.outline:
        canvas.drawPath(path, pen(Colors.white, w * 2 + 2));
        canvas.drawPath(path, pen(color, w));
    }
  }

  /// The stroke as dense points along the smoothed path, each with how wide
  /// the felt tip is there and how fast the hand was going (0–1).
  List<({Offset at, double width, double speed})> _feltPoints(Size size, double w) {
    final p = [for (final o in points) Offset(o.dx * size.width, o.dy * size.height)];
    // A felt tip lays down more ink where the hand slows and less on quick
    // flicks; ease towards it so the edge doesn't wobble.
    final widths = <double>[], speeds = <double>[];
    var width = w, speed = 0.0;
    for (var i = 0; i < p.length; i++) {
      final v = i == 0 ? 0.0 : ((p[i] - p[i - 1]).distance / (w * 2.2)).clamp(0.0, 1.0);
      speed += (v - speed) * .4;
      width += (w * (1.1 - .32 * speed) * _press(i) - width) * .35;
      widths.add(width);
      speeds.add(speed);
    }
    final out = <({Offset at, double width, double speed})>[(at: p.first, width: widths.first, speed: 0)];
    // Same curve as [_path]: through the midpoints, sampled finely.
    var from = p.first;
    for (var i = 1; i < p.length; i++) {
      final last = i == p.length - 1;
      final to = last ? p[i] : (p[i] + p[i + 1]) / 2;
      final n = max(1, ((to - from).distance / max(1, w * .4)).ceil());
      for (var k = 1; k <= n; k++) {
        final t = k / n;
        final at = last ? Offset.lerp(from, to, t)! : from * ((1 - t) * (1 - t)) + p[i] * (2 * (1 - t) * t) + to * (t * t);
        out.add((at: at, width: widths[i - 1] + (widths[i] - widths[i - 1]) * t, speed: speeds[i]));
      }
      from = to;
    }
    // A quick flick lifts off thinner.
    final tail = min(out.length - 1, 6);
    for (var k = 0; k < tail; k++) {
      final j = out.length - 1 - k, e = out[j];
      out[j] = (at: e.at, width: e.width * (1 - .3 * e.speed * (1 - k / tail)), speed: e.speed);
    }
    return out;
  }

  /// A marker on glossy photo paper: a soft-edged body that swells and thins
  /// with the hand, a little pool of ink where the tip lands, dry streaks
  /// on fast strokes and a sheen on metallic ink.
  void _paintFelt(Canvas canvas, Size size, double w, Paint Function(Color, double) pen) {
    final pts = _feltPoints(size, w);
    final rnd = Random(Object.hash(points.first.dx, points.first.dy));
    var bounds = Rect.fromCircle(center: pts.first.at, radius: w * 2);
    for (final e in pts) {
      bounds = bounds.expandToInclude(Rect.fromCircle(center: e.at, radius: e.width));
    }
    // Drawn opaque into a layer and laid down a touch see-through, so a
    // stroke doesn't darken over itself but two crossing strokes do.
    canvas.saveLayer(bounds, Paint()..color = const Color(0xF2000000));
    // The body as one shape (a dot of felt at every sample, merged) rather
    // than hundreds of separate lines: far fewer draws for the GPU.
    final body = Path()..addOval(Rect.fromCircle(center: pts.first.at, radius: pts.first.width * .56));
    for (var j = 0; j < pts.length; j++) {
      final e = pts[j];
      body.addOval(Rect.fromCircle(center: e.at, radius: e.width / 2));
      // One more between samples keeps the edge smooth, not beaded.
      if (j > 0) body.addOval(Rect.fromCircle(center: (pts[j - 1].at + e.at) / 2, radius: (pts[j - 1].width + e.width) / 4));
    }
    canvas.drawPath(body, Paint()..color = color);
    if (pts.length == 1) {
      canvas.restore();
      return;
    }
    Offset normal(int j) {
      final d = pts[min(j + 1, pts.length - 1)].at - pts[max(j - 1, 0)].at;
      final l = d.distance;
      return l == 0 ? Offset.zero : Offset(-d.dy / l, d.dx / l);
    }
    // Paint markers (light ink) cover well and barely streak.
    final light = color.computeLuminance() > .3;
    // Dry streaks: the felt runs thin on fast strokes and leaves broken
    // lines of paper showing through, always in the same places on this
    // stroke.
    // Grouped by how strong they are, so each streak is a few draws.
    for (var k = 0; k < 4; k++) {
      final side = (rnd.nextDouble() - .5) * .8, thin = .12 + rnd.nextDouble() * .14;
      final gaps = [for (var j = 0; j < pts.length; j++) rnd.nextDouble()];
      final levels = List.generate(4, (_) => Path());
      for (var j = 1; j < pts.length; j++) {
        final a = pts[j - 1], b = pts[j];
        final dry = ((b.speed - .4) / .6).clamp(0.0, 1.0);
        if (dry == 0 || gaps[j] < .35) continue;
        final from = a.at + normal(j - 1) * (side * a.width), to = b.at + normal(j) * (side * b.width);
        levels[min(3, (dry * gaps[j] * 4).floor())]
          ..moveTo(from.dx, from.dy)
          ..lineTo(to.dx, to.dy);
      }
      for (var l = 0; l < 4; l++) {
        canvas.drawPath(levels[l], pen(Color.fromRGBO(0, 0, 0, (light ? .14 : .32) * (l + .5) / 4), w * thin)..blendMode = BlendMode.dstOut);
      }
    }
    if (light) {
      // Paint markers catch the light down the middle.
      final shine = Path();
      for (var j = 0; j < pts.length; j++) {
        final at = pts[j].at - normal(j) * (pts[j].width * .1);
        j == 0 ? shine.moveTo(at.dx, at.dy) : shine.lineTo(at.dx, at.dy);
      }
      canvas.drawPath(shine, pen(Color.lerp(color, Colors.white, .6)!.withValues(alpha: .18), w * .2)
        ..blendMode = BlendMode.srcATop
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(.5, w * .16)));
    }
    if (light && HSVColor.fromColor(color).saturation > .25) {
      // Metallic ink: fine glitter that sparkles.
      final flecks = List.generate(3, (_) => Path());
      for (final e in pts) {
        if (rnd.nextDouble() > .5) continue;
        final at = e.at + Offset(rnd.nextDouble() - .5, rnd.nextDouble() - .5) * e.width * .9;
        flecks[rnd.nextInt(3)].addOval(Rect.fromCircle(center: at, radius: e.width * (.03 + rnd.nextDouble() * .05)));
      }
      for (var l = 0; l < 3; l++) {
        canvas.drawPath(flecks[l], Paint()
          ..blendMode = BlendMode.srcATop
          ..color = Color.lerp(color, Colors.white, .5 + l * .25)!.withValues(alpha: .6 + l * .2));
      }
    }
    canvas.restore();
  }

  /// 手指在 [at]（畫布像素）、半徑 [radius] 的範圍有沒有碰到這一筆。
  bool touches(Offset at, double radius, Size size) {
    final reach = radius + width * size.width * (style == PenStyle.marker ? 1.2 : style == PenStyle.outline ? 1 : .5);
    Offset px(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
    for (var i = 0; i < points.length; i++) {
      final a = px(points[i]);
      if (i == 0) {
        if ((a - at).distance <= reach) return true;
        continue;
      }
      if (_distToSegment(at, px(points[i - 1]), a) <= reach) return true;
    }
    return false;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

class DoodlePainter extends CustomPainter {
  final List<Stroke> strokes;
  /// 變了就重畫：畫的時候 [strokes] 最後一筆會一直加點，數量不會變。
  final int version;
  /// Repaint on this without rebuilding, while a stroke is being drawn.
  DoodlePainter(this.strokes, this.version, {super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final s in strokes) {
      s.paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(DoodlePainter old) => old.strokes != strokes || old.version != version;
}

/// [strokes] over the whole canvas. The finished ones are flattened into one
/// picture as they're done (each marker stroke is hundreds of draws and a
/// layer, too slow to redo every frame); only the last one repaints on
/// [repaint] while it is being drawn.
class InkLayer extends StatefulWidget {
  final List<Stroke> strokes;
  final int version;
  final Listenable? repaint;
  const InkLayer({super.key, required this.strokes, this.version = 0, this.repaint});

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  final _done = _FlatInk();

  @override
  void dispose() {
    _done.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strokes = widget.strokes;
    return IgnorePointer(child: Stack(fit: StackFit.expand, children: [
      if (strokes.length > 1)
        RepaintBoundary(child: CustomPaint(painter: _FlatInkPainter(_done, strokes.sublist(0, strokes.length - 1), widget.version))),
      if (strokes.isNotEmpty)
        CustomPaint(painter: DoodlePainter([strokes.last], widget.version, repaint: widget.repaint)),
    ]));
  }
}

/// Finished strokes as one image, big enough to save from (the long side
/// about as big as a saved picture), with each new stroke drawn on top of
/// the last image.
class _FlatInk {
  static const _longSide = 2400.0;
  ui.Image? image;
  List<Stroke> _drawn = const [];
  Size? _size;

  ui.Image update(List<Stroke> strokes, Size size) {
    final old = image;
    final scale = _longSide / max(1, size.longestSide);
    final w = max(1, (size.width * scale).round()), h = max(1, (size.height * scale).round());
    // Only strokes added after the ones already drawn: draw just those.
    final grows = old != null && _size == size && strokes.length >= _drawn.length &&
        Iterable.generate(_drawn.length).every((i) => identical(strokes[i], _drawn[i]));
    if (grows && strokes.length == _drawn.length) return old;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(scale);
    if (grows) canvas.drawImageRect(old, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Offset.zero & size, Paint());
    for (final s in strokes.skip(grows ? _drawn.length : 0)) {
      s.paint(canvas, size);
    }
    final picture = rec.endRecording();
    image = picture.toImageSync(w, h);
    picture.dispose();
    old?.dispose();
    _drawn = List.of(strokes);
    _size = size;
    return image!;
  }

  void dispose() => image?.dispose();
}

class _FlatInkPainter extends CustomPainter {
  final _FlatInk flat;
  final List<Stroke> strokes;
  final int version;
  _FlatInkPainter(this.flat, this.strokes, this.version);

  @override
  void paint(Canvas canvas, Size size) {
    final image = flat.update(strokes, size);
    canvas.drawImageRect(
      image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FlatInkPainter old) => old.version != version || old.strokes.length != strokes.length ||
      Iterable.generate(strokes.length).any((i) => !identical(strokes[i], old.strokes[i]));
}

/// Apple Pencil double-taps on the pen's side (iPad only;
/// ios/Runner/AppDelegate.swift). Each says what the user chose in the
/// iPad's Apple Pencil settings: `eraser` (to the eraser and back),
/// `previous` (the last tool and back), `palette` (the colours), `ignore`.
abstract final class PencilTaps {
  static const _channel = MethodChannel('picosnap/pencil');
  static final _taps = StreamController<String>.broadcast();
  static bool _asked = false;

  static Stream<String> get taps {
    _listen();
    return _taps.stream;
  }

  /// A double-tap, as if from the pencil (tests).
  @visibleForTesting
  static void debugTap(String action) => _taps.add(action);

  static void _listen() {
    if (_asked || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _asked = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tap') _taps.add(call.arguments as String? ?? 'eraser');
    });
    Future<void> attach([int tries = 0]) async {
      try {
        final ok = await _channel.invokeMethod<bool>('listen') ?? false;
        // No window yet: try again a little later.
        if (!ok && tries < 10) Future.delayed(const Duration(milliseconds: 500), () => attach(tries + 1));
      } catch (_) {
        // Not on an iPad build with the channel: no double-taps.
      }
    }
    attach();
  }
}

/// What touched the canvas: a pen's pressure (null for a finger) and
/// whether it is erasing (a pen's back end, or its side button held).
typedef PenTouch = ({double? pressure, bool erase});

/// 畫筆工具開著的時候蓋在畫布最上面，接住手指或筆。只跟第一根手指，
/// 第二根手指不會畫出線來。
///
/// 筆（S Pen、Apple Pencil）是螢幕自己認出來的，不用藍牙：每次觸碰都說得出
/// 是筆還是手指。用過筆之後一陣子，只有筆會畫，手掌、手指碰到畫布都不算
/// （寫字時手掌靠在螢幕上不會畫出線）。筆的壓力讓線條變粗變細；筆尾或按著
/// 側鍵是橡皮擦。
class DoodleInput extends StatefulWidget {
  /// 按下、移動的位置（畫布像素），和是什麼碰的。
  final void Function(Offset at, Size size, PenTouch touch) onStart, onMove;
  final VoidCallback onEnd;
  const DoodleInput({super.key, required this.onStart, required this.onMove, required this.onEnd});

  /// Only a pen draws right now (one was used lately).
  static bool get penMode => _DoodleInputState.penMode;

  /// Fingers draw again (tests).
  @visibleForTesting
  static void forgetPen() => _DoodleInputState._penAt = DateTime(0);

  @override
  State<DoodleInput> createState() => _DoodleInputState();
}

class _DoodleInputState extends State<DoodleInput> {
  /// When a pen last touched or hovered over a canvas: for a while after,
  /// fingers don't draw.
  static DateTime _penAt = DateTime(0);
  static const penWhile = Duration(seconds: 20);

  int? _pointer;
  /// Erasing for the whole of this line, as it started.
  bool _erase = false;

  Size get _size => (context.findRenderObject()! as RenderBox).size;

  static bool _isPen(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  /// Lately a pen has been drawing.
  static bool get penMode => DateTime.now().difference(_penAt) < penWhile;

  PenTouch _touch(PointerEvent e) {
    if (!_isPen(e)) return (pressure: null, erase: false);
    final range = e.pressureMax - e.pressureMin;
    final p = range > 0 ? (e.pressure - e.pressureMin) / range : .5;
    return (pressure: p.clamp(0.0, 1.0), erase: _erase);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerHover: (e) {
      if (_isPen(e)) _penAt = DateTime.now();
    },
    onPointerDown: (e) {
      final pen = _isPen(e);
      if (pen) {
        _penAt = DateTime.now();
        // A palm got there first: the pen takes over.
        if (_pointer != null) _end(_pointer!);
      } else if (penMode) {
        return;
      }
      if (_pointer != null) return;
      _pointer = e.pointer;
      _erase = pen && (e.kind == PointerDeviceKind.invertedStylus || e.buttons & kSecondaryStylusButton != 0);
      widget.onStart(e.localPosition, _size, _touch(e));
    },
    onPointerMove: (e) {
      if (e.pointer != _pointer) return;
      if (_isPen(e)) _penAt = DateTime.now();
      widget.onMove(e.localPosition, _size, _touch(e));
    },
    onPointerUp: (e) => _end(e.pointer),
    onPointerCancel: (e) => _end(e.pointer),
  );

  void _end(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    widget.onEnd();
  }
}

/// Clamp a canvas-pixel point into the canvas and turn it into 0–1.
Offset normalise(Offset at, Size size) => Offset(
  (at.dx / max(1, size.width)).clamp(0.0, 1.0),
  (at.dy / max(1, size.height)).clamp(0.0, 1.0),
);
