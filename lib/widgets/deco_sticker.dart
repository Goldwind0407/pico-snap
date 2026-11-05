import 'dart:math';

import 'package:flutter/material.dart';

/// Paper bits for a collage — washi tape, torn paper and sticky notes —
/// drawn here rather than cut from a sheet, so they come in every colour.
/// Their sticker ids are `deco:<kind>:<colour index>`.
enum DecoKind {
  tape('紙膠帶'),
  stripeTape('條紋膠帶'),
  gridTape('格紋膠帶'),
  torn('撕紙'),
  note('便利貼'),
  tag('標籤紙');

  final String label;
  const DecoKind(this.label);
}

/// The paper colours, soft like the rest of the App.
const decoColors = [
  Color(0xFFF7C5CC), // pink
  Color(0xFFFFE8A3), // butter
  Color(0xFFBFE0D0), // mint
  Color(0xFFC4DDF2), // sky
  Color(0xFFDCCEF2), // lilac
  Color(0xFFF2DCC2), // kraft
  Color(0xFFFFFFFF), // white
];

/// Every decoration, for the sticker book's 裝飾 page.
final decoStickers = [
  for (final k in DecoKind.values)
    for (var c = 0; c < decoColors.length; c++)
      if (!(k == DecoKind.note && c == 6)) 'deco:${k.name}:$c',
];

/// The decoration [id] names, or null when it isn't one.
(DecoKind, Color)? parseDeco(String id) {
  final parts = id.split(':');
  if (parts.length != 3 || parts[0] != 'deco') return null;
  final kind = DecoKind.values.asNameMap()[parts[1]];
  final c = int.tryParse(parts[2]);
  if (kind == null || c == null || c < 0 || c >= decoColors.length) return null;
  return (kind, decoColors[c]);
}

/// A decoration drawn in a square [size] box, as stickers are.
class DecoSticker extends StatelessWidget {
  final DecoKind kind;
  final Color color;
  final double size;
  const DecoSticker(this.kind, this.color, {super.key, this.size = 120});

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _DecoPainter(kind, color)));
}

class _DecoPainter extends CustomPainter {
  final DecoKind kind;
  final Color color;
  const _DecoPainter(this.kind, this.color);

  Color get _deeper => Color.lerp(color, const Color(0xFF6B5444), .25)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final shadow = Paint()..color = const Color(0xFF46322A).withValues(alpha: .16)..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .02);
    switch (kind) {
      case DecoKind.tape:
      case DecoKind.stripeTape:
      case DecoKind.gridTape:
        // A strip of tape across the box, with zig-zag torn ends; see-through.
        final rect = Rect.fromCenter(center: size.center(Offset.zero), width: s * .96, height: s * .3);
        final path = _zigzagEnds(rect, s * .03);
        canvas.drawPath(path.shift(Offset(0, s * .01)), shadow);
        canvas.save();
        canvas.clipPath(path);
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: .82));
        final ink = Paint()..color = _deeper.withValues(alpha: .45);
        if (kind == DecoKind.stripeTape) {
          for (var x = rect.left - rect.height; x < rect.right; x += s * .09) {
            canvas.drawPath(Path()
              ..moveTo(x, rect.bottom)..lineTo(x + s * .045, rect.bottom)
              ..lineTo(x + s * .045 + rect.height, rect.top)..lineTo(x + rect.height, rect.top)..close(), ink);
          }
        } else if (kind == DecoKind.gridTape) {
          final line = Paint()..color = _deeper.withValues(alpha: .35)..strokeWidth = s * .012;
          for (var x = rect.left; x < rect.right; x += s * .06) {
            canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), line);
          }
          for (var y = rect.top + s * .03; y < rect.bottom; y += s * .06) {
            canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
          }
        }
        // A soft sheen along the tape.
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + rect.height * .15, rect.width, rect.height * .18), Paint()..color = Colors.white.withValues(alpha: .22));
        canvas.restore();
      case DecoKind.torn:
        // A piece of paper torn off on its long sides.
        final rect = Rect.fromCenter(center: size.center(Offset.zero), width: s * .9, height: s * .42);
        final path = _tornEdges(rect, s * .028, color.hashCode);
        canvas.drawPath(path.shift(Offset(s * .008, s * .015)), shadow);
        canvas.drawPath(path, Paint()..color = color);
        // The torn fibres show lighter along the edge.
        canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: .55)..style = PaintingStyle.stroke..strokeWidth = s * .012);
      case DecoKind.note:
        // A square sticky note, its bottom corner lifting a little.
        final rect = Rect.fromCenter(center: size.center(Offset.zero), width: s * .78, height: s * .78);
        final path = Path()
          ..moveTo(rect.left, rect.top)..lineTo(rect.right, rect.top)..lineTo(rect.right, rect.bottom - s * .06)
          ..quadraticBezierTo(rect.right - s * .02, rect.bottom - s * .01, rect.right - s * .12, rect.bottom)
          ..lineTo(rect.left, rect.bottom)..close();
        canvas.drawPath(path.shift(Offset(s * .01, s * .03)), shadow);
        canvas.drawPath(path, Paint()..color = color);
        // The sticky strip along the top is a shade deeper.
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * .16), Paint()..color = _deeper.withValues(alpha: .12));
        canvas.drawPath(Path()
          ..moveTo(rect.right - s * .12, rect.bottom)..quadraticBezierTo(rect.right - s * .05, rect.bottom - s * .05, rect.right, rect.bottom - s * .06)
          ..lineTo(rect.right - s * .1, rect.bottom - s * .08)..close(), Paint()..color = _deeper.withValues(alpha: .25));
      case DecoKind.tag:
        // A tag with a punched hole.
        final rect = Rect.fromCenter(center: size.center(Offset.zero), width: s * .86, height: s * .4);
        final path = Path()
          ..moveTo(rect.left + rect.height * .35, rect.top)..lineTo(rect.right, rect.top)..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left + rect.height * .35, rect.bottom)..lineTo(rect.left, rect.center.dy)..close();
        canvas.drawPath(path.shift(Offset(s * .008, s * .02)), shadow);
        canvas.drawPath(path, Paint()..color = color);
        canvas.drawPath(path, Paint()..color = _deeper.withValues(alpha: .5)..style = PaintingStyle.stroke..strokeWidth = s * .01);
        canvas.drawCircle(Offset(rect.left + rect.height * .38, rect.center.dy), s * .035, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(rect.left + rect.height * .38, rect.center.dy), s * .035, Paint()..color = _deeper.withValues(alpha: .5)..style = PaintingStyle.stroke..strokeWidth = s * .008);
        // Ruled lines to write on.
        final line = Paint()..color = _deeper.withValues(alpha: .35)..strokeWidth = s * .008;
        for (final y in [rect.top + rect.height * .38, rect.top + rect.height * .66]) {
          canvas.drawLine(Offset(rect.left + rect.height * .7, y), Offset(rect.right - s * .05, y), line);
        }
    }
  }

  /// [rect] with zig-zag left and right ends, like tape torn off the roll.
  static Path _zigzagEnds(Rect rect, double tooth) {
    final path = Path()..moveTo(rect.left, rect.top);
    path.lineTo(rect.right, rect.top);
    var down = true;
    for (var y = rect.top; y < rect.bottom; y += tooth) {
      path.lineTo(rect.right - (down ? tooth : 0), min(y + tooth, rect.bottom));
      down = !down;
    }
    path.lineTo(rect.left, rect.bottom);
    down = true;
    for (var y = rect.bottom; y > rect.top; y -= tooth) {
      path.lineTo(rect.left + (down ? tooth : 0), max(y - tooth, rect.top));
      down = !down;
    }
    return path..close();
  }

  /// [rect] with ragged top and bottom, the same for the same [seed].
  static Path _tornEdges(Rect rect, double depth, int seed) {
    final random = Random(seed);
    final path = Path()..moveTo(rect.left, rect.top + random.nextDouble() * depth);
    final step = rect.width / 28;
    for (var x = rect.left + step; x <= rect.right + .1; x += step) {
      path.lineTo(x, rect.top + random.nextDouble() * depth);
    }
    for (var x = rect.right; x >= rect.left - .1; x -= step) {
      path.lineTo(x, rect.bottom - random.nextDouble() * depth);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_DecoPainter old) => old.kind != kind || old.color != color;
}
