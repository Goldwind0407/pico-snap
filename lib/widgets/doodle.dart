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
      case PenStyle.pen || PenStyle.eraser:
        canvas.drawPath(path, pen(color, w));
      case PenStyle.marker:
        canvas.drawPath(path, pen(color.withValues(alpha: .45), w * 2.4));
      case PenStyle.outline:
        canvas.drawPath(path, pen(Colors.white, w * 2 + 2));
        canvas.drawPath(path, pen(color, w));
    }
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
