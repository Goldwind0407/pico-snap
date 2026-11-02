import 'color_grade.dart';

/// Display-referred recipes for ordinary sRGB photos (not Log footage).
const negativeGrade = Grade(
  contrast: .22,
  saturation: 1.08,
  curve: [(0, .018), (.18, .135), (.5, .51), (.8, .84), (1, .98)],
  hsl: {
    Hue.red: Hsl(sat: -.08),
    Hue.orange: Hsl(sat: -.14, lum: .025),
    Hue.green: Hsl(hue: 12, sat: -.12),
    Hue.blue: Hsl(hue: -8, sat: -.08),
  },
  shadowTone: (-.008, .008, .006),
  highlightTone: (.012, .004, -.008),
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
