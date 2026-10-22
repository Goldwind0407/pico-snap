import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// 錄下編輯的過程，做成縮時影片。
///
/// 畫面有變化時呼叫 [request]，最多每 [_interval] 截一張（調整去背、拖貼紙
/// 時不會一直截），排版成 9:16 的畫格存成 PNG 放在暫存資料夾。畫格太多就
/// 隔一張丟一張、之後截得慢一點，影片長度維持在 [maxFrames] / [fps] 秒以內。
/// [render] 把所有畫格加上最後的成品（停 [holdSeconds] 秒）交給手機內建的
/// 編碼器做成 MP4。編輯得少、畫格少的時候每格多停一下（最多 [_maxRepeat]
/// 格），過程至少有 [minProcessSeconds] 秒，不會一閃而過。
class TimelapseRecorder {
  TimelapseRecorder({Directory? dir, this.maxFrames = 360}) : _baseDir = dir;

  static const width = 720, height = 1280, fps = 12, holdSeconds = 2, minProcessSeconds = 4;
  static const _maxRepeat = 6;
  static const _channel = MethodChannel('picosnap/video');

  final int maxFrames;
  final Directory? _baseDir;
  Directory? _dir;
  bool _noDir = false;
  final _frames = <String>[];
  var _interval = const Duration(milliseconds: 250);
  var _last = DateTime(0);
  Timer? _timer;
  Future<ui.Image?> Function()? _pending;
  bool _busy = false, _closed = false;
  int _seq = 0;

  int get frameCount => _frames.length;

  /// 每一格過程要重複幾次。
  int get _repeat => _frames.isEmpty ? 1 : min(_maxRepeat, max(1, (minProcessSeconds * fps / _frames.length).ceil()));

  /// 現在做成影片大約幾秒。
  int get seconds => (_frames.length * _repeat / fps).ceil() + holdSeconds;

  /// 畫面變了：等一下用 [source] 截一張。
  void request(Future<ui.Image?> Function() source) {
    if (_closed) return;
    _pending = source;
    if (_busy || (_timer?.isActive ?? false)) return;
    final wait = _interval - DateTime.now().difference(_last);
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _flush);
  }

  Future<void> _flush() async {
    final source = _pending;
    _pending = null;
    if (source == null || _closed) return;
    _busy = true;
    _last = DateTime.now();
    try {
      final art = await source();
      if (art != null) await _add(art);
    } catch (e) {
      // 截不到（畫面被別的頁面蓋住、正在換頁）就這次不截
      debugPrint('[TIMELAPSE] 截圖失敗: $e');
    } finally {
      _busy = false;
    }
    final next = _pending;
    if (next != null && !_closed) request(next);
  }

  Future<Directory?> _ensureDir() async {
    if (_dir != null || _noDir) return _dir;
    try {
      final base = _baseDir ?? await getTemporaryDirectory();
      _dir = await Directory('${base.path}/timelapse_${DateTime.now().microsecondsSinceEpoch}').create(recursive: true);
    } catch (e) {
      _noDir = true; // 網頁版、測試：不錄
      debugPrint('[TIMELAPSE] 沒有暫存資料夾，不錄影: $e');
    }
    return _dir;
  }

  Future<String?> _write(ui.Image art, String name) async {
    final dir = await _ensureDir();
    if (dir == null || _closed) {
      art.dispose();
      return null;
    }
    final frame = await composeFrame(art);
    art.dispose();
    final png = await frame.toByteData(format: ui.ImageByteFormat.png);
    frame.dispose();
    if (png == null || _closed) return null;
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(png.buffer.asUint8List());
    return file.path;
  }

  Future<void> _add(ui.Image art) async {
    final path = await _write(art, 'f${(_seq++).toString().padLeft(5, '0')}');
    if (path == null) return;
    _frames.add(path);
    if (_frames.length >= maxFrames) _thin();
  }

  /// 隔一張丟一張，之後截得慢一倍。
  void _thin() {
    final keep = <String>[];
    for (var i = 0; i < _frames.length; i++) {
      if (i.isEven) {
        keep.add(_frames[i]);
      } else {
        File(_frames[i]).delete().ignore();
      }
    }
    _frames
      ..clear()
      ..addAll(keep);
    _interval *= 2;
  }

  /// 做成 MP4：錄到的過程，最後是 [finished]（乾淨的成品）停兩秒。
  /// 回傳影片路徑；做不出來回傳 null。
  Future<String?> render(ui.Image finished) async {
    _timer?.cancel();
    final last = await _write(finished, 'final_${_seq++}');
    if (last == null) return null;
    final out = '${_dir!.path}/pico_snap_${DateTime.now().millisecondsSinceEpoch}.mp4';
    try {
      return await _channel.invokeMethod<String>('encode', {
        'frames': [for (final f in _frames) for (var i = 0; i < _repeat; i++) f, for (var i = 0; i < fps * holdSeconds; i++) last],
        'out': out, 'fps': fps, 'width': width, 'height': height,
      });
    } catch (e) {
      debugPrint('[TIMELAPSE] 影片編碼失敗: $e');
      return null;
    }
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    final dir = _dir;
    if (dir != null) dir.delete(recursive: true).ignore();
  }
}

/// 一格影片：奶油色底、上面 PICO SNAP、中間是作品、下面一行手寫字。
@visibleForTesting
Future<ui.Image> composeFrame(ui.Image art) {
  const w = TimelapseRecorder.width * 1.0, h = TimelapseRecorder.height * 1.0;
  final recorder = ui.PictureRecorder();
  final c = ui.Canvas(recorder)..drawRect(const ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = cream);
  _text(c, 'PICO SNAP', 62, ui.TextStyle(color: coral, fontSize: 44, fontFamily: 'Nunito', fontWeight: ui.FontWeight.w900, letterSpacing: 5));
  _text(c, 'the making of ♡', 122, ui.TextStyle(color: muted, fontSize: 36, fontFamily: 'Caveat', fontWeight: ui.FontWeight.w600));
  const box = ui.Rect.fromLTRB(56, 200, w - 56, h - 130);
  final s = min(box.width / art.width, box.height / art.height);
  final dst = ui.Rect.fromCenter(center: box.center, width: art.width * s, height: art.height * s);
  c
    ..drawRect(dst.shift(const ui.Offset(0, 10)), ui.Paint()
      ..color = ink.withValues(alpha: .16)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18))
    ..drawImageRect(art, ui.Rect.fromLTWH(0, 0, art.width * 1.0, art.height * 1.0), dst, ui.Paint()..filterQuality = ui.FilterQuality.medium);
  _text(c, 'made with PICO SNAP', h - 92, ui.TextStyle(color: muted, fontSize: 34, fontFamily: 'Caveat', fontWeight: ui.FontWeight.w600));
  return recorder.endRecording().toImage(TimelapseRecorder.width, TimelapseRecorder.height);
}

void _text(ui.Canvas c, String text, double y, ui.TextStyle style) {
  final p = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
        ..pushStyle(style)
        ..addText(text))
      .build()
    ..layout(const ui.ParagraphConstraints(width: TimelapseRecorder.width * 1.0));
  c.drawParagraph(p, ui.Offset(0, y));
}
