import 'color_grade.dart';

/// Instant film in warm light. Instant prints hold a narrow range: the
/// highlights wash out to a creamy white, the blacks sit a little lifted
/// with a green-cyan cast, colours are bold but deep (blue most of all) and
/// the whole print leans golden.
const instantGoldenGrade = Grade(
  exposure: .03,
  contrast: .12,
  saturation: 1.02,
  density: .45,
  shadowDesat: .2,
  highlightDesat: .45,
  curve: [(0, .045), (.15, .11), (.5, .51), (.8, .845), (1, .965)],
  hsl: {
    Hue.red: Hsl(sat: .05, lum: -.03),
    Hue.orange: Hsl(hue: 3, lum: .02),
    Hue.yellow: Hsl(hue: -6, sat: -.1),
    Hue.green: Hsl(hue: -6, sat: -.2, lum: -.05),
    Hue.aqua: Hsl(sat: -.15),
    Hue.blue: Hsl(hue: -6, sat: -.1, lum: -.2),
  },
  shadowTone: (-.022, .014, .018),
  midTone: (.024, .01, -.024),
  highlightTone: (.026, .014, -.03),
);

/// Instant film with the flash on: the film leans cold and overexposes, so
/// faces come out bright and a little pale, everything else falls off dark
/// and blue-green, and blues go deep. Does not relight the subject.
const instantCoolGrade = Grade(
  exposure: .02,
  contrast: .18,
  saturation: .95,
  density: .5,
  shadowDesat: .15,
  highlightDesat: .5,
  curve: [(0, .03), (.15, .09), (.5, .5), (.8, .85), (1, .98)],
  hsl: {
    Hue.red: Hsl(sat: .04),
    Hue.orange: Hsl(hue: -4, sat: -.12, lum: .04),
    Hue.yellow: Hsl(sat: -.25),
    Hue.green: Hsl(hue: 12, sat: -.25, lum: -.08),
    Hue.blue: Hsl(hue: -6, sat: -.05, lum: -.2),
  },
  shadowTone: (-.02, .004, .03),
  midTone: (-.014, .002, .02),
  highlightTone: (.006, .002, .004),
);

/// An old colour print that has sat in an album: blacks faded to a warm
/// brown, paper yellowed in the highlights, greens gone olive and blues
/// pale. Low contrast, never grey.
const retroSoftGrade = Grade(
  saturation: .84,
  density: .25,
  highlightDesat: .25,
  curve: [(0, .085), (.18, .215), (.5, .5), (.8, .775), (1, .94)],
  hsl: {
    Hue.red: Hsl(hue: 4, sat: -.05),
    Hue.orange: Hsl(sat: -.05, lum: .015),
    Hue.yellow: Hsl(hue: -8, sat: -.1),
    Hue.green: Hsl(hue: -18, sat: -.3),
    Hue.aqua: Hsl(hue: -8, sat: -.2),
    Hue.blue: Hsl(hue: -10, sat: -.3, lum: .03),
  },
  shadowTone: (.03, .012, -.006),
  midTone: (.012, .006, -.012),
  highlightTone: (.02, .012, -.03),
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

/// Consumer colour negative, the strong kind: hard contrast with slightly
/// faded blacks and creamy whites, cyan-green in the shadows and a touch of
/// magenta in the highlights. Reds stay deep and rich while greens slide
/// towards cyan and go dark, yellows and blues are held back, and colour
/// thins out in the deepest shadows.
const strongNegativeGrade = Grade(
  contrast: .22,
  saturation: .94,
  density: .55,
  shadowDesat: .35,
  highlightDesat: .3,
  curve: [(0, .022), (.12, .09), (.5, .5), (.85, .865), (1, .975)],
  hsl: {
    Hue.red: Hsl(hue: 2, sat: .12, lum: -.06),
    Hue.orange: Hsl(hue: -3, sat: -.06),
    Hue.yellow: Hsl(hue: -8, sat: -.25, lum: -.04),
    Hue.green: Hsl(hue: 22, sat: -.3, lum: -.12),
    Hue.aqua: Hsl(hue: -6, sat: -.18, lum: -.05),
    Hue.blue: Hsl(hue: -14, sat: -.2, lum: -.1),
    Hue.purple: Hsl(sat: -.25),
  },
  shadowTone: (-.022, .012, .016),
  highlightTone: (.02, -.006, .006),
);
