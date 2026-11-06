import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'cutout_page.dart' show bakeStickerStyled;
import 'grabcut.dart';
import 'sticker_shape.dart';
import 'subject_segmenter.dart';

/// 照片貼紙: someone (or something) cut out of the user's photo, worn as a
/// sticker on the page: its border, finish and how it moves can change at
/// any time, since the cut-out itself is kept.
///
/// On the page it is a sticker whose id is `cut:<key>`; [PhotoStickers]
/// holds what each id is while a piece is being edited.

/// How wide the border is, relative to the sticker's long side.
enum StickerEdge {
  none('無', 0),
  thin('細', .014),
  thick('粗', .03);

  final String label;
  final double size;
  const StickerEdge(this.label, this.size);
}

/// Border colours: white like a real sticker, then pastels and ink.
const stickerEdgeColors = <Color>[
  Colors.white, Color(0xFFFFC6D9), Color(0xFFFFE08A), Color(0xFFBFE3FF),
  Color(0xFFC8EBC9), Color(0xFFDCC9F5), Color(0xFF3A2E2A),
];

/// How the sticker moves in the motion video (and on screen).
enum StickerMotion {
  none('不動', CupertinoIcons.pause),
  bounce('彈跳', CupertinoIcons.arrow_up_down),
  wiggle('搖擺', CupertinoIcons.arrow_2_squarepath),
  float('漂浮', CupertinoIcons.cloud),
  spin('轉圈', CupertinoIcons.arrow_clockwise),
  pulse('心跳', CupertinoIcons.heart);

  final String label;
  final IconData icon;
  const StickerMotion(this.label, this.icon);
}

@immutable
class PhotoSticker {
  /// The cut-out subject: an image with a transparent background (or any
  /// picture, which then becomes a rectangle).
  final Uint8List cut;
  /// The photo it was cut from, to fix its edge; null for old pieces.
  final Uint8List? source;
  final StickerEdge edge;
  final int color;
  final StickerFinish finish;
  final StickerMotion motion;
  const PhotoSticker({required this.cut, this.source, this.edge = StickerEdge.thick, this.color = 0, this.finish = StickerFinish.matte, this.motion = StickerMotion.none});

  PhotoSticker copyWith({Uint8List? cut, StickerEdge? edge, int? color, StickerFinish? finish, StickerMotion? motion}) => PhotoSticker(
    cut: cut ?? this.cut, source: source, edge: edge ?? this.edge, color: color ?? this.color,
    finish: finish ?? this.finish, motion: motion ?? this.motion,
  );

  Color get edgeColor => stickerEdgeColors[color.clamp(0, stickerEdgeColors.length - 1)];

  /// The look, without the pictures (they are files in a draft).
  Map<String, Object?> styleJson() => {'edge': edge.name, 'color': color, 'finish': finish.name, 'motion': motion.name};

  factory PhotoSticker.fromJson(Map<String, Object?> json, Uint8List cut, Uint8List? source) => PhotoSticker(
    cut: cut, source: source,
    edge: StickerEdge.values.asNameMap()[json['edge']] ?? StickerEdge.thick,
    color: (json['color'] as int? ?? 0).clamp(0, stickerEdgeColors.length - 1),
    finish: StickerFinish.values.asNameMap()[json['finish']] ?? StickerFinish.matte,
    motion: StickerMotion.values.asNameMap()[json['motion']] ?? StickerMotion.none,
  );

  @override
  bool operator ==(Object other) => other is PhotoSticker && identical(other.cut, cut) && identical(other.source, source) &&
      other.edge == edge && other.color == color && other.finish == finish && other.motion == motion;

  @override
  int get hashCode => Object.hash(identityHashCode(cut), identityHashCode(source), edge, color, finish, motion);
}

bool isPhotoSticker(String id) => id.startsWith('cut:');

/// The photo stickers of the piece being edited, and their pictures.
abstract final class PhotoStickers {
  static final items = <String, PhotoSticker>{};
  /// Print a cutting line around each one (a sticker sheet).
  static bool cutLines = false;
  static final _art = <String, (Object, ui.Image)>{};
  static final _baking = <String, Object>{};
  /// Ticks when a picture is ready or the stickers change.
  static final changes = ValueNotifier(0);
  /// Where in its motion every sticker is (0–1), for the motion video and
  /// saving; null: moving by itself.
  static final clock = ValueNotifier<double?>(null);
  static var _serial = 0;

  static String newId() => 'cut:${DateTime.now().microsecondsSinceEpoch}_${_serial++}';

  static Object _key(PhotoSticker s) => Object.hash(identityHashCode(s.cut), s.edge, s.color, s.finish, cutLines);

  /// Make [next] the piece's stickers; pictures are made for new looks.
  static void sync(Map<String, PhotoSticker> next, {required bool cutLines}) {
    final linesChanged = PhotoStickers.cutLines != cutLines;
    PhotoStickers.cutLines = cutLines;
    final changed = linesChanged || !mapEquals(items, next);
    if (!changed) return;
    items
      ..clear()
      ..addAll(next);
    for (final id in _art.keys.where((id) => !items.containsKey(id)).toList()) {
      _art.remove(id)?.$2.dispose();
    }
    for (final MapEntry(key: id, value: s) in items.entries) {
      final key = _key(s);
      if (_art[id]?.$1 != key && _baking[id] != key) unawaited(_bake(id, s, key));
    }
    changes.value++;
  }

  static ui.Image? image(String id) => _art[id]?.$2;

  /// Every sticker's picture is up to date.
  static bool get ready => items.entries.every((e) => _art[e.key]?.$1 == _key(e.value));

  /// Waits (a while at most) for the pictures, before saving.
  static Future<void> settle() async {
    for (var i = 0; i < 100 && !ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  static Future<void> _bake(String id, PhotoSticker s, Object key) async {
    _baking[id] = key;
    try {
      final baked = await bakePhotoSticker(s, cutLine: cutLines);
      final image = await _imageFromRgba(baked.rgba, baked.w, baked.h);
      if (_baking[id] != key) return image.dispose();
      _baking.remove(id);
      if (!items.containsKey(id)) return image.dispose();
      _art.remove(id)?.$2.dispose();
      _art[id] = (key, image);
      changes.value++;
    } catch (e) {
      debugPrint('[STICKER] 做不出貼紙: $e');
      if (_baking[id] == key) _baking.remove(id);
    }
  }

  /// The finished sticker as a PNG, for the album or the sticker book.
  static Future<Uint8List?> png(String id) async {
    final s = items[id];
    if (s == null) return null;
    final baked = await bakePhotoSticker(s, cutLine: false);
    final image = await _imageFromRgba(baked.rgba, baked.w, baked.h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  // ---- Tilt, for the shine on 膨膨, 雷射, 亮片 and 寶石 ----

  /// Which way the phone leans (-1–1 each way).
  static final tilt = ValueNotifier(Offset.zero);
  static StreamSubscription<AccelerometerEvent>? _tilt;
  static int _watchers = 0;
  /// Replaces the phone's accelerometer (tests): an empty stream keeps it still.
  @visibleForTesting
  static Stream<AccelerometerEvent>? sensor;

  static void watchTilt() {
    if (_watchers++ > 0) return;
    try {
      _tilt = (sensor ?? accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)).listen((e) {
        final next = Offset((-e.x / 6).clamp(-1.0, 1.0), ((e.y - 6) / 6).clamp(-1.0, 1.0));
        // Smoothed: the shine glides rather than shakes.
        final v = tilt.value + (next - tilt.value) * .25;
        if ((v - tilt.value).distance > .004) tilt.value = v;
      }, onError: (Object _) {}, cancelOnError: true);
    } catch (_) {
      // No sensor (tests, desktop): the shine stays put.
    }
  }

  static void unwatchTilt() {
    if (--_watchers > 0) return;
    _watchers = 0;
    _tilt?.cancel();
    _tilt = null;
  }
}

Future<ui.Image> _imageFromRgba(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// The cut-out decoded (straight RGBA, alpha as the mask), with room around
/// it for the border, its long side at most [maxSide].
Future<({Uint8List rgba, Uint8List mask, int w, int h})> _decodeCut(Uint8List bytes, {int maxSide = 900}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final s = math.min(1.0, maxSide / math.max(desc.width, desc.height));
  final codec = await desc.instantiateCodec(targetWidth: math.max(1, (desc.width * s).round()), targetHeight: math.max(1, (desc.height * s).round()));
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  final pad = (math.max(image.width, image.height) * .045).ceil() + 2;
  final w = image.width + pad * 2, h = image.height + pad * 2;
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawImage(image, Offset(pad.toDouble(), pad.toDouble()), Paint());
  final padded = await rec.endRecording().toImage(w, h);
  image.dispose();
  final data = (await padded.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  padded.dispose();
  final mask = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    mask[i] = data[i * 4 + 3];
    data[i * 4 + 3] = 255;
  }
  return (rgba: data, mask: mask, w: w, h: h);
}

/// [s] with its border and finish, as premultiplied RGBA cropped to it.
Future<({Uint8List rgba, int w, int h})> bakePhotoSticker(PhotoSticker s, {required bool cutLine}) async {
  final cut = await _decodeCut(s.cut);
  return compute(bakeStickerStyled, (rgba: cut.rgba, mask: cut.mask, w: cut.w, h: cut.h,
    border: s.edge.size, finish: s.finish, edge: s.edgeColor.toARGB32(), cutLine: cutLine));
}

/// Cuts everyone and everything out of [photo] by itself: the phone's AI,
/// else GrabCut. Each one is a PNG of it on a transparent background, the
/// biggest first, at most [limit]. Nothing found: the photo as it is.
Future<List<Uint8List>> autoCutouts(Uint8List photo, {int limit = 4}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(photo);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final long = math.max(desc.width, desc.height);
  Future<ui.Image> decode(int side) async {
    final s = math.min(1.0, side / long);
    final codec = await desc.instantiateCodec(targetWidth: math.max(1, (desc.width * s).round()), targetHeight: math.max(1, (desc.height * s).round()));
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  }

  // Found at a small size, cut at a bigger one.
  final small = await decode(560);
  final sw = small.width, sh = small.height;
  final srgba = (await small.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  small.dispose();
  for (var i = 3; i < srgba.length; i += 4) {
    srgba[i] = 255;
  }
  List<Uint8List>? found = await SubjectSegmenter.subjects(srgba, sw, sh);
  if (found == null || found.isEmpty) {
    final fg = await compute(_grabJob, (rgba: srgba, w: sw, h: sh));
    found = await compute(_splitJob, (fg: fg, w: sw, h: sh));
  }
  // Specks and slivers aren't anyone.
  final masks = [for (final m in found!) if (_area(m) > sw * sh * .02) m].take(limit).toList();
  final big = await decode(1024);
  final out = <Uint8List>[];
  if (masks.isEmpty) {
    final data = await big.toByteData(format: ui.ImageByteFormat.png);
    big.dispose();
    desc.dispose();
    buffer.dispose();
    return [data!.buffer.asUint8List()];
  }
  final bw = big.width, bh = big.height;
  final brgba = (await big.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  big.dispose();
  desc.dispose();
  buffer.dispose();
  for (final m in masks) {
    final cut = await compute(_cutJob, (rgba: brgba, w: bw, h: bh, mask: m, mw: sw, mh: sh));
    if (cut == null) continue;
    final image = await _imageFromRgba(cut.rgba, cut.w, cut.h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data != null) out.add(data.buffer.asUint8List());
  }
  return out;
}

int _area(Uint8List m) {
  var n = 0;
  for (final v in m) {
    if (v > 127) n++;
  }
  return n;
}

Uint8List _grabJob(({Uint8List rgba, int w, int h}) a) => GrabCut.select(a.rgba, a.w, a.h);

List<Uint8List> _splitJob(({Uint8List fg, int w, int h}) a) => splitSubjects(a.fg, a.w, a.h);

/// The photo under [mask] (scaled up to it), cropped to the subject:
/// premultiplied RGBA.
({Uint8List rgba, int w, int h})? _cutJob(({Uint8List rgba, int w, int h, Uint8List mask, int mw, int mh}) a) {
  final m = resizeMask(a.mask, a.mw, a.mh, a.w, a.h);
  var x0 = a.w, y0 = a.h, x1 = -1, y1 = -1;
  for (var y = 0; y < a.h; y++) {
    for (var x = 0; x < a.w; x++) {
      if (m[y * a.w + x] > 20) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final i = (y + y0) * a.w + x + x0, j = (y * cw + x) * 4;
      final v = m[i];
      out[j] = a.rgba[i * 4] * v ~/ 255;
      out[j + 1] = a.rgba[i * 4 + 1] * v ~/ 255;
      out[j + 2] = a.rgba[i * 4 + 2] * v ~/ 255;
      out[j + 3] = v;
    }
  }
  return (rgba: out, w: cw, h: ch);
}

/// How long one loop of every motion takes: 轉圈 turns once in it (slow
/// enough not to make anyone dizzy), the others go round twice.
const motionLoop = Duration(milliseconds: 3000);

/// Where [motion] puts a sticker at [loop] (0–1 through [motionLoop]): how
/// far it moves (as a fraction of its size), turns and grows.
({Offset shift, double turn, double grow}) motionAt(StickerMotion motion, double loop) {
  final t = (loop * 2) % 1;
  final a = 2 * math.pi * t;
  return switch (motion) {
    StickerMotion.none => (shift: Offset.zero, turn: 0, grow: 1),
    StickerMotion.bounce => (shift: Offset(0, -.16 * math.sin(math.pi * t * 2).abs()), turn: 0, grow: 1 + .04 * math.cos(a * 2)),
    StickerMotion.wiggle => (shift: Offset.zero, turn: .16 * math.sin(a), grow: 1),
    StickerMotion.float => (shift: Offset(.03 * math.sin(a), .07 * math.sin(a + math.pi / 2)), turn: .05 * math.sin(a), grow: 1),
    StickerMotion.spin => (shift: Offset.zero, turn: 2 * math.pi * loop, grow: 1),
    StickerMotion.pulse => (shift: Offset.zero, turn: 0, grow: 1 + .1 * math.pow(math.max(0, math.sin(a * 2)), 3)),
  };
}

/// A photo sticker on the page: its picture, moving if it should, with
/// light gliding over shiny finishes as the phone tilts.
class PhotoStickerView extends StatefulWidget {
  final String id;
  final double size;
  const PhotoStickerView(this.id, {super.key, required this.size});

  @override
  State<PhotoStickerView> createState() => _PhotoStickerViewState();
}

class _PhotoStickerViewState extends State<PhotoStickerView> with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this, duration: motionLoop);
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    PhotoStickers.changes.addListener(_update);
    PhotoStickers.clock.addListener(_update);
    _update();
  }

  @override
  void dispose() {
    PhotoStickers.changes.removeListener(_update);
    PhotoStickers.clock.removeListener(_update);
    if (_watching) PhotoStickers.unwatchTilt();
    _loop.dispose();
    super.dispose();
  }

  void _update() {
    final s = PhotoStickers.items[widget.id];
    final moving = s != null && s.motion != StickerMotion.none && PhotoStickers.clock.value == null;
    if (moving && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!moving && _loop.isAnimating) {
      _loop.stop();
    }
    final shiny = s != null && s.finish != StickerFinish.matte;
    if (shiny != _watching) {
      _watching = shiny;
      shiny ? PhotoStickers.watchTilt() : PhotoStickers.unwatchTilt();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = PhotoStickers.items[widget.id];
    final image = PhotoStickers.image(widget.id);
    if (s == null || image == null) return SizedBox.square(dimension: widget.size);
    Widget art = RawImage(image: image, width: widget.size, height: widget.size, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    if (s.finish != StickerFinish.matte) {
      art = ValueListenableBuilder<Offset>(
        valueListenable: PhotoStickers.tilt,
        child: art,
        builder: (context, tilt, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => _shine(s.finish, PhotoStickers.clock.value == null ? tilt : Offset.zero, rect),
          child: child,
        ),
      );
    }
    if (s.motion == StickerMotion.none) return art;
    return AnimatedBuilder(
      animation: _loop,
      child: art,
      builder: (context, child) {
        final m = motionAt(s.motion, PhotoStickers.clock.value ?? _loop.value);
        return Transform.translate(
          offset: m.shift * widget.size,
          child: Transform.rotate(angle: m.turn, child: Transform.scale(scale: m.grow, child: child)),
        );
      },
    );
  }

  /// Light over the sticker, where the tilt puts it.
  static Shader _shine(StickerFinish finish, Offset tilt, Rect rect) {
    final at = Alignment(-.4 + tilt.dx * .9, -.5 + tilt.dy * .9);
    return switch (finish) {
      StickerFinish.holo => LinearGradient(
        begin: Alignment(-1 + tilt.dx, -1 + tilt.dy), end: Alignment(1 + tilt.dx, 1 + tilt.dy),
        colors: const [Color(0x00FFFFFF), Color(0x40FF9AD5), Color(0x408FE3FF), Color(0x40FFF59A), Color(0x00FFFFFF)],
        stops: const [.15, .35, .5, .65, .85],
      ).createShader(rect),
      StickerFinish.glitter => LinearGradient(
        begin: Alignment(-1.2 + tilt.dx * 1.4, -1), end: Alignment(-.2 + tilt.dx * 1.4, 1),
        colors: const [Color(0x00FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)],
      ).createShader(rect),
      _ => RadialGradient(
        center: at, radius: .55,
        colors: [Colors.white.withValues(alpha: finish == StickerFinish.gem ? .4 : .32), Colors.white.withValues(alpha: 0)],
      ).createShader(rect),
    };
  }
}
