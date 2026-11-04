import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const stickerPeelDuration = Duration(milliseconds: 760);
const stickerLandDuration = Duration(milliseconds: 620);

/// A diagonal cylindrical fold, rather than a rigid transform of the image.
/// The attached face stays still. Narrow bands wrap around the cylinder and
/// turn into the blank adhesive back when their normal faces away from us.
class StickerLift extends StatelessWidget {
  final double amount;
  final Widget child;
  const StickerLift({super.key, required this.amount, required this.child});

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return child;
    final a = amount.clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.isEmpty) return child;
      const n = Offset(.7071067811865476, -.7071067811865476);
      final reach = (size.width + size.height) / math.sqrt2;
      final radius = size.shortestSide * .14;
      final crease = size.width / math.sqrt2 - reach * a * 1.04;
      final extent = size.longestSide * 4;

      Matrix4 projection(double slope, double intercept) => Matrix4.identity()
        ..setEntry(0, 0, 1 + (slope - 1) * n.dx * n.dx)
        ..setEntry(0, 1, (slope - 1) * n.dx * n.dy)
        ..setEntry(1, 0, (slope - 1) * n.dx * n.dy)
        ..setEntry(1, 1, 1 + (slope - 1) * n.dy * n.dy)
        ..setEntry(0, 3, n.dx * intercept)
        ..setEntry(1, 3, n.dy * intercept);

      Widget band(double lo, double hi, Matrix4 transform, Widget face) => Positioned.fill(
        child: Transform(transform: transform, transformHitTests: false,
          child: ClipPath(clipBehavior: Clip.hardEdge, clipper: _PaperBand(lo, hi), child: face)),
      );
      final tailStart = crease + math.pi * radius;
      final tailTransform = projection(-1, 2 * crease + math.pi * radius);
      final departure = Curves.easeIn.transform(((a - .82) / .18).clamp(0.0, 1.0));
      final folded = Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < 12; i++)
          _arcBand(i, 24, crease, radius, projection, band),
        band(tailStart, extent, tailTransform,
          ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFF1EBDD), BlendMode.srcIn), child: child)),
        for (var i = 23; i >= 12; i--)
          _arcBand(i, 24, crease, radius, projection, band),
      ]);
      return Transform.translate(
        offset: Offset(-size.width * .1 * departure, -size.height * .32 * departure),
        child: ExcludeSemantics(child: Stack(clipBehavior: Clip.none, children: [
          band(-extent, crease, Matrix4.identity(), child),
          // Cast the deformed silhouette, not an undeformed image reflected
          // about the hinge (which would produce a large triangular shadow).
          Positioned.fill(child: Transform.translate(offset: Offset(radius * .12, radius * .3),
            child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: radius * .25, sigmaY: radius * .25),
              child: ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x48000000), BlendMode.srcIn), child: folded)))),
          Positioned.fill(child: folded),
        ])),
      );
    });
  }

  Widget _arcBand(int index, int count, double crease, double radius,
      Matrix4 Function(double, double) projection,
      Widget Function(double, double, Matrix4, Widget) band) {
    final angle = (index + .5) * math.pi / count;
    final u = crease + radius * angle;
    final slope = math.cos(angle);
    final intercept = crease + radius * math.sin(angle) - slope * u;
    final back = angle > math.pi / 2;
    final face = back
      ? ColorFiltered(
          colorFilter: ColorFilter.mode(Color.lerp(const Color(0xFFF1EBDD), const Color(0xFFB5AA97), math.sin(angle) * .55)!, BlendMode.srcIn),
          child: child)
      : ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: math.sin(angle) * .35), BlendMode.srcATop),
          child: child);
    // Tiny overlap prevents hairline cracks between adjacent projected bands.
    return band(crease + radius * index * math.pi / count - .35,
      crease + radius * (index + 1) * math.pi / count + .35,
      projection(slope, intercept), face);
  }
}

class _PaperBand extends CustomClipper<Path> {
  final double lo, hi;
  const _PaperBand(this.lo, this.hi);

  @override
  Path getClip(Size size) {
    final span = size.longestSide * 4;
    Offset point(double u, double v) => Offset((u + v) / math.sqrt2, (v - u) / math.sqrt2);
    return Path()..addPolygon([point(lo, -span), point(hi, -span), point(hi, span), point(lo, span)], true);
  }

  @override
  bool shouldReclip(_PaperBand old) => lo != old.lo || hi != old.hi;
}

/// Commit after peeling so the destination's landing follows the lift.
class PeelableSticker extends StatefulWidget {
  final Widget child;
  final VoidCallback onPick;
  const PeelableSticker({super.key, required this.child, required this.onPick});

  @override
  State<PeelableSticker> createState() => _PeelableStickerState();
}

class _PeelableStickerState extends State<PeelableSticker> with SingleTickerProviderStateMixin {
  late final _lift = AnimationController(vsync: this, duration: stickerPeelDuration);
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    _busy = true;
    HapticFeedback.selectionClick();
    try {
      if (!MediaQuery.disableAnimationsOf(context)) await _lift.forward(from: 0).orCancel;
      if (mounted) widget.onPick();
    } on TickerCanceled {
      // Closing the picker cancels the pending selection.
    } finally {
      if (mounted) _lift.reset();
      _busy = false;
    }
  }

  @override
  void dispose() {
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _pick,
    child: AnimatedBuilder(
      animation: _lift,
      child: widget.child,
      builder: (context, child) {
        final t = _lift.value;
        return Opacity(
          opacity: 1 - Curves.easeIn.transform(((t - .92) / .08).clamp(0.0, 1.0)),
          child: StickerLift(amount: Curves.easeInOutSine.transform(t), child: child!),
        );
      },
    ),
  );
}

/// Roll the adhesive face down from bottom-left to top-right. No bouncing:
/// once a part has touched the canvas, it stays attached.
class StickerLanding extends StatelessWidget {
  final double progress;
  final Widget child;
  const StickerLanding({super.key, required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    final lift = .84 * (1 - Curves.easeInOutSine.transform(progress.clamp(0.0, 1.0)));
    return StickerLift(amount: lift, child: child);
  }
}
