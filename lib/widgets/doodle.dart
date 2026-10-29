import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

enum PenStyle {
  pen(Icons.edit_rounded, '畫筆'),
  marker(Icons.highlight_rounded, '螢光筆'),
  outline(Icons.gesture_rounded, '白邊筆'),
  eraser(Icons.auto_fix_normal_outlined, '橡皮擦');

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
  Stroke({required this.points, required this.color, required this.width, required this.style});

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
        _paintFelt(canvas, size, w, pen);
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
      width += (w * (1.1 - .32 * speed) - width) * .35;
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
    final soft = MaskFilter.blur(BlurStyle.normal, max(.3, w * .04));
    canvas.drawCircle(pts.first.at, pts.first.width * .56, Paint()..color = color..maskFilter = soft);
    for (var j = 1; j < pts.length; j++) {
      canvas.drawLine(pts[j - 1].at, pts[j].at, pen(color, (pts[j - 1].width + pts[j].width) / 2)..maskFilter = soft);
    }
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
    for (var k = 0; k < 4; k++) {
      final side = (rnd.nextDouble() - .5) * .8, thin = .12 + rnd.nextDouble() * .14;
      final gaps = [for (var j = 0; j < pts.length; j++) rnd.nextDouble()];
      for (var j = 1; j < pts.length; j++) {
        final a = pts[j - 1], b = pts[j];
        final dry = ((b.speed - .4) / .6).clamp(0.0, 1.0);
        if (dry == 0 || gaps[j] < .35) continue;
        canvas.drawLine(
          a.at + normal(j - 1) * (side * a.width), b.at + normal(j) * (side * b.width),
          pen(Color.fromRGBO(0, 0, 0, (light ? .14 : .32) * dry * gaps[j]), b.width * thin)
            ..blendMode = BlendMode.dstOut
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.width * .06),
        );
      }
    }
    if (light) {
      // Paint markers catch the light down the middle.
      final shine = pen(Color.lerp(color, Colors.white, .6)!.withValues(alpha: .18), 1)
        ..blendMode = BlendMode.srcATop
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(.5, w * .16));
      for (var j = 1; j < pts.length; j++) {
        final a = pts[j - 1], b = pts[j];
        canvas.drawLine(
          a.at - normal(j - 1) * (a.width * .1), b.at - normal(j) * (b.width * .1),
          shine..strokeWidth = (a.width + b.width) * .18,
        );
      }
    }
    if (light && HSVColor.fromColor(color).saturation > .25) {
      // Metallic ink: fine glitter that sparkles.
      final fleck = Paint()..blendMode = BlendMode.srcATop;
      for (final e in pts) {
        if (rnd.nextDouble() > .5) continue;
        final at = e.at + Offset(rnd.nextDouble() - .5, rnd.nextDouble() - .5) * e.width * .9;
        canvas.drawCircle(at, e.width * (.03 + rnd.nextDouble() * .05),
            fleck..color = Color.lerp(color, Colors.white, .5 + rnd.nextDouble() * .5)!.withValues(alpha: .5 + rnd.nextDouble() * .5));
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
  const DoodlePainter(this.strokes, this.version);

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

/// 畫筆工具開著的時候蓋在畫布最上面，接住手指。只跟第一根手指，
/// 第二根手指不會畫出線來。
class DoodleInput extends StatefulWidget {
  /// 手指按下、移動、放開的位置（畫布像素）。
  final void Function(Offset at, Size size) onStart, onMove;
  final VoidCallback onEnd;
  const DoodleInput({super.key, required this.onStart, required this.onMove, required this.onEnd});

  @override
  State<DoodleInput> createState() => _DoodleInputState();
}

class _DoodleInputState extends State<DoodleInput> {
  int? _pointer;

  Size get _size => (context.findRenderObject()! as RenderBox).size;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) {
      if (_pointer != null) return;
      _pointer = e.pointer;
      widget.onStart(e.localPosition, _size);
    },
    onPointerMove: (e) {
      if (e.pointer == _pointer) widget.onMove(e.localPosition, _size);
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
