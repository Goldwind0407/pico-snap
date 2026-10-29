import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';

/// Teal shadows, orange highlights, greens pushed toward cyan.
const tealFilter = PhotoFilter('test_teal', '測試青橙', Grade(
  contrast: .32, highlights: -.35, shadows: .28,
  hsl: {Hue.green: Hsl(hue: 55, sat: -.35)},
  shadowTone: (-.1, .03, .12), highlightTone: (.11, .04, -.09),
), vignette: .24, soften: .3, halation: .45);

/// Faded warm film: lifted blacks plus every film effect.
const fadedFilter = PhotoFilter('test_faded', '測試褪色', Grade(
  temp: .3, curve: [(0, .1), (.5, .52), (1, .95)],
), grain: .4, vignette: .2, soften: .4, halation: .3);

/// The app ships no filters of its own; tests that need some add these to
/// [photoFilters] for their duration.
void useTestFilters() {
  setUp(() => photoFilters.addAll([tealFilter, fadedFilter]));
  tearDown(() => photoFilters.removeWhere((f) => f.id.startsWith('test_')));
}
