import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// 去背的工具：魔術棒、筆刷、套用遮罩。純 Dart，Android、iPhone 都一樣，不用任何 API。
///
/// 做法是「魔術棒」:從照片四邊往裡長,顏色跟起點接近的就當作背景挖掉。
/// 背景單純(牆、天空、桌面、草地)時一次就切得乾淨;背景雜的時候會切壞,
/// 再用 [paintMask] 手動擦掉/補回、或 [removeRegion] 點一下挖掉一整塊來修。
///
/// 遮罩 [Uint8List] 一格一個像素:255 留下,0 挖掉。
class Cutout {
  Cutout._();

  /// [tolerance] 0~100,越大挖得越多。
  static Uint8List autoMask(
    Uint8List rgba,
    int width,
    int height, {
    double tolerance = 18,
  }) {
    final n = width * height;
    final mask = Uint8List(n)..fillRange(0, n, 255);
    final seeds = <int>[];
    for (var x = 0; x < width; x++) {
      seeds.add(x);
      seeds.add((height - 1) * width + x);
    }
    for (var y = 1; y < height - 1; y++) {
      seeds.add(y * width);
      seeds.add(y * width + width - 1);
    }
    _grow(rgba, width, height, mask, seeds, tolerance);
    _dropSpecks(mask, width, height);
    _smooth(mask, width, height);
    return mask;
  }

  /// 點一下:把 (x, y) 那塊顏色接近的區域整片挖掉。
  static void removeRegion(
    Uint8List rgba,
    int width,
    int height,
    Uint8List mask,
    int x,
    int y, {
    double tolerance = 18,
  }) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    _grow(rgba, width, height, mask, [y * width + x], tolerance);
  }

  /// 用圓形筆刷擦掉([keep] false)或補回([keep] true)。
  static void paintMask(
    Uint8List mask,
    int width,
    int height,
    double cx,
    double cy,
    double radius, {
    required bool keep,
  }) {
    final v = keep ? 255 : 0;
    final r2 = radius * radius;
    final x0 = math.max(0, (cx - radius).floor());
    final x1 = math.min(width - 1, (cx + radius).ceil());
    final y0 = math.max(0, (cy - radius).floor());
    final y1 = math.min(height - 1, (cy + radius).ceil());
    for (var y = y0; y <= y1; y++) {
      final dy = y - cy;
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx;
        if (dx * dx + dy * dy <= r2) mask[y * width + x] = v;
      }
    }
  }

  /// 留下來的部分的範圍(左、上、右、下,含)。全部挖光回傳 null。
  static (int, int, int, int)? bounds(Uint8List mask, int width, int height) {
    var x0 = width, y0 = height, x1 = -1, y1 = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] > 127) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    return x1 < 0 ? null : (x0, y0, x1, y1);
  }

  /// 照片套上遮罩:挖掉的地方變透明。
  ///
  /// 顏色也一起乘上遮罩(預乘 alpha):decodeImageFromPixels 把像素當成
  /// 預乘過的,只改 alpha 的話挖掉的地方會變成一片白。
  static Uint8List apply(Uint8List rgba, Uint8List mask) {
    final out = Uint8List.fromList(rgba);
    for (var i = 0; i < mask.length; i++) {
      final m = mask[i];
      if (m == 255) continue;
      final j = i * 4;
      out[j] = out[j] * m ~/ 255;
      out[j + 1] = out[j + 1] * m ~/ 255;
      out[j + 2] = out[j + 2] * m ~/ 255;
      out[j + 3] = out[j + 3] * m ~/ 255;
    }
    return out;
  }

  /// 從 [seeds] 往外長,把背景設成 0。
  ///
  /// 每個像素記著它是從哪個起點長出來的:跟起點的顏色差在門檻內、跟上一步
  /// 的顏色也接近(不會一路慢慢漸層吃進主體),才算同一片背景。
  static void _grow(Uint8List rgba, int width, int height, Uint8List mask,
      List<int> seeds, double tolerance) {
    final n = width * height;
    // 顏色差用 RGB 的距離平方。tolerance 100 大約是兩個差很多的顏色
    final t = 10 + tolerance * 1.6;
    final seedLimit = t * t;
    final stepLimit = (t * 0.55) * (t * 0.55);
    final origin = Int32List(n)..fillRange(0, n, -1);
    final queue = Queue<int>();
    for (final s in seeds) {
      if (origin[s] != -1) continue;
      origin[s] = s;
      mask[s] = 0;
      queue.add(s);
    }
    int dist2(int a, int b) {
      final dr = rgba[a * 4] - rgba[b * 4];
      final dg = rgba[a * 4 + 1] - rgba[b * 4 + 1];
      final db = rgba[a * 4 + 2] - rgba[b * 4 + 2];
      return dr * dr + dg * dg + db * db;
    }

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      final seed = origin[p];
      final x = p % width;
      final y = p ~/ width;
      void visit(int q) {
        if (origin[q] != -1) return;
        if (dist2(q, seed) > seedLimit || dist2(q, p) > stepLimit) return;
        origin[q] = seed;
        mask[q] = 0;
        queue.add(q);
      }

      if (x > 0) visit(p - 1);
      if (x < width - 1) visit(p + 1);
      if (y > 0) visit(p - width);
      if (y < height - 1) visit(p + width);
    }
  }

  /// 把太小的碎塊(留下來的小點、挖掉的小洞)清掉:小於全圖 0.4% 的
  /// 留下區塊挖掉,被主體包住的小洞補回去。
  static void _dropSpecks(Uint8List mask, int width, int height) {
    final n = width * height;
    final minArea = math.max(16, (n * 0.004).round());
    final label = Int32List(n)..fillRange(0, n, -1);
    final queue = Queue<int>();
    var next = 0;
    for (var start = 0; start < n; start++) {
      if (label[start] != -1) continue;
      final keep = mask[start] > 127;
      final members = <int>[start];
      var touchesEdge = false;
      label[start] = next;
      queue.add(start);
      while (queue.isNotEmpty) {
        final p = queue.removeFirst();
        final x = p % width;
        final y = p ~/ width;
        if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
          touchesEdge = true;
        }
        void visit(int q) {
          if (label[q] != -1 || (mask[q] > 127) != keep) return;
          label[q] = next;
          members.add(q);
          queue.add(q);
        }

        if (x > 0) visit(p - 1);
        if (x < width - 1) visit(p + 1);
        if (y > 0) visit(p - width);
        if (y < height - 1) visit(p + width);
      }
      next++;
      if (members.length >= minArea) continue;
      // 主體上的小點挖掉;被主體包住(沒碰到邊)的小洞補回
      if (keep) {
        for (final m in members) {
          mask[m] = 0;
        }
      } else if (!touchesEdge) {
        for (final m in members) {
          mask[m] = 255;
        }
      }
    }
  }

  /// 邊緣去鋸齒:3x3 多數決一次,鋸齒狀的邊變平順。
  static void _smooth(Uint8List mask, int width, int height) {
    final src = Uint8List.fromList(mask);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        var on = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final row = (y + dy) * width;
          for (var dx = -1; dx <= 1; dx++) {
            if (src[row + x + dx] > 127) on++;
          }
        }
        mask[y * width + x] = on >= 5 ? 255 : 0;
      }
    }
  }
}
