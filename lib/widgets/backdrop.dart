import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The paper a 拍立得拼貼 lies on: drawn in the backdrop's colour, so every
/// pattern works with every colour.
enum BackdropPattern {
  plain('素面'),
  grid('方格紙'),
  dots('點點'),
  gingham('格紋'),
  stripes('條紋'),
  lined('筆記本'),
  checker('棋盤'),
  hearts('愛心'),
  stars('星星'),
  paper('紙紋'),
  gradient('漸層'),
  /// The first photo, blurred and tinted with the colour.
  photo('照片');

  final String label;
  const BackdropPattern(this.label);
}

bool _isDark(Color c) => c.computeLuminance() < .25;

/// The colour a pattern is drawn in on [base]: a soft deeper shade on light
/// paper, a light one on dark paper.
Color _ink(Color base) => _isDark(base)
    ? Colors.white.withValues(alpha: .3)
    : Color.lerp(base, const Color(0xFF6B5444), .34)!;

/// Draws [pattern] on [color]. [cells] is how many pattern units span the
/// width: the page uses more than a little thumbnail, so both look alike.
class BackdropPainter extends CustomPainter {
  final Color color;
  final BackdropPattern pattern;
  final double cells;
  const BackdropPainter(this.color, this.pattern, {this.cells = 22});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Motifs near the edge are cut at the page, not drawn past it.
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = color);
    final u = size.width / cells;
    final ink = _ink(color);
    final paint = Paint()..color = ink;
    switch (pattern) {
      case BackdropPattern.plain:
      case BackdropPattern.photo:
        break;
      case BackdropPattern.grid:
        final line = Paint()..color = ink.withValues(alpha: ink.a * .7)..strokeWidth = max(.6, u * .05);
        final bold = Paint()..color = ink..strokeWidth = max(.8, u * .08);
        var k = 0;
        for (var x = u * .5; x < size.width; x += u, k++) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), k % 4 == 0 ? bold : line);
        }
        k = 0;
        for (var y = u * .5; y < size.height; y += u, k++) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), k % 4 == 0 ? bold : line);
        }
      case BackdropPattern.dots:
        final step = u * 1.6;
        var row = 0;
        for (var y = step / 2; y < size.height + step; y += step * .87, row++) {
          for (var x = (row.isOdd ? step / 2 : 0) + step / 4; x < size.width + step; x += step) {
            canvas.drawCircle(Offset(x, y), u * .22, paint);
          }
        }
      case BackdropPattern.gingham:
        // Two see-through layers: where they cross it is darker, like woven cloth.
        final band = Paint()..color = (_isDark(color) ? Colors.white : const Color(0xFF6B5444)).withValues(alpha: .16);
        final step = u * 1.6;
        for (var x = 0.0; x < size.width; x += step) {
          canvas.drawRect(Rect.fromLTWH(x, 0, step / 2, size.height), band);
        }
        for (var y = 0.0; y < size.height; y += step) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, step / 2), band);
        }
      case BackdropPattern.stripes:
        final band = Paint()..color = ink.withValues(alpha: ink.a * .55);
        final step = u * 1.5;
        for (var x = 0.0; x < size.width; x += step) {
          canvas.drawRect(Rect.fromLTWH(x, 0, step * .45, size.height), band);
        }
      case BackdropPattern.lined:
        final line = Paint()..color = ink.withValues(alpha: ink.a * .8)..strokeWidth = max(.7, u * .06);
        for (var y = u * 2.4; y < size.height; y += u * 1.1) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        // The notebook's margin line.
        final margin = Paint()..color = const Color(0xFFE8838A).withValues(alpha: .55)..strokeWidth = max(.8, u * .08);
        canvas.drawLine(Offset(u * 2.2, 0), Offset(u * 2.2, size.height), margin);
      case BackdropPattern.checker:
        final square = Paint()..color = ink.withValues(alpha: ink.a * .45);
        final step = u * 1.8;
        var row = 0;
        for (var y = 0.0; y < size.height; y += step, row++) {
          for (var x = row.isOdd ? step : 0.0; x < size.width; x += step * 2) {
            canvas.drawRect(Rect.fromLTWH(x, y, step, step), square);
          }
        }
      case BackdropPattern.hearts:
      case BackdropPattern.stars:
        final step = u * 2.4;
        final shape = pattern == BackdropPattern.hearts ? _heart(u * .55) : _sparkle(u * .7);
        var row = 0;
        for (var y = step / 2; y < size.height + step; y += step * .8, row++) {
          for (var x = (row.isOdd ? step / 2 : 0) + step / 4; x < size.width + step; x += step) {
            canvas.drawPath(shape.shift(Offset(x, y)), paint);
          }
        }
      case BackdropPattern.paper:
        // Flecks and short fibres, the same every time.
        final random = Random(7);
        final dark = Paint()..color = (_isDark(color) ? Colors.white : const Color(0xFF6B5444)).withValues(alpha: .16);
        final light = Paint()..color = Colors.white.withValues(alpha: _isDark(color) ? .08 : .5);
        final n = (size.width * size.height / (u * u) * 8).round().clamp(0, 9000);
        for (var i = 0; i < n; i++) {
          final p = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
          canvas.drawCircle(p, u * (.02 + random.nextDouble() * .05), random.nextBool() ? dark : light);
        }
        final fibre = Paint()..color = dark.color..strokeWidth = max(.4, u * .02)..strokeCap = StrokeCap.round;
        for (var i = 0; i < n ~/ 6; i++) {
          final p = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
          final a = random.nextDouble() * pi;
          canvas.drawLine(p, p + Offset(cos(a), sin(a)) * u * (.2 + random.nextDouble() * .4), fibre);
        }
      case BackdropPattern.gradient:
        canvas.drawRect(rect, Paint()..shader = LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .6)!, color, Color.lerp(color, const Color(0xFF6B5444), .14)!],
        ).createShader(rect));
        // A soft glow, like light on paper.
        canvas.drawRect(rect, Paint()..shader = RadialGradient(
          center: const Alignment(-.5, -.6), radius: .9,
          colors: [Colors.white.withValues(alpha: .35), Colors.white.withValues(alpha: 0)],
        ).createShader(rect));
    }
  }

  static Path _heart(double r) => Path()
    ..moveTo(0, r * .9)
    ..cubicTo(-r * 1.3, 0, -r * .9, -r * 1.2, 0, -r * .45)
    ..cubicTo(r * .9, -r * 1.2, r * 1.3, 0, 0, r * .9)
    ..close();

  static Path _sparkle(double r) {
    final path = Path()..moveTo(0, -r);
    for (var i = 0; i < 4; i++) {
      final a = (i + 1) * pi / 2;
      final m = a - pi / 4;
      path.quadraticBezierTo(cos(m - pi / 2) * r * .14, sin(m - pi / 2) * r * .14, cos(a - pi / 2) * r, sin(a - pi / 2) * r);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(BackdropPainter old) => old.color != color || old.pattern != pattern || old.cells != cells;
}

/// The page's paper: [pattern] in [color], or [photo] blurred and tinted.
class Backdrop extends StatelessWidget {
  final Color color;
  final BackdropPattern pattern;
  final ImageProvider? photo;
  final double cells;
  final Widget? child;
  const Backdrop({super.key, required this.color, required this.pattern, this.photo, this.cells = 22, this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final usePhoto = pattern == BackdropPattern.photo && photo != null;
    return Stack(fit: StackFit.expand, children: [
      CustomPaint(painter: BackdropPainter(color, pattern, cells: cells)),
      if (usePhoto) ...[
        ClipRect(child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: c.maxWidth * .045, sigmaY: c.maxWidth * .045, tileMode: TileMode.mirror),
          child: Image(image: photo!, fit: BoxFit.cover, gaplessPlayback: true),
        )),
        ColoredBox(color: color.withValues(alpha: .28)),
      ],
      if (child != null) child!,
    ]);
  });
}
