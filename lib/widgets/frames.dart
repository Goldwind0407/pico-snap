import 'dart:math';

import 'package:flutter/material.dart';

import '../filters.dart';
import '../models.dart';
import '../theme.dart';

/// How a photo sits in its cell: zoom (1 = just covers the cell) and which
/// part is in view (like [Image.alignment]). Independent of the cell's size,
/// so it survives switching templates.
class PhotoFit {
  final double scale;
  final Alignment align;
  const PhotoFit([this.scale = 1, this.align = Alignment.center]);
}

/// A photo that covers its cell. With [onChanged] set, drag to move it and
/// pinch to zoom; it always keeps the cell covered.
class FittedPhoto extends StatefulWidget {
  final ImageProvider image;
  final PhotoFit fit;
  /// Width / height of the photo; needed to move it, unknown for assets.
  final double? aspect;
  final ValueChanged<PhotoFit>? onChanged;
  final PhotoFilter? filter;
  const FittedPhoto({super.key, required this.image, this.fit = const PhotoFit(), this.aspect, this.onChanged, this.filter});

  @override
  State<FittedPhoto> createState() => _FittedPhotoState();
}

class _FittedPhotoState extends State<FittedPhoto> {
  PhotoFit _start = const PhotoFit();
  Offset _focal = Offset.zero;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final fit = widget.fit;
    Widget photo = ClipRect(child: Transform.scale(
      scale: fit.scale,
      alignment: fit.align,
      child: Image(image: widget.image, fit: BoxFit.cover, alignment: fit.align, gaplessPlayback: true, width: c.maxWidth, height: c.maxHeight),
    ));
    final filter = widget.filter;
    if (filter != null) photo = SizedBox(width: c.maxWidth, height: c.maxHeight, child: FilterLayer(filter: filter, child: photo));
    final onChanged = widget.onChanged;
    final aspect = widget.aspect;
    if (onChanged == null || aspect == null) return photo;
    final cw = c.maxWidth, ch = c.maxHeight;
    // Size of the photo when it just covers the cell.
    final cover = aspect > cw / ch ? Size(ch * aspect, ch) : Size(cw, cw / aspect);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) {
        _start = widget.fit;
        _focal = d.localFocalPoint;
      },
      onScaleUpdate: (d) {
        final k = (_start.scale * d.scale).clamp(1.0, 4.0);
        final delta = d.localFocalPoint - _focal;
        // The photo's left edge is at (cw - w) * (align + 1) / 2, so moving it
        // by delta changes align by -2 * delta / (w - cw).
        double move(double a, double over, double dd) => over <= .5 ? a : (a - 2 * dd / over).clamp(-1.0, 1.0);
        onChanged(PhotoFit(k, Alignment(
          move(_start.align.x, cover.width * k - cw, delta.dx),
          move(_start.align.y, cover.height * k - ch, delta.dy),
        )));
      },
      child: photo,
    );
  });
}

class PhotoSlot extends StatelessWidget {
  final ImageProvider? image;
  final Color color;
  final Widget? placeholder;
  final bool selected;
  final double radius, outlineWidth;
  final VoidCallback? onTap;
  final PhotoFit fit;
  final double? aspect;
  final ValueChanged<PhotoFit>? onFit;
  final PhotoFilter? filter;
  const PhotoSlot({
    super.key, this.image, required this.color, this.placeholder, this.selected = false,
    this.radius = 3, this.outlineWidth = 1.4, this.onTap, this.fit = const PhotoFit(), this.aspect, this.onFit, this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final slot = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(radius),
        border: outlineWidth > 0 ? Border.all(color: outline, width: outlineWidth) : null,
      ),
      foregroundDecoration: selected
        ? BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: coral, width: 3.5))
        : null,
      child: image != null
        ? FittedPhoto(image: image!, fit: fit, aspect: aspect, onChanged: onFit, filter: filter)
        : Center(child: placeholder ?? const SizedBox.shrink()),
    );
    return onTap == null ? slot : GestureDetector(onTap: onTap, child: slot);
  }
}

/// Placeholder shown in an empty photo slot inside the editor.
class AddPhotoHint extends StatelessWidget {
  final double scale;
  const AddPhotoHint({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.add_circle_outline_rounded, size: 26 * scale, color: outline.withValues(alpha: .55)),
    SizedBox(height: 2 * scale),
    Text('tap to add', style: hand(17 * scale, color: outline.withValues(alpha: .6))),
  ]);
}

/// A four-cut photo booth strip drawn at a fixed design size; wrap it in a
/// FittedBox to show it at any size.
class PhotoStrip extends StatelessWidget {
  final StripTemplate template;
  final List<ImageProvider?> photos;
  final Widget? placeholder;
  final String? caption;
  final Widget? captionWidget;
  final int? selected;
  final ValueChanged<int>? onTapCell;
  /// Per-cell framing and photo aspect ratios; [onFit] makes cell [adjusting]
  /// draggable.
  final List<PhotoFit> fits;
  final List<double?> aspects;
  final int? adjusting;
  final void Function(int cell, PhotoFit fit)? onFit;
  final List<PhotoFilter> filters;
  const PhotoStrip({
    super.key, required this.template, this.photos = const [], this.placeholder,
    this.caption, this.captionWidget, this.selected, this.onTapCell,
    this.fits = const [], this.aspects = const [], this.adjusting, this.onFit, this.filters = const [],
  });

  Widget? _photo(int i) {
    if (i >= photos.length || photos[i] == null) return null;
    return FittedPhoto(
      image: photos[i]!,
      fit: i < fits.length ? fits[i] : const PhotoFit(),
      aspect: i < aspects.length ? aspects[i] : null,
      onChanged: adjusting == i && onFit != null ? (f) => onFit!(i, f) : null,
      filter: i < filters.length ? filters[i] : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = template;
    if (t.art != null) return _artStrip(t.art!);
    return SizedBox(
      width: 200, height: 620,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.frame2 == null ? t.frame : null,
            gradient: t.frame2 == null ? null : LinearGradient(colors: [t.frame, t.frame2!], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            border: t.outline ? Border.all(color: outline, width: 1.6) : null,
          ),
          child: CustomPaint(painter: _FramePatternPainter(t.pattern, t.patternColor)),
        )),
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: Column(children: [
            for (var i = 0; i < 4; i++) ...[
              SizedBox(height: 128, width: double.infinity, child: _StripCell(
                template: t,
                photo: _photo(i),
                placeholder: placeholder,
                selected: selected == i,
                onTap: onTapCell == null ? null : () => onTapCell!(i),
              )),
              if (i < 3) const SizedBox(height: 10),
            ],
            Expanded(child: Center(child: captionWidget ?? _footer())),
          ]),
        )),
        if (t.tape)
          const Positioned(right: -26, bottom: 6, child: WashiTape(width: 92, angle: -.65, colors: [Color(0xFFB9C9AE), Color(0xFFF4D98B)])),
        for (final d in t.decos)
          // Unconstrained so bubbles never wrap; centred on d.center.
          Positioned(
            left: d.center.dx, top: d.center.dy,
            child: FractionalTranslation(translation: const Offset(-.5, -.5), child: IgnorePointer(child: Transform.rotate(
              angle: d.angle,
              child: d.bubble ? SpeechBubble(d.content, fontSize: d.size * 1.3) : Transform.flip(flipX: d.flipped, child: StickerVisual(d.content, size: d.size)),
            ))),
          ),
      ]),
    );
  }

  Widget _artStrip(ArtFrame art) {
    final size = template.designSize;
    Rect px(Rect r) => Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width, r.height * size.height);
    return SizedBox.fromSize(size: size, child: Stack(children: [
      for (var i = 0; i < art.cells.length; i++)
        Positioned.fromRect(rect: px(art.cells[i]), child: GestureDetector(
          onTap: onTapCell == null ? null : () => onTapCell!(i),
          child: ColoredBox(color: template.cell, child: SizedBox.expand(child: _photo(i) ?? Center(child: placeholder ?? const SizedBox.shrink()))),
        )),
      // The illustration sits on top so its decorations overlap the photos.
      Positioned.fill(child: IgnorePointer(child: Image.asset(art.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium))),
      if (selected != null && selected! < art.cells.length)
        Positioned.fromRect(rect: px(art.cells[selected!]), child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: coral, width: 3.5)),
        ))),
    ]));
  }

  Widget _footer() {
    final t = template;
    final text = caption ?? t.caption;
    switch (t.footer) {
      case FooterStyle.caption:
        return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: hand(30, color: t.captionColor));
      case FooterStyle.logoDate:
        final now = DateTime.now();
        final date = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.photo_camera_outlined, size: 16, color: t.captionColor),
            const SizedBox(width: 5),
            Text('PICO SNAP', style: TextStyle(fontFamily: 'Nunito', fontSize: 15, letterSpacing: 2.4, color: t.captionColor, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 4),
          Text(text.isEmpty ? date : text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Nunito', fontSize: 9, letterSpacing: 1.6, color: t.captionColor.withValues(alpha: .7), fontWeight: FontWeight.w700)),
        ]);
      case FooterStyle.title:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Nunito', fontSize: 23, height: 1, letterSpacing: 1, color: t.captionColor, fontWeight: FontWeight.w900)),
          if (t.subtitle.isNotEmpty) Text(t.subtitle, style: hand(17, color: t.captionColor.withValues(alpha: .85))),
        ]);
    }
  }
}

const _grayscale = ColorFilter.matrix([
  .2126, .7152, .0722, 0, 0,
  .2126, .7152, .0722, 0, 0,
  .2126, .7152, .0722, 0, 0,
  0, 0, 0, 1, 0,
]);

class _StripCell extends StatelessWidget {
  final StripTemplate template;
  final Widget? photo;
  final Widget? placeholder;
  final bool selected;
  final VoidCallback? onTap;
  const _StripCell({required this.template, this.photo, this.placeholder, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final clipper = CellClipper(template.cellShape);
    Widget content = photo ?? Center(child: placeholder ?? const SizedBox.shrink());
    if (template.mono && photo != null) content = ColorFiltered(colorFilter: _grayscale, child: content);
    final strokeWidth = selected ? 3.5 : (template.outline ? 1.4 : 0.0);
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        foregroundPainter: strokeWidth == 0 ? null : _ClipStrokePainter(clipper, selected ? coral : outline, strokeWidth),
        child: ClipPath(clipper: clipper, child: ColoredBox(color: template.cell, child: SizedBox.expand(child: content))),
      ),
    );
  }
}

class CellClipper extends CustomClipper<Path> {
  final CellShape shape;
  const CellClipper(this.shape);

  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;
    switch (shape) {
      case CellShape.square:
        return Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)));
      case CellShape.rounded:
        return Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
      case CellShape.cloud:
        // A rounded box with a row of puffs along the top edge.
        const puffs = 5;
        final r = size.width / puffs / 2;
        var path = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(0, r * .8, size.width, size.height), const Radius.circular(16)));
        for (var i = 0; i < puffs; i++) {
          path = Path.combine(PathOperation.union, path, Path()..addOval(Rect.fromCircle(center: Offset(r + i * 2 * r, r * 1.05), radius: r * 1.02)));
        }
        return path;
      case CellShape.wavy:
        // Torn-paper style wobbly edge.
        const amp = 2.6, step = 4.0;
        final path = Path()..moveTo(amp, amp);
        double wob(double t) => amp + amp * sin(t * .55);
        for (var x = 0.0; x <= size.width; x += step) {
          path.lineTo(x, wob(x));
        }
        for (var y = 0.0; y <= size.height; y += step) {
          path.lineTo(size.width - wob(y + 3), y);
        }
        for (var x = size.width; x >= 0; x -= step) {
          path.lineTo(x, size.height - wob(x + 7));
        }
        for (var y = size.height; y >= 0; y -= step) {
          path.lineTo(wob(y + 11), y);
        }
        return path..close();
    }
  }

  @override
  bool shouldReclip(CellClipper oldClipper) => oldClipper.shape != shape;
}

class _ClipStrokePainter extends CustomPainter {
  final CellClipper clipper;
  final Color color;
  final double width;
  const _ClipStrokePainter(this.clipper, this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(clipper.getClip(size), Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width);

  @override
  bool shouldRepaint(_ClipStrokePainter old) => old.color != color || old.width != width || old.clipper.shape != clipper.shape;
}

class _FramePatternPainter extends CustomPainter {
  final FramePattern pattern;
  final Color color;
  const _FramePatternPainter(this.pattern, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    switch (pattern) {
      case FramePattern.none:
        return;
      case FramePattern.dots:
        for (var y = 6.0, row = 0; y < size.height; y += 12, row++) {
          for (var x = row.isEven ? 6.0 : 12.0; x < size.width; x += 12) {
            canvas.drawCircle(Offset(x, y), 2.6, paint);
          }
        }
      case FramePattern.paws:
        for (var y = 10.0, row = 0; y < size.height; y += 26, row++) {
          for (var x = row.isEven ? 10.0 : 23.0; x < size.width; x += 26) {
            canvas.save();
            canvas.translate(x, y);
            canvas.rotate((row + x) % 3 * .3 - .3);
            canvas.drawOval(Rect.fromCenter(center: const Offset(0, 2.5), width: 7, height: 6), paint);
            for (final toe in const [Offset(-4, -2.5), Offset(0, -4.5), Offset(4, -2.5)]) {
              canvas.drawCircle(toe, 1.7, paint);
            }
            canvas.restore();
          }
        }
      case FramePattern.confetti:
        // Fixed seed so the confetti doesn't jump around between builds.
        final rnd = Random(7);
        final colors = [color, const Color(0xFFF7D77C), const Color(0xFF8EC5E8), const Color(0xFFB9C9AE)];
        for (var i = 0; i < 70; i++) {
          final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
          final c = Paint()
            ..color = colors[i % colors.length]
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          if (i.isEven) {
            final a = rnd.nextDouble() * pi;
            canvas.drawArc(Rect.fromCircle(center: p, radius: 3.5), a, 2.2, false, c);
          } else {
            canvas.drawCircle(p, 1.6, c..style = PaintingStyle.fill);
          }
        }
      case FramePattern.gingham:
        GinghamPainter(Colors.transparent).paint(canvas, size);
      case FramePattern.stripes:
        for (var x = 0.0; x < size.width; x += 16) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 8, size.height), paint);
        }
    }
  }

  @override
  bool shouldRepaint(_FramePatternPainter old) => old.pattern != pattern || old.color != color;
}

/// A handwritten speech bubble with a little tail.
class SpeechBubble extends StatelessWidget {
  final String text;
  final double fontSize;
  const SpeechBubble(this.text, {super.key, this.fontSize = 20});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * .6, vertical: fontSize * .2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(fontSize), border: Border.all(color: outline, width: 1.3)),
      child: Text(text, style: hand(fontSize)),
    ),
    Transform.translate(offset: Offset(fontSize * .8, -fontSize * .25), child: Transform.rotate(angle: pi / 4, child: Container(
      width: fontSize * .45, height: fontSize * .45,
      decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: outline, width: 1.3), bottom: BorderSide(color: outline, width: 1.3))),
    ))),
  ]);
}

/// A Polaroid print drawn at a fixed design size, like [PhotoStrip].
class PolaroidCard extends StatelessWidget {
  static const width = 160.0, height = 196.0;
  final ImageProvider? image;
  final String caption;
  final Color color;
  final Widget? placeholder;
  final bool selected;
  /// Washi tape colours; null for no tape. [tapeRight] puts it on the top-right corner.
  final List<Color>? tape;
  final bool tapeRight;
  final VoidCallback? onTap;
  const PolaroidCard({
    super.key, this.image, required this.caption, required this.color, this.placeholder,
    this.selected = false, this.tape, this.tapeRight = false, this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width, height: height,
    child: Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: Container(
        padding: const EdgeInsets.fromLTRB(9, 9, 9, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF9),
          border: Border.all(color: outline, width: 1.6),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .14), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(children: [
          SizedBox(height: 142, width: double.infinity, child: PhotoSlot(image: image, color: color, placeholder: placeholder, selected: selected, onTap: onTap)),
          Expanded(child: Center(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: hand(28)))),
        ]),
      )),
      if (tape != null)
        Positioned(top: -4, left: tapeRight ? null : -22, right: tapeRight ? -22 : null,
          child: WashiTape(width: 64, height: 22, angle: tapeRight ? .75 : -.75, colors: tape!)),
    ]),
  );
}

class WashiTape extends StatelessWidget {
  final double width, height, angle;
  final List<Color> colors;
  const WashiTape({super.key, required this.width, this.height = 20, this.angle = 0, this.colors = const [Color(0xFFF59E95), Color(0xFFFFD9D4)]});

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Opacity(opacity: .9, child: ClipPath(
      clipper: const _TornEdgeClipper(),
      child: CustomPaint(size: Size(width, height), painter: _StripePainter(colors)),
    )),
  );
}

class _StripePainter extends CustomPainter {
  final List<Color> colors;
  const _StripePainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors[1]);
    final stripe = Paint()
      ..color = colors[0]
      ..strokeWidth = 5;
    for (var x = -size.height; x < size.width + size.height; x += 12) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), stripe);
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => oldDelegate.colors != colors;
}

class _TornEdgeClipper extends CustomClipper<Path> {
  const _TornEdgeClipper();

  @override
  Path getClip(Size size) {
    const tooth = 3.0;
    final path = Path()..moveTo(0, 0);
    path.lineTo(size.width, 0);
    for (var y = 0.0; y < size.height; y += tooth * 2) {
      path
        ..lineTo(size.width - tooth, y + tooth)
        ..lineTo(size.width, min(y + tooth * 2, size.height));
    }
    path.lineTo(0, size.height);
    for (var y = size.height; y > 0; y -= tooth * 2) {
      path
        ..lineTo(tooth, y - tooth)
        ..lineTo(0, max(y - tooth * 2, 0));
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Hand-drawn four-point sparkle.
class Sparkle extends StatelessWidget {
  final double size;
  final Color? fill;
  const Sparkle({super.key, this.size = 16, this.fill});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SparklePainter(fill));
}

class _SparklePainter extends CustomPainter {
  final Color? fill;
  const _SparklePainter(this.fill);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final path = Path()
      ..moveTo(c.dx, 0)
      ..quadraticBezierTo(c.dx, c.dy, s.width, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, s.height)
      ..quadraticBezierTo(c.dx, c.dy, 0, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, 0)
      ..close();
    if (fill != null) canvas.drawPath(path, Paint()..color = fill!);
    canvas.drawPath(path, Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => oldDelegate.fill != fill;
}

class DoodleHeart extends StatelessWidget {
  final double size;
  final Color color;
  const DoodleHeart({super.key, this.size = 16, this.color = coral});

  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
    Icon(Icons.favorite_rounded, size: size, color: color),
    Icon(Icons.favorite_border_rounded, size: size, color: outline),
  ]);
}

/// An emoji with a white die-cut border, like a real sticker.
class EmojiSticker extends StatelessWidget {
  final String emoji;
  final double size;
  const EmojiSticker(this.emoji, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final r = size * .07;
    return Text(emoji, style: TextStyle(fontSize: size, height: 1.15, shadows: [
      for (var a = 0; a < 12; a++)
        Shadow(color: Colors.white, offset: Offset(cos(a * pi / 6) * r, sin(a * pi / 6) * r)),
      Shadow(color: ink.withValues(alpha: .25), blurRadius: r * 2, offset: Offset(0, r)),
    ]));
  }
}

/// Renders a sticker id: an asset path for hand-drawn stickers, `my:` for
/// stickers cut out of the user's photos, else an emoji.
class StickerVisual extends StatelessWidget {
  final String sticker;
  final double size;
  const StickerVisual(this.sticker, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (sticker.startsWith('assets/')) return Image.asset(sticker, width: size, height: size, filterQuality: FilterQuality.medium);
    if (sticker.startsWith('my:')) {
      final custom = customStickers[sticker];
      // Deleted while still referenced somewhere: draw nothing.
      if (custom == null) return SizedBox.square(dimension: size);
      return Image.memory(custom, width: size, height: size, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    }
    return SizedBox.square(dimension: size, child: FittedBox(child: EmojiSticker(sticker, size: size * .8)));
  }
}

class GinghamPainter extends CustomPainter {
  final Color base;
  final Color? right;
  const GinghamPainter(this.base, [this.right]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    if (right != null) canvas.drawRect(Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height), Paint()..color = right!);
    final stripe = Paint()..color = Colors.white.withValues(alpha: .38);
    final step = size.width / 12, width = step / 2;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, 0, width, size.height), stripe);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, width), stripe);
    }
  }

  @override
  bool shouldRepaint(GinghamPainter oldDelegate) => oldDelegate.base != base || oldDelegate.right != right;
}

/// Soft wavy blob, like a hand-cut sticker backing.
class BlobClipper extends CustomClipper<Path> {
  final double phase;
  const BlobClipper({this.phase = 0});

  @override
  Path getClip(Size size) {
    final c = size.center(Offset.zero);
    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final t = i / 120 * 2 * pi;
      final r = (1 + .045 * sin(5 * t + phase) + .025 * sin(3 * t + 1 + phase)) / 1.07;
      final p = Offset(c.dx + cos(t) * size.width / 2 * r, c.dy + sin(t) * size.height / 2 * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldReclip(BlobClipper oldClipper) => oldClipper.phase != phase;
}
