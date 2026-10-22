import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme.dart';

enum EditorMode { fourCut, polaroid, sticker }

const samplePhotos = <ImageProvider>[
  AssetImage('assets/samples/girl1.jpg'),
  AssetImage('assets/samples/girl2.jpg'),
  AssetImage('assets/samples/girl3.jpg'),
  AssetImage('assets/samples/girl4.jpg'),
];
const sampleDuo = AssetImage('assets/samples/duo.jpg');

enum CellShape { square, rounded, cloud, wavy }

enum FramePattern { none, dots, paws, confetti, gingham, stripes }

/// What sits in the strip's bottom margin.
enum FooterStyle {
  /// Handwritten caption.
  caption,
  /// "PICO SNAP" wordmark with the date, like a classic photo booth print.
  logoDate,
  /// Big bold title with a handwritten subtitle.
  title,
}

/// A sticker or speech bubble printed on the template, in [PhotoStrip]
/// design coordinates (200 × 620).
class Deco {
  final String content;
  final Offset center;
  final double size, angle;
  final bool bubble;
  const Deco(this.content, this.center, {this.size = 44, this.angle = 0}) : bubble = false;
  const Deco.bubble(this.content, this.center, {this.size = 15, this.angle = 0}) : bubble = true;
}

/// A finished template illustration (generated with Gemini) whose photo
/// windows are transparent. [cells] are normalised window rects.
class ArtFrame {
  final String asset;
  /// Width / height of the illustration.
  final double aspect;
  final List<Rect> cells;
  const ArtFrame(this.asset, this.aspect, this.cells);
}

class StripTemplate {
  final String name, category, caption, subtitle;
  final Color frame, cell, captionColor;
  /// Optional bottom colour for a vertical gradient frame.
  final Color? frame2;
  final FramePattern pattern;
  final Color patternColor;
  final CellShape cellShape;
  final FooterStyle footer;
  /// Thin brown doodle outline around the frame and cells.
  final bool outline;
  final bool tape;
  /// Print photos in black and white.
  final bool mono;
  final List<Deco> decos;
  /// When set, the strip is this illustration and the drawing options above
  /// (except [cell], used for empty windows) are ignored.
  final ArtFrame? art;
  const StripTemplate({
    required this.name, required this.category, required this.caption, this.subtitle = '',
    required this.frame, this.frame2, required this.cell, this.captionColor = ink,
    this.pattern = FramePattern.none, this.patternColor = Colors.white, this.cellShape = CellShape.square,
    this.footer = FooterStyle.caption, this.outline = true, this.tape = false, this.mono = false, this.decos = const [], this.art,
  });

  /// Size of the strip in PhotoStrip design units (always 200 wide).
  Size get designSize => Size(200, art == null ? 620 : 200 / art!.aspect);
}

const stripCategories = ['精選', '可愛', '經典', '生日', '應援'];

const _navy = Color(0xFF1F1D2B);

const stripTemplates = [
  // Featured illustrated templates
  StripTemplate(
    name: 'Cat Party', category: '精選', caption: '', frame: Color(0xFFF9D3D6), cell: Color(0xFFFFE9E9),
    art: ArtFrame('assets/templates/t1-cat-party.webp', 0.3304, [Rect.fromLTWH(0.1005, 0.055, 0.8007, 0.2003), Rect.fromLTWH(0.1005, 0.2815, 0.8015, 0.2001), Rect.fromLTWH(0.1005, 0.5086, 0.8015, 0.1959), Rect.fromLTWH(0.1005, 0.7319, 0.8015, 0.2001)]),
  ),
  StripTemplate(
    name: 'Morning Friends', category: '精選', caption: '', frame: Color(0xFFFBE3D8), cell: Color(0xFFFFF6EC),
    art: ArtFrame('assets/templates/t2-morning-friends.webp', 0.3304, [Rect.fromLTWH(0.1149, 0.0631, 0.772, 0.1906), Rect.fromLTWH(0.1149, 0.2824, 0.772, 0.1903), Rect.fromLTWH(0.1149, 0.5017, 0.772, 0.1881), Rect.fromLTWH(0.1149, 0.7188, 0.772, 0.1889)]),
  ),
  StripTemplate(
    name: 'Birthday Party', category: '精選', caption: '', frame: Color(0xFFE7C3EC), cell: Color(0xFFFBEAF4),
    art: ArtFrame('assets/templates/t3-birthday-party.webp', 0.3304, [Rect.fromLTWH(0.1301, 0.082, 0.7399, 0.1875), Rect.fromLTWH(0.1301, 0.2919, 0.7399, 0.1875), Rect.fromLTWH(0.1301, 0.5017, 0.7399, 0.1875), Rect.fromLTWH(0.1301, 0.7115, 0.7399, 0.1872)]),
  ),
  StripTemplate(
    name: 'Strawberry Picnic', category: '精選', caption: '', frame: Color(0xFFF4A3A3), cell: Color(0xFFFFF2EF),
    art: ArtFrame('assets/templates/t4-strawberry-picnic.webp', 0.3304, [Rect.fromLTWH(0.114, 0.0424, 0.7728, 0.195), Rect.fromLTWH(0.1132, 0.2656, 0.7736, 0.195), Rect.fromLTWH(0.1132, 0.4874, 0.7736, 0.1864), Rect.fromLTWH(0.1132, 0.7003, 0.7728, 0.1864)]),
  ),
  StripTemplate(
    name: 'Dreamy Space', category: '精選', caption: '', frame: Color(0xFFB8AEE3), cell: Color(0xFFEAE5F8),
    art: ArtFrame('assets/templates/t5-dreamy-space.webp', 0.3304, [Rect.fromLTWH(0.0997, 0.0438, 0.8007, 0.1989), Rect.fromLTWH(0.0997, 0.267, 0.8007, 0.1989), Rect.fromLTWH(0.0997, 0.4897, 0.8007, 0.1967), Rect.fromLTWH(0.0997, 0.7098, 0.8007, 0.197)]),
  ),
  StripTemplate(
    name: 'Forest Camping', category: '精選', caption: '', frame: Color(0xFF8FA996), cell: Color(0xFFEEF3EB),
    art: ArtFrame('assets/templates/t6-forest-camping.webp', 0.3304, [Rect.fromLTWH(0.1486, 0.077, 0.7027, 0.1844), Rect.fromLTWH(0.1486, 0.2919, 0.7027, 0.1878), Rect.fromLTWH(0.1486, 0.5081, 0.7027, 0.1822), Rect.fromLTWH(0.1486, 0.7188, 0.7027, 0.1825)]),
  ),
  StripTemplate(
    name: 'Ocean Summer', category: '精選', caption: '', frame: Color(0xFFA9DDF0), cell: Color(0xFFE6F5FB),
    art: ArtFrame('assets/templates/t7-ocean-summer.webp', 0.3112, [Rect.fromLTWH(0.0966, 0.0469, 0.8068, 0.1922), Rect.fromLTWH(0.0966, 0.2673, 0.8068, 0.1916), Rect.fromLTWH(0.0966, 0.4854, 0.8068, 0.1919), Rect.fromLTWH(0.0966, 0.7053, 0.8068, 0.1845)]),
  ),
  StripTemplate(
    name: 'Classic Film', category: '精選', caption: '', frame: Color(0xFF6C6A78), cell: Color(0xFF3A3746),
    art: ArtFrame('assets/templates/t8-classic-film.webp', 0.3306, [Rect.fromLTWH(0.1588, 0.0262, 0.6824, 0.2089), Rect.fromLTWH(0.1588, 0.2577, 0.6824, 0.2075), Rect.fromLTWH(0.1588, 0.4881, 0.6824, 0.1985), Rect.fromLTWH(0.1588, 0.7079, 0.6824, 0.198)]),
  ),
  // Cute
  StripTemplate(name: 'Peach', category: '可愛', caption: 'cute caption ♡', frame: Color(0xFFF9CACB), cell: sky, tape: true),
  StripTemplate(name: 'Coral', category: '可愛', caption: 'little moments', frame: Color(0xFFF2867B), cell: Color(0xFFF8D0D4), captionColor: Colors.white),
  StripTemplate(
    name: 'Paw Party', category: '可愛', caption: 'PICO SNAP', subtitle: 'meow meow',
    frame: Color(0xFFFAD9D7), cell: Color(0xFF2A2730), pattern: FramePattern.paws, patternColor: Color(0xFFFFF4F2),
    cellShape: CellShape.wavy, footer: FooterStyle.title, captionColor: Color(0xFF2D3FA8), outline: false,
    decos: [
      Deco('assets/stickers/bunny.png', Offset(34, 138), size: 52, angle: -.2),
      Deco('assets/stickers/bear.png', Offset(168, 408), size: 56, angle: .15),
      Deco('assets/stickers/heart.png', Offset(176, 286), size: 26, angle: .2),
    ],
  ),
  StripTemplate(
    name: 'Morning', category: '可愛', caption: 'have a nice day',
    frame: Color(0xFFF4BCC4), cell: Colors.white, pattern: FramePattern.confetti, patternColor: Color(0xFFE3707F),
    outline: false,
    decos: [
      Deco.bubble('say cheese~', Offset(58, 34), angle: -.08),
      Deco('assets/stickers/egg.png', Offset(178, 300), size: 48, angle: .2),
      Deco('assets/stickers/daisy.png', Offset(22, 444), size: 34),
    ],
  ),
  StripTemplate(
    name: 'Confetti', category: '可愛', caption: 'so pretty!',
    frame: Color(0xFFD5C4EE), cell: Colors.white, pattern: FramePattern.confetti, patternColor: Color(0xFF8E73C9),
    cellShape: CellShape.rounded, outline: false,
    decos: [
      Deco('assets/stickers/strawberry.png', Offset(178, 160), size: 38, angle: .25),
      Deco('assets/stickers/cloud.png', Offset(30, 26), size: 40, angle: -.1),
      Deco('assets/stickers/sparkle.png', Offset(24, 560), size: 34),
    ],
  ),
  // Classic photo booth prints
  StripTemplate(name: 'Classic', category: '經典', caption: '', frame: _navy, cell: Color(0xFF3A3746), footer: FooterStyle.logoDate, captionColor: Colors.white, outline: false),
  StripTemplate(name: 'Mono', category: '經典', caption: '', frame: _navy, cell: Color(0xFF55525C), footer: FooterStyle.logoDate, captionColor: Colors.white, outline: false, mono: true),
  StripTemplate(
    name: 'Forest', category: '經典', caption: 'SLOW DAYS', subtitle: 'ready to rest',
    frame: Color(0xFF1F4D3A), cell: Color(0xFFF2F2F2), footer: FooterStyle.title, captionColor: Colors.white, outline: false,
    decos: [Deco('assets/stickers/bear.png', Offset(178, 470), size: 40, angle: .12)],
  ),
  // Birthday
  StripTemplate(
    name: 'Birthday Pop', category: '生日', caption: 'HAPPY DAY', subtitle: 'make a wish ♡',
    frame: Color(0xFFF6A6C9), frame2: Color(0xFFB79BE8), cell: Color(0xFFFFF4D6), cellShape: CellShape.cloud,
    footer: FooterStyle.title, captionColor: Colors.white, outline: false,
    decos: [
      Deco('assets/stickers/cake.png', Offset(176, 150), size: 42, angle: .15),
      Deco('assets/stickers/bow.png', Offset(24, 290), size: 38, angle: -.2),
      Deco('assets/stickers/sparkle.png', Offset(178, 428), size: 34),
    ],
  ),
  StripTemplate(
    name: 'Butter Cake', category: '生日', caption: 'make a wish',
    frame: Color(0xFFFBE7A6), cell: Colors.white, pattern: FramePattern.dots, patternColor: Color(0xFFFFF8DC),
    cellShape: CellShape.rounded,
    decos: [
      Deco('assets/stickers/cake.png', Offset(24, 300), size: 40, angle: -.15),
      Deco('assets/stickers/star.png', Offset(176, 26), size: 32, angle: .2),
    ],
  ),
  // Cheering
  StripTemplate(
    name: 'Ocean Cheer', category: '應援', caption: 'FIGHTING!', subtitle: 'you got this',
    frame: Color(0xFF9FD0EE), frame2: Color(0xFFC9B6EE), cell: Colors.white, cellShape: CellShape.rounded,
    footer: FooterStyle.title, captionColor: Colors.white, outline: false,
    decos: [
      Deco('assets/stickers/heart.png', Offset(178, 160), size: 32, angle: .2),
      Deco('assets/stickers/star.png', Offset(22, 432), size: 32, angle: -.2),
    ],
  ),
  StripTemplate(
    name: 'Mint Club', category: '應援', caption: '',
    frame: Color(0xFFCDE9D9), cell: Colors.white, pattern: FramePattern.stripes, patternColor: Color(0xFFE6F4EC),
    footer: FooterStyle.logoDate, captionColor: Color(0xFF2F5D49), outline: false,
    decos: [Deco('assets/stickers/sparkle.png', Offset(178, 26), size: 28)],
  ),
];

class GinghamPattern {
  final String name;
  final Color base;
  final Color? right;
  const GinghamPattern(this.name, this.base, [this.right]);
}

const ginghamPatterns = [
  GinghamPattern('Duo', Color(0xFFD9CBF2), Color(0xFFCADDC4)),
  GinghamPattern('Lemon', Color(0xFFFFE08A)),
  GinghamPattern('Peach', Color(0xFFFFC2C7)),
  GinghamPattern('Sky', Color(0xFFB9DDF5)),
  GinghamPattern('Lilac', Color(0xFFD9CBF2)),
  GinghamPattern('Mint', Color(0xFFC5E8D2)),
];

const backdrops = <(String, Color)>[
  ('White', Color(0xFFFFFFFF)),
  ('Beige', Color(0xFFEFE5D7)),
  ('Tan', Color(0xFFD9C3A5)),
  ('Black', Color(0xFF2B2422)),
];

const formats = <(String, double)>[('9:16', 9 / 16), ('1:1', 1), ('4:5', 4 / 5), ('3:4', 3 / 4)];

String _hand(String name) => 'assets/stickers/$name.png';

/// Sticker packs: hand-drawn stickers are asset paths, the rest are emoji.
/// Each entry is (chip icon, label, stickers).
final stickerPacks = <(String, String, List<String>)>[
  ('✨', '最愛', [for (final n in ['bunny', 'bear', 'ice_cream', 'strawberry', 'egg', 'tulip', 'daisy', 'cloud', 'star', 'heart', 'bow', 'sparkle', 'cherry', 'cake', 'camera', 'letter']) _hand(n)]),
  ('🐱', '動物', [_hand('bunny'), _hand('bear'), '🐱', '🐶', '🐥', '🐹', '🦄', '🐼', '🐨', '🐸', '🐧', '🦊']),
  ('🌸', '裝飾', [_hand('star'), _hand('heart'), _hand('bow'), _hand('sparkle'), _hand('cloud'), _hand('letter'), _hand('camera'), _hand('daisy'), _hand('tulip'), '🌈', '💌', '🫧']),
  ('🍰', '食物', [_hand('ice_cream'), _hand('strawberry'), _hand('egg'), _hand('cherry'), _hand('cake'), '🧁', '🍩', '🍑', '🧋', '🍪', '🍭', '🥞']),
];

/// Stickers the user cut out of their own photos on the 我的素材 page, keyed
/// by sticker id (`my:<key>`) → PNG. Managed (and saved) by MyLibrary.
final customStickers = <String, Uint8List>{};

/// Templates the user designed on the 我的素材 page. Managed by MyLibrary.
final customTemplates = <CustomTemplate>[];

const myCategory = '我的';

/// Built-in strip templates followed by the user's own.
List<StripTemplate> get allStripTemplates => [...stripTemplates, for (final t in customTemplates) t.template];

/// A strip template the user designed: just the choices they made; the
/// colours of the cells, pattern and text are worked out from the frame.
class CustomTemplate {
  final String id, caption;
  final Color frame;
  /// Bottom colour of a vertical gradient; null for a plain frame.
  final Color? frame2;
  final FramePattern pattern;
  final CellShape cellShape;
  final FooterStyle footer;
  /// Up to [decoSpots].length sticker ids printed on the frame.
  final List<String> stickers;
  const CustomTemplate({
    required this.id, this.caption = '', required this.frame, this.frame2, this.pattern = FramePattern.none,
    this.cellShape = CellShape.square, this.footer = FooterStyle.caption, this.stickers = const [],
  });

  /// Where printed stickers go, in PhotoStrip design units, with their tilt.
  static const decoSpots = [(Offset(26, 26), -.2), (Offset(176, 300), .15), (Offset(24, 470), -.1)];

  StripTemplate get template {
    final darkTop = frame.computeLuminance() < .4;
    final darkBottom = (frame2 ?? frame).computeLuminance() < .4;
    return StripTemplate(
      name: '我的模板', category: myCategory, caption: caption,
      frame: frame, frame2: frame2,
      cell: darkTop ? Color.lerp(frame, Colors.white, .15)! : Colors.white,
      captionColor: darkBottom ? Colors.white : ink,
      pattern: pattern,
      patternColor: darkTop ? Colors.white.withValues(alpha: .35) : Color.lerp(frame, Colors.white, .6)!,
      cellShape: cellShape, footer: footer, outline: !darkTop,
      decos: [
        for (var i = 0; i < stickers.length && i < decoSpots.length; i++)
          Deco(stickers[i], decoSpots[i].$1, size: 40, angle: decoSpots[i].$2),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id, 'caption': caption, 'frame': frame.toARGB32(), 'frame2': frame2?.toARGB32(),
    'pattern': pattern.name, 'cellShape': cellShape.name, 'footer': footer.name, 'stickers': stickers,
  };

  factory CustomTemplate.fromJson(Map<String, Object?> j) => CustomTemplate(
    id: j['id']! as String,
    caption: j['caption'] as String? ?? '',
    frame: Color(j['frame']! as int),
    frame2: j['frame2'] == null ? null : Color(j['frame2']! as int),
    pattern: FramePattern.values.byName(j['pattern']! as String),
    cellShape: CellShape.values.byName(j['cellShape']! as String),
    footer: FooterStyle.values.byName(j['footer']! as String),
    stickers: [for (final s in j['stickers'] as List? ?? const []) s as String],
  );
}

/// A sticker placed on the canvas. [center] is normalised (0–1) so it
/// survives the canvas resizing, e.g. when the keyboard opens.
class StickerData {
  /// An asset path for hand-drawn stickers, otherwise an emoji.
  final String sticker;
  final Offset center;
  final double scale, rotation;
  /// Mirrored left to right.
  final bool flipped;
  const StickerData({required this.sticker, required this.center, this.scale = 1, this.rotation = 0, this.flipped = false});

  StickerData copyWith({Offset? center, double? scale, double? rotation, bool? flipped}) => StickerData(
    sticker: sticker,
    center: center ?? this.center,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
    flipped: flipped ?? this.flipped,
  );
}
