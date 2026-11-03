import 'color_grade.dart';

/// Warm instant-print interpretation: cyan blacks, golden skin, muted colour
/// and a compressed paper-white shoulder. Texture is applied to the photo.
const instantGoldenGrade = Grade(
  exposure: -.12,
  saturation: .82,
  curve: [(0, .035), (.18, .155), (.5, .48), (.8, .76), (1, .925)],
  hsl: {
    Hue.red: Hsl(hue: 3, sat: -.08),
    Hue.orange: Hsl(hue: 4, sat: -.08, lum: .02),
    Hue.yellow: Hsl(hue: -5, sat: -.18),
    Hue.green: Hsl(hue: -10, sat: -.28),
    Hue.aqua: Hsl(sat: -.18),
    Hue.blue: Hsl(hue: -8, sat: -.24),
  },
  shadowTone: (-.028, .018, .025),
  midTone: (.025, .012, -.025),
  highlightTone: (.025, .018, -.028),
);

/// Cool flash-film interpretation: blue shadows with restrained pink warmth
/// in skin and highlights. Does not try to relight the subject with an overlay.
const instantCoolGrade = Grade(
  saturation: .84,
  curve: [(0, .018), (.18, .12), (.5, .48), (.8, .82), (1, .965)],
  hsl: {
    Hue.red: Hsl(sat: -.06),
    Hue.orange: Hsl(hue: -3, sat: -.10, lum: .025),
    Hue.yellow: Hsl(sat: -.22),
    Hue.green: Hsl(hue: 10, sat: -.30),
    Hue.aqua: Hsl(hue: 5, sat: -.12),
    Hue.blue: Hsl(sat: -.18),
  },
  shadowTone: (-.008, .006, .025),
  midTone: (-.018, .002, .024),
  highlightTone: (.018, .004, -.012),
);

/// Display-referred recipes for ordinary sRGB photos (not Log footage).
// The source retro Hald has spatial effects baked into its colour coordinates.
// Rebuild a smooth faded look; apply softening to the photo, never the Hald.
const retroSoftGrade = Grade(
  saturation: .78,
  curve: [(0, .09), (.18, .22), (.5, .5), (.8, .77), (1, .93)],
  hsl: {
    Hue.orange: Hsl(sat: -.04, lum: .015),
    Hue.yellow: Hsl(hue: -6, sat: -.08),
    Hue.green: Hsl(hue: -12, sat: -.18),
    Hue.blue: Hsl(sat: -.12),
  },
  shadowTone: (.012, .006, -.004),
  highlightTone: (.018, .006, -.018),
);

/// Warm near-whites, lifted blacks and muted foliage without a global
/// exposure boost: bright skin retains texture instead of clipping to white.
const koreanCreamGrade = Grade(
  saturation: .9,
  curve: [(0, .055), (.18, .235), (.5, .565), (.8, .825), (1, .965)],
  hsl: {
    Hue.orange: Hsl(sat: -.06, lum: .035),
    Hue.yellow: Hsl(sat: -.16),
    Hue.green: Hsl(hue: -8, sat: -.22, lum: .035),
    Hue.blue: Hsl(sat: -.18, lum: .025),
  },
  shadowTone: (.008, .006, .003),
  midTone: (.009, .003, -.004),
  highlightTone: (.018, .009, -.012),
);
