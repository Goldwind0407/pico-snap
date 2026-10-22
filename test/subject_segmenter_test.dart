// 主體分割回來的前景遮罩:只留長按的那一塊。
import 'dart:typed_data';

import 'package:pico_snap/cutout/subject_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 100×60:左邊一個人(方塊)抱著玩偶(貼在旁邊的圓),右邊另一個人
  const w = 100, h = 60;
  Uint8List scene() {
    final fg = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final person = x >= 10 && x < 30 && y >= 5 && y < 55;
        final plush = (x - 36) * (x - 36) + (y - 30) * (y - 30) < 8 * 8;
        final other = x >= 70 && x < 90 && y >= 5 && y < 55;
        if (person || plush || other) fg[y * w + x] = 230;
        // 人的邊緣有一圈半透明
        if (x == 9 && y >= 5 && y < 55) fg[y * w + x] = 90;
      }
    }
    return fg;
  }

  test('長按人:人跟抱著的玩偶一起留下,旁邊另一個人不要', () {
    final out = pickSubject(scene(), w, h, x: 20, y: 30)!;
    expect(out[30 * w + 20], 230, reason: '人');
    expect(out[30 * w + 38], 230, reason: '玩偶連在一起');
    expect(out[30 * w + 80], 0, reason: '另一個人');
    expect(out[30 * w + 9], 90, reason: '邊緣的半透明留著');
  });

  test('按在背景上(附近也沒有前景):回 null,退回 GrabCut', () {
    expect(pickSubject(scene(), w, h, x: 55, y: 30), isNull);
  });

  test('按在主體旁邊一點點也算', () {
    final out = pickSubject(scene(), w, h, x: 91, y: 30)!;
    expect(out[30 * w + 80], 230);
    expect(out[30 * w + 20], 0);
  });

  test('沒給位置:所有夠大的前景都留下', () {
    final out = pickSubject(scene(), w, h)!;
    expect(out[30 * w + 20], 230);
    expect(out[30 * w + 80], 230);
  });

  test('整張都沒有前景:回 null', () {
    expect(pickSubject(Uint8List(w * h), w, h, x: 20, y: 30), isNull);
  });
}
