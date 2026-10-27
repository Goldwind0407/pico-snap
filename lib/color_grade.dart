import 'dart:math' as math;
import 'dart:typed_data';

/// Hue bands for HSL adjustments, like Lightroom's colour mixer.
enum Hue {
  red(0), orange(30), yellow(60), green(120), aqua(180), blue(225), purple(270), magenta(315);

  /// Centre of the band, in degrees.
  final double center;
  const Hue(this.center);
}

/// One band's HSL change: hue shift in degrees, saturation and luminance
/// changes from -1 to 1.
class Hsl {
  final double hue, sat, lum;
  const Hsl({this.hue = 0, this.sat = 0, this.lum = 0});
}

/// A photo grade, the way photo apps build their filters: white balance,
/// exposure, HSL colour mixing, shadows / highlights, contrast, tone curves
/// (a raised black point gives the faded, airy look), split toning and
/// saturation. Values are 0–1 colour unless noted.
class Grade {
  /// Warm (+) / cool (−), −1 to 1.
  final double temp;
  /// Magenta (+) / green (−), −1 to 1.
  final double tint;
  /// Stops.
  final double exposure;
  /// Film-like S contrast, 0 to 1.
  final double contrast;
  /// Lift (+) or deepen (−) the shadows; lift (+) or pull down (−) the
  /// highlights. −1 to 1.
  final double shadows, highlights;
  final Map<Hue, Hsl> hsl;
  /// Tone curves as (in, out) points: master, then per channel.
  final List<(double, double)> curve, red, green, blue;
  /// Colour pushed into the shadows / highlights, as RGB offsets.
  final (double, double, double) shadowTone, highlightTone;
  /// Saturation multiplier; vibrance boosts dull colours more than vivid ones.
  final double saturation, vibrance;

  const Grade({
    this.temp = 0, this.tint = 0, this.exposure = 0, this.contrast = 0, this.shadows = 0, this.highlights = 0,
    this.hsl = const {}, this.curve = const [], this.red = const [], this.green = const [], this.blue = const [],
    this.shadowTone = (0, 0, 0), this.highlightTone = (0, 0, 0), this.saturation = 1, this.vibrance = 0,
  });

  static const none = Grade();

  /// Grade one colour (0–1 per channel).
  (double, double, double) apply(double r, double g, double b) => _Prepared.of(this).apply(r, g, b);

  /// A [n]³ RGB lookup table: index ((r·n + g)·n + b)·3.
  Float32List lut([int n = 33]) {
    final p = _Prepared.of(this);
    final out = Float32List(n * n * n * 3);
    var o = 0;
    for (var ri = 0; ri < n; ri++) {
      for (var gi = 0; gi < n; gi++) {
        for (var bi = 0; bi < n; bi++) {
          final (r, g, b) = p.apply(ri / (n - 1), gi / (n - 1), bi / (n - 1));
          out[o++] = r;
          out[o++] = g;
          out[o++] = b;
        }
      }
    }
    return out;
  }
}

/// Curves turned into tables once per grade.
class _Prepared {
  final Grade g;
  final Float32List? master, r, gr, b;
  _Prepared(this.g)
      : master = _table(g.curve),
        r = _table(g.red),
        gr = _table(g.green),
        b = _table(g.blue);

  static final _cache = Expando<_Prepared>();
  static _Prepared of(Grade g) => _cache[g] ??= _Prepared(g);

  static double _lookup(Float32List? t, double v) {
    if (t == null) return v;
    final x = v.clamp(0.0, 1.0) * 255;
    final i = x.floor().clamp(0, 254);
    final f = x - i;
    return t[i] + (t[i + 1] - t[i]) * f;
  }

  (double, double, double) apply(double r0, double g0, double b0) {
    final g = this.g;
    var r = r0, gg = g0, b = b0;
    // White balance and exposure.
    final ex = math.pow(2, g.exposure).toDouble();
    r *= (1 + .12 * g.temp) * ex;
    gg *= (1 - .08 * g.tint) * ex;
    b *= (1 - .12 * g.temp) * ex;
    // HSL colour mixing.
    if (g.hsl.isNotEmpty) (r, gg, b) = _mix(r, gg, b);
    // Shadows and highlights by luminance.
    if (g.shadows != 0 || g.highlights != 0) {
      final l = _luma(r, gg, b).clamp(0.0, 1.0);
      final ws = 1 - _smooth(0, .55, l), wh = _smooth(.45, 1, l);
      final d = g.shadows * .22 * ws * (1 - l) + g.highlights * .22 * wh * l;
      r += d;
      gg += d;
      b += d;
    }
    // S-shaped contrast.
    if (g.contrast > 0) {
      double s(double v) {
        final c = v.clamp(0.0, 1.0);
        return c + (c * c * (3 - 2 * c) - c) * g.contrast;
      }

      r = s(r);
      gg = s(gg);
      b = s(b);
    }
    // Tone curves.
    r = _lookup(this.r, _lookup(master, r));
    gg = _lookup(gr, _lookup(master, gg));
    b = _lookup(this.b, _lookup(master, b));
    // Split toning.
    final l = _luma(r, gg, b).clamp(0.0, 1.0);
    final ws = 1 - _smooth(0, .6, l), wh = _smooth(.4, 1, l);
    r += g.shadowTone.$1 * ws + g.highlightTone.$1 * wh;
    gg += g.shadowTone.$2 * ws + g.highlightTone.$2 * wh;
    b += g.shadowTone.$3 * ws + g.highlightTone.$3 * wh;
    // Saturation and vibrance around the luminance.
    if (g.saturation != 1 || g.vibrance != 0) {
      final y = _luma(r, gg, b);
      final mx = math.max(r, math.max(gg, b)), mn = math.min(r, math.min(gg, b));
      final sat = mx <= 0 ? 0.0 : (mx - mn) / mx;
      final k = g.saturation * (1 + g.vibrance * (1 - sat));
      r = y + (r - y) * k;
      gg = y + (gg - y) * k;
      b = y + (b - y) * k;
    }
    return (r.clamp(0.0, 1.0), gg.clamp(0.0, 1.0), b.clamp(0.0, 1.0));
  }

  (double, double, double) _mix(double r, double g, double b) {
    final (h, s, l) = _toHsl(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0));
    if (s < .001) return (r, g, b);
    var dh = 0.0, ds = 0.0, dl = 0.0;
    for (final e in this.g.hsl.entries) {
      final w = _bandWeight(h, e.key);
      if (w == 0) continue;
      dh += e.value.hue * w;
      ds += e.value.sat * w;
      dl += e.value.lum * w;
    }
    // Greys and near-greys barely move: there's no colour to judge.
    final k = math.min(1.0, s * 2.5);
    final s2 = (s * (1 + ds * k)).clamp(0.0, 1.0);
    final l2 = (l + dl * .25 * k * (1 - (l - .5).abs() * 2).clamp(.2, 1.0)).clamp(0.0, 1.0);
    return _fromHsl((h + dh * k) % 360, s2, l2);
  }

  /// Triangular weights between neighbouring band centres (they sum to 1).
  static double _bandWeight(double h, Hue band) {
    const bands = Hue.values;
    final i = band.index;
    final prev = bands[(i - 1 + bands.length) % bands.length].center;
    final next = bands[(i + 1) % bands.length].center;
    double dist(double a, double b) {
      final d = (a - b) % 360;
      return d < 0 ? d + 360 : d;
    }

    final up = dist(h, band.center), down = dist(band.center, h);
    if (up <= dist(next, band.center) && up < 180) return 1 - up / dist(next, band.center);
    if (down <= dist(band.center, prev) && down < 180) return 1 - down / dist(band.center, prev);
    return 0;
  }
}

double _luma(double r, double g, double b) => .2126 * r + .7152 * g + .0722 * b;

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

(double, double, double) _toHsl(double r, double g, double b) {
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  if (mx == mn) return (0, 0, l);
  final d = mx - mn;
  final s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn);
  double h;
  if (mx == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h * 60, s, l);
}

(double, double, double) _fromHsl(double h, double s, double l) {
  if (s == 0) return (l, l, l);
  final q = l < .5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  double c(double t) {
    t %= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  final hh = h / 360;
  return (c(hh + 1 / 3), c(hh), c(hh - 1 / 3));
}

/// A 256-entry table through [points] with a smooth monotone curve
/// (Fritsch–Carlson), so it never wiggles or reverses. Null when empty.
Float32List? _table(List<(double, double)> points) {
  if (points.isEmpty) return null;
  final pts = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
  if (pts.first.$1 > 0) pts.insert(0, (0, pts.first.$2));
  if (pts.last.$1 < 1) pts.add((1, pts.last.$2));
  final n = pts.length;
  final x = [for (final p in pts) p.$1], y = [for (final p in pts) p.$2];
  final d = [for (var i = 0; i < n - 1; i++) (y[i + 1] - y[i]) / math.max(1e-6, x[i + 1] - x[i])];
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i], b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  final out = Float32List(256);
  var k = 0;
  for (var i = 0; i < 256; i++) {
    final v = i / 255;
    while (k < n - 2 && v > x[k + 1]) {
      k++;
    }
    final hgt = x[k + 1] - x[k];
    final t = hgt <= 0 ? 0.0 : ((v - x[k]) / hgt).clamp(0.0, 1.0);
    final t2 = t * t, t3 = t2 * t;
    out[i] = ((2 * t3 - 3 * t2 + 1) * y[k] + (t3 - 2 * t2 + t) * hgt * m[k] + (-2 * t3 + 3 * t2) * y[k + 1] + (t3 - t2) * hgt * m[k + 1])
        .clamp(0.0, 1.0);
  }
  return out;
}

/// Grade RGBA pixels (alpha kept) through a [n]³ [lut] with trilinear
/// interpolation.
Uint8List applyLut(Uint8List rgba, Float32List lut, int n) {
  final out = Uint8List(rgba.length);
  final s = (n - 1) / 255;
  for (var i = 0; i < rgba.length; i += 4) {
    final fr = rgba[i] * s, fg = rgba[i + 1] * s, fb = rgba[i + 2] * s;
    final r0 = math.min(fr.floor(), n - 2), g0 = math.min(fg.floor(), n - 2), b0 = math.min(fb.floor(), n - 2);
    final tr = fr - r0, tg = fg - g0, tb = fb - b0;
    for (var c = 0; c < 3; c++) {
      double at(int r, int g, int b) => lut[((r * n + g) * n + b) * 3 + c];
      final c00 = at(r0, g0, b0) * (1 - tb) + at(r0, g0, b0 + 1) * tb;
      final c01 = at(r0, g0 + 1, b0) * (1 - tb) + at(r0, g0 + 1, b0 + 1) * tb;
      final c10 = at(r0 + 1, g0, b0) * (1 - tb) + at(r0 + 1, g0, b0 + 1) * tb;
      final c11 = at(r0 + 1, g0 + 1, b0) * (1 - tb) + at(r0 + 1, g0 + 1, b0 + 1) * tb;
      final v = (c00 * (1 - tg) + c01 * tg) * (1 - tr) + (c10 * (1 - tg) + c11 * tg) * tr;
      out[i + c] = (v * 255).round().clamp(0, 255);
    }
    out[i + 3] = rgba[i + 3];
  }
  return out;
}

/// The colour matrix closest to [lut] (least squares), for live previews
/// that can only take a matrix (the camera viewfinder).
List<double> fitMatrix(Float32List lut, int n) {
  // Normal equations for out = a·r + b·g + c·b + d, per channel.
  final ata = List.generate(4, (_) => List<double>.filled(4, 0));
  final atb = List.generate(3, (_) => List<double>.filled(4, 0));
  for (var ri = 0; ri < n; ri++) {
    for (var gi = 0; gi < n; gi++) {
      for (var bi = 0; bi < n; bi++) {
        final x = [ri / (n - 1), gi / (n - 1), bi / (n - 1), 1.0];
        final o = ((ri * n + gi) * n + bi) * 3;
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            ata[i][j] += x[i] * x[j];
          }
          for (var c = 0; c < 3; c++) {
            atb[c][i] += x[i] * lut[o + c];
          }
        }
      }
    }
  }
  List<double> solve(List<double> rhs) {
    final m = [for (var i = 0; i < 4; i++) [...ata[i], rhs[i]]];
    for (var c = 0; c < 4; c++) {
      var p = c;
      for (var r = c + 1; r < 4; r++) {
        if (m[r][c].abs() > m[p][c].abs()) p = r;
      }
      final t = m[c];
      m[c] = m[p];
      m[p] = t;
      for (var r = 0; r < 4; r++) {
        if (r == c) continue;
        final f = m[r][c] / m[c][c];
        for (var k = c; k < 5; k++) {
          m[r][k] -= f * m[c][k];
        }
      }
    }
    return [for (var i = 0; i < 4; i++) m[i][4] / m[i][i]];
  }

  final out = <double>[];
  for (var c = 0; c < 3; c++) {
    final s = solve(atb[c]);
    out.addAll([s[0], s[1], s[2], 0, s[3] * 255]);
  }
  out.addAll([0, 0, 0, 1, 0]);
  return out;
}

/// Film finishing on graded RGBA pixels (in place), the steps that make a
/// photo read as shot on film rather than coloured:
/// - [soften] (0–1): takes the edge off phone sharpening.
/// - [halation] (0–1): light glowing out of bright areas in [halationColor]
///   (r, g, b 0–1), like light bouncing back through film emulsion.
/// - [grain] (0–1): film grain, strongest in the mid tones, fading out in
///   deep shadows and bright highlights.
/// [source] is the ungraded photo; halation follows its real highlights.
void finishFilm(Uint8List rgba, Uint8List source, int w, int h,
    {double soften = 0, double halation = 0, (double, double, double) halationColor = (1, .38, .18), double grain = 0}) {
  final n = w * h;
  if (soften > 0) {
    // Mix in a small blur; the radius follows the image size so a full
    // photo and its thumbnail look alike.
    final r = math.max(1, (math.max(w, h) / 1100).round());
    for (var c = 0; c < 3; c++) {
      final ch = Float32List(n);
      for (var i = 0; i < n; i++) {
        ch[i] = rgba[i * 4 + c].toDouble();
      }
      final b = _boxBlur(ch, w, h, r);
      final k = soften * .55;
      for (var i = 0; i < n; i++) {
        rgba[i * 4 + c] = (ch[i] + (b[i] - ch[i]) * k).round().clamp(0, 255);
      }
    }
  }
  if (halation > 0) {
    // Bright parts of the original, on a quarter-size grid, spread out.
    const f = 4;
    final sw = math.max(1, w ~/ f), sh = math.max(1, h ~/ f);
    final m = Float32List(sw * sh);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final sx = math.min(w - 1, x * f + f ~/ 2), sy = math.min(h - 1, y * f + f ~/ 2);
        final j = (sy * w + sx) * 4;
        final l = (.2126 * source[j] + .7152 * source[j + 1] + .0722 * source[j + 2]) / 255;
        m[y * sw + x] = _smooth(.7, .97, l);
      }
    }
    final r = math.max(2, (math.min(sw, sh) * .035).round());
    var b = _boxBlur(m, sw, sh, r);
    b = _boxBlur(b, sw, sh, r);
    final (hr, hg, hb) = halationColor;
    for (var y = 0; y < h; y++) {
      final fy = ((y + .5) / f - .5).clamp(0.0, sh - 1.0);
      final y0 = fy.floor(), y1 = math.min(sh - 1, y0 + 1), ty = fy - y0;
      for (var x = 0; x < w; x++) {
        final fx = ((x + .5) / f - .5).clamp(0.0, sw - 1.0);
        final x0 = fx.floor(), x1 = math.min(sw - 1, x0 + 1), tx = fx - x0;
        final g = ((b[y0 * sw + x0] * (1 - tx) + b[y0 * sw + x1] * tx) * (1 - ty) + (b[y1 * sw + x0] * (1 - tx) + b[y1 * sw + x1] * tx) * ty) *
            halation * 1.6;
        if (g < .002) continue;
        final i = (y * w + x) * 4;
        // Screen blend: glows over dark areas, can't push whites past white.
        rgba[i] = (255 - (255 - rgba[i]) * (1 - (g * hr).clamp(0.0, 1.0))).round();
        rgba[i + 1] = (255 - (255 - rgba[i + 1]) * (1 - (g * hg).clamp(0.0, 1.0))).round();
        rgba[i + 2] = (255 - (255 - rgba[i + 2]) * (1 - (g * hb).clamp(0.0, 1.0))).round();
      }
    }
  }
  if (grain > 0) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final l = (.2126 * rgba[i] + .7152 * rgba[i + 1] + .0722 * rgba[i + 2]) / 255;
        // Mid tones carry the most grain, like silver halide density.
        final a = grain * 30 * (.2 + 3.2 * l * (1 - l));
        // Two octaves: fine grain with a little clumping.
        final v = (_noise(x, y) * .7 + _noise(x >> 1, (y >> 1) + 9173) * .3) * a;
        for (var c = 0; c < 3; c++) {
          rgba[i + c] = (rgba[i + c] + v).round().clamp(0, 255);
        }
      }
    }
  }
}

/// Deterministic noise in −1…1, the same for the same pixel every time.
double _noise(int x, int y) {
  var h = (x * 374761393 + y * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return (h & 0xffff) / 32767.5 - 1;
}

/// Separable box blur with radius [r].
Float32List _boxBlur(Float32List src, int w, int h, int r) {
  final tmp = Float32List(w * h), out = Float32List(w * h);
  final d = 2 * r + 1;
  for (var y = 0; y < h; y++) {
    var s = 0.0;
    for (var k = -r; k <= r; k++) {
      s += src[y * w + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[y * w + x] = s / d;
      s += src[y * w + math.min(w - 1, x + r + 1)] - src[y * w + math.max(0, x - r)];
    }
  }
  for (var x = 0; x < w; x++) {
    var s = 0.0;
    for (var k = -r; k <= r; k++) {
      s += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = s / d;
      s += tmp[math.min(h - 1, y + r + 1) * w + x] - tmp[math.max(0, y - r) * w + x];
    }
  }
  return out;
}
