import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/timelapse_recorder.dart';
import '../theme.dart';
import 'cutout.dart';
import 'grabcut.dart';
import 'sticker_shape.dart';
import 'subject_segmenter.dart';

/// 在這個大小（最長邊）上去背：GrabCut 貼齊邊緣一筆一兩秒內算完。
const int _workSize = 560;

/// 做成貼紙的大小（最長邊）：遮罩放大回這個大小再套。
const int _outSize = 1024;

enum _Mode { select, erase, restore, shape }

/// White border choices: label and size relative to the sticker's long side.
const _borders = [('無', 0.0), ('細', .014), ('粗', .03)];

/// 去背頁，一頁完成，右上角一直有成品的小預覽：
/// - 選主體：手機內建 AI 把每個人、東西找出來，點一下選或不選（可以多選）；
///   黏在一起的在中間畫一條線就切開；長按直接只留按到的那一個。AI 不能用就自動改用 GrabCut。
/// - 擦掉／補回：預設「貼齊邊緣」，畫一筆或點一下沿著邊緣整塊處理；打開「細修」變成一般筆刷。
///   兩指放大；按住看原圖；可以換深色背景看清楚毛邊。
/// - 外框：沿著輪廓，或做成方形、圓形、星形、愛心貼紙；白邊無、細、粗。
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
  ui.Image? _photo, _masked, _preview;
  Uint8List? _rgba;
  int _w = 0, _h = 0;
  bool _busy = true;
  String _status = '找主體中…';
  _Mode _mode = _Mode.select;
  bool _edited = false;

  /// One mask per subject (0–255, w × h), biggest first, and their bounds.
  List<Uint8List> _subjects = [];
  List<Rect> _boxes = [];
  final _chosen = <int>{};
  /// The result being edited.
  Uint8List _mask = Uint8List(0);
  /// Strokes so far (photo pixels): 1 / -1 snap-to-edge restore / erase,
  /// 2 / -2 fine brush. GrabCut treats them as must keep / must remove.
  Int8List _hints = Int8List(0);
  final _undo = <(Uint8List, Int8List)>[];
  final _redo = <(Uint8List, Int8List)>[];

  /// Fine brush instead of snap-to-edge.
  bool _fine = false;
  bool _darkBg = false, _showOriginal = false;
  double _brushScreen = 18;
  static const double _minBrush = 4, _maxBrush = 40;
  final _strokeScreen = <Offset>[];
  final _strokePhoto = <Offset>[];
  /// Selecting: a line drawn to cut touching subjects apart (screen points).
  final _cut = <Offset>[];
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

  StickerShape _shape = StickerShape.contour;
  ShapeFit _fit = const ShapeFit();
  ShapeFit _fitStart = const ShapeFit();
  int _border = 1;
  Timer? _previewTimer;
  final _shotKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _photo?.dispose();
    _masked?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  Future<ui.Image> _decode(int maxSide) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(widget.photo);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final s = math.min(1.0, maxSide / math.max(desc.width, desc.height));
    final codec = await desc.instantiateCodec(targetWidth: (desc.width * s).round(), targetHeight: (desc.height * s).round());
    return (await codec.getNextFrame()).image;
  }

  Future<void> _load() async {
    final image = await _decode(_workSize);
    // 不預乘 alpha：顏色才是原本的顏色
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (!mounted) {
      image.dispose();
      return;
    }
    final rgba = data!.buffer.asUint8List();
    final alpha = _alphaOf(rgba);
    setState(() {
      _photo = image;
      _rgba = rgba;
      _w = image.width;
      _h = image.height;
      _hints = Int8List(_w * _h);
      _mask = Uint8List(_w * _h);
    });
    if (alpha != null) {
      // 已經去好背的圖：直接用它的透明度
      _setSubjects([alpha], '這張本來就去好背了，直接用它的輪廓');
      await _compose();
    } else {
      await _findSubjects();
    }
    unawaited(_maybeShowTips());
  }

  /// 照片有透明背景的話，取出透明度當遮罩，照片本身改成不透明（遮罩另外
  /// 套）。沒有透明的地方回傳 null。
  static Uint8List? _alphaOf(Uint8List rgba) {
    final n = rgba.length ~/ 4;
    var clear = 0;
    for (var i = 0; i < n; i++) {
      if (rgba[i * 4 + 3] < 250) clear++;
    }
    // 一兩個半透明的像素不算（有些相機的圖邊緣會這樣）
    if (clear < n * .02) {
      for (var i = 0; i < n; i++) {
        rgba[i * 4 + 3] = 255;
      }
      return null;
    }
    final alpha = Uint8List(n);
    for (var i = 0; i < n; i++) {
      alpha[i] = rgba[i * 4 + 3];
      rgba[i * 4 + 3] = 255;
    }
    return alpha;
  }

  Future<void> _maybeShowTips() async {
    if (await CutoutTipStore.isDone() || !mounted) return;
    await CutoutTipStore.markDone();
    if (mounted) await showCutoutTips(context);
  }

  void _setSubjects(List<Uint8List> subjects, String status) {
    _subjects = subjects;
    _boxes = [for (final m in subjects) _bounds(m)];
    _chosen
      ..clear()
      ..addAll(List.generate(subjects.length, (i) => i));
    _hints = Int8List(_w * _h);
    _status = status;
    _busy = false;
  }

  /// Find the subjects with the phone's AI; without it (or when it finds
  /// nothing) fall back to GrabCut, split into pieces.
  Future<void> _findSubjects({bool manual = false}) async {
    final rgba = _rgba;
    if (rgba == null) return;
    setState(() {
      _busy = true;
      _status = manual ? '手動去背中…' : '找主體中…';
    });
    final found = manual ? null : await SubjectSegmenter.subjects(rgba, _w, _h);
    if (found != null && found.isNotEmpty) {
      if (!mounted) return;
      _pushUndo();
      _setSubjects(found, found.length > 1 ? '找到 ${found.length} 個主體，點一下可以取消或選回來' : '找到主體了，黏在一起的可以畫線切開');
    } else {
      final fg = await compute(_autoJob, (rgba: rgba, w: _w, h: _h));
      final parts = await compute(_splitJob, (fg: fg, w: _w, h: _h));
      if (!mounted) return;
      _pushUndo();
      _setSubjects(parts.isEmpty ? [fg] : parts, manual ? '用手動去背（依顏色和邊緣判斷）' : 'AI 這次認不出來，改用手動去背');
    }
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

  /// Rebuild the mask from the chosen subjects; fine-brush strokes stay.
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
      final h = _hints[i];
      if (h == 2) m[i] = 255;
      if (h == -2) m[i] = 0;
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
    _schedulePreview();
    final recorder = widget.recorder;
    if (recorder != null) WidgetsBinding.instance.addPostFrameCallback((_) => recorder.request(_frame));
  }

  /// 縮時影片的一格：去背中的照片（格紋底）。
  Future<ui.Image?> _frame() async {
    final b = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (!mounted || b == null || !b.attached || b.size.isEmpty) return null;
    return b.toImage(pixelRatio: 1000 / b.size.longestSide);
  }

  bool get _empty => _shape == StickerShape.contour && !_mask.any((v) => v > 127);

  // ---------------- 復原 ----------------

  void _pushUndo() {
    if (_mask.isEmpty) return;
    _undo.add((Uint8List.fromList(_mask), Int8List.fromList(_hints)));
    if (_undo.length > 15) _undo.removeAt(0);
    _redo.clear();
    _edited = true;
  }

  void _undoStep() {
    if (_undo.isEmpty || _busy) return;
    _redo.add((_mask, _hints));
    final (m, h) = _undo.removeLast();
    _mask = m;
    _hints = h;
    _refresh();
  }

  void _redoStep() {
    if (_redo.isEmpty || _busy) return;
    _undo.add((_mask, _hints));
    final (m, h) = _redo.removeLast();
    _mask = m;
    _hints = h;
    _refresh();
  }

  // ---------------- 選主體 ----------------

  int _subjectAt(Offset p) {
    final x = p.dx.floor(), y = p.dy.floor();
    if (x < 0 || y < 0 || x >= _w || y >= _h) return -1;
    var hit = -1, best = 0;
    for (var i = 0; i < _subjects.length; i++) {
      final v = _subjects[i][y * _w + x];
      if (v > 127 && v >= best) {
        hit = i;
        best = v;
      }
    }
    if (hit >= 0) return hit;
    // Not on a subject: the smallest box around the point.
    var area = double.infinity;
    for (var i = 0; i < _boxes.length; i++) {
      final b = _boxes[i];
      if (b.contains(p) && b.width * b.height < area) {
        hit = i;
        area = b.width * b.height;
      }
    }
    return hit;
  }

  void _toggle(int i) {
    _pushUndo();
    setState(() => _chosen.contains(i) ? _chosen.remove(i) : _chosen.add(i));
    _compose();
  }

  /// Long press: keep only what's under the finger (AI first, then GrabCut).
  Future<void> _keepOnly(Offset p) async {
    final rgba = _rgba;
    if (rgba == null || _busy || p.dx < 0 || p.dy < 0 || p.dx >= _w || p.dy >= _h) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _status = '選你按的那一個…';
    });
    final hints = Int8List(_w * _h);
    _paintHint(hints, p.dx, p.dy, math.min(_w, _h) * .03, 1);
    final Uint8List mask = await SubjectSegmenter.select(rgba, _w, _h, x: p.dx.floor(), y: p.dy.floor()) ??
        await compute(_selectJob, (rgba: rgba, w: _w, h: _h, x: p.dx.floor(), y: p.dy.floor(), hints: hints));
    if (!mounted) return;
    _pushUndo();
    _setSubjects([mask], '只留你按的那一個；黏在一起的可以畫線切開');
    await _compose();
  }

  /// Cut every subject along the drawn line and split the pieces into
  /// separate subjects (touching people come back from the AI as one).
  Future<void> _applyCut(List<Offset> screen) async {
    final pts = [for (final p in screen) _toPhoto(p)];
    final r = math.max(1.5, math.min(_w, _h) * .006);
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
      final pieces = parts.length > 1 ? parts : [_subjects[k]];
      split += pieces.length - 1;
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
    _pushUndo();
    _subjects = next;
    _boxes = [for (final m in next) _bounds(m)];
    _chosen
      ..clear()
      ..addAll(chosen);
    _status = '切開了，點一下不要的就會拿掉';
    await _compose();
  }

  // ---------------- 擦掉／補回 ----------------

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

  /// 貼齊邊緣的筆畫在照片上多粗：細細一條就好，畫歪一點跨到主體也沒關係。
  double get _strokeRadius => math.max(1.5, math.max(_w, _h) * .004);

  void _paintHint(Int8List a, double cx, double cy, double r, int v) {
    final x0 = math.max(0, (cx - r).floor()), x1 = math.min(_w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor()), y1 = math.min(_h - 1, (cy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) a[y * _w + x] = v;
      }
    }
  }

  void _brushAt(Offset local) {
    final p = _toPhoto(local);
    final r = _brushInPhoto;
    final keep = _mode == _Mode.restore;
    Cutout.paintMask(_mask, _w, _h, p.dx, p.dy, r, keep: keep);
    // 記下來：之後貼齊邊緣重切、換選主體時，這裡照筆刷的樣子不動
    _paintHint(_hints, p.dx, p.dy, r, keep ? 2 : -2);
    _cursor = local;
    final now = DateTime.now();
    if (now.difference(_lastRefresh).inMilliseconds > 50) {
      _lastRefresh = now;
      _refresh();
    } else {
      setState(() {});
    }
  }

  /// 貼齊邊緣：剛畫的一筆當作提示，用 GrabCut 重切；只有那一筆附近會變。
  Future<void> _applyStroke(List<Offset> pts) async {
    final rgba = _rgba;
    if (rgba == null || pts.isEmpty || _busy) return;
    final v = _mode == _Mode.erase ? -1 : 1;
    final radius = _strokeRadius;
    final stroke = Int8List(_w * _h);
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = i + 1 < pts.length ? pts[i + 1] : pts[i];
      final steps = math.max(1, ((b - a).distance / (radius * .5)).ceil());
      for (var k = 0; k <= steps; k++) {
        final q = Offset.lerp(a, b, k / steps)!;
        _paintHint(stroke, q.dx, q.dy, radius, v);
      }
    }
    final hints = Int8List.fromList(_hints);
    // 「補回」畫一筆：附近之前用細修擦掉的地方不再鎖住，不然補不回來
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
    setState(() {
      _busy = true;
      _status = v < 0 ? '沿著邊緣擦掉…' : '沿著邊緣補回…';
    });
    final out = await compute(_refineJob, (rgba: rgba, w: _w, h: _h, mask: _mask, hints: hints, stroke: stroke));
    if (!mounted) return;
    _pushUndo();
    _mask = out;
    _hints = hints;
    _busy = false;
    _status = '';
    await _refresh();
  }

  // ---------------- 手勢 ----------------

  void _onTapUp(TapUpDetails d) {
    if (_busy || _photo == null) return;
    final p = _toPhoto(d.localPosition);
    switch (_mode) {
      case _Mode.select:
        final i = _subjectAt(p);
        if (i >= 0) _toggle(i);
      case _Mode.erase || _Mode.restore:
        if (_fine) {
          _pushUndo();
          _brushAt(d.localPosition);
          setState(() => _cursor = null);
          _refresh();
        } else {
          // 點一下：點到的那個東西整塊擦掉（或補回）
          _applyStroke([p]);
        }
      case _Mode.shape:
        break;
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _twoFingers = d.pointerCount > 1;
    _gestureZoom = _zoom;
    _gesturePan = _pan;
    _gestureFocal = d.localFocalPoint;
    _fitStart = _fit;
    _painting = false;
    _strokeScreen.clear();
    _strokePhoto.clear();
    if (_twoFingers || _busy) return;
    switch (_mode) {
      case _Mode.select:
        _cut
          ..clear()
          ..add(d.localFocalPoint);
      case _Mode.erase || _Mode.restore:
        if (_fine) {
          _pushUndo();
          _painting = true;
          _brushAt(d.localFocalPoint);
        } else {
          _strokeScreen.add(d.localFocalPoint);
          _strokePhoto.add(_toPhoto(d.localFocalPoint));
        }
      case _Mode.shape:
        break;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_mode == _Mode.shape) {
      // Move and zoom the photo inside the shape.
      final side = _shapeSide;
      final aspect = _w / _h;
      final delta = (d.localFocalPoint - _gestureFocal) / side;
      setState(() => _fit = ShapeFit((_fitStart.zoom * d.scale).clamp(1.0, 5.0), _fitStart.offset + delta).clamped(aspect));
      _edited = true;
      _schedulePreview();
      return;
    }
    if (d.pointerCount > 1 || _twoFingers) {
      if (!_twoFingers) {
        // A second finger came down: what the first one did doesn't count.
        _twoFingers = true;
        _cut.clear();
        _strokeScreen.clear();
        _strokePhoto.clear();
        if (_painting && _undo.isNotEmpty) {
          final (m, h) = _undo.removeLast();
    _mask = m;
    _hints = h;
          _painting = false;
          _refresh();
        }
        _gestureZoom = _zoom;
        _gesturePan = _pan;
        _gestureFocal = d.localFocalPoint;
      }
      final zoom = (_gestureZoom * d.scale).clamp(1.0, 6.0);
      final anchor = (_gestureFocal - _gesturePan) / _gestureZoom;
      var pan = d.localFocalPoint - anchor * zoom;
      pan = Offset(pan.dx.clamp(_box.width * (1 - zoom), 0.0), pan.dy.clamp(_box.height * (1 - zoom), 0.0));
      setState(() {
        _zoom = zoom;
        _pan = pan;
        _cursor = null;
      });
      return;
    }
    if (_cut.isNotEmpty) setState(() => _cut.add(d.localFocalPoint));
    if (_painting) _brushAt(d.localFocalPoint);
    if (_strokeScreen.isNotEmpty) {
      setState(() {
        _strokeScreen.add(d.localFocalPoint);
        _strokePhoto.add(_toPhoto(d.localFocalPoint));
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // A real line, not a tap (taps are handled by onTapUp).
    if (_cut.length > 3 && (_cut.last - _cut.first).distance > 24) _applyCut(List.of(_cut));
    _cut.clear();
    if (_strokePhoto.length > 2) _applyStroke(List.of(_strokePhoto));
    _strokeScreen.clear();
    _strokePhoto.clear();
    if (_painting) _refresh();
    _painting = false;
    setState(() => _cursor = null);
  }

  // ---------------- 外框、預覽、完成 ----------------

  double get _shapeSide => math.min(_box.width, _box.height) * .86;

  void _schedulePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 200), _renderPreview);
  }

  Future<({Uint8List rgba, int w, int h})?> _bake(ui.Image photo, Uint8List rgba, int w, int h, Uint8List mask) async {
    if (_shape == StickerShape.contour) {
      if (!mask.any((v) => v > 127)) return null;
      return compute(bakeStickerWith, (rgba: rgba, mask: mask, w: w, h: h, border: _borders[_border].$2));
    }
    final size = math.max(w, h);
    final s = await renderShape(photo, _shape, _fit, size);
    return compute(bakeStickerWith, (rgba: s.rgba, mask: s.mask, w: s.w, h: s.h, border: _borders[_border].$2));
  }

  Future<void> _renderPreview() async {
    final photo = _photo, rgba = _rgba;
    if (photo == null || rgba == null) return;
    final baked = await _bake(photo, rgba, _w, _h, Uint8List.fromList(_mask));
    final img = baked == null ? null : await _imageFromRgba(baked.rgba, baked.w, baked.h);
    if (!mounted) {
      img?.dispose();
      return;
    }
    final old = _preview;
    setState(() => _preview = img);
    old?.dispose();
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
    // Full quality: the photo at the output size, the mask scaled up to it.
    final big = await _decode(_outSize);
    final data = await big.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final rgba = data!.buffer.asUint8List();
    for (var i = 3; i < rgba.length; i += 4) {
      rgba[i] = 255;
    }
    final mask = _shape == StickerShape.contour
      ? await compute(_resizeJob, (m: _mask, w: _w, h: _h, tw: big.width, th: big.height))
      : Uint8List(0);
    final baked = await _bake(big, rgba, big.width, big.height, mask);
    big.dispose();
    if (baked == null || !mounted) return;
    final img = await _imageFromRgba(baked.rgba, baked.w, baked.h);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (!mounted) return;
    _edited = false;
    Navigator.pop(context, png?.buffer.asUint8List());
  }

  void _setMode(_Mode m) => setState(() {
    _mode = m;
    if (m == _Mode.shape) {
      _zoom = 1;
      _pan = Offset.zero;
    }
  });

  // ---------------- 畫面 ----------------

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_edited,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final navigator = Navigator.of(context);
      if (await confirmLeave(context, '去好的背和修好的邊都不會留下來。')) navigator.pop();
    },
    child: Scaffold(
      backgroundColor: cream,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 14, 0),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close_rounded, color: ink)),
            const Text('去背', style: TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900)),
            IconButton(onPressed: () => showCutoutTips(context), icon: const Icon(Icons.help_outline_rounded, size: 20), color: muted, tooltip: '怎麼修'),
            const Spacer(),
            IconButton(onPressed: _undo.isEmpty || _busy ? null : _undoStep, icon: const Icon(Icons.undo_rounded), color: ink, disabledColor: line),
            IconButton(onPressed: _redo.isEmpty || _busy ? null : _redoStep, icon: const Icon(Icons.redo_rounded), color: ink, disabledColor: line),
            FilledButton(
              onPressed: _busy || _photo == null ? null : _done,
              style: FilledButton.styleFrom(backgroundColor: coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('完成', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 8), child: Stack(children: [
          Positioned.fill(child: _editor()),
          Positioned(right: 0, top: 0, child: _miniPreview()),
        ]))),
        _panel(),
      ])),
    ),
  );

  Widget _editor() {
    final photo = _photo;
    if (photo == null) return const Center(child: CircularProgressIndicator(color: coral));
    return LayoutBuilder(builder: (context, c) {
      _box = c.biggest;
      final shape = _mode == _Mode.shape && _shape != StickerShape.contour;
      return GestureDetector(
        onTapUp: _onTapUp,
        onLongPressStart: _mode == _Mode.select && !_busy ? (d) => _keepOnly(_toPhoto(d.localPosition)) : null,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ClipRect(child: Stack(children: [
          Positioned.fill(child: shape ? _shapeEditor(photo) : _maskEditor(photo)),
          if (_cut.length > 1) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _LinePainter(List.of(_cut), coral)))),
          if (_strokeScreen.length > 1)
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _LinePainter(List.of(_strokeScreen), _mode == _Mode.erase ? coral : const Color(0xFF4CB97A))))),
          if (_cursor != null && _fine)
            Positioned(
              left: _cursor!.dx - _brushScreen, top: _cursor!.dy - _brushScreen,
              child: IgnorePointer(child: Container(
                width: _brushScreen * 2, height: _brushScreen * 2,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)]),
              )),
            ),
          if (_zoom > 1.01)
            Positioned(left: 8, bottom: 8, child: GestureDetector(
              onTap: () => setState(() {
                _zoom = 1;
                _pan = Offset.zero;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: ink.withValues(alpha: .75), borderRadius: BorderRadius.circular(14)),
                child: Text('放大 ${_zoom.toStringAsFixed(1)} 倍 · 還原', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            )),
          if (_busy)
            Positioned.fill(child: IgnorePointer(child: ColoredBox(
              color: cream.withValues(alpha: .45),
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: ink.withValues(alpha: .15), blurRadius: 10)]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: coral)),
                  const SizedBox(width: 10),
                  Text(_status, style: const TextStyle(color: ink, fontWeight: FontWeight.w700)),
                ]),
              )),
            ))),
        ])),
      );
    });
  }

  Widget _maskEditor(ui.Image photo) {
    final f = _fitted(_box);
    final select = _mode == _Mode.select;
    final ghost = select || _mode == _Mode.restore;
    return Transform(
      transform: Matrix4.identity()
        ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
        ..scaleByDouble(_zoom, _zoom, 1, 1),
      child: Stack(children: [
        Positioned.fromRect(rect: f, child: RepaintBoundary(key: _shotKey, child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _CheckerPainter(dark: _darkBg)),
            if (_showOriginal) RawImage(image: photo, fit: BoxFit.fill)
            else ...[
              // Selecting: what isn't kept stays visible, dimmed. Restoring:
              // a faint ghost shows what can be painted back.
              if (ghost) Opacity(opacity: select ? .3 : .22, child: RawImage(image: photo, fit: BoxFit.fill)),
              if (_masked != null) RawImage(image: _masked, fit: BoxFit.fill),
            ],
          ]),
        ))),
        if (select && !_busy && !_showOriginal)
          for (var i = 0; i < _boxes.length; i++)
            if (_boxes[i] != Rect.zero) _badge(i, f),
      ]),
    );
  }

  /// The photo inside the chosen shape; drag and pinch to frame it.
  Widget _shapeEditor(ui.Image photo) {
    final side = _shapeSide;
    final r = _fit.rect(side, _w / _h);
    return Center(child: SizedBox.square(dimension: side, child: Stack(clipBehavior: Clip.none, children: [
      // The photo outside the shape, dimmed, so you see what gets cut off.
      Positioned.fromRect(rect: r, child: Opacity(opacity: .25, child: RawImage(image: photo, fit: BoxFit.fill))),
      Positioned.fill(child: ClipPath(
        clipper: _ShapeClipper(_shape),
        child: Stack(children: [Positioned.fromRect(rect: r, child: RawImage(image: photo, fit: BoxFit.fill))]),
      )),
      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ShapeOutlinePainter(_shape)))),
    ])));
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

  /// Always-on small preview of the finished sticker; tap to see it big.
  Widget _miniPreview() => GestureDetector(
    onTap: _preview == null ? null : () => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(children: [
                const Positioned.fill(child: CustomPaint(painter: _CheckerPainter())),
                Padding(padding: const EdgeInsets.all(16), child: RawImage(image: _preview, fit: BoxFit.contain, height: 320)),
              ])),
              const SizedBox(height: 10),
              const Text('做出來的貼紙', style: TextStyle(color: muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    ),
    child: Container(
      width: 78, height: 96, padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: line),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Stack(fit: StackFit.expand, children: [
          const CustomPaint(painter: _CheckerPainter()),
          if (_preview != null) Padding(padding: const EdgeInsets.all(3), child: RawImage(image: _preview, fit: BoxFit.contain)),
        ]))),
        const SizedBox(height: 3),
        const Text('做出來', style: TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  Widget _panel() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 18, offset: const Offset(0, -4))],
    ),
    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Modes.
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
        child: Row(children: [
          for (final (m, icon, label) in const [
            (_Mode.select, Icons.touch_app_outlined, '選主體'),
            (_Mode.erase, Icons.auto_fix_off_rounded, '擦掉'),
            (_Mode.restore, Icons.brush_rounded, '補回'),
            (_Mode.shape, Icons.interests_outlined, '外框'),
          ])
            Expanded(child: GestureDetector(
              onTap: () => _setMode(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: _mode == m ? blush : Colors.transparent, borderRadius: BorderRadius.circular(13)),
                child: Column(children: [
                  Icon(icon, size: 19, color: _mode == m ? ink : muted),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(fontSize: 12, color: _mode == m ? ink : muted, fontWeight: _mode == m ? FontWeight.w900 : FontWeight.w600)),
                ]),
              ),
            )),
        ]),
      ),
      const SizedBox(height: 10),
      ...switch (_mode) {
        _Mode.select => [
          _tip(_status.isEmpty ? '點一下選或不選，可以多選；長按只留那一個' : _status),
          _tip('黏在一起？在中間畫一條線就能切開', icon: Icons.content_cut_rounded),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: _busy ? null : () => _findSubjects(manual: true),
            style: TextButton.styleFrom(foregroundColor: ink, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
            label: const Text('找不到想要的？改用手動去背', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
          )),
        ],
        _Mode.erase || _Mode.restore => [
          Row(children: [
            _SmallSwitch(label: '細修', value: _fine, onChanged: (v) => setState(() => _fine = v)),
            const Spacer(),
            _HoldButton(onHold: (v) => setState(() => _showOriginal = v)),
            const SizedBox(width: 6),
            _IconChip(icon: Icons.contrast_rounded, label: _darkBg ? '淺色' : '深色', onTap: () => setState(() => _darkBg = !_darkBg)),
          ]),
          if (_fine)
            Row(children: [
              const Text('筆刷', style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
              Expanded(child: Slider(value: _brushScreen, min: _minBrush, max: _maxBrush, activeColor: coral, inactiveColor: line, onChanged: (v) => setState(() => _brushScreen = v))),
            ]),
          _tip(_fine
            ? '塗到哪裡就${_mode == _Mode.erase ? '擦到' : '補到'}哪裡，兩指放大修細的地方'
            : _mode == _Mode.erase
              ? '在多出來的東西上畫一筆或點一下，會沿著邊緣整塊擦掉'
              : '在少了的地方畫一筆，會沿著邊緣補回來'),
        ],
        _Mode.shape => [
          SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final s in StickerShape.values) ...[
              _IconChip(icon: s.icon, label: s.label, selected: _shape == s, onTap: () {
                setState(() => _shape = s);
                _edited = true;
                _schedulePreview();
              }),
              const SizedBox(width: 6),
            ],
          ])),
          const SizedBox(height: 8),
          Row(children: [
            const Text('白邊', style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            for (final (i, (label, _)) in _borders.indexed) ...[
              _IconChip(icon: i == 0 ? Icons.block_rounded : Icons.circle_outlined, label: label, selected: _border == i, onTap: () {
                setState(() => _border = i);
                _schedulePreview();
              }),
              const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 6),
          _tip(_shape == StickerShape.contour ? '沿著去好背的輪廓做成貼紙' : '拖曳照片調整位置，兩指放大縮小'),
        ],
      },
    ])),
  );

  Widget _tip(String text, {IconData icon = Icons.info_outline_rounded}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: icon == Icons.content_cut_rounded ? coral : muted)),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35, color: muted, fontWeight: FontWeight.w700))),
    ]),
  );
}

/// 去背小技巧。第一次進去背頁會自動跳出來，之後按「？」再看。
Future<void> showCutoutTips(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    Widget row(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: const BoxDecoration(color: blush, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: coral),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(text: '$title\n', style: const TextStyle(fontWeight: FontWeight.w900, color: ink)),
          TextSpan(text: text),
        ]), style: const TextStyle(fontSize: 13, height: 1.45, color: muted))),
      ]),
    );
    return Dialog(
      backgroundColor: cream,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('去背小技巧', style: TextStyle(fontSize: 19, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          row(Icons.touch_app_outlined, '選主體', '點一下選或不選，可以多選；長按只留按到的那一個。'),
          row(Icons.content_cut_rounded, '黏在一起', '在兩個人中間畫一條線就能切開。'),
          row(Icons.auto_fix_off_rounded, '多出來的東西', '選「擦掉」，在上面畫一筆或點一下，會沿著邊緣整塊擦掉。'),
          row(Icons.brush_rounded, '少了的地方', '選「補回」畫一筆。'),
          row(Icons.zoom_in_rounded, '細的地方', '兩指放大，打開「細修」用筆刷慢慢修；按住「原圖」對照。'),
          row(Icons.interests_outlined, '外框', '也可以做成方形、圓形、星形、愛心貼紙。'),
          const SizedBox(height: 2),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('知道了', style: TextStyle(fontWeight: FontWeight.w800)),
          )),
        ]),
      ),
    );
  },
);

/// 去背小技巧看過了沒，記在手機上。讀不到本機儲存（測試、網頁）就當作看過。
class CutoutTipStore {
  CutoutTipStore._();

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/cutout_tip_done.txt');

  static Future<bool> isDone() async {
    try {
      return await (await _file()).exists();
    } catch (_) {
      return true;
    }
  }

  static Future<void> markDone() async {
    try {
      await (await _file()).writeAsString('1');
    } catch (_) {}
  }
}

class _SmallSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SmallSwitch({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(height: 30, child: FittedBox(child: Switch(value: value, activeTrackColor: coral, onChanged: onChanged))),
    const SizedBox(width: 2),
    Text(label, style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
  ]);
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _IconChip({required this.icon, required this.label, this.selected = false, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? blush : cream, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? blushLine : line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: ink),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: ink, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
      ]),
    ),
  );
}

/// Press and hold to see the original photo.
class _HoldButton extends StatelessWidget {
  final ValueChanged<bool> onHold;
  const _HoldButton({required this.onHold});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => onHold(true),
    onTapUp: (_) => onHold(false),
    onTapCancel: () => onHold(false),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.compare_rounded, size: 15, color: ink),
        SizedBox(width: 4),
        Text('按住看原圖', style: TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _LinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  const _LinePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, false);
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..strokeWidth = w
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, stroke(Colors.white, 6))
      ..drawPath(path, stroke(color, 3));
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.points.length != points.length || old.color != color;
}

class _ShapeClipper extends CustomClipper<Path> {
  final StickerShape shape;
  const _ShapeClipper(this.shape);

  @override
  Path getClip(Size size) => shape.path(size.width);

  @override
  bool shouldReclip(_ShapeClipper old) => old.shape != shape;
}

class _ShapeOutlinePainter extends CustomPainter {
  final StickerShape shape;
  const _ShapeOutlinePainter(this.shape);

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(shape.path(size.width), Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3);

  @override
  bool shouldRepaint(_ShapeOutlinePainter old) => old.shape != shape;
}

/// Checkerboard that reads as "transparent": neutral light, or dark to see
/// white fringes.
class _CheckerPainter extends CustomPainter {
  final bool dark;
  const _CheckerPainter({this.dark = false});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF2E2E33) : Colors.white);
    final p = Paint()..color = dark ? const Color(0xFF3A3A40) : const Color(0xFFE4E4E6);
    const s = 12.0;
    for (var y = 0.0, r = 0; y < size.height; y += s, r++) {
      for (var x = r.isEven ? 0.0 : s; x < size.width; x += s * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.dark != dark;
}

// ---------------- 在背景執行緒跑的工作 ----------------

Uint8List _autoJob(({Uint8List rgba, int w, int h}) a) => GrabCut.select(a.rgba, a.w, a.h);

Uint8List _selectJob(({Uint8List rgba, int w, int h, int? x, int? y, Int8List hints}) a) =>
    GrabCut.select(a.rgba, a.w, a.h, px: a.x, py: a.y, hints: a.hints);

Uint8List _refineJob(({Uint8List rgba, int w, int h, Uint8List mask, Int8List hints, Int8List stroke}) a) =>
    GrabCut.refine(a.rgba, a.w, a.h, a.mask, a.hints, a.stroke);

List<Uint8List> _splitJob(({Uint8List fg, int w, int h}) a) => splitSubjects(a.fg, a.w, a.h);

Uint8List _resizeJob(({Uint8List m, int w, int h, int tw, int th}) a) => resizeMask(a.m, a.w, a.h, a.tw, a.th);

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
