import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 去背的第一步交給手機內建的主體分割:它「認得」哪個是人、玩偶、動物,
/// 不像魔術棒只看顏色(白褲子站在白舞台上、黑頭髮靠著黑雨棚就分不開)。
///
/// - Android:ML Kit 主體分割(Google Play 服務裡的模型,
///   android/app/src/main/kotlin/.../SubjectSegmenterChannel.kt)
/// - iPhone:Vision,iOS 17 以上是主體去背,iOS 15、16 只有人像分割
///   (ios/Runner/AppDelegate.swift)
///
/// 拿不到(沒有 Google Play 服務、模型還沒下載好、測試環境)或長按的地方
/// 不是前景,回 null,呼叫的地方退回原本的 GrabCut。之後的擦掉、補回、
/// 貼齊邊緣照舊用 GrabCut 修。
class SubjectSegmenter {
  SubjectSegmenter._();

  static const _channel = MethodChannel('picosnap/subject');

  /// 逾時過一次(模型卡住、沒有 Google Play 服務)就不再試:不然每次長按
  /// 都要先空等十幾秒才退回 GrabCut。重開 App 會再試。
  static bool _gaveUp = false;

  /// 前景遮罩(0~255,寬×高),只留長按的 ([x], [y]) 那一塊;沒給位置的話
  /// 留下所有夠大的前景。
  static Future<Uint8List?> select(
    Uint8List rgba,
    int width,
    int height, {
    int? x,
    int? y,
  }) async {
    if (_gaveUp) return null;
    final Uint8List? fg;
    try {
      fg = await _channel.invokeMethod<Uint8List>('foreground', {
        'rgba': rgba,
        'width': width,
        'height': height,
      }).timeout(const Duration(seconds: 12));
    } on TimeoutException catch (e) {
      _gaveUp = true;
      debugPrint('[SEGMENT] 主體分割逾時,這次開 App 都改用 GrabCut: $e');
      return null;
    } catch (e) {
      // 沒有原生實作(測試、桌機)、模型還沒下載好
      debugPrint('[SEGMENT] 主體分割不能用,改用 GrabCut: $e');
      return null;
    }
    if (fg == null || fg.length != width * height) return null;
    return compute(_pickJob, (fg: fg, w: width, h: height, x: x, y: y));
  }

  /// 照片裡每個主體分開的遮罩（0~255，寬×高），大的在前。
  /// AI 不能用回 null；可以用但什麼都沒找到回空清單。
  static Future<List<Uint8List>?> subjects(Uint8List rgba, int width, int height) async {
    if (_gaveUp) return null;
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('subjects', {
        'rgba': rgba,
        'width': width,
        'height': height,
      }).timeout(const Duration(seconds: 12));
    } on TimeoutException catch (e) {
      _gaveUp = true;
      debugPrint('[SEGMENT] 主體分割逾時,這次開 App 都改用 GrabCut: $e');
      return null;
    } catch (e) {
      debugPrint('[SEGMENT] 主體分割不能用,改用 GrabCut: $e');
      return null;
    }
    if (raw == null) return null;
    final parts = [
      for (final r in raw.cast<Map<Object?, Object?>>())
        (x: r['x']! as int, y: r['y']! as int, w: r['w']! as int, h: r['h']! as int, mask: r['mask']! as Uint8List),
    ];
    return compute(_placeJob, (parts: parts, w: width, h: height));
  }
}

List<Uint8List> _placeJob(({List<({int x, int y, int w, int h, Uint8List mask})> parts, int w, int h}) a) =>
    placeSubjects(a.parts, a.w, a.h);

/// 每個主體的框內遮罩放回整張照片大小；太小的（雜點）丟掉，大的排前面。
@visibleForTesting
List<Uint8List> placeSubjects(List<({int x, int y, int w, int h, Uint8List mask})> parts, int w, int h) {
  final out = <(int, Uint8List)>[];
  for (final p in parts) {
    if (p.mask.length != p.w * p.h) continue;
    final full = Uint8List(w * h);
    var area = 0;
    for (var y = 0; y < p.h; y++) {
      final fy = p.y + y;
      if (fy < 0 || fy >= h) continue;
      for (var x = 0; x < p.w; x++) {
        final fx = p.x + x;
        if (fx < 0 || fx >= w) continue;
        final v = p.mask[y * p.w + x];
        full[fy * w + fx] = v;
        if (v > 127) area++;
      }
    }
    if (area > w * h * .003) out.add((area, full));
  }
  out.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final (_, m) in out) m];
}

/// 一張前景遮罩拆成連在一起的幾塊（手動去背、或 AI 只給整張前景時用）。
List<Uint8List> splitSubjects(Uint8List fg, int w, int h) {
  final n = w * h;
  final id = Int32List(n)..fillRange(0, n, -1);
  final groups = <List<int>>[];
  final stack = <int>[];
  for (var s = 0; s < n; s++) {
    if (fg[s] < 128 || id[s] >= 0) continue;
    final c = groups.length;
    final members = <int>[];
    id[s] = c;
    stack.add(s);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      members.add(p);
      final px = p % w, py = p ~/ w;
      void visit(int q) {
        if (fg[q] >= 128 && id[q] < 0) {
          id[q] = c;
          stack.add(q);
        }
      }

      if (px > 0) visit(p - 1);
      if (px < w - 1) visit(p + 1);
      if (py > 0) visit(p - w);
      if (py < h - 1) visit(p + w);
    }
    groups.add(members);
  }
  groups.sort((a, b) => b.length.compareTo(a.length));
  final out = <Uint8List>[];
  for (final g in groups) {
    if (g.length < n * .003) break;
    final m = Uint8List(n);
    for (final i in g) {
      m[i] = fg[i];
    }
    // 邊緣半透明的那一圈（信心不到一半）也留著
    for (final i in g) {
      final px = i % w, py = i ~/ w;
      for (final q in [if (px > 0) i - 1, if (px < w - 1) i + 1, if (py > 0) i - w, if (py < h - 1) i + w]) {
        if (id[q] < 0 && fg[q] > 0) m[q] = fg[q];
      }
    }
    out.add(m);
  }
  return out;
}

Uint8List? _pickJob(({Uint8List fg, int w, int h, int? x, int? y}) a) =>
    pickSubject(a.fg, a.w, a.h, x: a.x, y: a.y);

/// 從整張前景遮罩挑出要的那一塊(連在一起的算同一塊:抱在懷裡的玩偶跟人
/// 是同一塊,旁邊另一個人不是)。邊緣的半透明照原樣留著。
///
/// 長按的點附近都不是前景、或前景小得不像主體,回 null。
@visibleForTesting
Uint8List? pickSubject(Uint8List fg, int w, int h, {int? x, int? y}) {
  final n = w * h;
  // 連通塊(上下左右),前景 = 信心過半
  final id = Int32List(n)..fillRange(0, n, -1);
  final sizes = <int>[];
  final stack = <int>[];
  for (var s = 0; s < n; s++) {
    if (fg[s] < 128 || id[s] >= 0) continue;
    final c = sizes.length;
    var size = 0;
    id[s] = c;
    stack.add(s);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      size++;
      final px = p % w, py = p ~/ w;
      void visit(int q) {
        if (fg[q] >= 128 && id[q] < 0) {
          id[q] = c;
          stack.add(q);
        }
      }

      if (px > 0) visit(p - 1);
      if (px < w - 1) visit(p + 1);
      if (py > 0) visit(p - w);
      if (py < h - 1) visit(p + w);
    }
    sizes.add(size);
  }
  if (sizes.isEmpty) return null;
  final biggest = sizes.reduce(math.max);

  final keep = <int>{};
  if (x != null && y != null) {
    // 長按的點,或附近一小圈(手指沒那麼準)
    final r = math.max(3, (math.min(w, h) * 0.03).round());
    var best = -1;
    var bestD = 1 << 30;
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        final c = id[yy * w + xx];
        final d = dx * dx + dy * dy;
        if (c >= 0 && d < bestD) {
          best = c;
          bestD = d;
        }
      }
    }
    if (best < 0) return null;
    keep.add(best);
  } else {
    for (var c = 0; c < sizes.length; c++) {
      if (sizes[c] >= biggest * 0.1) keep.add(c);
    }
  }
  final kept = keep.fold<int>(0, (s, c) => s + sizes[c]);
  // 只有一小撮(雜點、遠處的小東西)不算選到主體
  if (kept < n * 0.003) return null;

  // 留下的那幾塊照原本的信心值;外面一圈(3 格內)的半透明邊也留著,
  // 其他(別的主體、零星的雜點)清掉
  final out = Uint8List(n);
  final near = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (id[i] >= 0 && keep.contains(id[i])) near[i] = 1;
  }
  const grow = 3;
  for (var pass = 0; pass < grow; pass++) {
    final next = Uint8List.fromList(near);
    for (var i = 0; i < n; i++) {
      if (near[i] == 0) continue;
      final px = i % w, py = i ~/ w;
      if (px > 0) next[i - 1] = 1;
      if (px < w - 1) next[i + 1] = 1;
      if (py > 0) next[i - w] = 1;
      if (py < h - 1) next[i + w] = 1;
    }
    near.setAll(0, next);
  }
  for (var i = 0; i < n; i++) {
    if (near[i] == 0) continue;
    // 別的那一塊主體的本體不要(只是剛好貼在旁邊)
    if (id[i] >= 0 && !keep.contains(id[i])) continue;
    out[i] = fg[i];
  }
  return out;
}
