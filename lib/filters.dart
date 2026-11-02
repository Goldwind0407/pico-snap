import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'color_grade.dart';

/// LUT size: 33³ like the .cube files photo apps ship.
const lutSize = 33;

/// A photo filter: a colour grade (curves, HSL, shadows / highlights, split
/// toning…) plus film effects drawn on top (grain, vignette, flash, light
/// leak, haze, date stamp).
class PhotoFilter {
  final String id, name;
  final Grade grade;
  /// Film grain, 0–1.
  final double grain;
  /// Dark corners, 0–1.
  final double vignette;
  /// Bright centre, like a direct flash.
  final bool flash;
  /// A red-orange light leak from the edge.
  final bool leak;
  /// An orange date stamp in the corner, like a disposable camera.
  final bool date;
  /// Soft white-pink haze, 0–1.
  final double haze;
  /// Take the edge off phone sharpening, 0–1.
  final double soften;
  /// Glow around bright areas (film halation), 0–1, in [halationColor].
  final double halation;
  final (double, double, double) halationColor;
  /// A ready-made 33³ lookup table (from a .cube file or Hald image) used
  /// instead of [grade].
  final Float32List? table;
  const PhotoFilter(this.id, this.name, this.grade, {
    this.grain = 0, this.vignette = 0, this.flash = false, this.leak = false, this.date = false, this.haze = 0,
    this.soften = 0, this.halation = 0, this.halationColor = (1, .38, .18),
  }) : table = null;

  /// A filter from a lookup file; [table] is 33³, blue changing fastest.
  /// The file only holds colour: film effects come with it from [LutLook].
  PhotoFilter.lut(this.id, this.name, Float32List this.table, {
    this.grain = 0, this.vignette = 0, this.flash = false, this.leak = false, this.date = false, this.haze = 0,
    this.soften = 0, this.halation = 0, this.halationColor = (1, .38, .18),
  }) : grade = Grade.none;

  bool get isNone => id == 'none';

  static final _luts = Expando<Float32List>();
  static final _matrices = Expando<List<double>>();
  static final _preparing = Expando<Future<void>>();

  /// The grade as a lookup table (built once).
  Float32List get lut => _luts[this] ??= table ?? grade.lut(lutSize);

  /// The closest colour matrix, for the live camera viewfinder.
  List<double> get matrix => _matrices[this] ??= fitMatrix(lut, lutSize);

  ColorFilter? get preparedPreviewFilter {
    final m = _matrices[this];
    return m == null ? null : ColorFilter.matrix(m);
  }

  /// Generate both lookup data and the fallback preview off the UI isolate.
  Future<void> prepare() => _preparing[this] ??= () async {
    final result = await compute(_prepareFilter, (grade: grade, table: table));
    _luts[this] = result.$1;
    _matrices[this] = result.$2;
  }();

  ColorFilter get previewFilter => ColorFilter.matrix(matrix);
}

(Float32List, List<double>) _prepareFilter(({Grade grade, Float32List? table}) input) {
  final lut = input.table ?? input.grade.lut(lutSize);
  return (lut, fitMatrix(lut, lutSize));
}

/// Every filter in the app: 原圖 first, then the ones from lookup files
/// ([LutFiles]) as they load, in [lutLooks] order.
final photoFilters = <PhotoFilter>[
  const PhotoFilter('none', '原圖', Grade.none),
];

PhotoFilter filterById(String? id) => photoFilters.firstWhere((f) => f.id == id, orElse: () => photoFilters.first);

/// [base] graded with [filter]'s full colour grade (its lookup table, on a
/// background thread), at most [maxSide] pixels on the long side. Film effects
/// are drawn separately by [FilterEffects].
@immutable
class FilteredImage extends ImageProvider<FilteredImage> {
  static final _work = _FilterWorkQueue();
  final ImageProvider base;
  final PhotoFilter filter;
  final int maxSide;
  const FilteredImage(this.base, this.filter, {this.maxSide = 2048});

  @override
  Future<FilteredImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(FilteredImage key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    await filter.prepare();
    return _work.run(() async {
      final pixels = await _pixels(base, maxSide);
      final w = pixels.w, h = pixels.h;
      // Grain is per pixel: a tiny thumbnail gets less so it reads the same.
      final grain = filter.grain * math.min(1.0, math.max(w, h) / 900);
      final graded = await compute(_gradeJob, (
        rgba: pixels.rgba, lut: filter.lut, w: w, h: h,
        soften: filter.soften, halation: filter.halation, color: filter.halationColor, grain: grain,
      ));
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(graded, w, h, ui.PixelFormat.rgba8888, c.complete);
      return ImageInfo(image: await c.future);
    });
  }

  // Share thumbnail readbacks across filters. Bounded to avoid retaining photos
  // when switching between editing sessions; failed reads can be retried.
  static final _thumbPixels = <(ImageProvider, int), Future<({Uint8List rgba, int w, int h})>>{};

  static Future<({Uint8List rgba, int w, int h})> _pixels(ImageProvider base, int maxSide) async {
    if (maxSide > 256) return _readPixels(base, maxSide);
    final key = (base, maxSide);
    final cached = _thumbPixels.remove(key);
    final job = cached ?? _readPixels(base, maxSide);
    _thumbPixels[key] = job;
    while (_thumbPixels.length > 4) {
      _thumbPixels.remove(_thumbPixels.keys.first);
    }
    try {
      return await job;
    } catch (_) {
      if (identical(_thumbPixels[key], job)) _thumbPixels.remove(key);
      rethrow;
    }
  }

  static Future<({Uint8List rgba, int w, int h})> _readPixels(ImageProvider base, int maxSide) async {
    final src = await _resolve(base);
    final s = math.min(1.0, maxSide / math.max(src.width, src.height));
    final w = math.max(1, (src.width * s).round()), h = math.max(1, (src.height * s).round());
    final rec = ui.PictureRecorder();
    ui.Picture? picture;
    ui.Image? small;
    try {
      ui.Canvas(rec).drawImageRect(
        src, Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      picture = rec.endRecording();
      small = await picture.toImage(w, h);
      final data = await small.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) throw StateError('Cannot read photo pixels');
      return (rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), w: w, h: h);
    } finally {
      small?.dispose();
      picture?.dispose();
      src.dispose();
    }
  }

  static Future<ui.Image> _resolve(ImageProvider provider) {
    final c = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      c.complete(info.image.clone());
      info.dispose();
    }, onError: (e, st) {
      stream.removeListener(listener);
      c.completeError(e, st);
    });
    stream.addListener(listener);
    return c.future;
  }

  @override
  bool operator ==(Object other) => other is FilteredImage && other.base == base && other.filter == filter && other.maxSide == maxSide;

  @override
  int get hashCode => Object.hash(base, filter, maxSide);
}

/// Limit full-image allocations and isolates when several cells change at once.
class _FilterWorkQueue {
  int _active = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active >= 2) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await action();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeAt(0).complete();
      }
    }
  }
}

/// Wait for the images actually requested by a capture subtree, including a
/// replacement hidden by gaplessPlayback. A painted frame alone isn't enough.
Future<void> waitForPhotoImages(BuildContext context) async {
  final providers = <ImageProvider>{};
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Image) providers.add(widget.image);
    element.visitChildren(visit);
  }
  visit(context as Element);
  final cleanups = <VoidCallback>[];
  try {
    await Future.wait(providers.map((provider) {
      final done = Completer<void>();
      final stream = provider.resolve(createLocalImageConfiguration(context));
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        info.dispose();
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      }, onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.completeError(error, stack);
      });
      cleanups.add(() => stream.removeListener(listener));
      stream.addListener(listener);
      return done.future;
    })).timeout(const Duration(seconds: 30));
  } finally {
    for (final cleanup in cleanups) { cleanup(); }
  }
}

Uint8List _gradeJob(({Uint8List rgba, Float32List lut, int w, int h, double soften, double halation, (double, double, double) color, double grain}) a) {
  final out = applyLut(a.rgba, a.lut, lutSize);
  finishFilm(out, a.rgba, a.w, a.h, soften: a.soften, halation: a.halation, halationColor: a.color, grain: a.grain);
  return out;
}

/// A photo from [bytes], decoded no bigger than we ever save it. A phone
/// photo at full size is ~48 MB in memory; a few of them push each other
/// out of the image cache and get decoded again and again.
ImageProvider photoImage(Uint8List bytes) =>
    ResizeImage(MemoryImage(bytes), width: 2400, height: 2400, policy: ResizeImagePolicy.fit, allowUpscaling: false);

/// [image] with [filter] applied exactly: the graded photo plus film effects.
ImageProvider filtered(ImageProvider image, PhotoFilter? filter, {int maxSide = 2048}) =>
    filter == null || filter.isNone ? image : FilteredImage(image, filter, maxSide: maxSide);

/// A capture boundary that temporarily requests export-sized photo pixels.
/// Keeping the setting local also leaves thumbnail work at preview resolution.
class PhotoCapture extends StatefulWidget {
  final Widget child;
  const PhotoCapture({super.key, required this.child});

  @override
  State<PhotoCapture> createState() => PhotoCaptureState();
}

class PhotoCaptureState extends State<PhotoCapture> {
  int? _exportSide;

  void setExportSide(int? side) {
    if (mounted) setState(() => _exportSide = side);
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: PhotoResolution(maxSide: _exportSide, child: widget.child),
  );
}

class PhotoResolution extends InheritedWidget {
  final int? maxSide;
  const PhotoResolution({super.key, required this.maxSide, required super.child});

  static int? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PhotoResolution>()?.maxSide;

  @override
  bool updateShouldNotify(PhotoResolution oldWidget) => oldWidget.maxSide != maxSide;
}

/// Decode from the encoded source again for export, rather than enlarging the
/// 2400px preview. Camera frame providers without encoded originals are kept.
ImageProvider exportPhoto(ImageProvider image, int maxSide) {
  final source = image is ResizeImage ? image.imageProvider : image;
  return ResizeImage(source, width: maxSide, height: maxSide,
    policy: ResizeImagePolicy.fit, allowUpscaling: false);
}

/// Film effects of [filter] over [child] (which is already graded).
class FilterEffects extends StatelessWidget {
  final PhotoFilter filter;
  final Widget child;
  /// The photo already has grain in its pixels ([FilteredImage]); only live
  /// pictures need it drawn on top.
  final bool grainBaked;
  const FilterEffects({super.key, required this.filter, required this.child, this.grainBaked = true});

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final grain = !grainBaked && f.grain > 0;
    final effects = grain || f.vignette > 0 || f.flash || f.leak || f.date || f.haze > 0;
    if (!effects) return child;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: LayoutBuilder(
        builder: (context, c) => Stack(fit: StackFit.expand, children: [
          if (f.haze > 0)
            DecoratedBox(decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -.2),
                radius: 1.05,
                colors: [
                  const Color(0xFFFFF0F6).withValues(alpha: (f.haze * 1.25).clamp(0.0, 1.0)),
                  const Color(0xFFFFE0EC).withValues(alpha: f.haze * .85),
                ],
              ),
            )),
          if (f.flash)
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              radius: .78,
              colors: [Color(0x42FFFFFF), Color(0x18EAF2FF), Color(0x00FFFFFF)],
              stops: [0, .48, 1],
            ))),
          if (f.leak) ...[
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(-1.05, -.35), radius: 1.15,
              colors: [Color(0x96FF5E14), Color(0x48FF2A2A), Color(0x00FF2A2A)], stops: [0, .42, 1],
            ))),
            const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(1.1, .75), radius: .85,
              colors: [Color(0x58FFB82E), Color(0x1CFF6A1A), Color(0x00FF6A1A)], stops: [0, .45, 1],
            ))),
          ],
          if (f.vignette > 0)
            DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              radius: .85, colors: [Colors.transparent, Colors.black.withValues(alpha: f.vignette)], stops: const [.52, 1],
            ))),
          if (grain) CustomPaint(painter: _GrainPainter(f.grain)),
          if (f.date) Align(alignment: const Alignment(.88, .86), child: _DateStamp(size: c.biggest.shortestSide * .085)),
        ]),
      )))),
    ]);
  }
}

class _GrainPainter extends CustomPainter {
  final double amount;
  const _GrainPainter(this.amount);

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed: the grain doesn't crawl when the picture repaints.
    final rnd = math.Random(42);
    final n = (size.width * size.height / 18 * amount).round();
    final light = Paint()..color = Colors.white.withValues(alpha: .07 * amount + .03);
    final dark = Paint()..color = Colors.black.withValues(alpha: .09 * amount + .03);
    for (var i = 0; i < n; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(p, .35 + rnd.nextDouble() * .45, i.isEven ? light : dark);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.amount != amount;
}

class _DateStamp extends StatelessWidget {
  final double size;
  const _DateStamp({required this.size});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return Text("'${two(d.year % 100)} ${two(d.month)} ${two(d.day)}", style: TextStyle(
      fontSize: math.max(6, size), letterSpacing: size * .08, color: const Color(0xFFFF8A2B), fontWeight: FontWeight.w800,
      shadows: [Shadow(color: const Color(0xFFFF5A00).withValues(alpha: .8), blurRadius: size * .4)],
    ));
  }
}
