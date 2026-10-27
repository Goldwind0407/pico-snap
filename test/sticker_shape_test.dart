import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/cutout/sticker_shape.dart';

void main() {
  test('resizeMask：放大後形狀和位置不變', () {
    const w = 10, h = 10;
    final m = Uint8List(w * h);
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        m[y * w + x] = 255;
      }
    }
    final big = resizeMask(m, w, h, 40, 40);
    expect(big[5 * 40 + 5], 255, reason: '左上角');
    expect(big[35 * 40 + 35], 0, reason: '右下角');
  });

  test('ShapeFit：照片永遠蓋滿外框', () {
    // 2:1 的照片放在正方形裡，左右可以移，上下不行
    final fit = const ShapeFit(1, Offset(.9, .9)).clamped(2);
    final r = fit.rect(100, 2);
    expect(r.left, lessThanOrEqualTo(0));
    expect(r.right, greaterThanOrEqualTo(100));
    expect(r.top, 0);
    expect(r.bottom, 100);
  });

  test('每個外框形狀都在正方形裡', () {
    for (final s in StickerShape.values) {
      final b = s.path(100).getBounds();
      expect(b.left, greaterThanOrEqualTo(-3), reason: s.name);
      expect(b.right, lessThanOrEqualTo(103), reason: s.name);
      expect(b.width, greaterThan(80), reason: s.name);
    }
  });
}
