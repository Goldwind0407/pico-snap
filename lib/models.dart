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
  const StripTemplate({
    required this.name, required this.category, required this.caption, this.subtitle = '',
    required this.frame, this.frame2, required this.cell, this.captionColor = ink,
    this.pattern = FramePattern.none, this.patternColor = Colors.white, this.cellShape = CellShape.square,
    this.footer = FooterStyle.caption, this.outline = true, this.tape = false, this.mono = false, this.decos = const [],
  });
}

const stripCategories = ['可愛', '經典', '生日', '應援'];

const _navy = Color(0xFF1F1D2B);

const stripTemplates = [
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

/// A sticker placed on the canvas. [center] is normalised (0–1) so it
/// survives the canvas resizing, e.g. when the keyboard opens.
class StickerData {
  /// An asset path for hand-drawn stickers, otherwise an emoji.
  final String sticker;
  final Offset center;
  final double scale, rotation;
  const StickerData({required this.sticker, required this.center, this.scale = 1, this.rotation = 0});

  StickerData copyWith({Offset? center, double? scale, double? rotation}) => StickerData(
    sticker: sticker,
    center: center ?? this.center,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
  );
}
