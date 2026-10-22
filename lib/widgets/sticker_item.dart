import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'frames.dart';

/// A sticker inside the canvas Stack. Drag or pinch the body to move, scale
/// and rotate it; drag a right-hand corner handle to scale and rotate with one
/// finger; tap the trash handle to delete it.
class StickerItem extends StatefulWidget {
  static const baseFraction = .2, handle = 13.0;
  final StickerData data;
  final Size canvas;
  final bool selected;
  final VoidCallback onSelect, onDelete, onEditStart;
  final ValueChanged<StickerData> onChanged;
  final Offset Function(Offset global) toLocal;
  const StickerItem({
    super.key, required this.data, required this.canvas, required this.selected, required this.onSelect,
    required this.onDelete, required this.onEditStart, required this.onChanged, required this.toLocal,
  });

  @override
  State<StickerItem> createState() => _StickerItemState();
}

class _StickerItemState extends State<StickerItem> {
  late StickerData _start;
  Offset _startFocal = Offset.zero;

  // On tall narrow canvases (the four-cut strip) the width alone makes
  // stickers tiny, so the long side sets a minimum.
  double get _baseSize => max(widget.canvas.shortestSide * StickerItem.baseFraction, widget.canvas.longestSide * .12);
  Offset get _centerPx => Offset(widget.data.center.dx * widget.canvas.width, widget.data.center.dy * widget.canvas.height);

  void _onScaleStart(ScaleStartDetails d) {
    widget.onEditStart();
    _start = widget.data;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final delta = d.focalPoint - _startFocal;
    final c = _start.center + Offset(delta.dx / widget.canvas.width, delta.dy / widget.canvas.height);
    widget.onChanged(_start.copyWith(
      center: Offset(c.dx.clamp(0, 1), c.dy.clamp(0, 1)),
      scale: (_start.scale * d.scale).clamp(.3, 4),
      rotation: _start.rotation + d.rotation,
    ));
  }

  /// Drag a corner handle to scale and rotate. [cornerAngle] is where the
  /// handle sits relative to the centre before rotation (bottom-right = 45°).
  void _onHandleUpdate(DragUpdateDetails d, double cornerAngle) {
    final v = widget.toLocal(d.globalPosition) - _centerPx;
    final reach = _baseSize / 2 * sqrt2;
    widget.onChanged(widget.data.copyWith(scale: (v.distance / reach).clamp(.3, 4), rotation: v.direction - cornerAngle));
  }

  @override
  Widget build(BuildContext context) {
    final s = _baseSize * widget.data.scale;
    const h = StickerItem.handle;
    final c = _centerPx;
    return Positioned(
      left: c.dx - s / 2 - h, top: c.dy - s / 2 - h, width: s + h * 2, height: s + h * 2,
      child: Transform.rotate(angle: widget.data.rotation, child: Stack(children: [
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.all(h),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: CustomPaint(
              foregroundPainter: widget.selected ? const _DashedRectPainter() : null,
              child: StickerVisual(widget.data.sticker, size: 120),
            ),
          ),
        )),
        if (widget.selected) ...[
          const Positioned(left: h - 5, bottom: h - 5, child: _CornerDot()),
          Positioned(left: 0, top: 0, child: GestureDetector(
            onTap: widget.onDelete,
            child: const _Handle(child: Icon(Icons.delete_outline_rounded, size: 15, color: ink)),
          )),
          Positioned(right: 0, top: 0, child: GestureDetector(
            onPanStart: (_) => widget.onEditStart(),
            onPanUpdate: (d) => _onHandleUpdate(d, -pi / 4),
            child: const _Handle(child: Icon(Icons.rotate_right_rounded, size: 15, color: ink)),
          )),
          Positioned(right: 0, bottom: 0, child: GestureDetector(
            onPanStart: (_) => widget.onEditStart(),
            onPanUpdate: (d) => _onHandleUpdate(d, pi / 4),
            child: const _Handle(child: Icon(Icons.open_in_full_rounded, size: 12, color: ink)),
          )),
        ],
      ])),
    );
  }
}

class _Handle extends StatelessWidget {
  final Widget child;
  const _Handle({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: StickerItem.handle * 2, height: StickerItem.handle * 2,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: outline.withValues(alpha: .5)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .15), blurRadius: 4, offset: const Offset(0, 1))],
    ),
    child: child,
  );
}

class _CornerDot extends StatelessWidget {
  const _CornerDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2), border: Border.all(color: outline.withValues(alpha: .6))),
  );
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: .55)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const dash = 5.0, gap = 4.0;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * min(d + dash, len), paint);
      }
    }
    final r = Offset.zero & size;
    dashed(r.topLeft, r.topRight);
    dashed(r.topRight, r.bottomRight);
    dashed(r.bottomRight, r.bottomLeft);
    dashed(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) => false;
}
