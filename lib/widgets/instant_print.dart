import 'package:flutter/material.dart';

import '../filters.dart';
import '../theme.dart';
import 'doodle.dart';
import 'frames.dart';

/// Instant film. Every stock is a 3:4 card drawn with Gemini whose photo
/// window is transparent: the card lies over the photo, so its decorations
/// and characters can overlap the photo's edges.
enum FilmStock {
  white('白底片', '基本', 'assets/instant/film.png', Rect.fromLTWH(.10889, .11, .78333, .65167), ink, Colors.white, Color(0xFF1E1E20)),
  black('黑底片', '基本', 'assets/instant/film_black.png', Rect.fromLTWH(.10778, .11667, .78444, .6475), Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A)),
  filmFrame('底片框', '基本', 'assets/instant/frame_film.png', Rect.fromLTWH(.14222, .11833, .71556, .655), Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A)),
  smile('微笑', '基本', 'assets/instant/film_smile.png', Rect.fromLTWH(.10889, .105, .78222, .6625), ink, Colors.white, Color(0xFF1E1E20)),
  stars('星星', '基本', 'assets/instant/film_stars.png', Rect.fromLTWH(.12111, .09917, .75778, .66833), ink, Colors.white, Color(0xFF1E1E20)),
  // For testing only: other people's characters, names and logos, not ours
  // to ship.
  sanrioKitty('凱蒂貓', '三麗鷗', 'assets/instant/sanrio_kitty.png', Rect.fromLTWH(.10778, .125, .78444, .58417), ink, Colors.white, Color(0xFF1E1E20)),
  sanrioKeroppi('大眼蛙', '三麗鷗', 'assets/instant/sanrio_keroppi.png', Rect.fromLTWH(.10889, .12583, .78222, .57417), ink, Colors.white, Color(0xFF1E1E20)),
  sanrioCinnamoroll('大耳狗', '三麗鷗', 'assets/instant/sanrio_cinnamoroll.png', Rect.fromLTWH(.10667, .125, .78667, .58417), ink, Colors.white, Color(0xFF1E1E20)),
  sanrioPompompurin('布丁狗', '三麗鷗', 'assets/instant/sanrio_pompompurin.png', Rect.fromLTWH(.10667, .12667, .78667, .5825), ink, Colors.white, Color(0xFF1E1E20)),
  sanrioMelody('美樂蒂酷洛米', '三麗鷗', 'assets/instant/sanrio_melody.png', Rect.fromLTWH(.11222, .12917, .77556, .55667), ink, Colors.white, Color(0xFF1E1E20)),
  sanrioBadtz('酷企鵝', '三麗鷗', 'assets/instant/sanrio_badtz.png', Rect.fromLTWH(.11556, .1325, .76889, .54583), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonFrame('寶可夢框', '寶可夢', 'assets/instant/frame_pokemon.png', Rect.fromLTWH(.16667, .1175, .66444, .65), Colors.white, Color(0xFF1E1E20), Color(0xFFD4AF5A)),
  pokemonGs('心金魂銀', '寶可夢', 'assets/instant/pokemon_gs.png', Rect.fromLTWH(.10667, .11667, .78778, .5975), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonFrlg('火紅葉綠', '寶可夢', 'assets/instant/pokemon_frlg.png', Rect.fromLTWH(.10667, .125, .78667, .55667), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonRs('紅寶藍寶', '寶可夢', 'assets/instant/pokemon_rs.png', Rect.fromLTWH(.12222, .13417, .75667, .55667), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonDp('鑽石珍珠', '寶可夢', 'assets/instant/pokemon_dp.png', Rect.fromLTWH(.10208, .11233, .79248, .6117), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonBw2('黑2白2', '寶可夢', 'assets/instant/pokemon_bw2.png', Rect.fromLTWH(.10817, .11491, .77408, .60245), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonXy('XY', '寶可夢', 'assets/instant/pokemon_xy.png', Rect.fromLTWH(.09551, .10656, .79632, .61389), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonUsum('究極日月', '寶可夢', 'assets/instant/pokemon_usum.png', Rect.fromLTWH(.09971, .13467, .77959, .56887), ink, Colors.white, Color(0xFF1E1E20)),
  pokemonSwsh('劍盾', '寶可夢', 'assets/instant/pokemon_swsh.png', Rect.fromLTWH(.09452, .12192, .77867, .5923), ink, Colors.white, Color(0xFF1E1E20)),
  cpblBrothers('中信兄弟', '中職', 'assets/instant/cpbl_brothers.png', Rect.fromLTWH(.09047, .07581, .81809, .65199), ink, Colors.white, Color(0xFF1E1E20)),
  cpblLions('統一獅', '中職', 'assets/instant/cpbl_lions.png', Rect.fromLTWH(.09135, .07648, .81731, .67605), ink, Colors.white, Color(0xFF1E1E20)),
  rakutenFrame('樂天桃猿', '中職', 'assets/instant/cpbl_monkeys.png', Rect.fromLTWH(.0888, .07381, .82239, .6288), ink, Colors.white, Color(0xFF9E1B32)),
  cpblGuardians('富邦悍將', '中職', 'assets/instant/cpbl_guardians.png', Rect.fromLTWH(.09143, .07581, .81617, .64838), ink, Colors.white, Color(0xFF1E1E20)),
  cpblDragons('味全龍', '中職', 'assets/instant/cpbl_dragons.png', Rect.fromLTWH(.09318, .07925, .81268, .63617), ink, Colors.white, Color(0xFF1E1E20)),
  cpblHawks('台鋼雄鷹', '中職', 'assets/instant/cpbl_hawks.png', Rect.fromLTWH(.09423, .07931, .8125, .64888), ink, Colors.white, Color(0xFF1E1E20)),
  keroroFrame('Keroro', '動漫', 'assets/instant/frame_keroro.png', Rect.fromLTWH(.11333, .085, .77111, .69917), ink, Colors.white, ink),
  animeConan('名偵探柯南', '動漫', 'assets/instant/anime_conan.png', Rect.fromLTWH(.09908, .06742, .80127, .72818), ink, Colors.white, Color(0xFF1E1E20)),
  animeShinchan('蠟筆小新', '動漫', 'assets/instant/anime_shinchan.png', Rect.fromLTWH(.10642, .07728, .78322, .71242), ink, Colors.white, Color(0xFF1E1E20));

  /// The film picker's tabs, in order.
  static const series = ['基本', '三麗鷗', '寶可夢', '中職', '動漫'];

  final String label, group, asset;
  /// The photo window, as fractions of the print.
  final Rect window;
  final Color text, swatch;
  /// The pen handwriting starts with: black on white film, gold on black.
  final Color pen;
  const FilmStock(this.label, this.group, this.asset, this.window, this.text, this.swatch, this.pen);

  /// Width / height of a print: the same for every stock.
  double get aspect => .75;

  bool get dark => text == Colors.white;
}

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
  /// Ticks as a stroke grows, to repaint just the ink.
  final Listenable? handwritingRepaint;
  final VoidCallback? onCaption, onTap;
  /// Shown in an empty window.
  final Widget? placeholder;
  final bool selected;
  /// Outline the caption: it is the one being typed.
  final bool captionSelected;
  final PhotoFit fit;
  final double? aspect;
  final ValueChanged<PhotoFit>? onFit;
  final PhotoFilter? filter;
  const InstantPrint({
    super.key, this.image, this.film = FilmStock.white, this.develop = 1, required this.caption, this.handwriting = const [], this.handwritingVersion = 0, this.handwritingRepaint,
    this.onCaption, this.onTap, this.placeholder, this.selected = false, this.captionSelected = false, this.fit = const PhotoFit(), this.aspect, this.onFit, this.filter,
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
      Positioned.fromRect(rect: w, child: GestureDetector(onTap: onTap, child: ClipRect(child: window))),
      // Over the photo: the window is transparent and the art may overlap it.
      Positioned.fill(child: IgnorePointer(child: Image.asset(film.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium))),
      if (selected)
        Positioned.fromRect(rect: w.inflate(1), child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: coral, width: 3)),
        ))),
      if (captionSelected)
        Positioned(left: 6, right: 6, top: w.bottom + 4, bottom: 4, child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: coral, width: 2.5), borderRadius: BorderRadius.circular(6)),
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
        Positioned.fill(child: InkLayer(strokes: handwriting, version: handwritingVersion, repaint: handwritingRepaint)),
    ]));
  }
}
