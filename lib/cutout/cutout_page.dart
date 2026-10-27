import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/timelapse_recorder.dart';
import '../theme.dart';
import 'cutout.dart';
import 'grabcut.dart';
import 'subject_segmenter.dart';

/// 在這個大小（最長邊）上去背：做成貼紙夠清楚，GrabCut 也還算得快。
const int _workSize = 1024;

enum _Step { select, refine, preview }

/// White border choices: label and size relative to the photo's long side.
const _borders = [('無', 0.0), ('細', .014), ('粗', .03)];

/// 去背頁，三個步驟：
/// 1. 選主體：手機內建 AI 把照片裡的人和東西一個個找出來，點要留下的（可以多選）；
///    AI 不能用或找不到，自動改用手動去背（GrabCut）。
/// 2. 修邊：擦掉或補回，兩指可以放大、拖曳。
/// 3. 預覽：看做成貼紙（加白邊）的樣子，選白邊粗細。
///
/// 回傳做好的貼紙 PNG；按返回回傳 null。
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
  ui.Image? _photo, _masked, _baked;
  Uint8List? _rgba;
  int _w = 0, _h = 0;
  bool _busy = true;
  String _status = '找主體中…';
  _Step _step = _Step.select;

  /// One mask per subject (0–255, w × h), biggest first, and their bounds.
  List<Uint8List> _subjects = [];
  List<Rect> _boxes = [];
  final _chosen = <int>{};
  /// Brush edits on top of the chosen subjects: 1 keep, -1 erase, 0 as chosen.
  Int8List _edits = Int8List(0);
  /// The result: chosen subjects plus edits.
  Uint8List _mask = Uint8List(0);
  final _undo = <Int8List>[];
  final _redo = <Int8List>[];

  /// Selecting: a line drawn to cut touching subjects apart (screen points).
  final _cut = <Offset>[];
  bool _restore = false;
  /// Brush radius on screen.
  double _brushScreen = 22;
  static const double _minBrush = 6, _maxBrush = 60;
  Offset? _cursor;
  bool _painting = false;
  DateTime _lastRefresh = DateTime(0);

  // Two-finger zoom and pan of the picture.
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _gestureZoom = 1;
  Offset _gesturePan = Offset.zero, _gestureFocal = Offset.zero;
  bool _twoFingers = false;
  Size _box = Size.zero;

  int _border = 1;
  final _shotKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _photo?.dispose();
    _masked?.dispose();
    _baked?.dispose();
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
      _edits = Int8List(_w * _h);
      _mask = Uint8List(_w * _h);
    });
    await _findSubjects();
  }

  /// Find the subjects with the phone's AI; without it (or when it finds
  /// nothing) fall back to manual cut-out (GrabCut), split into pieces.
  Future<void> _findSubjects({bool manual = false}) async {
    final rgba = _rgba;
    if (rgba == null) return;
    setState(() {
      _busy = true;
      _status = manual ? '手動去背中…' : '找主體中…';
    });
    List<Uint8List>? found = manual ? null : await SubjectSegmenter.subjects(rgba, _w, _h);
    var usedAi = found != null && found.isNotEmpty;
    if (!usedAi) {
      final fg = await compute(_autoJob, (rgba: rgba, w: _w, h: _h));
      final parts = await compute(_splitJob, (fg: fg, w: _w, h: _h));
      found = parts.isEmpty ? [fg] : parts;
    }
    if (!mounted) return;
    _subjects = found;
    _boxes = [for (final m in _subjects) _bounds(m)];
    _chosen
      ..clear()
      ..addAll(List.generate(_subjects.length, (i) => i));
    _edits = Int8List(_w * _h);
    _undo.clear();
    _redo.clear();
    _status = usedAi
      ? (_subjects.length > 1 ? '找到 ${_subjects.length} 個主體，點一下可以取消或選回來' : '找到主體了，不是要的可以改用手動去背')
      : (manual ? '用手動去背（依顏色和邊緣判斷）' : 'AI 這次認不出來，改用手動去背');
    _busy = false;
    await _compose();
  }

  Rect _bounds(Uint8List m) {
    var x0 = _w, y0 = _h, x1 = -1, y1 = -1;
    for (var y = 0; y < _h; y += 2) {
      final row = y * _w;
      for (var x = 0; x < _w; x += 2) {
        if (m[row + x] > 127) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    return x1 < 0 ? Rect.zero : Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
  }

  /// Rebuild [_mask] from the chosen subjects and the brush edits.
  Future<void> _compose() async {
    final n = _w * _h;
    final m = Uint8List(n);
    for (final c in _chosen) {
      final s = _subjects[c];
      for (var i = 0; i < n; i++) {
        if (s[i] > m[i]) m[i] = s[i];
      }
    }
    for (var i = 0; i < n; i++) {
      final e = _edits[i];
      if (e != 0) m[i] = e > 0 ? 255 : 0;
    }
    _mask = m;
    await _refresh();
  }

  Future<void> _refresh() async {
    final rgba = _rgba;
    if (rgba == null) return;
    final img = await _imageFromRgba(Cutout.apply(rgba, _mask), _w, _h);
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

  bool get _empty => !_mask.any((v) => v > 127);

  // ---------------- 選主體 ----------------

  void _toggleAt(Offset p) {
    final x = p.dx.floor(), y = p.dy.floor();
    if (x < 0 || y < 0 || x >= _w || y >= _h) return;
    var hit = -1;
    var best = 0;
    for (var i = 0; i < _subjects.length; i++) {
      final v = _subjects[i][y * _w + x];
      if (v > 127 && v >= best) {
        hit = i;
        best = v;
      }
    }
    if (hit < 0) {
      // Not on a subject: the smallest box around the point.
      var area = double.infinity;
      for (var i = 0; i < _boxes.length; i++) {
        final b = _boxes[i];
        if (b.contains(p) && b.width * b.height < area) {
          hit = i;
          area = b.width * b.height;
        }
      }
    }
    if (hit >= 0) _toggle(hit);
  }

  /// Cut every subject along the drawn line and split the pieces into
  /// separate subjects (touching people come back from the AI as one).
  Future<void> _applyCut(List<Offset> screen) async {
    if (screen.length < 2) return;
    final pts = [for (final p in screen) _toPhoto(p)];
    final r = math.max(2.0, math.min(_w, _h) * .006);
    final next = <Uint8List>[];
    final chosen = <int>{};
    var split = 0;
    for (var k = 0; k < _subjects.length; k++) {
      final m = Uint8List.fromList(_subjects[k]);
      for (var i = 0; i + 1 < pts.length; i++) {
        final a = pts[i], b = pts[i + 1];
        final steps = math.max(1, ((b - a).distance / (r * .5)).ceil());
        for (var j = 0; j <= steps; j++) {
          final q = Offset.lerp(a, b, j / steps)!;
          final x0 = math.max(0, (q.dx - r).floor()), x1 = math.min(_w - 1, (q.dx + r).ceil());
          final y0 = math.max(0, (q.dy - r).floor()), y1 = math.min(_h - 1, (q.dy + r).ceil());
          for (var y = y0; y <= y1; y++) {
            for (var x = x0; x <= x1; x++) {
              if ((x - q.dx) * (x - q.dx) + (y - q.dy) * (y - q.dy) <= r * r) m[y * _w + x] = 0;
            }
          }
        }
      }
      final parts = await compute(_splitJob, (fg: m, w: _w, h: _h));
      final pieces = parts.isEmpty ? [_subjects[k]] : parts;
      if (pieces.length > 1) split += pieces.length - 1;
      for (final piece in pieces) {
        if (_chosen.contains(k)) chosen.add(next.length);
        next.add(piece);
      }
    }
    if (!mounted) return;
    if (split == 0) {
      showMessage(context, '沒有切開，線要從一邊畫到另一邊，把兩個主體完全分開');
      return;
    }
    _subjects = next;
    _boxes = [for (final m in next) _bounds(m)];
    _chosen
      ..clear()
      ..addAll(chosen);
    _edits = Int8List(_w * _h);
    _status = '切開了，點一下不要的就會拿掉';
    await _compose();
  }

  void _toggle(int i) {
    setState(() => _chosen.contains(i) ? _chosen.remove(i) : _chosen.add(i));
    _compose();
  }

  // ---------------- 修邊 ----------------

  /// The picture's rect inside the editor box, before zoom.
  Rect _fitted(Size box) {
    final s = math.min(box.width / _w, box.height / _h);
    return Rect.fromLTWH((box.width - _w * s) / 2, (box.height - _h * s) / 2, _w * s, _h * s);
  }

  Offset _toPhoto(Offset local) {
    final f = _fitted(_box);
    final v = (local - _pan) / _zoom;
    final s = f.width / _w;
    return Offset((v.dx - f.left) / s, (v.dy - f.top) / s);
  }

  double get _brushInPhoto => _brushScreen / (_fitted(_box).width / _w * _zoom);

  void _pushUndo() {
    _undo.add(Int8List.fromList(_edits));
    if (_undo.length > 20) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _redo.add(_edits);
    _edits = _undo.removeLast();
    _compose();
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _undo.add(_edits);
    _edits = _redo.removeLast();
    _compose();
  }

  void _paintAt(Offset local) {
    final p = _toPhoto(local);
    final r = _brushInPhoto;
    final v = _restore ? 1 : -1;
    final x0 = math.max(0, (p.dx - r).floor()), x1 = math.min(_w - 1, (p.dx + r).ceil());
    final y0 = math.max(0, (p.dy - r).floor()), y1 = math.min(_h - 1, (p.dy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if ((x - p.dx) * (x - p.dx) + (y - p.dy) * (y - p.dy) <= r * r) {
          final i = y * _w + x;
          _edits[i] = v;
          _mask[i] = v > 0 ? 255 : 0;
        }
      }
    }
    _cursor = local;
    // 邊塗邊看，但不要每一格都重畫整張
    final now = DateTime.now();
    if (now.difference(_lastRefresh).inMilliseconds > 50) {
      _lastRefresh = now;
      _refresh();
    } else {
      setState(() {});
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _twoFingers = d.pointerCount > 1;
    _gestureZoom = _zoom;
    _gesturePan = _pan;
    _gestureFocal = d.localFocalPoint;
    _painting = false;
    if (!_twoFingers && _step == _Step.refine && !_busy) {
      _pushUndo();
      _painting = true;
      _paintAt(d.localFocalPoint);
    }
    if (!_twoFingers && _step == _Step.select && !_busy) _cut..clear()..add(d.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1 || _twoFingers) {
      if (!_twoFingers) {
        // A second finger came down: what the first one painted doesn't count.
        _twoFingers = true;
        _cut.clear();
        if (_painting && _undo.isNotEmpty) {
          _edits = _undo.removeLast();
          _painting = false;
          _compose();
        }
        _gestureZoom = _zoom;
        _gesturePan = _pan;
        _gestureFocal = d.localFocalPoint;
      }
      final zoom = (_gestureZoom * d.scale).clamp(1.0, 6.0);
      final anchor = (_gestureFocal - _gesturePan) / _gestureZoom;
      var pan = d.localFocalPoint - anchor * zoom;
      // Keep the picture on screen.
      pan = Offset(pan.dx.clamp(_box.width * (1 - zoom), 0.0), pan.dy.clamp(_box.height * (1 - zoom), 0.0));
      setState(() {
        _zoom = zoom;
        _pan = pan;
        _cursor = null;
      });
      return;
    }
    if (_painting) _paintAt(d.localFocalPoint);
    if (_cut.isNotEmpty) setState(() => _cut.add(d.localFocalPoint));
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // A real line, not a tap (taps toggle subjects).
    if (_cut.length > 3 && (_cut.last - _cut.first).distance > 24) _applyCut(List.of(_cut));
    _cut.clear();
    if (_painting) _refresh();
    _painting = false;
    setState(() => _cursor = null);
  }

  // ---------------- 預覽、完成 ----------------

  Future<({Uint8List rgba, int w, int h})> _bake() =>
      compute(bakeStickerWith, (rgba: _rgba!, mask: Uint8List.fromList(_mask), w: _w, h: _h, border: _borders[_border].$2));

  Future<void> _renderPreview() async {
    if (_empty) return;
    setState(() => _busy = true);
    final baked = await _bake();
    final img = await _imageFromRgba(baked.rgba, baked.w, baked.h);
    if (!mounted) {
      img.dispose();
      return;
    }
    final old = _baked;
    setState(() {
      _baked = img;
      _busy = false;
    });
    old?.dispose();
  }

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _zoom = 1;
      _pan = Offset.zero;
    });
    if (step == _Step.preview) _renderPreview();
  }

  Future<void> _done() async {
    if (_rgba == null || _busy) return;
    if (_empty) {
      showMessage(context, '還沒選到任何東西，先點一個主體或用補回塗一點');
      return;
    }
    setState(() {
      _busy = true;
      _status = '做成貼紙中…';
    });
    final baked = await _bake();
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
        padding: const EdgeInsets.fromLTRB(4, 4, 14, 0),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: ink)),
          const Text('去背', style: TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900)),
          const Spacer(),
          if (_step == _Step.refine) ...[
            IconButton(onPressed: _undo.isEmpty || _busy ? null : _undoStep, icon: const Icon(Icons.undo_rounded), color: ink, disabledColor: line),
            IconButton(onPressed: _redo.isEmpty || _busy ? null : _redoStep, icon: const Icon(Icons.redo_rounded), color: ink, disabledColor: line),
          ],
          FilledButton(
            onPressed: _busy || _photo == null ? null : _done,
            style: FilledButton.styleFrom(backgroundColor: coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('完成', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      _stepper(),
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 8), child: _step == _Step.preview ? _previewView() : _editor())),
      _panel(),
    ])),
  );

  Widget _stepper() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
    child: Row(children: [
      for (final (i, (step, label)) in [(_Step.select, '選主體'), (_Step.refine, '修邊'), (_Step.preview, '預覽')].indexed) ...[
        if (i > 0) Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 6), color: _step.index >= i ? coral : line)),
        GestureDetector(
          onTap: _busy || _photo == null ? null : () => _goTo(step),
          child: Row(children: [
            Container(
              width: 22, height: 22, alignment: Alignment.center,
              decoration: BoxDecoration(color: _step.index >= i ? coral : Colors.white, shape: BoxShape.circle, border: Border.all(color: _step.index >= i ? coral : line, width: 1.5)),
              child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: _step.index >= i ? Colors.white : muted, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 13, color: _step == step ? ink : muted, fontWeight: _step == step ? FontWeight.w900 : FontWeight.w600)),
          ]),
        ),
      ],
    ]),
  );

  Widget _editor() {
    final photo = _photo;
    if (photo == null) return const Center(child: CircularProgressIndicator(color: coral));
    return LayoutBuilder(builder: (context, c) {
      _box = c.biggest;
      final f = _fitted(_box);
      final select = _step == _Step.select;
      return GestureDetector(
        onTapUp: select && !_busy ? (d) => _toggleAt(_toPhoto(d.localPosition)) : null,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ClipRect(child: Stack(children: [
          Positioned.fill(child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
              ..scaleByDouble(_zoom, _zoom, 1, 1),
            child: Stack(children: [
              Positioned.fromRect(rect: f, child: RepaintBoundary(key: _shotKey, child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(fit: StackFit.expand, children: [
                  const CustomPaint(painter: _CheckerPainter()),
                  // Selecting: the unchosen parts stay visible, dimmed.
                  // Restoring: a faint ghost shows what can be painted back.
                  if (select || _restore) Opacity(opacity: select ? .3 : .22, child: RawImage(image: photo, fit: BoxFit.fill)),
                  if (_masked != null) RawImage(image: _masked, fit: BoxFit.fill),
                ]),
              ))),
              if (select && !_busy)
                for (var i = 0; i < _boxes.length; i++)
                  if (_boxes[i] != Rect.zero) _badge(i, f),
            ]),
          )),
          if (_cut.length > 1)
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _CutPainter(List.of(_cut))))),
          if (_cursor != null && _step == _Step.refine)
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
        ])),
      );
    });
  }

  /// Numbered badge at the top of subject [i]; filled when it's kept.
  Widget _badge(int i, Rect f) {
    final s = f.width / _w;
    final b = _boxes[i];
    final on = _chosen.contains(i);
    final center = Offset(f.left + b.center.dx * s, f.top + b.top * s + 16);
    return Positioned(
      left: center.dx - 15, top: center.dy - 15,
      child: GestureDetector(
        onTap: () => _toggle(i),
        child: Container(
          width: 30, height: 30, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? coral : Colors.white, shape: BoxShape.circle, border: Border.all(color: on ? Colors.white : muted, width: 2),
            boxShadow: [BoxShadow(color: ink.withValues(alpha: .25), blurRadius: 4)],
          ),
          child: on
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
            : Text('${i + 1}', style: const TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  Widget _previewView() {
    final baked = _baked;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(fit: StackFit.expand, children: [
        const CustomPaint(painter: _CheckerPainter()),
        if (baked != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 6))]),
              child: RawImage(image: baked, fit: BoxFit.contain),
            )),
          ),
        if (_busy) const Center(child: CircularProgressIndicator(color: coral)),
      ]),
    );
  }

  Widget _panel() => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 18, offset: const Offset(0, -4))],
    ),
    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...switch (_step) {
        _Step.select => [
          const Text('點要留下的人或東西', style: TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(_status, style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.content_cut_rounded, size: 15, color: coral),
            const SizedBox(width: 6),
            Expanded(child: Text('兩個人黏在一起？在中間畫一條線就能切開', style: TextStyle(fontSize: 12, color: ink.withValues(alpha: .8), fontWeight: FontWeight.w700))),
          ]),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: _busy ? null : () => _findSubjects(manual: true),
            style: TextButton.styleFrom(foregroundColor: ink, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.touch_app_outlined, size: 17),
            label: const Text('找不到想要的？改用手動去背', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
          )),
        ],
        _Step.refine => [
          Row(children: [
            _ToggleChip(icon: Icons.auto_fix_off_rounded, label: '擦掉', selected: !_restore, onTap: () => setState(() => _restore = false)),
            const SizedBox(width: 8),
            _ToggleChip(icon: Icons.brush_rounded, label: '補回', selected: _restore, onTap: () => setState(() => _restore = true)),
            const Spacer(),
            Text('兩指可以放大', style: hand(18, color: muted)),
          ]),
          Row(children: [
            const Text('筆刷', style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
            Expanded(child: Slider(
              value: _brushScreen, min: _minBrush, max: _maxBrush,
              activeColor: coral, inactiveColor: line,
              onChanged: (v) => setState(() => _brushScreen = v),
            )),
            SizedBox.square(dimension: 40, child: Center(child: Container(
              width: math.min(40, _brushScreen), height: math.min(40, _brushScreen),
              decoration: BoxDecoration(
                color: (_restore ? const Color(0xFF4CB97A) : coral).withValues(alpha: .35), shape: BoxShape.circle,
                border: Border.all(color: _restore ? const Color(0xFF4CB97A) : coral, width: 1.5),
              ),
            ))),
          ]),
        ],
        _Step.preview => [
          const Text('白邊', style: TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(children: [
            for (final (i, (label, _)) in _borders.indexed) ...[
              _ToggleChip(icon: i == 0 ? Icons.block_rounded : Icons.circle_outlined, label: label, selected: _border == i, onTap: () {
                setState(() => _border = i);
                _renderPreview();
              }),
              const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 4),
        ],
      },
      const SizedBox(height: 8),
      Row(children: [
        if (_step != _Step.select) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _goTo(_Step.values[_step.index - 1]),
            style: OutlinedButton.styleFrom(
              foregroundColor: ink, side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('上一步', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: FilledButton(
          onPressed: _busy || _photo == null ? null : switch (_step) {
            _Step.select => () => _goTo(_Step.refine),
            _Step.refine => () => _goTo(_Step.preview),
            _Step.preview => _done,
          },
          style: FilledButton.styleFrom(
            backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(switch (_step) {
            _Step.select => '下一步：修邊',
            _Step.refine => '下一步：預覽貼紙',
            _Step.preview => '做成貼紙',
          }, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        )),
      ]),
    ])),
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

class _CutPainter extends CustomPainter {
  final List<Offset> points;
  const _CutPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, false);
    canvas.drawPath(path, Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(path, Paint()
      ..color = coral
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_CutPainter old) => old.points.length != points.length;
}

/// Neutral light checkerboard: reads as "transparent" without tinting skin.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()..color = const Color(0xFFE4E4E6);
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

// ---------------- 在背景執行緒跑的工作 ----------------

Uint8List _autoJob(({Uint8List rgba, int w, int h}) a) => GrabCut.select(a.rgba, a.w, a.h);

List<Uint8List> _splitJob(({Uint8List fg, int w, int h}) a) => splitSubjects(a.fg, a.w, a.h);

Future<ui.Image> _imageFromRgba(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 去好背的主體加上一圈白色描邊（像真的貼紙），裁到主體大小。
/// 回傳預乘 alpha 的 RGBA（decodeImageFromPixels 把像素當成預乘過的）。
@visibleForTesting
({Uint8List rgba, int w, int h}) bakeSticker(({Uint8List rgba, Uint8List mask, int w, int h}) a) =>
    bakeStickerWith((rgba: a.rgba, mask: a.mask, w: a.w, h: a.h, border: .022));

/// [bakeSticker] with the white border [border] × the photo's long side
/// (0 = no border).
({Uint8List rgba, int w, int h}) bakeStickerWith(({Uint8List rgba, Uint8List mask, int w, int h, double border}) a) {
  final w = a.w, h = a.h, n = w * h;
  final r = a.border <= 0 ? 0 : math.max(4, (math.max(w, h) * a.border).round());
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
