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

final photoFilters = <PhotoFilter>[
  const PhotoFilter._('none', '原圖', Grade.none),
  // Japanese Fujifilm Pro 400H / Aqua: airy cyan skies, emerald-mint foliage,
  // clean luminous skin, cool-green shadows and warm highlights.
  const PhotoFilter._('fuji_clear', '日系富士', Grade(
    exposure: .14, temp: -.14, tint: -.08, shadows: .32, highlights: -.28, contrast: .08, vibrance: .22,
    curve: [(0, .07), (.25, .28), (.75, .82), (1, .98)],
    green: [(0, .04), (.5, .53), (1, .98)], blue: [(0, .06), (.5, .54), (1, 1)],
    hsl: {Hue.orange: Hsl(sat: -.16, lum: .2), Hue.yellow: Hsl(hue: -12, sat: -.22, lum: .1), Hue.green: Hsl(hue: 28, sat: -.12, lum: .08), Hue.aqua: Hsl(hue: -8, sat: .28, lum: .06), Hue.blue: Hsl(hue: -16, sat: .2, lum: .05)},
    shadowTone: (-.04, .03, .05), highlightTone: (.04, .03, -.02),
  ), grain: .18, soften: .3, halation: .25, halationColor: (.85, .96, 1)),
  // Early-2000s Y2K CCD digicam: punchy direct flash, blooming highlights,
  // cool cyan-lilac cast, nostalgic date stamp.
  const PhotoFilter._('ccd_dream', '千禧 CCD', Grade(
    exposure: .1, temp: -.18, tint: .22, contrast: .26, highlights: -.15, shadows: -.05, saturation: 1.12,
    curve: [(0, .02), (.25, .22), (.72, .84), (1, 1)],
    blue: [(0, .06), (.5, .55), (1, 1)],
    hsl: {Hue.orange: Hsl(sat: -.2, lum: .22), Hue.red: Hsl(sat: .1, lum: .1), Hue.green: Hsl(hue: 24, sat: .1), Hue.blue: Hsl(hue: -10, sat: .25), Hue.purple: Hsl(sat: .2)},
    shadowTone: (-.02, -.01, .06), highlightTone: (.04, .01, .06),
  ), flash: true, date: true, vignette: .32, grain: .28, soften: .45, halation: .6, halationColor: (.9, .78, 1)),
  // Cinematic teal & orange: deep teal shadows, golden-orange highlights;
  // foliage pushed toward cyan-teal, skin kept clean and dimensional.
  const PhotoFilter._('teal_orange', '青橙', Grade(
    contrast: .32, highlights: -.35, shadows: .28, saturation: 1.08,
    curve: [(0, .04), (.25, .21), (.75, .82), (1, .98)],
    hsl: {Hue.orange: Hsl(sat: .12, lum: .1), Hue.yellow: Hsl(hue: -18, sat: -.25), Hue.green: Hsl(hue: 55, sat: -.35), Hue.aqua: Hsl(sat: .28), Hue.blue: Hsl(hue: -18, sat: .22, lum: -.12)},
    shadowTone: (-.1, .03, .12), midTone: (-.02, .01, .03), highlightTone: (.11, .04, -.09),
  ), vignette: .24, soften: .3, halation: .45),
  // Dark tea: ink blacks, charcoal greys, a cold tea-green sheen in the
  // midtones and highlights, almost monochrome editorial mood.
  const PhotoFilter._('dark_tea', '黑茶', Grade(
    exposure: -.16, contrast: .36, highlights: -.42, saturation: .24,
    curve: [(0, .06), (.3, .22), (.7, .68), (1, .88)],
    hsl: {Hue.orange: Hsl(sat: .35, lum: .08), Hue.green: Hsl(sat: -.6), Hue.blue: Hsl(sat: -.5)},
    shadowTone: (-.025, .02, .035), midTone: (-.015, .025, .01), highlightTone: (-.015, .04, .02),
  ), grain: .32, vignette: .22, soften: .45),
  // Kodak Gold warm film: faded matte blacks, golden-honey midtones, lifted
  // warm-blue shadows, nostalgic halation and grain.
  const PhotoFilter._('warm_film', '暖底片', Grade(
    temp: .42, tint: .06, highlights: -.25, shadows: .2, saturation: 1.06,
    curve: [(0, .07), (.5, .54), (1, .96)],
    red: [(0, .05), (.5, .56), (1, 1)], green: [(0, .05), (.5, .52), (1, .96)], blue: [(0, .09), (.5, .45), (1, .86)],
    hsl: {Hue.orange: Hsl(sat: -.08, lum: .14), Hue.yellow: Hsl(hue: -8, sat: .12), Hue.green: Hsl(hue: -22, sat: -.28), Hue.blue: Hsl(hue: -22, sat: -.18)},
    shadowTone: (.02, .01, -.02), midTone: (.04, .02, -.03), highlightTone: (.06, .03, -.05),
  ), grain: .48, vignette: .24, soften: .55, halation: .5),
  // Nordic cool grey: lifted slate blacks, low saturation, crisp icy-blue cast.
  const PhotoFilter._('cool_grey', '冷淡灰', Grade(
    temp: -.38, tint: -.04, highlights: -.22, shadows: .24, saturation: .62,
    curve: [(0, .13), (.5, .51), (1, .92)],
    hsl: {Hue.orange: Hsl(sat: -.18, lum: .16), Hue.yellow: Hsl(sat: -.45), Hue.green: Hsl(hue: 20, sat: -.5), Hue.blue: Hsl(hue: -12, sat: -.15)},
    shadowTone: (-.03, .01, .06), midTone: (-.02, 0, .03), highlightTone: (-.02, .01, .04),
  ), grain: .25, soften: .45),
  // Direct cool flash: high-contrast sapphire shadows, porcelain-white skin,
  // strong central flash and dark party corners.
  const PhotoFilter._('flash_blue', '冷豔閃光', Grade(
    exposure: .06, temp: -.42, contrast: .35, highlights: -.18,
    curve: [(0, 0), (.25, .19), (.75, .84), (1, 1)],
    hsl: {Hue.orange: Hsl(sat: -.28, lum: .24), Hue.red: Hsl(sat: -.15, lum: .12), Hue.yellow: Hsl(sat: -.35, lum: .15), Hue.blue: Hsl(hue: -10, sat: .32)},
    shadowTone: (-.05, 0, .09), highlightTone: (-.02, .02, .05),
  ), vignette: .55, flash: true, grain: .22, soften: .18),
  // Sunny spring picnic: pure neutral balance on greys, vibrant emerald-mint
  // greens, azure skies, and radiant non-yellowed skin.
  const PhotoFilter._('picnic', '清透野餐', Grade(
    exposure: .14, shadows: .32, highlights: -.32, contrast: .08, saturation: 1.04, vibrance: .2,
    curve: [(0, .03), (.5, .56), (1, 1)],
    hsl: {Hue.orange: Hsl(sat: -.18, lum: .18), Hue.yellow: Hsl(hue: 10, sat: -.22, lum: .12), Hue.green: Hsl(hue: 24, sat: .12, lum: .06), Hue.aqua: Hsl(sat: .2), Hue.blue: Hsl(hue: -12, sat: .18)},
  ), soften: .25),
  // Soft romance: dreamy pink-lilac haze, low contrast, glowing rose skin.
  const PhotoFilter._('romance', '浪漫柔霧', Grade(
    temp: .14, tint: .42, exposure: .16, contrast: -.06,
    curve: [(0, .11), (.5, .56), (1, .96)],
    hsl: {Hue.orange: Hsl(sat: -.14, lum: .18), Hue.magenta: Hsl(sat: .2, lum: .08), Hue.purple: Hsl(sat: .18), Hue.green: Hsl(hue: -15, sat: -.4)},
    shadowTone: (.03, -.02, .05), midTone: (.04, -.01, .03), highlightTone: (.06, 0, .05),
  ), haze: .16, grain: .15, soften: .58, halation: .42, halationColor: (1, .52, .68)),
  // 1998 disposable: hard contrast, cross-processed channels, warm-red film
  // burn light leak, retro date stamp.
  const PhotoFilter._('leak', '漏光老照片', Grade(
    temp: .18, contrast: .42, saturation: 1.1,
    red: [(0, .06), (.5, .56), (1, 1)], green: [(0, .02), (.5, .49), (1, .94)], blue: [(0, .12), (.5, .44), (1, .82)],
    hsl: {Hue.orange: Hsl(sat: .08, lum: .08), Hue.green: Hsl(hue: 18, sat: -.15)},
    shadowTone: (-.02, .01, .05), highlightTone: (.06, .02, -.05),
  ), grain: .52, vignette: .38, leak: true, date: true, soften: .45, halation: .6),
  // Modern vintage matte: velvety lifted blacks, pulled-down parchment
  // highlights, muted cinema palette.
  const PhotoFilter._('matte', '霧面電影', Grade(
    temp: .08, highlights: -.32, shadows: .15, saturation: .78,
    curve: [(0, .15), (.22, .24), (.78, .8), (1, .9)],
    hsl: {Hue.green: Hsl(hue: -20, sat: -.38), Hue.orange: Hsl(sat: -.1, lum: .08), Hue.blue: Hsl(hue: -12, sat: -.28)},
    shadowTone: (-.03, .015, .04), midTone: (.01, .01, -.01), highlightTone: (.04, .03, -.02),
  ), grain: .28, vignette: .2, soften: .5, halation: .3),
  // Classic photo-booth B&W silver gelatin film (Ilford HP5 / Tri-X): rich
  // blacks, silky silver highlights, flattering panchromatic skin luminance.
  const PhotoFilter._('bw_film', '銀鹽黑白', Grade(
    exposure: .06, contrast: .38, shadows: .1, highlights: -.2, saturation: 0,
    curve: [(0, .05), (.22, .18), (.76, .84), (1, .97)],
    hsl: {Hue.red: Hsl(lum: .18), Hue.orange: Hsl(lum: .24), Hue.yellow: Hsl(lum: .15), Hue.green: Hsl(lum: -.12), Hue.blue: Hsl(lum: -.2)},
    shadowTone: (.01, .01, .015), highlightTone: (.015, .015, .01),
  ), grain: .42, vignette: .26, soften: .3, halation: .3, halationColor: (1, 1, .95)),
  // Night cinema film (CineStill 800T / Wong Kar-wai): emerald-teal shadows,
  // warm tungsten highlights blooming neon red-orange, heavy grain.
  const PhotoFilter._('night_cine', '夜景電影', Grade(
    temp: -.28, tint: -.08, contrast: .3, shadows: .22, highlights: -.25, saturation: .96,
    curve: [(0, .06), (.28, .24), (.75, .82), (1, .96)],
    hsl: {Hue.orange: Hsl(sat: .16, lum: .08), Hue.yellow: Hsl(hue: -15, sat: .1), Hue.green: Hsl(hue: 45, sat: -.25), Hue.aqua: Hsl(sat: .25), Hue.blue: Hsl(hue: -14, sat: .18, lum: -.12)},
    shadowTone: (-.06, .03, .08), midTone: (-.02, .02, .01), highlightTone: (.07, .03, -.04),
  ), grain: .55, vignette: .34, soften: .45, halation: .85, halationColor: (1, .3, .12)),
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
          if (f.haze > 0)
            DecoratedBox(decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -.2),
                radius: 1.05,
                colors: [
                  const Color(0xFFFFF0F6).withValues(alpha: (f.haze * 1.25).clamp(0.0, 1.0)),
                  const Color(0xFFFFE0EC).withValues(alpha: f.haze * .85),
                ],
              ),
            )),
          if (f.flash)
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              radius: .78,
              colors: [Color(0x42FFFFFF), Color(0x18EAF2FF), Color(0x00FFFFFF)],
              stops: [0, .48, 1],
            ))),
          if (f.leak) ...[
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(-1.05, -.35), radius: 1.15,
              colors: [Color(0x96FF5E14), Color(0x48FF2A2A), Color(0x00FF2A2A)], stops: [0, .42, 1],
            ))),
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(1.1, .75), radius: .85,
              colors: [Color(0x58FFB82E), Color(0x1CFF6A1A), Color(0x00FF6A1A)], stops: [0, .45, 1],
            ))),
          ],
          if (f.vignette > 0)
            DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              radius: .85, colors: [Colors.transparent, Colors.black.withValues(alpha: f.vignette)], stops: const [.52, 1],
            ))),
          if (grain) CustomPaint(painter: _GrainPainter(f.grain)),
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
