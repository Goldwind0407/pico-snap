import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/color_grade.dart';
import 'package:pico_snap/filters.dart';
import 'package:pico_snap/lut_files.dart';

/// A 2³ .cube that swaps red and blue, listed red fastest like real files.
String _swapCube({String header = ''}) {
  final b = StringBuffer('TITLE "Swap RB"\n# comment\n$header LUT_3D_SIZE 2\n');
  for (var bi = 0; bi < 2; bi++) {
    for (var gi = 0; gi < 2; gi++) {
      for (var ri = 0; ri < 2; ri++) {
        b.writeln('$bi.0 $gi.0 $ri.0');
      }
    }
  }
  return b.toString();
}

void main() {
  test('.cube：讀出標題、紅色最快的順序換成我們的順序', () {
    final lut = parseCube(_swapCube());
    expect(lut.title, 'Swap RB');
    expect(lut.size, 2);
    final graded = applyLut(Uint8List.fromList([255, 128, 0, 255]), lut.table, 2);
    expect(graded, [0, 128, 255, 255], reason: '紅藍互換，綠色線性插值不變');
  });

  test('.cube：DOMAIN 不是 0–1 也換算回來；資料不完整就報錯', () {
    final lut = parseCube(_swapCube(header: 'DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n'));
    expect(lut.table.reduce((a, b) => a > b ? a : b), .5);
    expect(() => parseCube('LUT_3D_SIZE 2\n0 0 0\n'), throwsFormatException);
    expect(() => parseCube('LUT_1D_SIZE 4\n'), throwsFormatException);
  });

  test('換成 33³：恆等 LUT 換尺寸還是恆等', () {
    final identity = resampleLut(parseCube(_identityCube(5)).table, 5, lutSize);
    expect(identity.length, lutSize * lutSize * lutSize * 3);
    final pixels = Uint8List.fromList([12, 200, 99, 255, 255, 0, 64, 255]);
    final out = applyLut(pixels, identity, lutSize);
    for (var i = 0; i < pixels.length; i++) {
      expect((out[i] - pixels[i]).abs(), lessThanOrEqualTo(1));
    }
  });

  test('Hald 圖：level 2（8×8 像素、4³）照紅色最快一列一列讀', () {
    const n = 4;
    final rgba = Uint8List(8 * 8 * 4);
    for (var k = 0; k < n * n * n; k++) {
      final r = k % n, g = (k ~/ n) % n, b = k ~/ (n * n);
      rgba.setAll(k * 4, [r * 85, g * 85, b * 85, 255]);
    }
    final lut = haldFromPixels(rgba, 8, 8);
    expect(lut.size, n);
    // Our order: blue fastest. Entry (r=1, g=2, b=3).
    final o = ((1 * n + 2) * n + 3) * 3;
    expect(lut.table.sublist(o, o + 3), pairwiseCompare([85 / 255, 170 / 255, 1.0], (double a, double e) => (a - e).abs() < 1e-6, 'close to'));
    expect(() => haldFromPixels(Uint8List(10 * 10 * 4), 10, 10), throwsFormatException);
  });

  test('濾鏡檔做成的濾鏡直接用那張表', () {
    final table = resampleLut(parseCube(_swapCube()).table, 2, lutSize);
    final f = PhotoFilter.lut('lut:swap', '互換', table);
    expect(f.lut, same(table));
    expect(f.isNone, isFalse);
    final m = f.matrix;
    expect(m[2], closeTo(1, .01), reason: '新的紅色取自藍色');
    expect(m[10], closeTo(1, .01), reason: '新的藍色取自紅色');
  });

  test('濾鏡檔帶著自己的名字和底片效果', () {
    const look = LutLook('暖調人像', grain: .35, halation: .35);
    final f = PhotoFilter.lut('lut:warm', look.name, resampleLut(parseCube(_swapCube()).table, 2, lutSize),
        grain: look.grain, halation: look.halation);
    expect(f.grain, look.grain);
    expect(f.halation, look.halation);
    expect(f.vignette, 0);
  });
}

String _identityCube(int n) {
  final b = StringBuffer('LUT_3D_SIZE $n\n');
  for (var bi = 0; bi < n; bi++) {
    for (var gi = 0; gi < n; gi++) {
      for (var ri = 0; ri < n; ri++) {
        b.writeln('${ri / (n - 1)} ${gi / (n - 1)} ${bi / (n - 1)}');
      }
    }
  }
  return b.toString();
}
