import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filters.dart';

/// 從檔案來的濾鏡：放在 assets/luts/ 的調色檔，重新建置 App 就會出現在濾鏡列表最後面。
///
/// - `.cube`：調色軟體（DaVinci、Premiere、Photoshop、Lightroom 外掛）匯出的 3D LUT。
/// - `.png`：Hald 圖。把 design/hald/ 裡的標準色卡圖丟進任何修圖 App 調色後匯出，
///   那張圖就記下了整個調色。
///
/// 檔名就是濾鏡的 id；中文名字寫在 [lutNames]，沒寫的用檔案裡的 TITLE 或檔名。
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

  static Future<void> load() async {
    final List<String> paths;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      paths = manifest.listAssets()
          .where((p) => p.startsWith(folder) && (_isCube(p) || p.toLowerCase().endsWith('.png')))
          .toList()
        ..sort();
    } catch (e) {
      debugPrint('[LUT] 讀不到濾鏡檔清單: $e');
      return;
    }
    for (final path in paths) {
      final file = Uri.decodeComponent(path.substring(folder.length));
      final base = file.substring(0, file.lastIndexOf('.'));
      try {
        // A .cube is a megabyte of text: parse it off the UI thread.
        final lut = _isCube(path)
            ? await compute(_cube33, await rootBundle.loadString(path, cache: false))
            : await parseHald(await rootBundle.load(path));
        photoFilters.add(PhotoFilter.lut('lut:$base', lutNames[base] ?? lut.title ?? base, resampleLut(lut.table, lut.size, lutSize)));
        changes.value++;
      } catch (e) {
        debugPrint('[LUT] $file 讀取失敗，略過: $e');
      }
    }
  }
}

/// 濾鏡檔的中文名字（key 是檔名，不含副檔名）。
const lutNames = {
  'BlueArchitecture': '藍調建築',
  'BlueHour': '藍色時刻',
  'ColdChrome': '冷調鉻黃',
  'CrispAutumn': '清爽秋日',
  'DarkAndSomber': '暗調憂鬱',
  'HardBoost': '強烈鮮豔',
  'LongBeachMorning': '海灘晨光',
  'LushGreen': '濃郁綠意',
  'MagicHour': '魔幻時刻',
  'NaturalBoost': '自然增豔',
  'OrangeAndBlue': '橘藍電影',
  'SoftBlackAndWhite': '柔和黑白',
  'Waves': '海浪',
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
          table[o + c] = ((v[c]! - lo[c]) / (hi[c] - lo[c])).clamp(0.0, 1.0);
        }
    }
  }
  if (table == null || k != n * n * n) throw FormatException('LUT 資料不完整：$k / ${n * n * n}');
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
Float32List resampleLut(Float32List src, int n, int m) {
  if (n == m) return src;
  final out = Float32List(m * m * m * 3);
  double at(int r, int g, int b, int c) => src[((r * n + g) * n + b) * 3 + c];
  var o = 0;
  for (var ri = 0; ri < m; ri++) {
    for (var gi = 0; gi < m; gi++) {
      for (var bi = 0; bi < m; bi++) {
        final fr = ri * (n - 1) / (m - 1), fg = gi * (n - 1) / (m - 1), fb = bi * (n - 1) / (m - 1);
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
