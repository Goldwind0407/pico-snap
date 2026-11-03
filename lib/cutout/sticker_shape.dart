import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// How the sticker is cut: along the subject's outline, or as a shape.
enum StickerShape {
  contour('輪廓', Icons.gesture_rounded),
  square('方形', Icons.crop_square_rounded),
  circle('圓形', Icons.circle_outlined),
  star('星形', Icons.star_outline_rounded),
  heart('愛心', Icons.favorite_border_rounded);

  final String label;
  final IconData icon;
  const StickerShape(this.label, this.icon);

  /// The shape filling a [size] square (not for [contour]).
  Path path(double size) {
    final s = size;
    switch (this) {
      case StickerShape.contour:
      case StickerShape.square:
        return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * .12)));
      case StickerShape.circle:
        return Path()..addOval(Rect.fromLTWH(0, 0, s, s));
      case StickerShape.star:
        final p = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? s * .5 : s * .235;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = Offset(s / 2 + r * math.cos(a), s * .53 + r * math.sin(a));
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        return p..close();
      case StickerShape.heart:
        return Path()
          ..moveTo(s * .5, s * .92)
          ..cubicTo(s * .1, s * .66, -s * .02, s * .38, s * .14, s * .18)
          ..cubicTo(s * .28, 0, s * .46, s * .06, s * .5, s * .22)
          ..cubicTo(s * .54, s * .06, s * .72, 0, s * .86, s * .18)
          ..cubicTo(s * 1.02, s * .38, s * .9, s * .66, s * .5, s * .92)
          ..close();
    }
  }
}

/// Where the photo sits inside a shape frame: zoom (1 = just covers the
/// frame) and the photo centre's offset from the frame centre, as a fraction
/// of the frame's side.
class ShapeFit {
  final double zoom;
  final Offset offset;
  const ShapeFit([this.zoom = 1, this.offset = Offset.zero]);

  /// The photo's rect inside a frame of [side], for a photo of [aspect].
  Rect rect(double side, double aspect) {
    final cover = aspect >= 1 ? Size(side * aspect, side) : Size(side, side / aspect);
    final w = cover.width * zoom, h = cover.height * zoom;
    return Rect.fromCenter(center: Offset(side / 2 + offset.dx * side, side / 2 + offset.dy * side), width: w, height: h);
  }

  /// Kept so the photo always covers the frame.
  ShapeFit clamped(double aspect) {
    final r = rect(1, aspect);
    final mx = math.max(0.0, (r.width - 1) / 2), my = math.max(0.0, (r.height - 1) / 2);
    return ShapeFit(zoom, Offset(offset.dx.clamp(-mx, mx), offset.dy.clamp(-my, my)));
  }
}

/// The photo cut to [shape] in a [size] square: straight RGBA and a mask, ready
/// for the white border.
Future<({Uint8List rgba, Uint8List mask, int w, int h})> renderShape(ui.Image photo, StickerShape shape, ShapeFit fit, int size) async {
  final s = size.toDouble();
  final src = Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble());
  final dst = fit.rect(s, photo.width / photo.height);
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawImageRect(photo, src, dst, Paint()..filterQuality = FilterQuality.high);
  final img = await rec.endRecording().toImage(size, size);
  final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  img.dispose();
  final mrec = ui.PictureRecorder();
  ui.Canvas(mrec).drawPath(shape.path(s), Paint()..color = const Color(0xFFFFFFFF)..isAntiAlias = true);
  final mimg = await mrec.endRecording().toImage(size, size);
  final m = (await mimg.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  mimg.dispose();
  final mask = Uint8List(size * size);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = m[i * 4 + 3];
  }
  return (rgba: rgba, mask: mask, w: size, h: size);
}

/// Bilinear resize of a 0–255 mask.
Uint8List resizeMask(Uint8List m, int w, int h, int tw, int th) {
  if (w == tw && h == th) return m;
  final out = Uint8List(tw * th);
  for (var y = 0; y < th; y++) {
    final fy = ((y + .5) * h / th - .5).clamp(0.0, h - 1.0);
    final y0 = fy.floor(), y1 = math.min(h - 1, y0 + 1);
    final ty = fy - y0;
    for (var x = 0; x < tw; x++) {
      final fx = ((x + .5) * w / tw - .5).clamp(0.0, w - 1.0);
      final x0 = fx.floor(), x1 = math.min(w - 1, x0 + 1);
      final tx = fx - x0;
      final top = m[y0 * w + x0] * (1 - tx) + m[y0 * w + x1] * tx;
      final bot = m[y1 * w + x0] * (1 - tx) + m[y1 * w + x1] * tx;
      out[y * tw + x] = (top * (1 - ty) + bot * ty).round();
    }
  }
  return out;
}

/// What the sticker is printed on: plain, or the shiny finishes of real
/// sticker sheets. Only the picture changes; the white border stays white.
enum StickerFinish {
  matte('霧面', Icons.crop_square_rounded),
  glitter('亮片', Icons.auto_awesome_rounded),
  holo('雷射', Icons.blur_on_rounded),
  gem('寶石', Icons.diamond_outlined);

  final String label;
  final IconData icon;
  const StickerFinish(this.label, this.icon);
}

/// A fixed pseudo-random number in 0–1 for grain cell ([x], [y]).
double _hash(int x, int y) {
  final v = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// The picture's colour [r], [g], [b] (0–1) at ([x], [y]) of a [w] × [h]
/// sticker with [finish]. [inside] is how far the pixel is inside the
/// picture's edge, in pixels (for the gem's rounded rim).
(double, double, double) applyFinish(StickerFinish finish, double r, double g, double b, int x, int y, int w, int h, double inside) {
  if (finish == StickerFinish.matte) return (r, g, b);
  final side = math.max(w, h);
  // Glitter grains a few pixels across, whatever the sticker's size.
  final cell = math.max(1, (side / 260).round());
  final cx = x ~/ cell, cy = y ~/ cell;
  final n1 = _hash(cx, cy), n2 = _hash(cx + 917, cy + 431);
  final l = .2126 * r + .7152 * g + .0722 * b;
  double mix(double a, double b, double t) => a + (b - a) * t;
  switch (finish) {
    case StickerFinish.matte:
      return (r, g, b);
    case StickerFinish.glitter:
      // Every grain catches the light a little differently; a few sparkle.
      // Gentle enough that faces and lines stay readable.
      final k = .86 + .3 * n1;
      double c(double v) => ((l + (v - l) * 1.18) * k).clamp(0.0, 1.0);
      var (cr, cg, cb) = (c(r), c(g), c(b));
      final spark = n2 > .985 ? .75 : n2 > .96 ? .3 : 0.0;
      return (mix(cr, 1, spark), mix(cg, 1, spark), mix(cb, 1, spark));
    case StickerFinish.holo:
      // A rainbow sheen sweeping across, over the picture rather than
      // instead of it, broken into fine grains.
      final hue = ((x * .7 + y) / (w * .7 + h) * 1.4 + n1 * .08) % 1.0;
      final (hr, hg, hb) = _rainbow(hue);
      final k = .9 + .2 * n1;
      // Strongest in the mid tones, where foil shows through ink.
      final sheen = .32 * (1 - (l - .55).abs() * 1.2).clamp(.35, 1.0);
      double c(double v, double h) => (mix(v, .35 + .65 * h, sheen) * k).clamp(0.0, 1.0);
      var (cr, cg, cb) = (c(r, hr), c(g, hg), c(b, hb));
      final spark = n2 > .985 ? .7 : 0.0;
      return (mix(cr, 1, spark), mix(cg, 1, spark), mix(cb, 1, spark));
    case StickerFinish.gem:
      // Rich colour, a darker rim where the surface curves away, a bright
      // band of gloss across the top and a glint on the edge below: a domed
      // resin sticker.
      final rim = (inside / (side * .07)).clamp(0.0, 1.0);
      final shade = .6 + .4 * math.sqrt(rim);
      final fy = y / h;
      final band = (1 - ((fy - .22) / .14).abs()).clamp(0.0, 1.0) * rim;
      final glint = (1 - ((fy - .86) / .05).abs()).clamp(0.0, 1.0) * (1 - rim) * .5;
      final gloss = math.max(band * band * .55, glint);
      double c(double v) => mix(((l + (v - l) * 1.4) * shade).clamp(0.0, 1.0), 1, gloss);
      return (c(r), c(g), c(b));
  }
}

/// A soft rainbow for hue [h] (0–1).
(double, double, double) _rainbow(double h) {
  double ch(double o) => .5 + .5 * math.cos(2 * math.pi * (h + o));
  return (ch(0), ch(-1 / 3), ch(-2 / 3));
}
