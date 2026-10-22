import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'cutout.dart';

/// 沿著輪廓選主體:GrabCut(Rother 等人 2004),純 Dart,不用任何模型。
///
/// 1. 先用魔術棒([Cutout.autoMask])粗估主體在哪,框出一個範圍(往外多留
///    一圈);範圍外一定是背景,範圍內先當作主體。
/// 2. 主體、背景各用 5 個高斯的混合模型(GMM)記住顏色分布。
/// 3. 每個像素「像主體還是像背景」當作成本,相鄰像素顏色差越小、越不該被
///    切開,用最小割(Boykov–Kolmogorov 最大流)找出總成本最低的分界線。
/// 4. 用新的分界重新估顏色模型,重複幾次。
/// 5. 主體裡面被切掉的小洞(眼睛、嘴巴這種跟背景同色的地方)補回來。
/// 6. 在小圖上算完放大回來,用導向濾波(guided filter,He 等人 2010)
///    照原圖的顏色邊緣把遮罩修順:邊緣貼著真正的輪廓、有一點半透明。
///
/// 玩家的筆畫(提示,[hints])當作硬限制:畫過「擦掉」的地方一定是背景、
/// 「補回」的一定是主體,再重算一次([refine]),分界線會自己沿著邊緣走。
/// 所以要去掉旁邊黏著的東西,在上面隨手畫一筆就好,不用沿著邊慢慢擦。
///
/// 提示的值:1 / -1 是「貼齊邊緣」的筆畫(只當作分界的限制);
/// 2 / -2 是一般筆刷,放大回原圖之後也照筆刷原樣蓋上去。
class GrabCut {
  GrabCut._();

  /// 在這個大小(最長邊)上算,一般手機半秒內算完。
  static const int workSize = 360;

  /// 選主體。[px]、[py] 是長按的位置(照片像素);null 是自動去背,
  /// 留下最大的那一塊。回傳遮罩(0~255,邊緣有半透明)。
  static Uint8List select(
    Uint8List rgba,
    int width,
    int height, {
    int? px,
    int? py,
    Int8List? hints,
  }) {
    final g = _Work(rgba, width, height);
    final w = g.w, h = g.h, n = w * h;
    final sh = g.hints(hints);
    final sx = px == null ? -1 : (px * w / width).floor().clamp(0, w - 1);
    final sy = py == null ? -1 : (py * h / height).floor().clamp(0, h - 1);

    // ---- 粗估:魔術棒,取長按的那一塊(或最大的一塊),框出範圍 ----
    final rough = Cutout.autoMask(_toRgba(g.img, n), w, h, tolerance: 22);
    final roughLabel = Uint8List(n);
    for (var i = 0; i < n; i++) {
      roughLabel[i] = rough[i] > 127 ? 1 : 0;
    }
    final comps = _Components(roughLabel, w, h, 1);
    final id = sx >= 0 ? comps.near(sx, sy) : comps.largest();
    var x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1;
    if (id >= 0) {
      (x0, y0, x1, y1) = comps.bounds(id);
      // 粗估常常少了一截(腳、耳朵跟背景同色),範圍往外多留一些
      final m = (0.15 * math.max(x1 - x0, y1 - y0)).ceil() + 2;
      x0 = math.max(0, x0 - m);
      y0 = math.max(0, y0 - m);
      x1 = math.min(w - 1, x1 + m);
      y1 = math.min(h - 1, y1 + m);
    }
    // 長按的點一定在範圍裡
    if (sx >= 0) {
      x0 = math.min(x0, sx);
      y0 = math.min(y0, sy);
      x1 = math.max(x1, sx);
      y1 = math.max(y1, sy);
    }

    final label = Uint8List(n);
    final hard = Int8List(n); // 1 主體、-1 背景、0 未知
    const band = 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final inBox = x >= x0 && x <= x1 && y >= y0 && y <= y1;
        final onEdge = x < band || y < band || x >= w - band || y >= h - band;
        if (!inBox || onEdge) {
          hard[i] = -1;
        } else {
          label[i] = 1;
        }
      }
    }
    if (sx >= 0) {
      final r = math.max(2.0, math.min(w, h) * 0.03);
      _disc(hard, w, h, sx, sy, r, 1);
    }
    for (var i = 0; i < n; i++) {
      if (sh[i] != 0) hard[i] = sh[i];
      if (hard[i] != 0) label[i] = hard[i] > 0 ? 1 : 0;
    }

    _cut(g, label, hard, iterations: 5);

    // 只留長按那一塊(與玩家補回過的),圖割有時會在遠處留下同色的小塊
    final out = _Components(label, w, h, 1);
    final keep = <int>{};
    if (sx >= 0) {
      final k = out.near(sx, sy);
      if (k >= 0) keep.add(k);
    } else {
      final k = out.largest();
      if (k >= 0) keep.add(k);
    }
    for (var i = 0; i < n; i++) {
      if (sh[i] > 0 && out.id[i] >= 0) keep.add(out.id[i]);
    }
    for (var i = 0; i < n; i++) {
      if (label[i] == 1 && !keep.contains(out.id[i])) label[i] = 0;
    }
    _fillHoles(label, w, h, hard);
    return _upscale(label, g, hints);
  }

  /// 玩家畫了一筆之後重算。[mask] 是現在的遮罩,[hints] 是到目前為止所有
  /// 的筆畫,[stroke] 是剛剛那一筆(只有它附近的地方會變,其他地方不動,
  /// 才不會修這裡、那裡跑掉)。
  static Uint8List refine(
    Uint8List rgba,
    int width,
    int height,
    Uint8List mask,
    Int8List hints,
    Int8List stroke,
  ) {
    final g = _Work(rgba, width, height);
    final w = g.w, h = g.h, n = w * h;
    final label = g.mask(mask);
    final sh = g.hints(hints);
    final st = g.hints(stroke);

    // 離這一筆多遠以內可以變(小圖像素)
    // 點一下(筆畫只有一個點那麼大)只動附近一小塊、也不學它的顏色;
    // 畫一筆才動到比較大的範圍
    var sx0 = w, sy0 = h, sx1 = -1, sy1 = -1;
    for (var i = 0; i < n; i++) {
      if (st[i] == 0) continue;
      final x = i % w, y = i ~/ w;
      if (x < sx0) sx0 = x;
      if (x > sx1) sx1 = x;
      if (y < sy0) sy0 = y;
      if (y > sy1) sy1 = y;
    }
    final isTap = math.max(sx1 - sx0, sy1 - sy0) < 6;
    // 這一筆是擦掉還是補回:擦掉只會變少(現在是背景的維持背景),補回
    // 只會變多。不然擦一筆時,之前擦掉、跟主體同色的東西(白球)會被重切回來
    var stFg = 0, stBg = 0;
    for (final v in st) {
      if (v > 0) stFg++;
      if (v < 0) stBg++;
    }
    final erasingStroke = stBg >= stFg;
    // 真的有作用的那一段:擦掉時只算畫在「現在還是主體」上的部分,補回時
    // 只算畫在「現在是背景」上的。畫到外面已經去掉的地方(順手多拖一段)
    // 只當限制,不從那裡往外擴:實測擦吉祥物旁邊的煙,筆畫整段都在背景上,
    // 卻沿著同樣粉白色的煙一路推到褲管和鞋子,把腳整個切掉。
    // 點一下維持原樣(可能點在殘邊旁邊一點點)。
    // 差一點點沒畫到(離邊緣幾格)也算有畫到:手指沒那麼準。
    const slack = 3;
    bool touches(int x, int y, int want) {
      for (var yy = math.max(0, y - slack);
          yy <= math.min(h - 1, y + slack);
          yy++) {
        for (var xx = math.max(0, x - slack);
            xx <= math.min(w - 1, x + slack);
            xx++) {
          if (label[yy * w + xx] == want) return true;
        }
      }
      return false;
    }

    final active = Int8List(n);
    var nActive = 0;
    for (var i = 0; i < n; i++) {
      final v = st[i];
      if (v == 0) continue;
      if (isTap || touches(i % w, i ~/ w, v < 0 ? 1 : 0)) {
        active[i] = v;
        nActive++;
      }
    }
    final reach = nActive == 0 ? 0.0 : (isTap ? 0.12 : 0.25) * math.max(w, h);
    final dist = _distance(nActive == 0 ? st : active, w, h);
    final hard = Int8List(n);
    const band = 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (dist[i] > reach) {
          hard[i] = label[i] == 1 ? 1 : -1;
        } else if (erasingStroke ? label[i] == 0 : label[i] == 1) {
          hard[i] = label[i] == 1 ? 1 : -1;
        } else if (label[i] == 0 &&
            (x < band || y < band || x >= w - band || y >= h - band)) {
          hard[i] = -1;
        }
        if (sh[i] != 0) hard[i] = sh[i];
        if (hard[i] != 0) label[i] = hard[i] > 0 ? 1 : 0;
      }
    }

    // 剛剛那一筆的顏色:擦掉的話「這種顏色是背景」(例如黏在旁邊的白球,
    // 跟白色的主體同色,不這樣做的話只會挖掉筆畫經過的那一條)
    final strokeFg = <int>[], strokeBg = <int>[];
    for (var i = 0; i < n; i++) {
      if (active[i] > 0) strokeFg.add(i);
      if (active[i] < 0) strokeBg.add(i);
    }
    // 沿著照片走的距離:同一個東西裡面走起來近、跨過顏色邊界很遠。
    // 擦掉一筆時,離這一筆比離主體近的地方傾向背景(白球整顆跟著走,
    // 不會只挖掉筆畫那一條);補回一筆時反過來。
    final erasing = erasingStroke;
    final toStroke = _geodesic(g, erasing ? strokeBg : strokeFg);
    // 「留下那一邊」原本只從可以變的範圍外面算起:擦吉祥物腳邊的舞台時,
    // 膝蓋以下整截褲管都在範圍內,離範圍外的主體反而比離筆畫遠,褲管和
    // 鞋子會跟著舞台一起被擦掉。所以範圍內、離筆畫稍遠(長邊的 3.5%)、
    // 顏色又比較像主體而不像這一筆擦到的東西的地方,也算留下那一邊。
    // 顏色要比:不然跟筆畫同一種東西的其他部分(圍網的另一半)也被當成
    // 主體保護起來,擦不乾淨。
    final near = 0.035 * math.max(w, h);
    final keepSide = <int>[
      for (var i = 0; i < n; i++)
        if (erasing ? hard[i] > 0 : hard[i] < 0) i
    ];
    if (erasing && strokeBg.isNotEmpty) {
      List<int> sample(List<int> from, int max) {
        final step = math.max(1, from.length ~/ max);
        return [for (var k = 0; k < from.length; k += step) from[k]];
      }

      // 筆畫擦到的顏色、範圍外確定留下的主體的顏色(各取幾十個代表)。雨棚
      // 的黑色在範圍外的主體裡沒有,就不會被當成主體保護起來。
      final erased = sample(strokeBg, 48);
      final kept = sample(keepSide, 96);
      const far = 40;
      bool closeTo(int i, List<int> palette) {
        for (final j in palette) {
          if (_d2(g.img, i, j) < far * far) return true;
        }
        return false;
      }

      for (var i = 0; i < n; i++) {
        if (label[i] != 1 || hard[i] != 0 || dist[i] <= near) continue;
        if (!closeTo(i, erased) && closeTo(i, kept)) keepSide.add(i);
      }
    }
    final toOther = _geodesic(g, keepSide);
    final bias = Float64List(n); // > 0 傾向背景
    for (var i = 0; i < n; i++) {
      final a = toStroke[i], b = toOther[i];
      if (a.isInfinite && b.isInfinite) continue;
      final t = a.isInfinite
          ? -1.0
          : b.isInfinite
              ? 1.0
              : (b - a) / (a + b + 1e-9);
      // 只往筆畫那一邊推:擦掉時「離主體比較近」不代表它是主體(旁邊的牆)。
      // 離筆畫越遠推得越輕,到可以變的範圍邊上變成 0:不然範圍內一律被推,
      // 切出來的缺口是方的(實測熊貓半邊臉被切成一塊方形)
      final fade = (1 - dist[i] / reach).clamp(0.0, 1.0);
      if (t > 0) bias[i] = (erasing ? t : -t) * fade;
    }
    // 點一下的時候不學它的顏色:點在球邊緣的深色殘線上,
    // 學到「深色是背景」的話,熊貓的手、耳朵、腳都會被一起擦掉
    final learn = !isTap;
    _cut(g, label, hard,
        iterations: 3,
        extraFg: learn ? strokeFg : const [],
        extraBg: learn ? strokeBg : const [],
        bias: bias);

    // 留下有「一定是主體」的那幾塊:擦掉一筆之後切下來的碎塊會一起消失
    final out = _Components(label, w, h, 1);
    final keep = <int>{};
    for (var i = 0; i < n; i++) {
      if (hard[i] > 0 && out.id[i] >= 0) keep.add(out.id[i]);
    }
    if (keep.isEmpty) {
      final k = out.largest();
      if (k >= 0) keep.add(k);
    }
    for (var i = 0; i < n; i++) {
      if (label[i] == 1 && !keep.contains(out.id[i])) label[i] = 0;
    }
    _fillHoles(label, w, h, hard);
    return _upscale(label, g, hints);
  }

  /// 估顏色模型 → 最小割,重複 [iterations] 次。[label] 直接改成結果。
  static void _cut(_Work g, Uint8List label, Int8List hard,
      {required int iterations,
      List<int> extraFg = const [],
      List<int> extraBg = const [],
      Float64List? bias}) {
    final w = g.w, h = g.h, n = w * h;
    final img = g.img;
    final right = Float64List(n), down = Float64List(n);
    var sum = 0.0;
    var cnt = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (x < w - 1) {
          sum += _d2(img, i, i + 1);
          cnt++;
        }
        if (y < h - 1) {
          sum += _d2(img, i, i + w);
          cnt++;
        }
      }
    }
    final beta = cnt == 0 || sum == 0 ? 0.0 : 1 / (2 * sum / cnt);
    const gamma = 50.0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (x < w - 1) right[i] = gamma * math.exp(-beta * _d2(img, i, i + 1));
        if (y < h - 1) down[i] = gamma * math.exp(-beta * _d2(img, i, i + w));
      }
    }

    for (var it = 0; it < iterations; it++) {
      final fg = _Gmm.fit(img, label, 1, extraFg);
      final bg = _Gmm.fit(img, label, 0, extraBg);
      final source = Float64List(n), sink = Float64List(n);
      const inf = 1e9;
      for (var i = 0; i < n; i++) {
        if (hard[i] > 0) {
          source[i] = inf;
        } else if (hard[i] < 0) {
          sink[i] = inf;
        } else {
          // 接到 source(主體)的容量 = 當背景的代價
          source[i] = bg.cost(img, i);
          sink[i] = fg.cost(img, i);
          if (bias != null) {
            final b = bias[i];
            if (b > 0) sink[i] += _biasWeight * b;
            if (b < 0) source[i] -= _biasWeight * b;
          }
        }
      }
      final cut = _MaxFlow(w, h, source, sink, right, down).solve();
      var changed = 0;
      for (var i = 0; i < n; i++) {
        final v = cut[i] ? 1 : 0;
        if (v != label[i]) changed++;
        label[i] = v;
      }
      if (changed < n * 0.002) break;
    }
  }

  /// 沿路徑距離佔多重(顏色模型的成本大約 10~30)。
  static const double _biasWeight = 40;

  /// 從 [seeds] 出發、沿著照片走到每一格的最短距離:每走一格 1,再加上
  /// 跨過的顏色差(邊界越明顯越遠)。Dijkstra,八個方向。
  static Float64List _geodesic(_Work g, List<int> seeds) {
    final w = g.w, h = g.h, n = w * h;
    final img = g.img;
    final d = Float64List(n)..fillRange(0, n, double.infinity);
    if (seeds.isEmpty) return d;
    final heap = _Heap();
    for (final s in seeds) {
      d[s] = 0;
      heap.push(s, 0);
    }
    const k = 0.25; // 顏色差(0~441)換成距離
    while (heap.isNotEmpty) {
      final (p, dp) = heap.pop();
      if (dp > d[p]) continue;
      final px = p % w, py = p ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        final y = py + dy;
        if (y < 0 || y >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final x = px + dx;
          if ((dx == 0 && dy == 0) || x < 0 || x >= w) continue;
          final q = y * w + x;
          final step = (dx != 0 && dy != 0 ? 1.4142 : 1.0) +
              k * math.sqrt(_d2(img, p, q));
          final nd = dp + step;
          if (nd < d[q]) {
            d[q] = nd;
            heap.push(q, nd);
          }
        }
      }
    }
    return d;
  }

  /// 被主體整個包住、又沒有被玩家標成背景的洞補起來:熊貓的黑眼圈、
  /// 嘴巴的線條常常跟背景(深色陰影)顏色接近,會被切成洞。
  /// 真的是洞的地方(手臂跟身體中間看得到牆)點一下擦掉就不會再補。
  static void _fillHoles(Uint8List label, int w, int h, Int8List hard) {
    final holes = _Components(label, w, h, 0);
    final open = <int>{};
    for (var x = 0; x < w; x++) {
      open.add(holes.id[x]);
      open.add(holes.id[(h - 1) * w + x]);
    }
    for (var y = 0; y < h; y++) {
      open.add(holes.id[y * w]);
      open.add(holes.id[y * w + w - 1]);
    }
    for (var i = 0; i < label.length; i++) {
      if (hard[i] < 0) open.add(holes.id[i]);
    }
    for (var i = 0; i < label.length; i++) {
      if (label[i] == 0 && !open.contains(holes.id[i])) label[i] = 1;
    }
  }

  /// 小圖的結果放大回原圖:先雙線性放大成 0~1,再用原圖當導引做導向濾波,
  /// 邊緣就會貼著原圖的顏色邊、有一點半透明。最後一般筆刷畫過的地方照原樣蓋上。
  static Uint8List _upscale(Uint8List label, _Work g, Int8List? hints) {
    final w = g.w, h = g.h;
    final width = g.width, height = g.height;
    final rgba = g.rgba;
    final total = width * height;
    final p = Float32List(total);
    for (var y = 0; y < height; y++) {
      final fy = ((y + 0.5) * h / height - 0.5).clamp(0.0, h - 1.0);
      final ya = fy.floor(), yb = math.min(h - 1, ya + 1);
      final ty = fy - ya;
      for (var x = 0; x < width; x++) {
        final fx = ((x + 0.5) * w / width - 0.5).clamp(0.0, w - 1.0);
        final xa = fx.floor(), xb = math.min(w - 1, xa + 1);
        final tx = fx - xa;
        final top = label[ya * w + xa] * (1 - tx) + label[ya * w + xb] * tx;
        final bot = label[yb * w + xa] * (1 - tx) + label[yb * w + xb] * tx;
        p[y * width + x] = top * (1 - ty) + bot * ty;
      }
    }
    final r = math.max(2, (1.5 * width / w).round());
    final q = _guidedFilter(rgba, width, height, p, r, 0.003);
    final out = Uint8List(total);
    for (var i = 0; i < total; i++) {
      // 濾波會把邊緣拉得有點寬,拉回來一點,邊緣才不會霧霧的
      final a = ((q[i] - 0.5) * 1.6 + 0.5).clamp(0.0, 1.0);
      out[i] = (a * 255).round();
    }
    if (hints != null) {
      for (var i = 0; i < total; i++) {
        final v = hints[i];
        if (v == 2) out[i] = 255;
        if (v == -2) out[i] = 0;
      }
    }
    return out;
  }

  /// 彩色導向濾波:q = a·I + b,a、b 在每個 (2r+1)² 的視窗裡用最小平方
  /// 求出來。I 是原圖(0~1),p 是要修的遮罩。
  static Float32List _guidedFilter(
      Uint8List rgba, int w, int h, Float32List p, int r, double eps) {
    final n = w * h;
    final ir = Float32List(n), ig = Float32List(n), ib = Float32List(n);
    for (var i = 0; i < n; i++) {
      ir[i] = rgba[i * 4] / 255;
      ig[i] = rgba[i * 4 + 1] / 255;
      ib[i] = rgba[i * 4 + 2] / 255;
    }
    Float32List mul(Float32List a, Float32List b) {
      final o = Float32List(n);
      for (var i = 0; i < n; i++) {
        o[i] = a[i] * b[i];
      }
      return o;
    }

    Float32List box(Float32List a) => _box(a, w, h, r);
    final mr = box(ir), mg = box(ig), mb = box(ib), mp = box(p);
    final mrp = box(mul(ir, p)), mgp = box(mul(ig, p)), mbp = box(mul(ib, p));
    final vrr = box(mul(ir, ir)),
        vrg = box(mul(ir, ig)),
        vrb = box(mul(ir, ib));
    final vgg = box(mul(ig, ig)),
        vgb = box(mul(ig, ib)),
        vbb = box(mul(ib, ib));
    final ar = Float32List(n), ag = Float32List(n), ab = Float32List(n);
    final bb = Float32List(n);
    for (var i = 0; i < n; i++) {
      final cr = mrp[i] - mr[i] * mp[i];
      final cg = mgp[i] - mg[i] * mp[i];
      final cb = mbp[i] - mb[i] * mp[i];
      // 視窗裡全部同一邊(遮罩沒有變化):a = 0,不用算反矩陣
      if (cr.abs() < 1e-6 && cg.abs() < 1e-6 && cb.abs() < 1e-6) {
        bb[i] = mp[i];
        continue;
      }
      final s00 = vrr[i] - mr[i] * mr[i] + eps;
      final s01 = vrg[i] - mr[i] * mg[i];
      final s02 = vrb[i] - mr[i] * mb[i];
      final s11 = vgg[i] - mg[i] * mg[i] + eps;
      final s12 = vgb[i] - mg[i] * mb[i];
      final s22 = vbb[i] - mb[i] * mb[i] + eps;
      // 對稱 3x3 反矩陣
      final i00 = s11 * s22 - s12 * s12;
      final i01 = s02 * s12 - s01 * s22;
      final i02 = s01 * s12 - s02 * s11;
      final i11 = s00 * s22 - s02 * s02;
      final i12 = s01 * s02 - s00 * s12;
      final i22 = s00 * s11 - s01 * s01;
      final det = s00 * i00 + s01 * i01 + s02 * i02;
      final a0 = (i00 * cr + i01 * cg + i02 * cb) / det;
      final a1 = (i01 * cr + i11 * cg + i12 * cb) / det;
      final a2 = (i02 * cr + i12 * cg + i22 * cb) / det;
      ar[i] = a0;
      ag[i] = a1;
      ab[i] = a2;
      bb[i] = mp[i] - a0 * mr[i] - a1 * mg[i] - a2 * mb[i];
    }
    final mar = box(ar), mag = box(ag), mab = box(ab), mbb = box(bb);
    final q = Float32List(n);
    for (var i = 0; i < n; i++) {
      q[i] = mar[i] * ir[i] + mag[i] * ig[i] + mab[i] * ib[i] + mbb[i];
    }
    return q;
  }

  /// 視窗平均(邊界只算照片裡面的格子)。
  static Float32List _box(Float32List a, int w, int h, int r) {
    final tmp = Float32List(w * h);
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var s = 0.0;
      for (var x = 0; x <= math.min(r, w - 1); x++) {
        s += a[row + x];
      }
      for (var x = 0; x < w; x++) {
        final lo = x - r, hi = x + r;
        tmp[row + x] = s / (math.min(hi, w - 1) - math.max(lo, 0) + 1);
        if (hi + 1 < w) s += a[row + hi + 1];
        if (lo >= 0) s -= a[row + lo];
      }
    }
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var y = 0; y <= math.min(r, h - 1); y++) {
        s += tmp[y * w + x];
      }
      for (var y = 0; y < h; y++) {
        final lo = y - r, hi = y + r;
        out[y * w + x] = s / (math.min(hi, h - 1) - math.max(lo, 0) + 1);
        if (hi + 1 < h) s += tmp[(hi + 1) * w + x];
        if (lo >= 0) s -= tmp[lo * w + x];
      }
    }
    return out;
  }

  /// 每格到最近的筆畫(不是 0 的格子)有多遠(兩次掃描的近似距離)。
  static Float32List _distance(Int8List marks, int w, int h) {
    final n = w * h;
    const far = 1e9;
    final d = Float32List(n);
    for (var i = 0; i < n; i++) {
      d[i] = marks[i] != 0 ? 0 : far;
    }
    const diag = 1.4142;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        var v = d[i];
        if (x > 0) v = math.min(v, d[i - 1] + 1);
        if (y > 0) {
          v = math.min(v, d[i - w] + 1);
          if (x > 0) v = math.min(v, d[i - w - 1] + diag);
          if (x < w - 1) v = math.min(v, d[i - w + 1] + diag);
        }
        d[i] = v;
      }
    }
    for (var y = h - 1; y >= 0; y--) {
      for (var x = w - 1; x >= 0; x--) {
        final i = y * w + x;
        var v = d[i];
        if (x < w - 1) v = math.min(v, d[i + 1] + 1);
        if (y < h - 1) {
          v = math.min(v, d[i + w] + 1);
          if (x < w - 1) v = math.min(v, d[i + w + 1] + diag);
          if (x > 0) v = math.min(v, d[i + w - 1] + diag);
        }
        d[i] = v;
      }
    }
    return d;
  }

  static void _disc(
      Int8List a, int w, int h, int cx, int cy, double r, int value) {
    for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
      for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
          a[y * w + x] = value;
        }
      }
    }
  }

  static Uint8List _toRgba(Float64List img, int n) {
    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      out[i * 4] = img[i * 3].round();
      out[i * 4 + 1] = img[i * 3 + 1].round();
      out[i * 4 + 2] = img[i * 3 + 2].round();
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  static double _d2(Float64List img, int a, int b) {
    final dr = img[a * 3] - img[b * 3];
    final dg = img[a * 3 + 1] - img[b * 3 + 1];
    final db = img[a * 3 + 2] - img[b * 3 + 2];
    return dr * dr + dg * dg + db * db;
  }
}

/// 最小堆積(Dijkstra 用)。
class _Heap {
  final List<int> _node = [];
  final List<double> _key = [];

  bool get isNotEmpty => _node.isNotEmpty;

  void push(int node, double key) {
    _node.add(node);
    _key.add(key);
    var i = _node.length - 1;
    while (i > 0) {
      final up = (i - 1) >> 1;
      if (_key[up] <= _key[i]) break;
      _swap(i, up);
      i = up;
    }
  }

  (int, double) pop() {
    final top = (_node[0], _key[0]);
    final last = _node.length - 1;
    _swap(0, last);
    _node.removeLast();
    _key.removeLast();
    var i = 0;
    while (true) {
      final l = 2 * i + 1, r = l + 1;
      var m = i;
      if (l < _node.length && _key[l] < _key[m]) m = l;
      if (r < _node.length && _key[r] < _key[m]) m = r;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
    return top;
  }

  void _swap(int a, int b) {
    final n = _node[a];
    _node[a] = _node[b];
    _node[b] = n;
    final k = _key[a];
    _key[a] = _key[b];
    _key[b] = k;
  }
}

/// 照片縮成 [GrabCut.workSize] 的小圖,與原圖、小圖之間的換算。
class _Work {
  _Work(this.rgba, this.width, this.height)
      : k = math.min(1.0, GrabCut.workSize / math.max(width, height)) {
    w = math.max(8, (width * k).round());
    h = math.max(8, (height * k).round());
    img = _downscale();
  }

  final Uint8List rgba;
  final int width, height;
  final double k;
  late final int w, h;
  late final Float64List img;

  Float64List _downscale() {
    final out = Float64List(w * h * 3);
    for (var y = 0; y < h; y++) {
      final y0 = y * height ~/ h, y1 = math.max(y0 + 1, (y + 1) * height ~/ h);
      for (var x = 0; x < w; x++) {
        final x0 = x * width ~/ w, x1 = math.max(x0 + 1, (x + 1) * width ~/ w);
        var r = 0.0, g = 0.0, b = 0.0;
        var c = 0;
        for (var yy = y0; yy < y1; yy++) {
          for (var xx = x0; xx < x1; xx++) {
            final j = (yy * width + xx) * 4;
            r += rgba[j];
            g += rgba[j + 1];
            b += rgba[j + 2];
            c++;
          }
        }
        final i = (y * w + x) * 3;
        out[i] = r / c;
        out[i + 1] = g / c;
        out[i + 2] = b / c;
      }
    }
    return out;
  }

  int _cell(int i) {
    final x = i % width, y = i ~/ width;
    return (y * h ~/ height) * w + x * w ~/ width;
  }

  /// 原圖的遮罩縮成小圖的 0/1(一格裡一半以上留下就算留下)。
  Uint8List mask(Uint8List full) {
    final sum = Int32List(w * h), cnt = Int32List(w * h);
    for (var i = 0; i < full.length; i++) {
      final c = _cell(i);
      sum[c] += full[i];
      cnt[c]++;
    }
    return Uint8List.fromList([
      for (var c = 0; c < w * h; c++)
        cnt[c] > 0 && sum[c] > cnt[c] * 127 ? 1 : 0
    ]);
  }

  /// 原圖的筆畫縮成小圖:1 主體、-1 背景(同一格兩種都有的話算背景)。
  Int8List hints(Int8List? full) {
    final out = Int8List(w * h);
    if (full == null) return out;
    for (var i = 0; i < full.length; i++) {
      final v = full[i];
      if (v == 0) continue;
      final c = _cell(i);
      if (v < 0) {
        out[c] = -1;
      } else if (out[c] == 0) {
        out[c] = 1;
      }
    }
    return out;
  }
}

/// 連通的區塊(上下左右相連)。[id] 是每格屬於哪一塊,不是 [value] 的格子是 -1。
class _Components {
  _Components(Uint8List label, this.w, this.h, int value)
      : id = Int32List(w * h)..fillRange(0, w * h, -1) {
    final q = Queue<int>();
    for (var s = 0; s < w * h; s++) {
      if (label[s] != value || id[s] >= 0) continue;
      final c = sizes.length;
      var size = 0;
      var x0 = w, y0 = h, x1 = -1, y1 = -1;
      id[s] = c;
      q.add(s);
      while (q.isNotEmpty) {
        final p = q.removeFirst();
        size++;
        final px = p % w, py = p ~/ w;
        if (px < x0) x0 = px;
        if (px > x1) x1 = px;
        if (py < y0) y0 = py;
        if (py > y1) y1 = py;
        void visit(int o) {
          if (id[o] < 0 && label[o] == value) {
            id[o] = c;
            q.add(o);
          }
        }

        if (px > 0) visit(p - 1);
        if (px < w - 1) visit(p + 1);
        if (py > 0) visit(p - w);
        if (py < h - 1) visit(p + w);
      }
      sizes.add(size);
      _bounds.add((x0, y0, x1, y1));
    }
  }

  final int w, h;
  final Int32List id;
  final List<int> sizes = [];
  final List<(int, int, int, int)> _bounds = [];

  (int, int, int, int) bounds(int c) => _bounds[c];

  int largest() {
    var best = -1;
    for (var c = 0; c < sizes.length; c++) {
      if (best < 0 || sizes[c] > sizes[best]) best = c;
    }
    return best;
  }

  /// (x, y) 所在的那一塊;不在任何一塊上的話找附近最近的。
  int near(int x, int y) {
    for (var r = 0; r <= 6; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          final c = id[yy * w + xx];
          if (c >= 0) return c;
        }
      }
    }
    return -1;
  }
}

/// 高斯混合模型(3 維 RGB,完整共變異矩陣)。
class _Gmm {
  _Gmm(this.weights, this.means, this.inv, this.logNorm);

  static const int k = 5;

  final List<double> weights;
  final List<Float64List> means; // k 個 [r,g,b]
  final List<Float64List> inv; // k 個 3x3 反矩陣
  final List<double> logNorm; // log(weight) - 0.5 log det - 1.5 log 2π

  /// 用 [label] == [which] 的像素估模型:k-means 分 5 群,再算每群的
  /// 平均與共變異。像素太少時退回一個寬寬的高斯。
  static _Gmm fit(Float64List img, Uint8List label, int which,
      [List<int> extra = const []]) {
    final idx = <int>[];
    for (var i = 0; i < label.length; i++) {
      if (label[i] == which) idx.add(i);
    }
    // 玩家剛畫過的地方:顏色份量拉到三成,模型才記得「這種顏色是這一邊」
    if (extra.isNotEmpty) {
      final times = (idx.length * 0.3 / extra.length).ceil().clamp(1, 400);
      for (var t = 0; t < times; t++) {
        idx.addAll(extra);
      }
    }
    // 太多點的話抽樣,k-means 快一點
    final step = math.max(1, idx.length ~/ 6000);
    final pts = [for (var j = 0; j < idx.length; j += step) idx[j]];
    if (pts.length < k * 4) {
      return _Gmm(
        [1.0],
        [
          Float64List.fromList([128, 128, 128])
        ],
        [
          Float64List.fromList([1 / 4000, 0, 0, 0, 1 / 4000, 0, 0, 0, 1 / 4000])
        ],
        [-0.5 * math.log(4000.0 * 4000 * 4000) - 1.5 * math.log(2 * math.pi)],
      );
    }
    // k-means++ 簡化:照亮度排序後平均取 k 個起點(結果穩定、可重現)
    pts.sort((a, b) => (img[a * 3] + img[a * 3 + 1] + img[a * 3 + 2])
        .compareTo(img[b * 3] + img[b * 3 + 1] + img[b * 3 + 2]));
    final centers = [
      for (var c = 0; c < k; c++)
        Float64List.fromList([
          for (var ch = 0; ch < 3; ch++)
            img[pts[(pts.length * (c + 0.5) / k).floor()] * 3 + ch]
        ])
    ];
    final assign = Int32List(pts.length);
    for (var iter = 0; iter < 8; iter++) {
      for (var j = 0; j < pts.length; j++) {
        final p = pts[j] * 3;
        var best = 0;
        var bestD = double.infinity;
        for (var c = 0; c < k; c++) {
          final dr = img[p] - centers[c][0];
          final dg = img[p + 1] - centers[c][1];
          final db = img[p + 2] - centers[c][2];
          final d = dr * dr + dg * dg + db * db;
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        assign[j] = best;
      }
      for (var c = 0; c < k; c++) {
        var r = 0.0, g = 0.0, b = 0.0;
        var cnt = 0;
        for (var j = 0; j < pts.length; j++) {
          if (assign[j] != c) continue;
          final p = pts[j] * 3;
          r += img[p];
          g += img[p + 1];
          b += img[p + 2];
          cnt++;
        }
        if (cnt > 0) {
          centers[c]
            ..[0] = r / cnt
            ..[1] = g / cnt
            ..[2] = b / cnt;
        }
      }
    }
    final weights = <double>[];
    final means = <Float64List>[];
    final inv = <Float64List>[];
    final logNorm = <double>[];
    for (var c = 0; c < k; c++) {
      final members = [
        for (var j = 0; j < pts.length; j++)
          if (assign[j] == c) pts[j]
      ];
      if (members.length < 3) continue;
      final m = Float64List(3);
      for (final p in members) {
        for (var ch = 0; ch < 3; ch++) {
          m[ch] += img[p * 3 + ch];
        }
      }
      for (var ch = 0; ch < 3; ch++) {
        m[ch] /= members.length;
      }
      final cov = Float64List(9);
      for (final p in members) {
        for (var a = 0; a < 3; a++) {
          for (var b = 0; b < 3; b++) {
            cov[a * 3 + b] += (img[p * 3 + a] - m[a]) * (img[p * 3 + b] - m[b]);
          }
        }
      }
      for (var a = 0; a < 9; a++) {
        cov[a] /= members.length;
      }
      // 加一點點對角線,避免奇異矩陣(單色的區域)
      for (var a = 0; a < 3; a++) {
        cov[a * 4] += 4;
      }
      final det = _det3(cov);
      weights.add(members.length / pts.length);
      means.add(m);
      inv.add(_inv3(cov, det));
      logNorm.add(math.log(members.length / pts.length) -
          0.5 * math.log(det) -
          1.5 * math.log(2 * math.pi));
    }
    return _Gmm(weights, means, inv, logNorm);
  }

  /// −log p(顏色)。[img] 第 [i] 個像素。
  double cost(Float64List img, int i) {
    _tmp[0] = img[i * 3];
    _tmp[1] = img[i * 3 + 1];
    _tmp[2] = img[i * 3 + 2];
    return costOf(_tmp);
  }

  static final Float64List _tmp = Float64List(3);

  double costOf(Float64List px) {
    // log-sum-exp
    var best = -double.infinity;
    final terms = List<double>.filled(means.length, 0);
    for (var c = 0; c < means.length; c++) {
      final m = means[c], v = inv[c];
      final d0 = px[0] - m[0], d1 = px[1] - m[1], d2 = px[2] - m[2];
      final q = d0 * (v[0] * d0 + v[1] * d1 + v[2] * d2) +
          d1 * (v[3] * d0 + v[4] * d1 + v[5] * d2) +
          d2 * (v[6] * d0 + v[7] * d1 + v[8] * d2);
      final t = logNorm[c] - 0.5 * q;
      terms[c] = t;
      if (t > best) best = t;
    }
    var s = 0.0;
    for (final t in terms) {
      s += math.exp(t - best);
    }
    // 上限:極端不像的顏色不要給無限大的成本
    return math.min(60.0, -(best + math.log(s)));
  }

  static double _det3(Float64List m) =>
      m[0] * (m[4] * m[8] - m[5] * m[7]) -
      m[1] * (m[3] * m[8] - m[5] * m[6]) +
      m[2] * (m[3] * m[7] - m[4] * m[6]);

  static Float64List _inv3(Float64List m, double det) {
    final d = 1 / det;
    return Float64List.fromList([
      (m[4] * m[8] - m[5] * m[7]) * d,
      (m[2] * m[7] - m[1] * m[8]) * d,
      (m[1] * m[5] - m[2] * m[4]) * d,
      (m[5] * m[6] - m[3] * m[8]) * d,
      (m[0] * m[8] - m[2] * m[6]) * d,
      (m[2] * m[3] - m[0] * m[5]) * d,
      (m[3] * m[7] - m[4] * m[6]) * d,
      (m[1] * m[6] - m[0] * m[7]) * d,
      (m[0] * m[4] - m[1] * m[3]) * d,
    ]);
  }
}

/// 格子圖上的最大流(Boykov–Kolmogorov)。每個像素接 source、sink 與
/// 上下左右四個鄰居。[solve] 回傳每個像素在不在 source 那一邊(= 主體)。
class _MaxFlow {
  _MaxFlow(this.w, this.h, Float64List source, Float64List sink,
      Float64List right, Float64List down)
      : n = w * h,
        tr = Float64List(w * h),
        cap = Float64List(w * h * 4) {
    for (var i = 0; i < n; i++) {
      // 同時接 source 與 sink 的部分先直接流掉,只留差
      tr[i] = source[i] - sink[i];
      final x = i % w, y = i ~/ w;
      if (x < w - 1) {
        cap[i * 4 + _r] = right[i];
        cap[(i + 1) * 4 + _l] = right[i];
      }
      if (y < h - 1) {
        cap[i * 4 + _d] = down[i];
        cap[(i + w) * 4 + _u] = down[i];
      }
    }
  }

  final int w, h, n;

  /// > 0:還能從 source 流進來多少;< 0:還能流到 sink 多少。
  final Float64List tr;

  /// cap[i*4 + 方向]:從 i 往那個方向的鄰居還能流多少。
  final Float64List cap;

  static const _l = 0, _r = 1, _u = 2, _d = 3;
  static const _none = -1, _terminal = -2;
  static const _eps = 1e-9;

  int _nb(int i, int dir) => switch (dir) {
        _l => i - 1,
        _r => i + 1,
        _u => i - w,
        _ => i + w,
      };

  static int _opp(int dir) => dir ^ 1;

  bool _has(int i, int dir) {
    final x = i % w, y = i ~/ w;
    return switch (dir) {
      _l => x > 0,
      _r => x < w - 1,
      _u => y > 0,
      _ => y < h - 1,
    };
  }

  List<bool> solve() {
    final tree = Int8List(n); // 0 自由、1 S、2 T
    final parent = Int32List(n)..fillRange(0, n, _none); // 往父節點的方向
    final ts = Int32List(n);
    final dist = Int32List(n);
    var time = 0;
    final active = Queue<int>();
    final orphans = Queue<int>();
    for (var i = 0; i < n; i++) {
      if (tr[i] > _eps) {
        tree[i] = 1;
        parent[i] = _terminal;
        dist[i] = 1;
        active.add(i);
      } else if (tr[i] < -_eps) {
        tree[i] = 2;
        parent[i] = _terminal;
        dist[i] = 1;
        active.add(i);
      }
    }

    while (true) {
      // ---- 長樹,直到兩棵樹碰到 ----
      var meetS = -1, meetT = -1, meetDir = -1;
      while (active.isNotEmpty && meetS < 0) {
        final p = active.first;
        if (tree[p] == 0) {
          active.removeFirst();
          continue;
        }
        for (var dir = 0; dir < 4; dir++) {
          if (!_has(p, dir)) continue;
          final q = _nb(p, dir);
          final c = tree[p] == 1 ? cap[p * 4 + dir] : cap[q * 4 + _opp(dir)];
          if (c <= _eps) continue;
          if (tree[q] == 0) {
            tree[q] = tree[p];
            parent[q] = _opp(dir);
            ts[q] = ts[p];
            dist[q] = dist[p] + 1;
            active.add(q);
          } else if (tree[q] != tree[p]) {
            if (tree[p] == 1) {
              meetS = p;
              meetT = q;
              meetDir = dir;
            } else {
              meetS = q;
              meetT = p;
              meetDir = _opp(dir);
            }
            break;
          }
        }
        // 四個鄰居都看過了;碰到另一棵樹的話留著,增廣完再從它繼續長
        if (meetS < 0) active.removeFirst();
      }
      if (meetS < 0) break;

      // ---- 增廣:找瓶頸 ----
      var bottleneck = cap[meetS * 4 + meetDir];
      for (var x = meetS; parent[x] != _terminal;) {
        final y = _nb(x, parent[x]);
        final c = cap[y * 4 + _opp(parent[x])];
        if (c < bottleneck) bottleneck = c;
        x = y;
      }
      var root = meetS;
      while (parent[root] != _terminal) {
        root = _nb(root, parent[root]);
      }
      if (tr[root] < bottleneck) bottleneck = tr[root];
      for (var x = meetT; parent[x] != _terminal;) {
        final c = cap[x * 4 + parent[x]];
        if (c < bottleneck) bottleneck = c;
        x = _nb(x, parent[x]);
      }
      var rootT = meetT;
      while (parent[rootT] != _terminal) {
        rootT = _nb(rootT, parent[rootT]);
      }
      if (-tr[rootT] < bottleneck) bottleneck = -tr[rootT];

      // ---- 推流 ----
      cap[meetS * 4 + meetDir] -= bottleneck;
      cap[meetT * 4 + _opp(meetDir)] += bottleneck;
      for (var x = meetS; parent[x] != _terminal;) {
        final y = _nb(x, parent[x]);
        cap[y * 4 + _opp(parent[x])] -= bottleneck;
        cap[x * 4 + parent[x]] += bottleneck;
        if (cap[y * 4 + _opp(parent[x])] <= _eps) {
          parent[x] = _none;
          orphans.add(x);
        }
        x = y;
      }
      tr[root] -= bottleneck;
      if (tr[root] <= _eps) {
        parent[root] = _none;
        orphans.add(root);
      }
      for (var x = meetT; parent[x] != _terminal;) {
        final y = _nb(x, parent[x]);
        cap[x * 4 + parent[x]] -= bottleneck;
        cap[y * 4 + _opp(parent[x])] += bottleneck;
        if (cap[x * 4 + parent[x]] <= _eps) {
          parent[x] = _none;
          orphans.add(x);
        }
        x = y;
      }
      tr[rootT] += bottleneck;
      if (tr[rootT] >= -_eps) {
        parent[rootT] = _none;
        orphans.add(rootT);
      }

      // ---- 收養孤兒 ----
      time++;
      while (orphans.isNotEmpty) {
        final o = orphans.removeFirst();
        final t = tree[o];
        var bestDir = -1;
        var bestDist = 1 << 30;
        for (var dir = 0; dir < 4; dir++) {
          if (!_has(o, dir)) continue;
          final q = _nb(o, dir);
          if (tree[q] != t) continue;
          final c = t == 1 ? cap[q * 4 + _opp(dir)] : cap[o * 4 + dir];
          if (c <= _eps) continue;
          // q 的根是不是終端
          var d = 0;
          var x = q;
          var ok = false;
          while (true) {
            if (ts[x] == time) {
              d += dist[x];
              ok = true;
              break;
            }
            final pd = parent[x];
            d++;
            if (pd == _terminal) {
              ts[x] = time;
              dist[x] = 1;
              ok = true;
              break;
            }
            if (pd == _none) break;
            x = _nb(x, pd);
          }
          if (ok) {
            // 沿路記下時間與距離,下次查得快
            var y = q;
            var dd = d;
            while (ts[y] != time) {
              ts[y] = time;
              dist[y] = dd--;
              y = _nb(y, parent[y]);
            }
            if (d < bestDist) {
              bestDist = d;
              bestDir = dir;
            }
          }
        }
        if (bestDir >= 0) {
          parent[o] = bestDir;
          ts[o] = time;
          dist[o] = bestDist + 1;
          continue;
        }
        // 找不到新爸爸:變自由節點,鄰居可能要重新長
        for (var dir = 0; dir < 4; dir++) {
          if (!_has(o, dir)) continue;
          final q = _nb(o, dir);
          if (tree[q] != t) continue;
          final c = t == 1 ? cap[q * 4 + _opp(dir)] : cap[o * 4 + dir];
          if (c > _eps) active.add(q);
          if (parent[q] != _none &&
              parent[q] != _terminal &&
              _nb(q, parent[q]) == o) {
            parent[q] = _none;
            orphans.add(q);
          }
        }
        tree[o] = 0;
      }
    }
    return [for (var i = 0; i < n; i++) tree[i] == 1];
  }
}
