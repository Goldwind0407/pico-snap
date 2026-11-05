import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'collage_layout.dart';

/// One print of a 拍立得拼貼, lying where [place] says: drag it to move it,
/// pinch to scale and turn it; once selected, the bottom-right handle
/// scales and turns it with one finger and the top-left one takes it away.
class PrintItem extends StatefulWidget {
  /// Half the handles' touch area: a fingertip.
  static const handle = 22.0;
  final PrintPlace place;
  /// Height / width of the print.
  final double heightRatio;
  final Size canvas;
  final bool selected;
  /// Off while the photo inside is being moved instead.
  final bool movable;
  final Widget child;
  final VoidCallback onSelect, onEditStart, onEditEnd, onDelete;
  final ValueChanged<PrintPlace> onChanged;
  final Offset Function(Offset global) toLocal;
  const PrintItem({
    super.key, required this.place, required this.heightRatio, required this.canvas, required this.selected, required this.movable,
    required this.child, required this.onSelect, required this.onEditStart, required this.onEditEnd, required this.onDelete,
    required this.onChanged, required this.toLocal,
  });

  @override
  State<PrintItem> createState() => _PrintItemState();
}

class _PrintItemState extends State<PrintItem> {
  late PrintPlace _start;
  Offset _startFocal = Offset.zero;

  double get _w => widget.place.width * widget.canvas.width;
  Offset get _center => Offset(widget.place.center.dx * widget.canvas.width, widget.place.center.dy * widget.canvas.height);

  void _onScaleStart(ScaleStartDetails d) {
    widget.onEditStart();
    _start = widget.place;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final delta = d.focalPoint - _startFocal;
    final c = _start.center + Offset(delta.dx / widget.canvas.width, delta.dy / widget.canvas.height);
    widget.onChanged((
      center: Offset(c.dx.clamp(0, 1), c.dy.clamp(0, 1)),
      width: (_start.width * d.scale).clamp(.14, .95),
      angle: _start.angle + d.rotation,
    ));
  }

  /// The bottom-right handle: how far it is from the centre sets the size,
  /// which way sets the turn.
  void _onHandleUpdate(DragUpdateDetails d) {
    final v = widget.toLocal(d.globalPosition) - _center;
    final corner = Offset(_w / 2, _w * widget.heightRatio / 2);
    final width = _w * v.distance / corner.distance;
    widget.onChanged((
      center: widget.place.center,
      width: (width / widget.canvas.width).clamp(.14, .95),
      angle: v.direction - corner.direction,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = _w, hgt = w * widget.heightRatio, h = PrintItem.handle, c = _center;
    return Positioned(
      left: c.dx - w / 2 - h, top: c.dy - hgt / 2 - h, width: w + h * 2, height: hgt + h * 2,
      child: Transform.rotate(angle: widget.place.angle, child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: Padding(
          padding: EdgeInsets.all(h),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            onScaleStart: widget.movable ? _onScaleStart : null,
            onScaleUpdate: widget.movable ? _onScaleUpdate : null,
            onScaleEnd: widget.movable ? (_) { HapticFeedback.lightImpact(); widget.onEditEnd(); } : null,
            child: CustomPaint(foregroundPainter: widget.selected ? const _DashedRectPainter() : null, child: widget.child),
          ),
        )),
        if (widget.selected && widget.movable) ...[
          Positioned(left: 0, top: 0, child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDelete,
            child: const _Handle(label: '拿掉這張', delete: true, child: Icon(CupertinoIcons.trash, size: 15, color: Color(0xFFB4483C))),
          )),
          Positioned(right: 0, bottom: 0, child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => widget.onEditStart(),
            onPanUpdate: _onHandleUpdate,
            onPanEnd: (_) { HapticFeedback.lightImpact(); widget.onEditEnd(); },
            child: const _Handle(label: '拖曳縮放、旋轉', child: Icon(CupertinoIcons.arrow_up_left_arrow_down_right, size: 12, color: ink)),
          )),
        ],
      ])),
    );
  }
}

class _Handle extends StatelessWidget {
  final String label;
  final bool delete;
  final Widget child;
  const _Handle({required this.label, required this.child, this.delete = false});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: label,
    child: SizedBox.square(dimension: PrintItem.handle * 2, child: Center(child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: delete ? const Color(0xFFB4483C).withValues(alpha: .6) : outline.withValues(alpha: .5), width: delete ? 1.4 : 1),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: .15), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: child,
    ))),
  );
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink.withValues(alpha: .55)..strokeWidth = 1.4..style = PaintingStyle.stroke;
    const dash = 5.0, gap = 4.0;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * min(d + dash, len), paint);
      }
    }
    final r = (Offset.zero & size).inflate(3);
    dashed(r.topLeft, r.topRight);
    dashed(r.topRight, r.bottomRight);
    dashed(r.bottomRight, r.bottomLeft);
    dashed(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) => false;
}

/// Where a moving print snaps: its centre to the page's middle lines and to
/// other prints' centres, its turn to straight. Returns the snapped place
/// and the guide lines to show (x positions, then y positions, as
/// fractions of the page).
({PrintPlace place, List<double> xs, List<double> ys}) snapPrint(PrintPlace p, List<PrintPlace> others, Size canvas) {
  const reach = 7.0; // pixels
  var x = p.center.dx, y = p.center.dy, angle = p.angle;
  final xs = <double>[], ys = <double>[];
  double? near(double v, Iterable<double> targets, double size) {
    double? best;
    for (final t in targets) {
      if ((v - t).abs() * size <= reach && (best == null || (v - t).abs() < (v - best).abs())) best = t;
    }
    return best;
  }
  final sx = near(x, [.5, for (final o in others) o.center.dx], canvas.width);
  if (sx != null) { x = sx; xs.add(sx); }
  final sy = near(y, [.5, for (final o in others) o.center.dy], canvas.height);
  if (sy != null) { y = sy; ys.add(sy); }
  // Straight up, within about 2.5°.
  final turns = angle / (pi / 2);
  final nearest = turns.roundToDouble();
  if ((turns - nearest).abs() * pi / 2 < .045) angle = nearest * pi / 2;
  return (place: (center: Offset(x, y), width: p.width, angle: angle), xs: xs, ys: ys);
}

/// The snapping guides over the page while a print moves.
class GuidePainter extends CustomPainter {
  final List<double> xs, ys;
  const GuidePainter(this.xs, this.ys);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF4FA3E0)..strokeWidth = 1.2;
    for (final x in xs) {
      canvas.drawLine(Offset(x * size.width, 0), Offset(x * size.width, size.height), paint);
    }
    for (final y in ys) {
      canvas.drawLine(Offset(0, y * size.height), Offset(size.width, y * size.height), paint);
    }
  }

  @override
  bool shouldRepaint(GuidePainter old) => old.xs != xs || old.ys != ys;
}
