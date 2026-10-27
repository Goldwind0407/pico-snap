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
