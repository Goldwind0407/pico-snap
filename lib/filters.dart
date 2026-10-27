import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A 4 × 5 colour matrix (as [ColorFilter.matrix] takes it).
typedef _M = List<double>;

const _M _identity = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];

/// [a] then [b].
_M _then(_M a, _M b) {
  final c = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += b[i * 5 + k] * a[k * 5 + j];
      }
      c[i * 5 + j] = v + (j == 4 ? b[i * 5 + 4] : 0);
    }
  }
  return c;
}

_M _chain(List<_M> steps) => steps.fold(_identity, _then);

/// Saturation: 0 grey, 1 unchanged.
_M _sat(double s) {
  const l = [.2126, .7152, .0722];
  return [
    for (var i = 0; i < 3; i++) ...[for (var k = 0; k < 3; k++) l[k] * (1 - s) + (i == k ? s : 0), 0, 0],
    0, 0, 0, 1, 0,
  ];
}

_M _contrast(double c) => [c, 0, 0, 0, 128 * (1 - c), 0, c, 0, 0, 128 * (1 - c), 0, 0, c, 0, 128 * (1 - c), 0, 0, 0, 1, 0];

_M _bright(double b) => [1, 0, 0, 0, b, 0, 1, 0, 0, b, 0, 0, 1, 0, b, 0, 0, 0, 1, 0];

/// Channel gains and offsets (0–255).
_M _tint(double r, double g, double b, [double or = 0, double og = 0, double ob = 0]) =>
    [r, 0, 0, 0, or, 0, g, 0, 0, og, 0, 0, b, 0, ob, 0, 0, 0, 1, 0];

/// Lift the blacks (matte): black becomes [l], white stays white.
_M _lift(double l) {
  final k = 1 - l / 255;
  return [k, 0, 0, 0, l, 0, k, 0, 0, l, 0, 0, k, 0, l, 0, 0, 0, 1, 0];
}

/// A photo filter: a colour grade plus optional film effects drawn on top.
class PhotoFilter {
  final String id, name;
  final List<double> matrix;
  /// Film grain, 0–1.
  final double grain;
  /// Dark corners, 0–1.
  final double vignette;
  /// Bright centre, like a direct flash.
  final bool flash;
  /// A red-orange light leak from the edge.
  final bool leak;
  /// An orange date stamp in the corner, like a disposable camera.
  final bool date;
  /// Soft white-pink haze, 0–1.
  final double haze;
  const PhotoFilter._(this.id, this.name, this.matrix, {this.grain = 0, this.vignette = 0, this.flash = false, this.leak = false, this.date = false, this.haze = 0});

  bool get isNone => id == 'none';

  ColorFilter get colorFilter => ColorFilter.matrix(matrix);
}

final photoFilters = <PhotoFilter>[
  const PhotoFilter._('none', '原圖', _identity),
  // Teal shadows, orange highlights; strong complementary colour.
  PhotoFilter._('teal_orange', '青橙', _chain([_sat(1.1), _tint(1.15, 1.02, .86, -14, 4, 22), _contrast(1.12)]), vignette: .2),
  // Ink black and charcoal grey, a hint of tea green in the highlights.
  PhotoFilter._('dark_tea', '黑茶', _chain([_sat(.28), _contrast(1.2), _bright(-16), _tint(.96, 1.01, 1, 0, 2, 4)]), grain: .2),
  // Fine, natural warm film with grain.
  PhotoFilter._('warm_film', '暖底片', _chain([_sat(.95), _tint(1.06, 1, .9, 6, 2, -4), _contrast(1.05), _lift(12)]), grain: .5, vignette: .25),
  // Cool, grey, low saturation.
  PhotoFilter._('cool_grey', '冷淡灰', _chain([_sat(.7), _tint(.96, 1, 1.05, -2, 2, 8), _lift(20), _contrast(.95), _bright(4)]), grain: .25),
  // Warm brown, old wood.
  PhotoFilter._('vintage_brown', '復古棕', _chain([_sat(.78), _tint(1.08, 1, .86, 10, 4, -6), _lift(18), _contrast(1.02)]), grain: .3, vignette: .2),
  // Y2K digicam: clear, slightly blue-green.
  PhotoFilter._('y2k_clear', '千禧通透', _chain([_sat(1.12), _tint(.98, 1.03, 1.04, -4, 4, 6), _bright(14), _contrast(1.06)]), grain: .35),
  // Cool blue, crisp, direct flash with dark corners.
  PhotoFilter._('flash_blue', '冷豔閃光', _chain([_sat(1.15), _tint(.92, 1, 1.12), _contrast(1.2), _bright(6)]), vignette: .55, flash: true),
  // Clean, bright, washed of muddy colours.
  PhotoFilter._('picnic', '清透野餐', _chain([_sat(1.18), _bright(16), _contrast(1.04), _tint(1, 1.02, 1.03)])),
  // Soft pink haze.
  PhotoFilter._('romance', '浪漫柔霧', _chain([_sat(.9), _tint(1.06, .98, 1, 10, 0, 6), _contrast(.88), _bright(10)]), haze: .14),
  // 1998 disposable: high contrast, red channel, light leak and date stamp.
  PhotoFilter._('leak', '漏光老照片', _chain([_sat(1.05), _contrast(1.25), _tint(1.12, .96, .9, 4, -2, -8)]), grain: .45, vignette: .35, leak: true, date: true),
  // Modern vintage: matte blacks, muted colour.
  PhotoFilter._('matte', '霧面電影', _chain([_sat(.82), _lift(26), _tint(1.03, 1, .96)]), grain: .2),
];

PhotoFilter filterById(String? id) => photoFilters.firstWhere((f) => f.id == id, orElse: () => photoFilters.first);

/// [child] (a photo) graded with [filter], with its film effects on top.
class FilterLayer extends StatelessWidget {
  final PhotoFilter filter;
  final Widget child;
  const FilterLayer({super.key, required this.filter, required this.child});

  @override
  Widget build(BuildContext context) {
    if (filter.isNone) return child;
    final f = filter;
    final effects = f.grain > 0 || f.vignette > 0 || f.flash || f.leak || f.date || f.haze > 0;
    return Stack(fit: StackFit.passthrough, children: [
      ColorFiltered(colorFilter: f.colorFilter, child: child),
      if (effects) Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: LayoutBuilder(
        builder: (context, c) => Stack(fit: StackFit.expand, children: [
          if (f.haze > 0) ColoredBox(color: const Color(0xFFFFE6EE).withValues(alpha: f.haze)),
          if (f.flash)
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(radius: .7, colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)]))),
          if (f.leak)
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(-1.1, -.4), radius: 1.1,
              colors: [Color(0x99FF6A1A), Color(0x44FF3B2F), Color(0x00FF3B2F)], stops: [0, .35, 1],
            ))),
          if (f.vignette > 0)
            DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              radius: .85, colors: [Colors.transparent, Colors.black.withValues(alpha: f.vignette)], stops: const [.55, 1],
            ))),
          if (f.grain > 0) CustomPaint(painter: _GrainPainter(f.grain)),
          if (f.date) Align(alignment: const Alignment(.88, .86), child: _DateStamp(size: c.biggest.shortestSide * .085)),
        ]),
      )))),
    ]);
  }
}

class _GrainPainter extends CustomPainter {
  final double amount;
  const _GrainPainter(this.amount);

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed: the grain doesn't crawl when the picture repaints.
    final rnd = math.Random(42);
    final n = (size.width * size.height / 22 * amount).round();
    final light = Paint()..color = Colors.white.withValues(alpha: .10 * amount + .04);
    final dark = Paint()..color = Colors.black.withValues(alpha: .12 * amount + .04);
    for (var i = 0; i < n; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(p, .45 + rnd.nextDouble() * .5, i.isEven ? light : dark);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.amount != amount;
}

class _DateStamp extends StatelessWidget {
  final double size;
  const _DateStamp({required this.size});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return Text("'${two(d.year % 100)} ${two(d.month)} ${two(d.day)}", style: TextStyle(
      fontSize: math.max(6, size), letterSpacing: size * .08, color: const Color(0xFFFF8A2B), fontWeight: FontWeight.w800,
      shadows: [Shadow(color: const Color(0xFFFF5A00).withValues(alpha: .8), blurRadius: size * .4)],
    ));
  }
}
