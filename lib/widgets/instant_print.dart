import 'package:flutter/material.dart';

import '../filters.dart';
import '../theme.dart';
import 'doodle.dart';
import 'frames.dart';

/// Instant film. Both stocks come from photos of the same print, so their
/// photo windows sit in (almost) the same place. The frames after them are
/// whole cards with their own shape.
enum FilmStock {
  white('白底片', 'assets/instant/film.png', Rect.fromLTWH(.07148, .08732, .85399, .71087), ink, Colors.white, Color(0xFF1E1E20)),
  black('黑底片', 'assets/instant/film_black.png', Rect.fromLTWH(.07088, .08738, .85595, .71133), Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A)),
  // Film-strip cards drawn with Gemini. For testing only: the character ones
  // use other people's characters and names, not ours to ship.
  filmFrame('底片框', 'assets/instant/frame_film.png', _frameWindow, Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A), aspect: _frameAspect),
  keroroFrame('Keroro 框', 'assets/instant/frame_keroro.png', _frameWindow, Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A), aspect: _frameAspect),
  pokemonFrame('寶可夢框', 'assets/instant/frame_pokemon.png', _frameWindow, Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A), aspect: _frameAspect);

  final String label, asset;
  /// The photo window, as fractions of the print.
  final Rect window;
  final Color text, swatch;
  /// The pen handwriting starts with: black on white film, gold on black.
  final Color pen;
  /// Width / height of a print.
  final double aspect;
  const FilmStock(this.label, this.asset, this.window, this.text, this.swatch, this.pen, {this.aspect = .85058});

  bool get dark => text == Colors.white;
}

const _frameAspect = 900 / 1260;
const _frameWindow = Rect.fromLTWH(.12816, .10957, .74563, .681);

/// How instax film develops at [t] (0–1): a flat pale grey-blue blank, then
/// a faint, warm, low-contrast picture that gains colour and contrast.
@visibleForTesting
ColorFilter developFilter(double t) {
  t = t.clamp(0.0, 1.0);
  const blank = <double>[0, 0, 0, 0, 196, 0, 0, 0, 0, 202, 0, 0, 0, 0, 206, 0, 0, 0, 1, 0];
  final s = Curves.easeIn.transform(t);
  final sat = s, contrast = .5 + .5 * s, warm = 22 * (1 - s);
  const lum = [.2126, .7152, .0722];
  List<double> row(int i, double offset) {
    final r = [for (final l in lum) l * (1 - sat)];
    r[i] += sat;
    return [for (final v in r) contrast * v, 0, 128 * (1 - contrast) + offset];
  }

  final photo = [...row(0, warm), ...row(1, warm * .4), ...row(2, -warm * .6), 0, 0, 0, 1, 0];
  // The picture appears during the first three quarters.
  final k = Curves.easeInOut.transform((t / .75).clamp(0.0, 1.0));
  return ColorFilter.matrix([for (var i = 0; i < 20; i++) blank[i] + (photo[i] - blank[i]) * k]);
}

/// An instax print with the photo in its window, a typed caption on the wide
/// bottom border and finger handwriting over the whole print. Design size
/// [width] × [heightOf] the film.
class InstantPrint extends StatelessWidget {
  static const width = 160.0;
  static double heightOf(FilmStock film) => width / film.aspect;
  final ImageProvider? image;
  final FilmStock film;
  /// Developing progress; 1 = fully developed.
  final double develop;
  final String caption;
  /// Finger writing anywhere on the print, in fractions of the print.
  final List<Stroke> handwriting;
  /// Bump while a stroke is being drawn so it repaints.
  final int handwritingVersion;
  final VoidCallback? onCaption, onTap;
  /// Shown in an empty window.
  final Widget? placeholder;
  final bool selected;
  final PhotoFit fit;
  final double? aspect;
  final ValueChanged<PhotoFit>? onFit;
  final PhotoFilter? filter;
  const InstantPrint({
    super.key, this.image, this.film = FilmStock.white, this.develop = 1, required this.caption, this.handwriting = const [], this.handwritingVersion = 0,
    this.onCaption, this.onTap, this.placeholder, this.selected = false, this.fit = const PhotoFit(), this.aspect, this.onFit, this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final height = heightOf(film);
    final w = Rect.fromLTWH(film.window.left * width, film.window.top * height, film.window.width * width, film.window.height * height);
    Widget window = image == null
      ? ColoredBox(color: film.dark ? const Color(0xFF2E2E31) : const Color(0xFFF1EDE8), child: Center(child: placeholder))
      : FittedPhoto(image: image!, fit: fit, aspect: aspect, onChanged: onFit, filter: filter);
    if (image != null && develop < 1) window = ColorFiltered(colorFilter: developFilter(develop), child: window);
    return SizedBox(width: width, height: height, child: Stack(children: [
      Positioned.fill(child: Image.asset(film.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
      Positioned.fromRect(rect: w, child: GestureDetector(onTap: onTap, child: ClipRect(child: window))),
      if (selected)
        Positioned.fromRect(rect: w.inflate(1), child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: coral, width: 3)),
        ))),
      Positioned(left: 8, right: 8, top: w.bottom + 2, bottom: 4, child: GestureDetector(
        key: const ValueKey('instant-caption'),
        onTap: onCaption,
        behavior: HitTestBehavior.opaque,
        child: caption.isEmpty
          ? const SizedBox.expand()
          : Center(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: hand(24, color: film.text))),
      )),
      if (handwriting.isNotEmpty)
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: DoodlePainter(handwriting, handwritingVersion)))),
    ]));
  }
}
