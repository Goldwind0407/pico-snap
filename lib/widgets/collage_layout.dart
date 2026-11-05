import 'dart:math';
import 'dart:ui';

/// How the prints of a 拍立得拼貼 lie on the page.
enum CollageArrangement {
  scatter('隨意'),
  grid('整齊'),
  pile('疊放');

  final String label;
  const CollageArrangement(this.label);
}

/// Where one print goes: its centre as fractions of the page, its width as a
/// fraction of the page's width, and its tilt.
typedef PrintPlace = ({Offset center, double width, double angle});

/// Width / height of a print (every film stock is 3:4).
const _print = .75;
const _tilts = [-.07, .06, -.05, .07, -.06, .05];

/// Places [count] prints on a page of [aspect] (width / height) so they use
/// the page whatever its shape: rows and columns are picked for the biggest
/// prints that fit, and the group sits in the middle.
List<PrintPlace> collageLayout(int count, CollageArrangement arrangement, double aspect) {
  final n = count.clamp(1, 6);
  // Measured in page heights: the page is aspect × 1.
  final pageW = aspect, pageH = 1.0, margin = .05;
  final innerW = pageW - 2 * margin, innerH = pageH - 2 * margin;

  // The rows × columns giving the widest prints, with a little air between.
  var cols = 1, w = 0.0;
  for (var c = 1; c <= n; c++) {
    final rows = (n / c).ceil();
    final fit = min(innerW / c * .84, innerH / rows * .84 * _print);
    if (fit > w + 1e-9) { w = fit; cols = c; }
  }
  final rows = (n / cols).ceil();

  PrintPlace place(double x, double y, double width, double angle) =>
      (center: Offset(x / pageW, y / pageH), width: width / pageW, angle: angle);

  switch (arrangement) {
    case CollageArrangement.grid:
    case CollageArrangement.scatter:
      final scatter = arrangement == CollageArrangement.scatter;
      // Scattered prints are a little bigger and overlap a little.
      final pw = scatter ? min(w * 1.02, innerW / cols) : w;
      final ph = pw / _print;
      // Spread out over the page, but not further apart than looks like a group.
      final sx = min(innerW / cols, pw * (scatter ? 1.16 : 1.1));
      final sy = min(innerH / rows, ph * (scatter ? 1.1 : 1.08));
      final places = <PrintPlace>[];
      for (var i = 0; i < n; i++) {
        final r = i ~/ cols, c = i % cols;
        // A short last row sits in the middle.
        final inRow = r == rows - 1 ? n - r * cols : cols;
        var x = pageW / 2 + (c - (inRow - 1) / 2) * sx;
        var y = pageH / 2 + (r - (rows - 1) / 2) * sy;
        if (scatter && n > 1) {
          // Zig-zag like an album page: every other column a bit lower,
          // every other row a bit to the side.
          if (cols > 1) y += (c.isOdd ? 1 : -1) * min(ph * .1, (innerH - sy * (rows - 1) - ph) / 2 + ph * .06);
          if (cols == 1) x += (r.isOdd ? 1 : -1) * min(pw * .14, (innerW - pw) / 2);
        }
        places.add(place(x, y, pw, scatter ? _tilts[i % _tilts.length] : 0));
      }
      return places;
    case CollageArrangement.pile:
      // Bigger prints, overlapping, fanned down the page.
      final pw = n == 1 ? w : min(min(innerW * (n <= 3 ? .64 : .56), innerH * (n <= 3 ? .6 : .52) * _print), max(w * 1.3, innerW * .45));
      final ph = pw / _print;
      final spanY = max(0.0, innerH - ph), spanX = max(0.0, (innerW - pw) / 2);
      return [
        for (var i = 0; i < n; i++)
          place(
            pageW / 2 + (n == 1 ? 0 : (i.isEven ? -1 : 1) * min(spanX, pw * .42)),
            margin + ph / 2 + (n == 1 ? spanY / 2 : spanY * i / (n - 1)),
            pw,
            n == 1 ? -.04 : (i.isEven ? -1 : 1) * (.09 + .03 * (i % 3)),
          ),
      ];
  }
}
