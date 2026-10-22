import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../services/timelapse_recorder.dart';
import '../theme.dart';
import 'cutout.dart';
import 'grabcut.dart';
import 'subject_segmenter.dart';

/// 在這個大小（最長邊）上去背：做成貼紙夠清楚，GrabCut 也還算得快。
const int _workSize = 1024;

enum _Engine { ai, grabcut }

enum _Brush { erase, restore }

/// 去背編輯頁。打開就先自動去背（手機內建 AI，不能用就退回 GrabCut），
/// 也可以自己換引擎、長按重選主體、用筆刷擦掉或補回。
///
/// 回傳去好背、加上白色描邊、裁到主體大小的 PNG；按返回回傳 null。
class CutoutPage extends StatefulWidget {
  /// 照片原檔（jpg、png…）。
  final Uint8List photo;
  /// 有的話，去背的過程也錄進縮時影片。
  final TimelapseRecorder? recorder;
  const CutoutPage({super.key, required this.photo, this.recorder});

  static Future<Uint8List?> open(BuildContext context, Uint8List photo, {TimelapseRecorder? recorder}) =>
      Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => CutoutPage(photo: photo, recorder: recorder)));

  @override
  State<CutoutPage> createState() => _CutoutPageState();
}

class _CutoutPageState extends State<CutoutPage> {
  ui.Image? _photo, _masked;
  Uint8List? _rgba, _mask;
  Int8List? _hints;
  int _w = 0, _h = 0;
  bool _busy = true;
  String _status = '去背中…';
  _Brush _brush = _Brush.erase;
  /// 開著：畫一筆之後用 GrabCut 沿著邊緣重切；關著：筆刷塗到哪就是哪。
  bool _snap = true;
  // 每一步連狀態列的說明一起記，復原之後才不會顯示錯的去背方法
  final _undo = <(Uint8List, Int8List, String)>[];
  final _redo = <(Uint8List, Int8List, String)>[];
  final _strokeScreen = <Offset>[];
  final _strokePhoto = <Offset>[];
  Offset? _cursor;
  bool _painted = false;
  final _shotKey = GlobalKey();
  DateTime _lastRefresh = DateTime(0);

  /// 筆刷半徑（螢幕上的點）。
  double _brushScreen = 22;
  static const double _minBrush = 6, _maxBrush = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _photo?.dispose();
    _masked?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(widget.photo);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final s = math.min(1.0, _workSize / math.max(desc.width, desc.height));
    final codec = await desc.instantiateCodec(targetWidth: (desc.width * s).round(), targetHeight: (desc.height * s).round());
    final image = (await codec.getNextFrame()).image;
    // 不預乘 alpha：顏色才是原本的顏色
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (!mounted) {
      image.dispose();
      return;
    }
    final rgba = data!.buffer.asUint8List();
    // 透明的地方當作不透明處理：遮罩另外套
    for (var i = 3; i < rgba.length; i += 4) {
      rgba[i] = 255;
    }
    setState(() {
      _photo = image;
      _rgba = rgba;
      _w = image.width;
      _h = image.height;
      _hints = Int8List(_w * _h);
    });
    await _run(_Engine.ai);
  }

  /// 整張重新去背。[at] 是長按的位置（照片像素），只留那一塊。
  /// AI 不能用（模擬器、沒有 Google Play 服務、按的地方不是前景）會自動改用 GrabCut。
  Future<void> _run(_Engine engine, {Offset? at}) async {
    final rgba = _rgba;
    if (rgba == null) return;
    setState(() {
      _busy = true;
      _status = engine == _Engine.ai ? 'AI 去背中…' : '手動去背中…';
    });
    final x = at?.dx.floor(), y = at?.dy.floor();
    final hints = Int8List(_w * _h);
    if (at != null) _paintHint(hints, at.dx, at.dy, math.min(_w, _h) * .03, 1);
    Uint8List? mask;
    var used = engine;
    if (engine == _Engine.ai) mask = await SubjectSegmenter.select(rgba, _w, _h, x: x, y: y);
    if (mask == null) {
      used = _Engine.grabcut;
      mask = await compute(_selectJob, (rgba: rgba, w: _w, h: _h, x: x, y: y, hints: hints));
    }
    if (!mounted) return;
    if (_mask != null) _pushUndo();
    _mask = mask;
    _hints = hints;
    _busy = false;
    _status = switch ((engine, used)) {
      (_Engine.ai, _Engine.ai) => '用手機內建 AI 去背',
      (_Engine.ai, _) => 'AI 這次認不出來，改用手動去背',
      _ => '用手動去背（依顏色和邊緣判斷）',
    };
    await _refresh();
  }

  // ---------------- 筆刷 ----------------

  Size _fitted(Size box) {
    final s = math.min(box.width / _w, box.height / _h);
    return Size(_w * s, _h * s);
  }

  Offset _toPhoto(Offset local, Size box) {
    final f = _fitted(box);
    final s = f.width / _w;
    return Offset((local.dx - (box.width - f.width) / 2) / s, (local.dy - (box.height - f.height) / 2) / s);
  }

  double _brushInPhoto(Size box) => _brushScreen / (_fitted(box).width / _w);

  /// 貼齊邊緣的筆畫在照片上多粗：細細一條就好，畫歪一點跨到主體也沒關係；
  /// 筆刷調粗時跟著粗一點，一筆可以蓋到比較大的東西。
  double _strokeRadius(Size box) => math.max(math.max(1.5, math.max(_w, _h) * .004), _brushInPhoto(box) * .35);

  void _paintHint(Int8List a, double cx, double cy, double r, int v) {
    final x0 = math.max(0, (cx - r).floor()), x1 = math.min(_w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor()), y1 = math.min(_h - 1, (cy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) a[y * _w + x] = v;
      }
    }
  }

  /// 編輯區的大小（最近一次手勢時），放開手指時換算筆畫粗細用。
  Size _box = Size.zero;

  void _onPanStart(DragStartDetails d, Size box) {
    _box = box;
    if (_busy || _mask == null) return;
    _strokeScreen
      ..clear()
      ..add(d.localPosition);
    _strokePhoto
      ..clear()
      ..add(_toPhoto(d.localPosition, box));
    if (!_snap) {
      _pushUndo();
      _painted = true;
      _brushAt(d.localPosition, box);
    }
    setState(() => _cursor = d.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails d, Size box) {
    if (_busy || _mask == null) return;
    if (_snap) {
      setState(() {
        _strokeScreen.add(d.localPosition);
        _strokePhoto.add(_toPhoto(d.localPosition, box));
        _cursor = d.localPosition;
      });
    } else {
      _brushAt(d.localPosition, box);
    }
  }

  void _onPanEnd() {
    setState(() => _cursor = null);
    if (_snap && _strokePhoto.isNotEmpty) {
      _applyStroke(List.of(_strokePhoto), _strokeRadius(_box));
    } else if (_painted) {
      _painted = false;
      _refresh();
    }
  }

  void _brushAt(Offset local, Size box) {
    final mask = _mask, hints = _hints;
    if (mask == null) return;
    final p = _toPhoto(local, box);
    final r = _brushInPhoto(box);
    final keep = _brush == _Brush.restore;
    Cutout.paintMask(mask, _w, _h, p.dx, p.dy, r, keep: keep);
    // 記下來：之後貼齊邊緣重切時，這裡照筆刷的樣子不動
    if (hints != null) _paintHint(hints, p.dx, p.dy, r, keep ? 2 : -2);
    _cursor = local;
    // 邊塗邊看，但不要每一格都重畫整張
    final now = DateTime.now();
    if (now.difference(_lastRefresh).inMilliseconds > 60) {
      _lastRefresh = now;
      _refresh();
    } else {
      setState(() {});
    }
  }

  /// 貼齊邊緣：剛畫的一筆當作提示，用 GrabCut 重切一次。
  Future<void> _applyStroke(List<Offset> pts, double radius) async {
    final rgba = _rgba, mask = _mask;
    if (rgba == null || mask == null || pts.isEmpty) return;
    final v = _brush == _Brush.erase ? -1 : 1;
    final stroke = Int8List(_w * _h);
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = i + 1 < pts.length ? pts[i + 1] : pts[i];
      final steps = math.max(1, ((b - a).distance / (radius * .5)).ceil());
      for (var k = 0; k <= steps; k++) {
        final q = Offset.lerp(a, b, k / steps)!;
        _paintHint(stroke, q.dx, q.dy, radius, v);
      }
    }
    final hints = Int8List.fromList(_hints ?? Int8List(_w * _h));
    // 「補回」畫一筆：附近之前用一般筆刷擦掉的地方不再鎖住，不然補不回來
    if (v > 0) {
      final r = math.max(_w, _h) * .15;
      final x0 = math.max(0, (pts.map((p) => p.dx).reduce(math.min) - r).floor());
      final x1 = math.min(_w - 1, (pts.map((p) => p.dx).reduce(math.max) + r).ceil());
      final y0 = math.max(0, (pts.map((p) => p.dy).reduce(math.min) - r).floor());
      final y1 = math.min(_h - 1, (pts.map((p) => p.dy).reduce(math.max) + r).ceil());
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final i = y * _w + x;
          if (hints[i] != -2) continue;
          for (final p in pts) {
            if ((p.dx - x) * (p.dx - x) + (p.dy - y) * (p.dy - y) <= r * r) {
              hints[i] = 0;
              break;
            }
          }
        }
      }
    }
    for (var i = 0; i < stroke.length; i++) {
      if (stroke[i] != 0) hints[i] = stroke[i];
    }
    setState(() => _busy = true);
    final out = await compute(_refineJob, (rgba: rgba, w: _w, h: _h, mask: mask, hints: hints, stroke: stroke));
    if (!mounted) return;
    _pushUndo();
    _mask = out;
    _hints = hints;
    _busy = false;
    _strokeScreen.clear();
    _strokePhoto.clear();
    await _refresh();
  }

  // ---------------- 復原 ----------------

  (Uint8List, Int8List, String) _snapshot() => (Uint8List.fromList(_mask!), Int8List.fromList(_hints ?? Int8List(_w * _h)), _status);

  void _pushUndo() {
    if (_mask == null) return;
    _redo.clear();
    _undo.add(_snapshot());
    if (_undo.length > 12) _undo.removeAt(0);
  }

  void _undoStep() {
    if (_undo.isEmpty || _mask == null || _busy) return;
    _redo.add(_snapshot());
    final (mask, hints, status) = _undo.removeLast();
    _mask = mask;
    _hints = hints;
    _status = status;
    _refresh();
  }

  void _redoStep() {
    if (_redo.isEmpty || _mask == null || _busy) return;
    _undo.add(_snapshot());
    final (mask, hints, status) = _redo.removeLast();
    _mask = mask;
    _hints = hints;
    _status = status;
    _refresh();
  }

  Future<void> _refresh() async {
    final rgba = _rgba, mask = _mask;
    if (rgba == null || mask == null) return;
    final img = await _imageFromRgba(Cutout.apply(rgba, mask), _w, _h);
    if (!mounted) {
      img.dispose();
      return;
    }
    final old = _masked;
    setState(() => _masked = img);
    old?.dispose();
    final recorder = widget.recorder;
    if (recorder != null) WidgetsBinding.instance.addPostFrameCallback((_) => recorder.request(_frame));
  }

  /// 縮時影片的一格：去背中的照片（格紋底）。
  Future<ui.Image?> _frame() async {
    final b = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (!mounted || b == null || !b.attached || b.size.isEmpty) return null;
    return b.toImage(pixelRatio: 1000 / b.size.longestSide);
  }

  // ---------------- 完成 ----------------

  Future<void> _done() async {
    final rgba = _rgba, mask = _mask;
    if (rgba == null || mask == null || _busy) return;
    if (Cutout.bounds(mask, _w, _h) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('全部都擦掉了，先補回一點再完成')));
      return;
    }
    setState(() {
      _busy = true;
      _status = '做成貼紙中…';
    });
    final baked = await compute(bakeSticker, (rgba: rgba, mask: mask, w: _w, h: _h));
    final img = await _imageFromRgba(baked.rgba, baked.w, baked.h);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (!mounted) return;
    Navigator.pop(context, png?.buffer.asUint8List());
  }

  // ---------------- 畫面 ----------------

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: ink)),
          const Expanded(child: Text('去背', style: TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900))),
          IconButton(onPressed: _undo.isEmpty || _busy ? null : _undoStep, icon: const Icon(Icons.undo_rounded), color: ink, disabledColor: line),
          IconButton(onPressed: _redo.isEmpty || _busy ? null : _redoStep, icon: const Icon(Icons.redo_rounded), color: ink, disabledColor: line),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _busy || _mask == null ? null : _done,
            style: FilledButton.styleFrom(backgroundColor: coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('完成', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: _editor())),
      _controls(),
    ])),
  );

  Widget _editor() {
    final photo = _photo;
    if (photo == null) return const Center(child: CircularProgressIndicator(color: coral));
    return LayoutBuilder(builder: (context, c) {
      final box = c.biggest;
      final f = _fitted(box);
      final rect = Rect.fromLTWH((box.width - f.width) / 2, (box.height - f.height) / 2, f.width, f.height);
      return GestureDetector(
        onPanStart: (d) => _onPanStart(d, box),
        onPanUpdate: (d) => _onPanUpdate(d, box),
        onPanEnd: (_) => _onPanEnd(),
        onLongPressStart: _busy ? null : (d) {
          HapticFeedback.mediumImpact();
          final p = _toPhoto(d.localPosition, box);
          if (p.dx >= 0 && p.dy >= 0 && p.dx < _w && p.dy < _h) _run(_Engine.ai, at: p);
        },
        child: Stack(children: [
          Positioned.fromRect(rect: rect, child: RepaintBoundary(key: _shotKey, child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(fit: StackFit.expand, children: [
              const CustomPaint(painter: _CheckerPainter()),
              // 原圖淡淡的一層：看得到擦掉了什麼，補回才知道要塗哪裡
              Opacity(opacity: .22, child: RawImage(image: photo, fit: BoxFit.fill)),
              if (_masked != null) RawImage(image: _masked, fit: BoxFit.fill),
            ]),
          ))),
          if (_strokeScreen.length > 1)
            Positioned.fill(child: CustomPaint(painter: _StrokePainter(List.of(_strokeScreen), _brush == _Brush.erase ? coral : const Color(0xFF4CB97A), math.max(4, _brushScreen * .7)))),
          if (_cursor != null)
            Positioned(
              left: _cursor!.dx - _brushScreen, top: _cursor!.dy - _brushScreen,
              child: IgnorePointer(child: Container(
                width: _brushScreen * 2, height: _brushScreen * 2,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)]),
              )),
            ),
          if (_busy)
            Positioned.fill(child: ColoredBox(
              color: cream.withValues(alpha: .55),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: coral),
                const SizedBox(height: 12),
                Text(_status, style: const TextStyle(color: ink, fontWeight: FontWeight.w700)),
              ])),
            )),
        ]),
      );
    });
  }

  Widget _controls() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 18, offset: const Offset(0, -4))],
    ),
    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.info_outline_rounded, size: 15, color: muted.withValues(alpha: .9)),
        const SizedBox(width: 6),
        Expanded(child: Text(_busy ? _status : '$_status・長按想留下的東西可以重選', maxLines: 2,
          style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _ChoiceButton(icon: Icons.auto_awesome_rounded, label: 'AI 去背', onTap: _busy ? null : () => _run(_Engine.ai))),
        const SizedBox(width: 8),
        Expanded(child: _ChoiceButton(icon: Icons.touch_app_outlined, label: '手動去背', onTap: _busy ? null : () => _run(_Engine.grabcut))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _ToggleChip(icon: Icons.auto_fix_off_rounded, label: '擦掉', selected: _brush == _Brush.erase, onTap: () => setState(() => _brush = _Brush.erase)),
        const SizedBox(width: 8),
        _ToggleChip(icon: Icons.brush_rounded, label: '補回', selected: _brush == _Brush.restore, onTap: () => setState(() => _brush = _Brush.restore)),
        const Spacer(),
        const Text('貼齊邊緣', style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
        Switch(value: _snap, activeTrackColor: coral, onChanged: (v) => setState(() => _snap = v)),
      ]),
      Row(children: [
        const Text('筆刷大小', style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
        Expanded(child: Slider(
          value: _brushScreen, min: _minBrush, max: _maxBrush,
          activeColor: coral, inactiveColor: line,
          onChanged: (v) => setState(() => _brushScreen = v),
        )),
        // 實際大小的預覽
        SizedBox.square(dimension: 40, child: Center(child: Container(
          width: math.min(40, _brushScreen), height: math.min(40, _brushScreen),
          decoration: BoxDecoration(
            color: (_brush == _Brush.erase ? coral : const Color(0xFF4CB97A)).withValues(alpha: .35),
            shape: BoxShape.circle,
            border: Border.all(color: _brush == _Brush.erase ? coral : const Color(0xFF4CB97A), width: 1.5),
          ),
        ))),
      ]),
      Text(_snap ? '在要擦掉（或補回）的東西上隨手畫一筆，會自動沿著邊緣切。' : '筆刷塗到哪裡就擦到哪裡，適合修小地方。',
        style: TextStyle(fontSize: 11, color: muted.withValues(alpha: .9))),
    ])),
  );
}

class _ChoiceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ChoiceButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    style: OutlinedButton.styleFrom(
      foregroundColor: ink, backgroundColor: cream, side: const BorderSide(color: line, width: 1.3),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class _ToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? blush : cream, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? blushLine : line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: ink),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 13, color: ink, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
      ]),
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()..color = const Color(0xFFEDE7E1);
    const s = 12.0;
    for (var y = 0.0, r = 0; y < size.height; y += s, r++) {
      for (var x = r.isEven ? 0.0 : s; x < size.width; x += s * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}

class _StrokePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double width;
  const _StrokePainter(this.points, this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPoints(ui.PointMode.polygon, points, Paint()
    ..color = color.withValues(alpha: .7)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round);

  @override
  bool shouldRepaint(_StrokePainter old) => old.points.length != points.length || old.color != color || old.width != width;
}

// ---------------- 在背景執行緒跑的工作 ----------------

Uint8List _selectJob(({Uint8List rgba, int w, int h, int? x, int? y, Int8List hints}) a) =>
    GrabCut.select(a.rgba, a.w, a.h, px: a.x, py: a.y, hints: a.hints);

Uint8List _refineJob(({Uint8List rgba, int w, int h, Uint8List mask, Int8List hints, Int8List stroke}) a) =>
    GrabCut.refine(a.rgba, a.w, a.h, a.mask, a.hints, a.stroke);

Future<ui.Image> _imageFromRgba(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 去好背的主體加上一圈白色描邊（像真的貼紙），裁到主體大小。
/// 回傳預乘 alpha 的 RGBA（decodeImageFromPixels 把像素當成預乘過的）。
@visibleForTesting
({Uint8List rgba, int w, int h}) bakeSticker(({Uint8List rgba, Uint8List mask, int w, int h}) a) {
  final w = a.w, h = a.h, n = w * h;
  final r = math.max(4, (math.max(w, h) * .022).round());
  // 到主體的距離（3-4 倒角距離，除以 3 約等於像素）
  const inf = 1 << 28;
  final d = Int32List(n);
  for (var i = 0; i < n; i++) {
    d[i] = a.mask[i] > 127 ? 0 : inf;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var v = d[i];
      if (v == 0) continue;
      if (x > 0) v = math.min(v, d[i - 1] + 3);
      if (y > 0) {
        v = math.min(v, d[i - w] + 3);
        if (x > 0) v = math.min(v, d[i - w - 1] + 4);
        if (x < w - 1) v = math.min(v, d[i - w + 1] + 4);
      }
      d[i] = v;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      var v = d[i];
      if (v == 0) continue;
      if (x < w - 1) v = math.min(v, d[i + 1] + 3);
      if (y < h - 1) {
        v = math.min(v, d[i + w] + 3);
        if (x < w - 1) v = math.min(v, d[i + w + 1] + 4);
        if (x > 0) v = math.min(v, d[i + w - 1] + 4);
      }
      d[i] = v;
    }
  }
  // 範圍：主體加上描邊
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (d[y * w + x] <= (r + 1) * 3) {
        x0 = math.min(x0, x);
        x1 = math.max(x1, x);
        y0 = math.min(y0, y);
        y1 = math.max(y1, y);
      }
    }
  }
  final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final i = (y + y0) * w + (x + x0);
      final m = a.mask[i] / 255;
      final dist = d[i] / 3;
      final o = (r + .5 - dist).clamp(0.0, 1.0); // 白邊覆蓋率
      final alpha = m + (1 - m) * o;
      final j = (y * cw + x) * 4;
      for (var c = 0; c < 3; c++) {
        out[j + c] = (a.rgba[i * 4 + c] * m + 255 * (1 - m) * o).round().clamp(0, 255);
      }
      out[j + 3] = (alpha * 255).round().clamp(0, 255);
    }
  }
  return (rgba: out, w: cw, h: ch);
}
