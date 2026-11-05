import 'dart:math';
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

enum FramePattern { none, dots, paws, confetti, gingham, stripes, hearts, stars, flowers, checker, waves }

/// What sits in the strip's bottom margin.
enum FooterStyle {
  /// Handwritten caption.
  caption,
  /// 快趣拍 wordmark with the date, like a classic photo booth print.
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
  final bool bubble, flipped;
  const Deco(this.content, this.center, {this.size = 44, this.angle = 0, this.flipped = false}) : bubble = false;
  const Deco.bubble(this.content, this.center, {this.size = 15, this.angle = 0}) : bubble = true, flipped = false;
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

const stripCategories = ['精選', '日常可愛', '底片復古', '黑白', '生日派對', '婚禮', '畢業', '節慶', 'Y2K'];

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
  // Themed strips drawn with Gemini, quiet paper-print style.
  // 日常可愛
  StripTemplate(name: 'Picnic Day Paper', category: '日常可愛', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/picnic-day-b.webp', 0.3673, [Rect.fromLTWH(0.2086, 0.0415, 0.5829, 0.1867), Rect.fromLTWH(0.2108, 0.2573, 0.5785, 0.1859), Rect.fromLTWH(0.213, 0.4718, 0.5741, 0.1855), Rect.fromLTWH(0.2097, 0.6863, 0.5807, 0.1859)])),
  StripTemplate(name: 'Bestie Paper', category: '日常可愛', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/bestie-b.webp', 0.3668, [Rect.fromLTWH(0.2066, 0.0423, 0.5857, 0.187), Rect.fromLTWH(0.2088, 0.2576, 0.5813, 0.1866), Rect.fromLTWH(0.2099, 0.472, 0.5791, 0.1862), Rect.fromLTWH(0.2077, 0.6864, 0.5846, 0.1862)])),
  // 底片復古
  StripTemplate(name: 'Vintage Film Paper', category: '底片復古', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/vintage-film-b.webp', 0.4444, [Rect.fromLTWH(0.1577, 0.0196, 0.673, 0.2194), Rect.fromLTWH(0.1577, 0.2626, 0.673, 0.2162), Rect.fromLTWH(0.1586, 0.5016, 0.6721, 0.2166), Rect.fromLTWH(0.1586, 0.741, 0.6721, 0.217)])),
  StripTemplate(name: 'Kodak Yellow Paper', category: '底片復古', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/kodak-yellow-b.webp', 0.3678, [Rect.fromLTWH(0.2059, 0.0407, 0.586, 0.1882), Rect.fromLTWH(0.2081, 0.2562, 0.5827, 0.1873), Rect.fromLTWH(0.2081, 0.4706, 0.5816, 0.1873), Rect.fromLTWH(0.207, 0.6853, 0.5838, 0.1873)])),
  // 黑白
  StripTemplate(name: 'Darkroom Paper', category: '黑白', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/darkroom-b.webp', 0.3664, [Rect.fromLTWH(0.214, 0.0464, 0.571, 0.1812), Rect.fromLTWH(0.2151, 0.26, 0.5677, 0.1816), Rect.fromLTWH(0.2172, 0.4728, 0.5633, 0.18), Rect.fromLTWH(0.2151, 0.6848, 0.5677, 0.1812)])),
  StripTemplate(name: 'Paper Mono Paper', category: '黑白', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/paper-mono-b.webp', 0.3693, [Rect.fromLTWH(0.2061, 0.0415, 0.5812, 0.1869), Rect.fromLTWH(0.2061, 0.2557, 0.5812, 0.1865), Rect.fromLTWH(0.2061, 0.47, 0.5812, 0.1865), Rect.fromLTWH(0.2072, 0.6843, 0.5823, 0.1865)])),
  // 生日派對
  StripTemplate(name: 'Pastel Party Paper', category: '生日派對', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/pastel-party-b.webp', 0.3643, [Rect.fromLTWH(0.2073, 0.0422, 0.5854, 0.1867), Rect.fromLTWH(0.2106, 0.257, 0.5788, 0.1855), Rect.fromLTWH(0.2117, 0.4699, 0.5766, 0.1847), Rect.fromLTWH(0.2095, 0.6823, 0.581, 0.1855)])),
  StripTemplate(name: 'Gold Balloon Paper', category: '生日派對', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/gold-balloon-b.webp', 0.3684, [Rect.fromLTWH(0.2099, 0.0429, 0.578, 0.1846), Rect.fromLTWH(0.2121, 0.2591, 0.5736, 0.1838), Rect.fromLTWH(0.2132, 0.4733, 0.5725, 0.183), Rect.fromLTWH(0.211, 0.6874, 0.578, 0.1842)])),
  // 婚禮
  StripTemplate(name: 'Ivory Lace Paper', category: '婚禮', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/ivory-lace-b.webp', 0.3674, [Rect.fromLTWH(0.2068, 0.0457, 0.5842, 0.1783), Rect.fromLTWH(0.209, 0.2607, 0.5809, 0.1807), Rect.fromLTWH(0.2101, 0.4766, 0.5776, 0.1807), Rect.fromLTWH(0.209, 0.6932, 0.5831, 0.1807)])),
  StripTemplate(name: 'Garden Bloom Paper', category: '婚禮', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/garden-bloom-b.webp', 0.3681, [Rect.fromLTWH(0.2057, 0.0411, 0.5842, 0.1877), Rect.fromLTWH(0.2079, 0.2565, 0.581, 0.1873), Rect.fromLTWH(0.209, 0.4712, 0.5788, 0.1869), Rect.fromLTWH(0.2079, 0.6855, 0.5821, 0.1869)])),
  // 畢業
  StripTemplate(name: 'Class Of Paper', category: '畢業', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/class-of-b.webp', 0.3893, [Rect.fromLTWH(0.2112, 0.03, 0.5776, 0.1944), Rect.fromLTWH(0.2145, 0.2587, 0.5732, 0.1944), Rect.fromLTWH(0.2156, 0.4861, 0.571, 0.194), Rect.fromLTWH(0.2134, 0.7135, 0.5776, 0.1953)])),
  // 節慶
  StripTemplate(name: 'Cozy Christmas Paper', category: '節慶', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/cozy-christmas-b.webp', 0.3738, [Rect.fromLTWH(0.2075, 0.0431, 0.5829, 0.1892), Rect.fromLTWH(0.2097, 0.2626, 0.5785, 0.1888), Rect.fromLTWH(0.2108, 0.4813, 0.5752, 0.1883), Rect.fromLTWH(0.2097, 0.6992, 0.5796, 0.1888)])),
  StripTemplate(name: 'New Year Red Paper', category: '節慶', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/new-year-red-b.webp', 0.3707, [Rect.fromLTWH(0.2118, 0.0417, 0.5753, 0.1833), Rect.fromLTWH(0.214, 0.2574, 0.571, 0.1837), Rect.fromLTWH(0.2151, 0.4719, 0.5677, 0.1833), Rect.fromLTWH(0.2129, 0.6868, 0.5731, 0.1845)])),
  // Y2K
  StripTemplate(name: 'Jelly Pink Paper', category: 'Y2K', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/jelly-pink-b.webp', 0.3696, [Rect.fromLTWH(0.2199, 0.0469, 0.5711, 0.182), Rect.fromLTWH(0.221, 0.2645, 0.5678, 0.1803), Rect.fromLTWH(0.2221, 0.4792, 0.5656, 0.1795), Rect.fromLTWH(0.2199, 0.6935, 0.5711, 0.1799)])),
  StripTemplate(name: 'Cyber Blue Paper', category: 'Y2K', caption: '', frame: Colors.white, cell: Color(0xFFEDEAE4),
    art: ArtFrame('assets/templates/cyber-blue-b.webp', 0.3689, [Rect.fromLTWH(0.216, 0.0639, 0.5691, 0.1606), Rect.fromLTWH(0.216, 0.2795, 0.568, 0.161), Rect.fromLTWH(0.216, 0.4947, 0.5691, 0.161), Rect.fromLTWH(0.216, 0.71, 0.5691, 0.1606)])),
];

/// Strips drawn in code: where the user's own templates start from, and the
/// home page's sample. Not offered as templates themselves any more.
const drawnTemplates = [
  // Cute
  StripTemplate(name: 'Peach', category: '可愛', caption: 'cute caption ♡', frame: Color(0xFFF9CACB), cell: sky, tape: true),
  StripTemplate(name: 'Coral', category: '可愛', caption: 'little moments', frame: Color(0xFFF2867B), cell: Color(0xFFF8D0D4), captionColor: Colors.white),
  StripTemplate(
    name: 'Paw Party', category: '可愛', caption: '快趣拍', subtitle: 'meow meow',
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


/// Stickers the user cut out of their own photos on the 我的素材 page, keyed
/// by sticker id (`my:<key>`) → PNG. Managed (and saved) by MyLibrary.
// Null means an on-disk sticker: decode it only when a view needs it.
final customStickers = <String, Uint8List?>{};

/// The user's own sticker sheets: named groups of their stickers, shown as
/// pages of the sticker book. A sticker in no sheet goes on [unsortedSheet].
class MySheet {
  final String id;
  final String name;
  /// Sticker ids, in the order they sit on the sheet.
  final List<String> stickers;
  const MySheet({required this.id, required this.name, this.stickers = const []});

  MySheet copyWith({String? name, List<String>? stickers}) => MySheet(id: id, name: name ?? this.name, stickers: stickers ?? this.stickers);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'stickers': stickers};
  factory MySheet.fromJson(Map<String, Object?> j) =>
      MySheet(id: j['id'] as String, name: j['name'] as String, stickers: [for (final s in j['stickers'] as List) s as String]);
}

const unsortedSheet = '未分類';

/// The user's sheets, in order (see MyLibrary).
final mySheets = <MySheet>[];

/// Names the user gave their stickers, by sticker id.
final stickerNames = <String, String>{};

/// The sheets as shown: the user's, then 未分類 for stickers in none (if any).
List<MySheet> get shownSheets {
  final placed = {for (final s in mySheets) ...s.stickers};
  final loose = [for (final id in customStickers.keys) if (!placed.contains(id)) id];
  return [
    for (final s in mySheets) s.copyWith(stickers: [for (final id in s.stickers) if (customStickers.containsKey(id)) id]),
    if (loose.isNotEmpty) MySheet(id: '', name: unsortedSheet, stickers: loose),
  ];
}
final customStickerPaths = <String, String>{};

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
  /// Stickers printed on the strip, placed like stickers on a canvas
  /// ([StickerData.center] normalised over the 200 × 620 strip).
  final List<StickerData> stickers;
  const CustomTemplate({
    required this.id, this.caption = '', required this.frame, this.frame2, this.pattern = FramePattern.none,
    this.cellShape = CellShape.square, this.footer = FooterStyle.caption, this.stickers = const [],
  });

  static const _strip = Size(200, 620);

  /// Sticker size at scale 1 on the strip; the same rule StickerItem uses,
  /// so stickers print exactly as they were placed.
  static final stickerBase = max(_strip.shortestSide * .2, _strip.longestSide * .12);

  /// Where the old fixed-spot stickers went (templates saved before stickers
  /// could be placed freely).
  static const _oldSpots = [(Offset(26, 26), -.2), (Offset(176, 300), .15), (Offset(24, 470), -.1)];

  /// A starting point copied from a built-in drawn template.
  factory CustomTemplate.from(StripTemplate t) => CustomTemplate(
    id: '', caption: t.caption, frame: t.frame, frame2: t.frame2, pattern: t.pattern, cellShape: t.cellShape, footer: t.footer,
    stickers: [
      for (final d in t.decos)
        if (!d.bubble)
          StickerData(
            sticker: d.content, center: Offset(d.center.dx / _strip.width, d.center.dy / _strip.height),
            scale: d.size / stickerBase, rotation: d.angle, flipped: d.flipped,
          ),
    ],
  );

  CustomTemplate copyWith({String? id, String? caption, Color? frame, Color? Function()? frame2, FramePattern? pattern,
      CellShape? cellShape, FooterStyle? footer, List<StickerData>? stickers}) => CustomTemplate(
    id: id ?? this.id, caption: caption ?? this.caption, frame: frame ?? this.frame,
    frame2: frame2 == null ? this.frame2 : frame2(), pattern: pattern ?? this.pattern,
    cellShape: cellShape ?? this.cellShape, footer: footer ?? this.footer, stickers: stickers ?? this.stickers,
  );

  StripTemplate get template {
    final darkTop = frame.computeLuminance() < .4;
    final darkBottom = (frame2 ?? frame).computeLuminance() < .4;
    return StripTemplate(
      name: '我的模板', category: myCategory, caption: caption,
      frame: frame, frame2: frame2,
      cell: darkTop ? Color.lerp(frame, Colors.white, .15)! : Colors.white,
      captionColor: darkBottom ? Colors.white : ink,
      pattern: pattern,
      // A frame almost white (cream) can't take a whiter pattern: a darker tint.
      patternColor: darkTop ? Colors.white.withValues(alpha: .35)
          : frame.computeLuminance() > .8 ? Color.lerp(frame, const Color(0xFFD9BFA8), .55)!
          : Color.lerp(frame, Colors.white, .6)!,
      cellShape: cellShape, footer: footer, outline: !darkTop,
      decos: [
        for (final s in stickers)
          Deco(s.sticker, Offset(s.center.dx * _strip.width, s.center.dy * _strip.height),
            size: stickerBase * s.scale, angle: s.rotation, flipped: s.flipped),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id, 'caption': caption, 'frame': frame.toARGB32(), 'frame2': frame2?.toARGB32(),
    'pattern': pattern.name, 'cellShape': cellShape.name, 'footer': footer.name,
    'decos': [
      for (final s in stickers)
        {'sticker': s.sticker, 'x': s.center.dx, 'y': s.center.dy, 'scale': s.scale, 'rotation': s.rotation, 'flipped': s.flipped},
    ],
  };

  factory CustomTemplate.fromJson(Map<String, Object?> j) => CustomTemplate(
    id: j['id']! as String,
    caption: j['caption'] as String? ?? '',
    frame: Color(j['frame']! as int),
    frame2: j['frame2'] == null ? null : Color(j['frame2']! as int),
    pattern: FramePattern.values.byName(j['pattern']! as String),
    cellShape: CellShape.values.byName(j['cellShape']! as String),
    footer: FooterStyle.values.byName(j['footer']! as String),
    stickers: j['decos'] is List
      ? [
          for (final d in (j['decos']! as List).cast<Map>())
            StickerData(
              sticker: d['sticker'] as String, center: Offset((d['x'] as num).toDouble(), (d['y'] as num).toDouble()),
              scale: (d['scale'] as num).toDouble(), rotation: (d['rotation'] as num).toDouble(), flipped: d['flipped'] == true,
            ),
        ]
      : [
          // Saved before free placement: a list of sticker ids in fixed spots.
          for (final (i, s) in (j['stickers'] as List? ?? const []).indexed)
            if (i < _oldSpots.length)
              StickerData(
                sticker: s as String, center: Offset(_oldSpots[i].$1.dx / _strip.width, _oldSpots[i].$1.dy / _strip.height),
                scale: 40 / stickerBase, rotation: _oldSpots[i].$2,
              ),
        ],
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

  StickerData copyWith({String? sticker, Offset? center, double? scale, double? rotation, bool? flipped}) => StickerData(
    sticker: sticker ?? this.sticker,
    center: center ?? this.center,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
    flipped: flipped ?? this.flipped,
  );
}
