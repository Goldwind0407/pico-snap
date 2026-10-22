import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/services/timelapse_recorder.dart';

/// 一張純色的「作品」。
Future<ui.Image> _art(Color color, {int w = 200, int h = 620}) {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(ui.Rect.fromLTWH(0, 0, w * 1.0, h * 1.0), ui.Paint()..color = color);
  return r.endRecording().toImage(w, h);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('timelapse_test'));
  tearDown(() async {
    // The recorder deletes its own folder in the background too.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // already gone
    }
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 400));

  test('畫格是 720×1280，作品置中', () async {
    final frame = await composeFrame(await _art(const Color(0xFF2050F0)));
    expect([frame.width, frame.height], [720, 1280]);
    final px = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int at(int x, int y, int c) => px.getUint8((y * 720 + x) * 4 + c);
    expect(at(360, 640, 2), greaterThan(200), reason: '中間是作品（藍色）');
    expect(at(5, 640, 0), greaterThan(240), reason: '旁邊是奶油色底');
  });

  test('一直有變化也不會每次都截：最多每 250ms 一張，最後的狀態一定會截到', () async {
    final rec = TimelapseRecorder(dir: tmp);
    var calls = 0;
    Future<ui.Image?> source() async {
      calls++;
      return _art(const Color(0xFFFF0000));
    }

    for (var i = 0; i < 20; i++) {
      rec.request(source);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await settle();
    expect(calls, inInclusiveRange(2, 4), reason: '20 次變化 × 20ms ≈ 400ms，只截 2～4 張');
    expect(rec.frameCount, calls);
    rec.dispose();
  });

  test('畫格太多就隔一張丟一張', () async {
    final rec = TimelapseRecorder(dir: tmp, maxFrames: 4);
    for (var i = 0; i < 4; i++) {
      rec.request(() => _art(const Color(0xFF00FF00)));
      await settle();
    }
    expect(rec.frameCount, 2);
    rec.dispose();
  });

  test('做成影片：畫格依序送給編碼器，畫格少的時候每格多停一下，最後的成品停兩秒', () async {
    const channel = MethodChannel('picosnap/video');
    MethodCall? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return (call.arguments as Map)['out'];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final rec = TimelapseRecorder(dir: tmp);
    for (final c in [0xFFFF0000, 0xFF00FF00, 0xFF0000FF]) {
      rec.request(() => _art(Color(c)));
      await settle();
    }
    final out = await rec.render(await _art(const Color(0xFFFFFFFF)));
    expect(out, endsWith('.mp4'));
    final args = sent!.arguments as Map;
    final frames = (args['frames'] as List).cast<String>();
    // 只有 3 格：每格停 6 格（0.5 秒），成品停 2 秒
    expect(frames, hasLength(3 * 6 + TimelapseRecorder.fps * TimelapseRecorder.holdSeconds));
    expect(frames.take(6).toSet(), hasLength(1));
    expect(frames.toSet(), hasLength(4), reason: '3 張過程 + 1 張成品');
    expect(frames.every((f) => File(f).existsSync()), isTrue);
    expect([args['width'], args['height'], args['fps']], [720, 1280, 12]);
    rec.dispose();
  });

  test('編碼器不能用時回傳 null，不會當掉', () async {
    final rec = TimelapseRecorder(dir: tmp);
    rec.request(() => _art(const Color(0xFFFF0000)));
    await settle();
    expect(await rec.render(await _art(const Color(0xFFFFFFFF))), isNull);
    rec.dispose();
  });
}
