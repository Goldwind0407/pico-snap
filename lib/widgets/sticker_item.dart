import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/app_sounds.dart';
import '../theme.dart';
import 'frames.dart';
import 'sticker_motion.dart';

/// A sticker inside the canvas Stack. Drag or pinch the body to move, scale
/// and rotate it; drag the bottom-right handle to scale and rotate with one
/// finger; tap the top-right handle to flip it and the trash handle to delete it.
class StickerItem extends StatefulWidget {
  /// [handle] is half the handles' touch area (44 px, a fingertip); they
  /// are drawn smaller ([_Handle.dot]).
  static const baseFraction = .2, handle = 22.0;
  final StickerData data;
  final Size canvas;
  final bool selected;
  final bool animatePlacement, animationsEnabled;
  final VoidCallback onSelect, onDelete, onFlip, onEditStart;
  final ValueChanged<StickerData> onChanged;
  final Offset Function(Offset global) toLocal;
  /// How much the canvas is magnified on screen; the handles shrink by as
  /// much so they keep their fingertip size.
  final double zoom;
  const StickerItem({
    super.key, required this.data, required this.canvas, required this.selected, required this.onSelect,
    required this.onDelete, required this.onFlip, required this.onEditStart, required this.onChanged, required this.toLocal,
    this.zoom = 1, this.animatePlacement = false, this.animationsEnabled = true,
  });

  @override
  State<StickerItem> createState() => _StickerItemState();
}

class _StickerItemState extends State<StickerItem> with SingleTickerProviderStateMixin {
  late final _landing = AnimationController(vsync: this, value: 1, duration: stickerLandDuration)..addStatusListener(_onLanded);
  bool _initialized = false;
  bool _stampPending = false;
  late StickerData _start;
  Offset _startFocal = Offset.zero;

  bool get _canAnimate => widget.animationsEnabled && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.animatePlacement && widget.animationsEnabled) {
        if (_canAnimate) {
          _stampPending = true;
          _landing.forward(from: 0);
        } else {
          AppSounds.shared.play(AppSound.stamp);
        }
      }
    }
    if (!_canAnimate) _landing.value = 1;
  }

  @override
  void didUpdateWidget(StickerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animationsEnabled && oldWidget.animationsEnabled) _landing.value = 1;
  }

  @override
  void dispose() {
    _landing.dispose();
    super.dispose();
  }

  Future<void> _select() async {
    widget.onSelect();
    HapticFeedback.selectionClick();
    if (!_canAnimate) return;
    AppSounds.shared.play(AppSound.peel);
    try {
      // Lift the corner before rolling it back down. Starting halfway through
      // a landing would flash an already-folded sticker on a simple tap.
      await _landing.animateBack(.3, duration: const Duration(milliseconds: 260)).orCancel;
      if (mounted && _canAnimate) {
        _stampPending = true;
        await _landing.forward().orCancel;
      }
    } on TickerCanceled {
      // A new tap, drag or removal owns the motion now.
    } finally {
      AppSounds.shared.stop(AppSound.peel);
    }
  }

  void _onLanded(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_stampPending) return;
    _stampPending = false;
    if (mounted && widget.animationsEnabled) AppSounds.shared.play(AppSound.stamp);
  }

  void _land() {
    if (_canAnimate) {
      _stampPending = true;
      _landing.forward();
    } else if (widget.animationsEnabled) {
      AppSounds.shared.play(AppSound.stamp);
    }
    HapticFeedback.lightImpact();
  }

  // On tall narrow canvases (the four-cut strip) the width alone makes
  // stickers tiny, so the long side sets a minimum.
  double get _baseSize => max(widget.canvas.shortestSide * StickerItem.baseFraction, widget.canvas.longestSide * .12);
  Offset get _centerPx => Offset(widget.data.center.dx * widget.canvas.width, widget.data.center.dy * widget.canvas.height);

  void _onScaleStart(ScaleStartDetails d) {
    _landing.value = _canAnimate ? .52 : 1;
    widget.onEditStart();
    _start = widget.data;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final delta = d.focalPoint - _startFocal;
    final c = _start.center + Offset(delta.dx / widget.canvas.width, delta.dy / widget.canvas.height);
    widget.onChanged(_start.copyWith(
      center: Offset(c.dx.clamp(0, 1), c.dy.clamp(0, 1)),
      scale: (_start.scale * d.scale).clamp(.3, _maxScale),
      rotation: _start.rotation + d.rotation,
    ));
  }

  /// Up to 4 times, but never so big that the handles stick out past a
  /// narrow canvas (the four-cut strip), where they couldn't be tapped.
  double get _maxScale => max(.3, min(4.0, (widget.canvas.shortestSide - StickerItem.handle * 2 / widget.zoom) / _baseSize));

  /// Drag the bottom-right handle to scale and rotate. [cornerAngle] is where
  /// the handle sits relative to the centre before rotation (45°).
  void _onHandleUpdate(DragUpdateDetails d, double cornerAngle) {
    final v = widget.toLocal(d.globalPosition) - _centerPx;
    final reach = _baseSize / 2 * sqrt2;
    widget.onChanged(widget.data.copyWith(scale: (v.distance / reach).clamp(.3, _maxScale), rotation: v.direction - cornerAngle));
  }

  @override
  Widget build(BuildContext context) {
    final s = _baseSize * widget.data.scale;
    final h = StickerItem.handle / widget.zoom;
    Widget sized(Widget handle) => SizedBox.square(dimension: h * 2, child: FittedBox(child: handle));
    final c = _centerPx;
    return Positioned(
      left: c.dx - s / 2 - h, top: c.dy - s / 2 - h, width: s + h * 2, height: s + h * 2,
      child: Transform.rotate(angle: widget.data.rotation, child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: Padding(
          padding: EdgeInsets.all(h),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _select,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: (_) => _land(),
            child: CustomPaint(
              foregroundPainter: widget.selected ? const _DashedRectPainter() : null,
              child: AnimatedBuilder(
                animation: _landing,
                child: Transform.flip(flipX: widget.data.flipped, child: StickerVisual(widget.data.sticker, size: 120)),
                builder: (context, child) => StickerLanding(progress: _canAnimate ? _landing.value : 1, child: child!),
              ),
            ),
          ),
        )),
        if (widget.selected) ...[
          Positioned(left: h - 5 / widget.zoom, bottom: h - 5 / widget.zoom, child: SizedBox.square(dimension: 10 / widget.zoom, child: const FittedBox(child: _CornerDot()))),
          Positioned(left: 0, top: 0, child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDelete,
            child: sized(const _Handle(label: '刪除貼紙', delete: true, child: Icon(CupertinoIcons.trash, size: 15, color: Color(0xFFB4483C)))),
          )),
          Positioned(right: 0, top: 0, child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onFlip,
            child: sized(const _Handle(label: '左右翻轉', child: Icon(CupertinoIcons.arrow_left_right_square, size: 15, color: ink))),
          )),
          Positioned(right: 0, bottom: 0, child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              _landing.value = _canAnimate ? .52 : 1;
              widget.onEditStart();
            },
            onPanUpdate: (d) => _onHandleUpdate(d, pi / 4),
            onPanEnd: (_) => _land(),
            child: sized(const _Handle(label: '拖曳縮放、旋轉', child: Icon(CupertinoIcons.arrow_up_left_arrow_down_right, size: 12, color: ink))),
          )),
        ],
      ])),
    );
  }
}

class _Handle extends StatelessWidget {
  static const dot = 28.0;
  final String label;
  final bool delete;
  final Widget child;
  const _Handle({required this.label, required this.child, this.delete = false});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: label,
    child: SizedBox.square(dimension: StickerItem.handle * 2, child: Center(child: Container(
      width: dot, height: dot,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        // Delete is set apart so it isn't mistaken for the others.
        border: Border.all(color: delete ? const Color(0xFFB4483C).withValues(alpha: .6) : outline.withValues(alpha: .5), width: delete ? 1.4 : 1),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: .15), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: child,
    ))),
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
