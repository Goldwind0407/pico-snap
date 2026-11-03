import 'color_grade.dart';

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
