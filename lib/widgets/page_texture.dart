import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A look over the whole 拍立得拼貼 page (photos, paper, stickers and all),
/// like it was shot on film or printed long ago.
enum PageTexture {
  none('無'),
  grain('底片顆粒'),
  warm('暖陽'),
  leak('漏光'),
  faded('復古褪色'),
  dust('灰塵刮痕'),
  paper('紙張');

  final String label;
  const PageTexture(this.label);
}

/// The page's colours under [texture] at [strength] (0–1): null when it
/// leaves them alone.
List<double>? textureMatrix(PageTexture texture, double strength) {
  final s = strength.clamp(0.0, 1.0);
  switch (texture) {
    case PageTexture.warm:
      return [
        1 + .08 * s, 0, 0, 0, 12 * s,
        0, 1 + .02 * s, 0, 0, 5 * s,
        0, 0, 1 - .1 * s, 0, -6 * s,
        0, 0, 0, 1, 0,
      ];
    case PageTexture.faded:
    case PageTexture.grain:
      // Less colour and contrast, blacks lifted (a little for grain).
      final k = texture == PageTexture.faded ? s : s * .35;
      final sat = 1 - .32 * k, contrast = 1 - .2 * k, lift = 22 * k;
      const lum = [.2126, .7152, .0722];
      List<double> row(int i, double tint) => [
        for (var j = 0; j < 3; j++) contrast * (lum[j] * (1 - sat) + (i == j ? sat : 0)),
        0, 128 * (1 - contrast) + lift + tint,
      ];
      return [...row(0, 6 * k), ...row(1, 2 * k), ...row(2, -4 * k), 0, 0, 0, 1, 0];
    case PageTexture.none:
    case PageTexture.leak:
    case PageTexture.dust:
    case PageTexture.paper:
      return null;
  }
}

/// Puts [texture] on [child]: its colours changed, and grain, light or
/// marks laid over it. Its size decides how fine the grain is, so a saved
/// picture looks like the screen.
class TexturedPage extends StatelessWidget {
  final PageTexture texture;
  final double strength;
  final Widget child;
  const TexturedPage({super.key, required this.texture, required this.strength, required this.child});

  @override
  Widget build(BuildContext context) {
    if (texture == PageTexture.none || strength <= 0) return child;
    final matrix = textureMatrix(texture, strength);
    return Stack(fit: StackFit.passthrough, children: [
      matrix == null ? child : ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child),
      Positioned.fill(child: IgnorePointer(child: _TextureLayer(texture: texture, strength: strength))),
    ]);
  }
}

class _TextureLayer extends StatefulWidget {
  final PageTexture texture;
  final double strength;
  const _TextureLayer({required this.texture, required this.strength});

  @override
  State<_TextureLayer> createState() => _TextureLayerState();
}

class _TextureLayerState extends State<_TextureLayer> {
  /// Grey noise, made once for every page.
  static final Future<ui.Image> _noise = _makeNoise();
  static ui.Image? _ready;

  static Future<ui.Image> _makeNoise() {
    const side = 256;
    final random = Random(11);
    final pixels = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i++) {
      // Mostly mid grey, which leaves a picture alone under overlay.
      final v = (128 + (random.nextDouble() + random.nextDouble() - 1) * 120).round().clamp(0, 255);
      pixels[i * 4] = v;
      pixels[i * 4 + 1] = v;
      pixels[i * 4 + 2] = v;
      pixels[i * 4 + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, side, side, ui.PixelFormat.rgba8888, done.complete);
    return done.future.then((image) => _ready = image);
  }

  @override
  void initState() {
    super.initState();
    if (_ready == null) _noise.then((_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _TexturePainter(widget.texture, widget.strength, _ready));
}

class _TexturePainter extends CustomPainter {
  final PageTexture texture;
  final double strength;
  final ui.Image? noise;
  const _TexturePainter(this.texture, this.strength, this.noise);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final s = strength.clamp(0.0, 1.0);
    canvas.clipRect(rect);
    void grain(double amount) {
      final n = noise;
      if (n == null || amount <= 0) return;
      // About 700 grains across the page, however big it is drawn.
      final k = size.width / 900;
      canvas.drawRect(rect, Paint()
        ..shader = ImageShader(n, TileMode.repeated, TileMode.repeated, Matrix4.diagonal3Values(k, k, 1).storage)
        ..color = Colors.black.withValues(alpha: amount)
        ..blendMode = BlendMode.overlay);
    }
    void vignette(double amount) => canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(radius: .85, colors: [Colors.transparent, Colors.black.withValues(alpha: amount)], stops: const [.55, 1]).createShader(rect));

    switch (texture) {
      case PageTexture.none:
        break;
      case PageTexture.grain:
        grain(.4 * s);
        vignette(.12 * s);
      case PageTexture.warm:
        canvas.drawRect(rect, Paint()
          ..shader = RadialGradient(center: const Alignment(.6, -.7), radius: 1.1,
            colors: [const Color(0xFFFFC27A).withValues(alpha: .28 * s), const Color(0x00FFC27A)]).createShader(rect)
          ..blendMode = BlendMode.screen);
        grain(.2 * s);
        vignette(.18 * s);
      case PageTexture.leak:
        // Tinted over, not screened: a leak shows on white paper too.
        void glow(Alignment at, double radius, Color color) => canvas.drawRect(rect, Paint()
          ..shader = RadialGradient(center: at, radius: radius, colors: [color.withValues(alpha: .7 * s), color.withValues(alpha: .25 * s), color.withValues(alpha: 0)], stops: const [0, .45, 1]).createShader(rect));
        glow(const Alignment(-1.1, -.9), .95, const Color(0xFFFF6A2B));
        glow(const Alignment(-1.05, -.15), .55, const Color(0xFFFF3D6E));
        glow(const Alignment(1.15, 1), .7, const Color(0xFFFFB347));
        grain(.18 * s);
      case PageTexture.faded:
        grain(.3 * s);
        vignette(.1 * s);
      case PageTexture.dust:
        final random = Random(23);
        final u = size.width / 100;
        final light = Paint()..color = Colors.white.withValues(alpha: .7 * s);
        final dark = Paint()..color = Colors.black.withValues(alpha: .35 * s);
        for (var i = 0; i < 160; i++) {
          final p = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
          canvas.drawCircle(p, u * (.05 + random.nextDouble() * random.nextDouble() * .35), random.nextInt(3) == 0 ? dark : light);
        }
        final scratch = Paint()..color = Colors.white.withValues(alpha: .45 * s)..strokeWidth = max(.5, u * .08)..style = PaintingStyle.stroke;
        for (var i = 0; i < 7; i++) {
          final x = random.nextDouble() * size.width, y = random.nextDouble() * size.height, len = u * (8 + random.nextDouble() * 30);
          canvas.drawPath(Path()..moveTo(x, y)..quadraticBezierTo(x + u * (random.nextDouble() * 4 - 2), y + len / 2, x + u * (random.nextDouble() * 6 - 3), y + len), scratch);
        }
        grain(.25 * s);
      case PageTexture.paper:
        // Paper fibres pressed into everything, and a little grain.
        final random = Random(5);
        final u = size.width / 60;
        canvas.drawRect(rect, Paint()..color = const Color(0xFFF2E8D8).withValues(alpha: .35 * s)..blendMode = BlendMode.multiply);
        final fibre = Paint()..color = const Color(0xFF8A7560).withValues(alpha: .22 * s)..strokeWidth = max(.4, u * .03)..strokeCap = StrokeCap.round;
        for (var i = 0; i < 900; i++) {
          final p = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
          final a = random.nextDouble() * pi;
          canvas.drawLine(p, p + Offset(cos(a), sin(a)) * u * (.2 + random.nextDouble() * .5), fibre);
        }
        grain(.35 * s);
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) => old.texture != texture || old.strength != strength || old.noise != noise;
}
