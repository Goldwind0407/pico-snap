import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'color_grade.dart';

/// LUT size: 33³ like the .cube files photo apps ship.
const _lutSize = 33;

/// A photo filter: a colour grade (curves, HSL, shadows / highlights, split
/// toning…) plus film effects drawn on top (grain, vignette, flash, light
/// leak, haze, date stamp).
class PhotoFilter {
  final String id, name;
  final Grade grade;
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
  /// Take the edge off phone sharpening, 0–1.
  final double soften;
  /// Glow around bright areas (film halation), 0–1, in [halationColor].
  final double halation;
  final (double, double, double) halationColor;
  const PhotoFilter._(this.id, this.name, this.grade, {
    this.grain = 0, this.vignette = 0, this.flash = false, this.leak = false, this.date = false, this.haze = 0,
    this.soften = 0, this.halation = 0, this.halationColor = (1, .38, .18),
  });

  bool get isNone => id == 'none';

  static final _luts = <String, Float32List>{};
  static final _matrices = <String, List<double>>{};

  /// The grade as a lookup table (built once).
  Float32List get lut => _luts[id] ??= grade.lut(_lutSize);

  /// The closest colour matrix, for the live camera viewfinder.
  List<double> get matrix => _matrices[id] ??= fitMatrix(lut, _lutSize);

  ColorFilter get previewFilter => ColorFilter.matrix(matrix);
}

const _skin = Hsl(sat: -.12, lum: .12);

final photoFilters = <PhotoFilter>[
  const PhotoFilter._('none', '原圖', Grade.none),
  // Cinematic teal & orange: teal shadows, orange highlights; greens pushed to
  // teal, skin kept clean; highlights held, shadows opened.
  const PhotoFilter._('teal_orange', '青橙', Grade(
    contrast: .25, highlights: -.35, shadows: .3,
    curve: [(0, .04), (.25, .22), (.75, .8), (1, .97)],
    hsl: {Hue.orange: Hsl(sat: -.05, lum: .08), Hue.yellow: Hsl(hue: -10, sat: -.25), Hue.green: Hsl(hue: 45, sat: -.35), Hue.aqua: Hsl(sat: .15), Hue.blue: Hsl(hue: -15, sat: .1, lum: -.1)},
    shadowTone: (-.06, .02, .07), highlightTone: (.06, .02, -.05),
  ), vignette: .18, soften: .3, halation: .35),
  // Dark tea: ink blacks, charcoal greys, a cold tea-green sheen in the
  // highlights, almost no colour; highlights matte instead of white.
  const PhotoFilter._('dark_tea', '黑茶', Grade(
    exposure: -.15, contrast: .3, highlights: -.4, saturation: .3,
    curve: [(0, .06), (.3, .24), (.7, .7), (1, .9)],
    hsl: {Hue.orange: Hsl(sat: .3), Hue.green: Hsl(sat: -.5), Hue.blue: Hsl(sat: -.4)},
    shadowTone: (-.015, .015, .025), highlightTone: (-.01, .03, .015),
  ), grain: .25, soften: .45),
  // Fine warm film: faded blacks, warm mids, blue lifted in the shadows,
  // yellowed greens, soft highlights, grain.
  const PhotoFilter._('warm_film', '暖底片', Grade(
    temp: .3, highlights: -.25, shadows: .15,
    curve: [(0, .06), (.5, .52), (1, .96)],
    red: [(0, .02), (.5, .53), (1, 1)], blue: [(0, .08), (.5, .48), (1, .9)],
    hsl: {Hue.orange: _skin, Hue.green: Hsl(hue: -15, sat: -.25), Hue.blue: Hsl(hue: -20, sat: -.15)},
  ), grain: .5, vignette: .2, soften: .55, halation: .45),
  // Cool, grey, airy: lifted blacks, low saturation, cool shadows.
  const PhotoFilter._('cool_grey', '冷淡灰', Grade(
    temp: -.3, highlights: -.2, shadows: .2, saturation: .72,
    curve: [(0, .12), (.5, .5), (1, .93)],
    hsl: {Hue.orange: Hsl(sat: -.15, lum: .1), Hue.green: Hsl(sat: -.4), Hue.blue: Hsl(hue: -10, sat: -.2)},
    shadowTone: (-.01, 0, .03),
  ), grain: .25, soften: .45),
  // Vintage brown: warm, faded, brown-yellow greens, muted blues.
  const PhotoFilter._('vintage_brown', '復古棕', Grade(
    temp: .45, tint: .1, saturation: .8,
    curve: [(0, .1), (.5, .52), (1, .9)],
    red: [(0, .04), (1, 1)], blue: [(0, .06), (1, .86)],
    hsl: {Hue.green: Hsl(hue: -25, sat: -.4), Hue.blue: Hsl(sat: -.4), Hue.orange: Hsl(lum: .05)},
    highlightTone: (.05, .02, -.04),
  ), grain: .35, vignette: .22, soften: .5, halation: .3),
  // Y2K digicam: bright, clear, cyan-leaning greens and blues, bright skin.
  const PhotoFilter._('y2k_clear', '千禧通透', Grade(
    exposure: .1, temp: -.15, contrast: .15, highlights: -.3, saturation: 1.08,
    curve: [(0, .02), (.5, .56), (1, 1)],
    hsl: {Hue.orange: _skin, Hue.green: Hsl(hue: 20), Hue.aqua: Hsl(sat: .2), Hue.blue: Hsl(hue: -12, sat: .15)},
  ), grain: .3, soften: .2),
  // Cool flash: crisp, cold blues, porcelain skin, direct flash and corners.
  const PhotoFilter._('flash_blue', '冷豔閃光', Grade(
    exposure: 0, temp: -.35, contrast: .3, highlights: -.2,
    curve: [(0, 0), (.25, .2), (.75, .82), (1, 1)],
    hsl: {Hue.orange: Hsl(sat: -.2, lum: .15), Hue.red: Hsl(sat: -.1), Hue.blue: Hsl(hue: -8, sat: .25)},
    shadowTone: (-.03, 0, .06),
  ), vignette: .5, flash: true, grain: .2, soften: .15),
  // Clear picnic: bright and clean; muddy yellows tamed, fresh greens.
  const PhotoFilter._('picnic', '清透野餐', Grade(
    exposure: .12, shadows: .3, highlights: -.35, contrast: .05, saturation: 1.05, vibrance: .15,
    curve: [(0, .03), (.5, .55), (1, 1)],
    hsl: {Hue.orange: Hsl(sat: -.08, lum: .1), Hue.yellow: Hsl(sat: -.15), Hue.green: Hsl(hue: 18, sat: -.1), Hue.blue: Hsl(hue: -10, sat: .1)},
  ), soften: .25),
  // Soft romance: pink haze, low contrast, glowing skin.
  const PhotoFilter._('romance', '浪漫柔霧', Grade(
    temp: .1, tint: .3, exposure: .15,
    curve: [(0, .1), (.5, .55), (1, .95)],
    hsl: {Hue.orange: Hsl(sat: -.1, lum: .12), Hue.magenta: Hsl(sat: .1), Hue.green: Hsl(sat: -.3)},
    highlightTone: (.04, 0, .03),
  ), haze: .12, grain: .15, soften: .5, halation: .25, halationColor: (1, .55, .6)),
  // 1998 disposable: hard contrast, cross-processed channels, red light leak,
  // date stamp.
  const PhotoFilter._('leak', '漏光老照片', Grade(
    temp: .12, contrast: .4, saturation: 1.05,
    red: [(0, .05), (.5, .53), (1, 1)], green: [(0, .02), (.5, .48), (1, .95)], blue: [(0, .1), (.5, .45), (1, .85)],
    hsl: {Hue.orange: Hsl(sat: .05)},
  ), grain: .5, vignette: .35, leak: true, date: true, soften: .45, halation: .55),
  // Modern vintage, matte: no pure black or white, muted colour.
  const PhotoFilter._('matte', '霧面電影', Grade(
    temp: .05, highlights: -.3, shadows: .1, saturation: .85,
    curve: [(0, .14), (.2, .22), (.8, .82), (1, .92)],
    hsl: {Hue.green: Hsl(hue: -15, sat: -.3), Hue.orange: Hsl(sat: -.1, lum: .05), Hue.blue: Hsl(hue: -10, sat: -.2)},
    shadowTone: (-.02, .01, .03), highlightTone: (.03, .02, -.01),
  ), grain: .25, vignette: .15, soften: .5, halation: .3),
  // Night cinema film (tungsten 800-style): teal shadows, warm practical
  // lights blooming red-orange, lifted blacks, heavy grain.
  const PhotoFilter._('night_cine', '夜景電影', Grade(
    temp: -.25, contrast: .25, shadows: .2, highlights: -.25, saturation: .95,
    curve: [(0, .06), (.3, .26), (.75, .8), (1, .96)],
    hsl: {Hue.orange: Hsl(sat: .1, lum: .05), Hue.yellow: Hsl(hue: -12), Hue.green: Hsl(hue: 40, sat: -.3), Hue.blue: Hsl(hue: -12, sat: .1, lum: -.1)},
    shadowTone: (-.04, .01, .06), highlightTone: (.05, .02, -.03),
  ), grain: .55, vignette: .3, soften: .45, halation: .8, halationColor: (1, .32, .14)),
];

PhotoFilter filterById(String? id) => photoFilters.firstWhere((f) => f.id == id, orElse: () => photoFilters.first);

/// [base] graded with [filter]'s full colour grade (its lookup table, on a
/// background thread), at most [maxSide] pixels on the long side. Film effects
/// are drawn separately by [FilterEffects].
@immutable
class FilteredImage extends ImageProvider<FilteredImage> {
  final ImageProvider base;
  final PhotoFilter filter;
  final int maxSide;
  const FilteredImage(this.base, this.filter, {this.maxSide = 2048});

  @override
  Future<FilteredImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(FilteredImage key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final src = await _resolve(base);
    final s = math.min(1.0, maxSide / math.max(src.width, src.height));
    final w = math.max(1, (src.width * s).round()), h = math.max(1, (src.height * s).round());
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawImageRect(
      src, Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    src.dispose();
    final small = await rec.endRecording().toImage(w, h);
    final data = await small.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    small.dispose();
    // Grain is per pixel: a tiny thumbnail gets less so it reads the same.
    final grain = filter.grain * math.min(1.0, math.max(w, h) / 900);
    final graded = await compute(_gradeJob, (
      rgba: data!.buffer.asUint8List(), lut: filter.lut, w: w, h: h,
      soften: filter.soften, halation: filter.halation, color: filter.halationColor, grain: grain,
    ));
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(graded, w, h, ui.PixelFormat.rgba8888, c.complete);
    return ImageInfo(image: await c.future);
  }

  static Future<ui.Image> _resolve(ImageProvider provider) {
    final c = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      c.complete(info.image.clone());
      info.dispose();
    }, onError: (e, st) {
      stream.removeListener(listener);
      c.completeError(e, st);
    });
    stream.addListener(listener);
    return c.future;
  }

  @override
  bool operator ==(Object other) => other is FilteredImage && other.base == base && other.filter.id == filter.id && other.maxSide == maxSide;

  @override
  int get hashCode => Object.hash(base, filter.id, maxSide);
}

Uint8List _gradeJob(({Uint8List rgba, Float32List lut, int w, int h, double soften, double halation, (double, double, double) color, double grain}) a) {
  final out = applyLut(a.rgba, a.lut, _lutSize);
  finishFilm(out, a.rgba, a.w, a.h, soften: a.soften, halation: a.halation, halationColor: a.color, grain: a.grain);
  return out;
}

/// [image] with [filter] applied exactly: the graded photo plus film effects.
ImageProvider filtered(ImageProvider image, PhotoFilter? filter, {int maxSide = 2048}) =>
    filter == null || filter.isNone ? image : FilteredImage(image, filter, maxSide: maxSide);

/// Film effects of [filter] over [child] (which is already graded).
class FilterEffects extends StatelessWidget {
  final PhotoFilter filter;
  final Widget child;
  /// The photo already has grain in its pixels ([FilteredImage]); only live
  /// pictures need it drawn on top.
  final bool grainBaked;
  const FilterEffects({super.key, required this.filter, required this.child, this.grainBaked = true});

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final grain = !grainBaked && f.grain > 0;
    final effects = grain || f.vignette > 0 || f.flash || f.leak || f.date || f.haze > 0;
    if (!effects) return child;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: LayoutBuilder(
        builder: (context, c) => Stack(fit: StackFit.expand, children: [
          if (f.haze > 0) ColoredBox(color: const Color(0xFFFFE6EE).withValues(alpha: f.haze)),
          if (f.flash)
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(radius: .7, colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)]))),
          if (f.leak)
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(-1.1, -.4), radius: 1.1,
              colors: [Color(0x80FF6A1A), Color(0x33FF3B2F), Color(0x00FF3B2F)], stops: [0, .35, 1],
            ))),
          if (f.vignette > 0)
            DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              radius: .85, colors: [Colors.transparent, Colors.black.withValues(alpha: f.vignette)], stops: const [.55, 1],
            ))),
          if (grain) CustomPaint(painter: _GrainPainter(f.grain)),
          if (f.date) Align(alignment: const Alignment(.88, .86), child: _DateStamp(size: c.biggest.shortestSide * .085)),
        ]),
      )))),
    ]);
  }
}

/// A live picture (the camera viewfinder) with [filter] approximated by a
/// colour matrix, plus its film effects.
class FilterLayer extends StatelessWidget {
  final PhotoFilter filter;
  final Widget child;
  const FilterLayer({super.key, required this.filter, required this.child});

  @override
  Widget build(BuildContext context) => filter.isNone
      ? child
      : FilterEffects(filter: filter, grainBaked: false, child: ColorFiltered(colorFilter: filter.previewFilter, child: child));
}

class _GrainPainter extends CustomPainter {
  final double amount;
  const _GrainPainter(this.amount);

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed: the grain doesn't crawl when the picture repaints.
    final rnd = math.Random(42);
    final n = (size.width * size.height / 18 * amount).round();
    final light = Paint()..color = Colors.white.withValues(alpha: .07 * amount + .03);
    final dark = Paint()..color = Colors.black.withValues(alpha: .09 * amount + .03);
    for (var i = 0; i < n; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(p, .35 + rnd.nextDouble() * .45, i.isEven ? light : dark);
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
