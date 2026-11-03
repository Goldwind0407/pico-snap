import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filters.dart';
import 'color_grade.dart';
import 'filter_recipes.dart';

/// 從檔案來的濾鏡：放在 assets/luts/ 的調色檔，重新建置 App 就會出現在濾鏡列表最後面。
///
/// - `.cube`：調色軟體（DaVinci、Premiere、Photoshop、Lightroom 外掛）匯出的 3D LUT。
/// - `.png`：Hald 圖。把 design/hald/ 裡的標準色卡圖丟進任何修圖 App 調色後匯出，
///   那張圖就記下了整個調色。
///
/// 檔名就是濾鏡的 id；中文名字和底片效果（顆粒、暗角、光暈…）寫在 [lutLooks]，
/// 沒寫的用檔案裡的 TITLE 或檔名、不加效果。
class LutFiles {
  LutFiles._();

  static const folder = 'assets/luts/';

  /// Bumped as each file's filter is added to [photoFilters].
  static final changes = ValueNotifier<int>(0);

  /// Photoshop exports .CUBE, most others .cube.
  static bool _isCube(String path) => path.toLowerCase().endsWith('.cube');

  static LutData _cube33(String text) {
    final lut = parseCube(text);
    return (table: resampleLut(lut.table, lut.size, lutSize), size: lutSize, title: lut.title);
  }

  static Future<void>? _loading;

  /// [lutLooks] order first, then any other file by name.
  static int _byRank(String a, String b) {
    int rank(String path) {
      final file = Uri.decodeComponent(path.substring(folder.length));
      final i = lutLooks.keys.toList().indexOf(file.substring(0, file.lastIndexOf('.')));
      return i < 0 ? lutLooks.length : i;
    }

    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.compareTo(b);
  }

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    final List<String> paths;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      paths = manifest.listAssets()
          .where((p) => p.startsWith(folder) && (_isCube(p) || p.toLowerCase().endsWith('.png')))
          .toList()
        ..sort(_byRank);
    } catch (e) {
      debugPrint('[LUT] 讀不到濾鏡檔清單: $e');
      return;
    }
    for (final path in paths) {
      final file = Uri.decodeComponent(path.substring(folder.length));
      final base = file.substring(0, file.lastIndexOf('.'));
      if (photoFilters.any((f) => f.id == 'lut:$base')) continue;
      try {
        final look = lutLooks[base];
        // Keep saved filter IDs, but replace a Log conversion with a recipe
        // intended for the sRGB photos the editor actually receives.
        if (look?.grade case final grade?) {
          final filter = PhotoFilter('lut:$base', look!.name, grade,
            grain: look.grain, vignette: look.vignette, soften: look.soften,
            halation: look.halation, halationColor: look.halationColor);
          await filter.prepare();
          photoFilters.add(filter);
          changes.value++;
          continue;
        }
        // A .cube is a megabyte of text: parse it off the UI thread.
        final lut = _isCube(path)
            ? await compute(_cube33, await rootBundle.loadString(path, cache: false))
            : await parseHald(await rootBundle.load(path));
        photoFilters.add(PhotoFilter.lut(
          'lut:$base', look?.name ?? lut.title ?? base, resampleLut(lut.table, lut.size, lutSize),
          grain: look?.grain ?? 0, vignette: look?.vignette ?? 0, soften: look?.soften ?? 0,
          halation: look?.halation ?? 0, halationColor: look?.halationColor ?? (1, .38, .18),
        ));
        changes.value++;
      } catch (e) {
        debugPrint('[LUT] $file 讀取失敗，略過: $e');
      }
    }
  }
}

/// A lookup file's name in the app and the film effects drawn with it.
class LutLook {
  final String name;
  final Grade? grade;
  final double grain, vignette, soften, halation;
  final (double, double, double) halationColor;
  const LutLook(this.name, {this.grade, this.grain = 0, this.vignette = 0, this.soften = 0, this.halation = 0, this.halationColor = (1, .38, .18)});
}

/// 濾鏡檔的中文名字和底片效果（key 是檔名，不含副檔名）。
const lutLooks = <String, LutLook>{
  // Historical asset ID retained so existing drafts still resolve this look.
  'fuji_classic_neg_raw': LutLook('濃烈負片', grade: negativeGrade, grain: .12),
  // Warm amber skin against cool teal backgrounds, like Japanese street snaps.
  'teal_amber_street': LutLook('日系街拍', grain: .2, vignette: .12, soften: .2, halation: .1),
  // Our own grades, made on design/hald/hald_identity_8.png in a photo app
  // (exported as JPEG, so smoothed a touch before saving as PNG).
  'cool': LutLook('冷調'),
  'warm': LutLook('暖調'),
  'soft': LutLook('柔軟', soften: .32),
  'late_autumn': LutLook('深秋'),
  'warm_cool': LutLook('冷暖對比'),
  'retro_soft': LutLook('復古柔和'),
  'macaron': LutLook('馬卡龍'),
  'cyberpunk': LutLook('賽博朋克'),
  'mono': LutLook('黑白'),
};

/// A LUT as read from a file: [size]³ entries of r, g, b (0–1), blue
/// changing fastest like [PhotoFilter.lut].
typedef LutData = ({Float32List table, int size, String? title});

/// Entry [k] of a file that lists red fastest (.cube, Hald) goes to our
/// blue-fastest position.
int _ours(int k, int n) {
  final r = k % n, g = (k ~/ n) % n, b = k ~/ (n * n);
  return ((r * n + g) * n + b) * 3;
}

/// Read a .cube file (3D only).
LutData parseCube(String text) {
  var n = 0;
  String? title;
  var lo = [0.0, 0.0, 0.0], hi = [1.0, 1.0, 1.0];
  Float32List? table;
  var k = 0;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final t = line.split(RegExp(r'\s+'));
    switch (t.first) {
      case 'TITLE':
        final m = RegExp(r'"(.*)"').firstMatch(line);
        title = (m?.group(1) ?? t.skip(1).join(' ')).trim();
        if (title.isEmpty) title = null;
      case 'LUT_3D_SIZE':
        n = int.parse(t[1]);
        if (n < 2 || n > 256) throw FormatException('LUT_3D_SIZE $n');
        table = Float32List(n * n * n * 3);
      case 'LUT_1D_SIZE':
        throw const FormatException('只支援 3D LUT');
      case 'DOMAIN_MIN':
        lo = [for (final v in t.skip(1)) double.parse(v)];
      case 'DOMAIN_MAX':
        hi = [for (final v in t.skip(1)) double.parse(v)];
      default:
        if (table == null || t.length != 3) continue;
        final v = [for (final s in t) double.tryParse(s)];
        if (v.contains(null)) continue;
        if (k >= n * n * n) throw const FormatException('資料比 LUT_3D_SIZE 多');
        final o = _ours(k++, n);
        for (var c = 0; c < 3; c++) {
          table[o + c] = v[c]!.clamp(0.0, 1.0);
        }
    }
  }
  if (table == null || k != n * n * n) throw FormatException('LUT 資料不完整：$k / ${n * n * n}');
  if (lo.length != 3 || hi.length != 3 ||
      List.generate(3, (c) => !lo[c].isFinite || !hi[c].isFinite || hi[c] <= lo[c]).any((v) => v)) {
    throw const FormatException('Invalid LUT input domain');
  }
  // DOMAIN describes input coordinates, never output RGB. Bake a custom
  // domain into the standard 0–1 grid used by both CPU and shader sampling.
  if (lo.any((v) => v != 0) || hi.any((v) => v != 1)) {
    final size = math.max(n, lutSize);
    return (table: resampleLut(table, n, size, domainMin: lo, domainMax: hi), size: size, title: title);
  }
  return (table: table, size: n, title: title);
}

/// Read a Hald CLUT image: level L is an L³ × L³ picture holding an L²-sized
/// cube, red fastest, row by row.
Future<LutData> parseHald(ByteData bytes) async {
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final w = image.width, h = image.height;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  image.dispose();
  return haldFromPixels(data!.buffer.asUint8List(), w, h);
}

LutData haldFromPixels(Uint8List rgba, int w, int h) {
  final level = math.pow(w, 1 / 3).round();
  final n = level * level;
  if (w != h || level * level * level != w) throw FormatException('不是 Hald 圖：$w×$h');
  final table = Float32List(n * n * n * 3);
  for (var k = 0; k < n * n * n; k++) {
    final o = _ours(k, n);
    for (var c = 0; c < 3; c++) {
      table[o + c] = rgba[k * 4 + c] / 255;
    }
  }
  return (table: table, size: n, title: null);
}

/// Resample an [n]³ LUT to [m]³ (trilinear).
Float32List resampleLut(Float32List src, int n, int m, {
  List<double> domainMin = const [0, 0, 0],
  List<double> domainMax = const [1, 1, 1],
}) {
  if (n == m && domainMin.every((v) => v == 0) && domainMax.every((v) => v == 1)) return src;
  double coordinate(int i, int c) =>
      ((i / (m - 1) - domainMin[c]) / (domainMax[c] - domainMin[c])).clamp(0.0, 1.0) * (n - 1);
  final out = Float32List(m * m * m * 3);
  double at(int r, int g, int b, int c) => src[((r * n + g) * n + b) * 3 + c];
  var o = 0;
  for (var ri = 0; ri < m; ri++) {
    for (var gi = 0; gi < m; gi++) {
      for (var bi = 0; bi < m; bi++) {
        final fr = coordinate(ri, 0), fg = coordinate(gi, 1), fb = coordinate(bi, 2);
        final r0 = math.min(fr.floor(), n - 2), g0 = math.min(fg.floor(), n - 2), b0 = math.min(fb.floor(), n - 2);
        final tr = fr - r0, tg = fg - g0, tb = fb - b0;
        for (var c = 0; c < 3; c++) {
          final c00 = at(r0, g0, b0, c) * (1 - tb) + at(r0, g0, b0 + 1, c) * tb;
          final c01 = at(r0, g0 + 1, b0, c) * (1 - tb) + at(r0, g0 + 1, b0 + 1, c) * tb;
          final c10 = at(r0 + 1, g0, b0, c) * (1 - tb) + at(r0 + 1, g0, b0 + 1, c) * tb;
          final c11 = at(r0 + 1, g0 + 1, b0, c) * (1 - tb) + at(r0 + 1, g0 + 1, b0 + 1, c) * tb;
          out[o++] = (c00 * (1 - tg) + c01 * tg) * (1 - tr) + (c10 * (1 - tg) + c11 * tg) * tr;
        }
      }
    }
  }
  return out;
}
