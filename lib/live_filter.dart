import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'filters.dart';

/// A filter over a live picture (the camera viewfinder). On the GPU it is the
/// same look as the saved photo: the LUT, softening, halation and grain
/// (shaders/film.frag). Where custom shader filters aren't available (no
/// Impeller, tests) it falls back to the closest colour matrix.
class FilterLayer extends StatefulWidget {
  final PhotoFilter filter;
  final Widget child;
  const FilterLayer({super.key, required this.filter, required this.child});

  @override
  State<FilterLayer> createState() => _FilterLayerState();
}

class _FilterLayerState extends State<FilterLayer> {
  ui.FragmentShader? _shader;
  /// What [_shader] was set up for.
  (String, double)? _shaderFor;
  final _luts = <String, ui.Image>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FilterLayer old) {
    super.didUpdateWidget(old);
    if (old.filter.id != widget.filter.id) _load();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final f = widget.filter;
    if (f.isNone || _luts.containsKey(f.id) || !FilmShader.supported) return;
    final program = await FilmShader.program;
    if (program == null) return;
    final lut = await FilmShader.lut(f);
    if (mounted) setState(() => _luts[f.id] = lut);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    if (f.isNone) return widget.child;
    final program = FilmShader.loaded, lut = _luts[f.id];
    if (program == null || lut == null) {
      return FilterEffects(filter: f, grainBaked: false, child: ColorFiltered(colorFilter: f.previewFilter, child: widget.child));
    }
    return FilterEffects(filter: f, child: LayoutBuilder(builder: (context, c) {
      final side = c.biggest.longestSide * MediaQuery.devicePixelRatioOf(context);
      final shader = _shaderOf(program, lut, f, side);
      return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: widget.child);
    }));
  }

  ui.FragmentShader _shaderOf(ui.FragmentProgram program, ui.Image lut, PhotoFilter f, double side) {
    final key = (f.id, side);
    final existing = _shader;
    if (existing != null && _shaderFor == key) return existing;
    existing?.dispose();
    final (hr, hg, hb) = f.halationColor;
    // Floats 0–1 are the size, set by the engine. Grain is per pixel: a
    // small viewfinder gets less, like a thumbnail.
    final shader = program.fragmentShader()
      ..setFloat(2, f.soften)
      ..setFloat(3, f.halation)
      ..setFloat(4, f.grain * math.min(1.0, side / 900))
      ..setFloat(5, 0)
      ..setFloat(6, hr)
      ..setFloat(7, hg)
      ..setFloat(8, hb)
      ..setImageSampler(1, lut, filterQuality: FilterQuality.low);
    _shader = shader;
    _shaderFor = key;
    return shader;
  }
}

/// shaders/film.frag and the filters' LUTs as textures.
abstract final class FilmShader {
  static bool get supported {
    try {
      return ui.ImageFilter.isShaderFilterSupported;
    } catch (_) {
      return false;
    }
  }

  static ui.FragmentProgram? loaded;
  static Future<ui.FragmentProgram?>? _program;

  /// The compiled shader, or null if it can't be loaded on this device.
  static Future<ui.FragmentProgram?> get program => _program ??= () async {
    try {
      return loaded = await ui.FragmentProgram.fromAsset('shaders/film.frag');
    } catch (e) {
      debugPrint('[FILTER] live shader unavailable: $e');
      return null;
    }
  }();

  static final _luts = <String, Future<ui.Image>>{};

  /// [filter]'s LUT laid out for the shader: 33 slices of red × green side
  /// by side, one per blue step.
  static Future<ui.Image> lut(PhotoFilter filter) => _luts[filter.id] ??= () {
    final src = filter.lut;
    final n = math.pow(src.length ~/ 3, 1 / 3).round();
    final px = lutPixels(src, n);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, n * n, n, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }();

  /// RGBA pixels of an [n]³ LUT as an n² × n image: x = blue · n + red,
  /// y = green.
  static Uint8List lutPixels(Float32List lut, int n) {
    final w = n * n;
    final px = Uint8List(w * n * 4);
    for (var r = 0; r < n; r++) {
      for (var g = 0; g < n; g++) {
        for (var b = 0; b < n; b++) {
          final s = ((r * n + g) * n + b) * 3, o = (g * w + b * n + r) * 4;
          for (var k = 0; k < 3; k++) {
            px[o + k] = (lut[s + k] * 255).round().clamp(0, 255);
          }
          px[o + 3] = 255;
        }
      }
    }
    return px;
  }
}
