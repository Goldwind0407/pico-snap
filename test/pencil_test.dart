// Apple Pencil: the double-tap settings, palm then pen, the pen's back end,
// pressure edges and a landscape iPad canvas.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/editor_screen.dart';
import 'package:pico_snap/services/my_works.dart';
import 'package:pico_snap/widgets/doodle.dart';
import 'package:pico_snap/widgets/frames.dart';

Future<void> _phone(WidgetTester t, Widget home, {Size size = const Size(390, 844)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

List<Stroke> _strokes(WidgetTester t) {
  final ink = find.byType(InkLayer);
  return ink.evaluate().isEmpty ? const [] : t.widget<InkLayer>(ink).strokes;
}

Future<void> _draw(WidgetTester t, Offset from, Offset by) async {
  final g = await t.startGesture(from);
  for (var i = 1; i <= 10; i++) {
    await g.moveTo(from + by * (i / 10));
    await t.pump();
  }
  await g.up();
  await t.pumpAndSettle();
}

Future<void> _pen(WidgetTester t, int id, Offset from, Offset by,
    {PointerDeviceKind kind = PointerDeviceKind.stylus, double pressure = .6, bool up = true}) async {
  t.binding.handlePointerEvent(PointerDownEvent(pointer: id, kind: kind, position: from, pressure: pressure, pressureMin: 0, pressureMax: 1));
  for (var k = 1; k <= 8; k++) {
    t.binding.handlePointerEvent(PointerMoveEvent(pointer: id, kind: kind, position: from + by * (k / 8), pressure: pressure, pressureMin: 0, pressureMax: 1));
    await t.pump(const Duration(milliseconds: 16));
  }
  if (up) {
    t.binding.handlePointerEvent(PointerUpEvent(pointer: id, kind: kind, position: from + by));
    await t.pump();
  }
}

Future<Offset> _openBrush(WidgetTester t, {Size size = const Size(390, 844)}) async {
  await _phone(t, const EditorScreen(), size: size);
  await t.tap(find.text('畫筆').first);
  await t.pumpAndSettle();
  return t.getRect(find.byType(PhotoStrip)).center;
}

void main() {
  setUp(MyWorks.reset);
  tearDown(DoodleInput.forgetPen);

  testWidgets('點兩下設成「切換到上一個工具」：螢光筆 ↔ 畫筆', (t) async {
    final c = await _openBrush(t);
    await t.tap(find.text('螢光筆'));
    await t.pumpAndSettle();
    PencilTaps.debugTap('previous');
    await t.pump();
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t).last.style, PenStyle.pen, reason: '回到上一個工具（畫筆）');
    PencilTaps.debugTap('previous');
    await t.pump();
    await _draw(t, c - const Offset(40, 30), const Offset(80, 0));
    expect(_strokes(t).last.style, PenStyle.marker, reason: '再點兩下回到螢光筆');
  });

  testWidgets('點兩下設成「顯示顏色」：換下一個顏色', (t) async {
    final c = await _openBrush(t);
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    final before = _strokes(t).last.color;
    PencilTaps.debugTap('palette');
    await t.pump();
    await _draw(t, c - const Offset(40, 30), const Offset(80, 0));
    final after = _strokes(t).last.color;
    expect(after, isNot(before));
    expect(penColors.indexOf(after), (penColors.indexOf(before) + 1) % penColors.length);
  });

  testWidgets('點兩下設成「關閉」：什麼都不變', (t) async {
    final c = await _openBrush(t);
    PencilTaps.debugTap('ignore');
    await t.pump();
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t).single.style, PenStyle.pen);
  });

  testWidgets('橡皮擦狀態下點「顯示顏色」：回到畫筆再換色', (t) async {
    final c = await _openBrush(t);
    PencilTaps.debugTap('eraser');
    await t.pump();
    PencilTaps.debugTap('palette');
    await t.pump();
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t).single.style, PenStyle.pen);
  });

  testWidgets('沒開畫筆工具時點兩下：不會偷偷切到橡皮擦', (t) async {
    await _phone(t, const EditorScreen());
    PencilTaps.debugTap('eraser');
    await t.pump();
    await t.tap(find.text('畫筆').first);
    await t.pumpAndSettle();
    final c = t.getRect(find.byType(PhotoStrip)).center;
    await _draw(t, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t), hasLength(1), reason: '還是畫筆，不是橡皮擦');
  });

  testWidgets('手掌先碰到、筆再下去：筆接手，手掌那筆不會繼續畫', (t) async {
    final c = await _openBrush(t);
    final palm = await t.startGesture(c + const Offset(-60, 80));
    await palm.moveBy(const Offset(10, 0));
    await t.pump();
    await _pen(t, 7, c - const Offset(40, 20), const Offset(80, 0));
    await palm.moveBy(const Offset(60, 0));
    await t.pump();
    await palm.up();
    await t.pumpAndSettle();
    final pens = _strokes(t).where((s) => s.pressures != null).toList();
    expect(pens, hasLength(1), reason: '筆畫出了一條線');
    final palms = _strokes(t).where((s) => s.pressures == null).toList();
    for (final s in palms) {
      expect(s.points.length, lessThanOrEqualTo(3), reason: '手掌那筆在筆下去時就停了');
    }
  });

  testWidgets('筆尾（invertedStylus）是橡皮擦', (t) async {
    final c = await _openBrush(t);
    await _pen(t, 1, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t), hasLength(1));
    await _pen(t, 2, c - const Offset(0, 30), const Offset(0, 60), kind: PointerDeviceKind.invertedStylus);
    expect(_strokes(t), isEmpty);
  });

  testWidgets('壓力 0 和 1 不會超出範圍；沒有壓力範圍的筆當作中間值', (t) async {
    final c = await _openBrush(t);
    await _pen(t, 1, c - const Offset(40, 0), const Offset(80, 0), pressure: 1);
    expect(_strokes(t).last.pressures!.every((p) => p >= 0 && p <= 1), isTrue);
    t.binding.handlePointerEvent(PointerDownEvent(pointer: 3, kind: PointerDeviceKind.stylus, position: c, pressure: 0, pressureMin: 1, pressureMax: 1));
    t.binding.handlePointerEvent(PointerMoveEvent(pointer: 3, kind: PointerDeviceKind.stylus, position: c + const Offset(30, 30), pressure: 0, pressureMin: 1, pressureMax: 1));
    t.binding.handlePointerEvent(PointerUpEvent(pointer: 3, kind: PointerDeviceKind.stylus, position: c + const Offset(30, 30)));
    await t.pump();
    expect(_strokes(t).last.pressures!.first, .5);
  });

  testWidgets('iPad 尺寸（橫的）也能用筆畫', (t) async {
    final c = await _openBrush(t, size: const Size(1366, 1024));
    await _pen(t, 1, c - const Offset(40, 0), const Offset(80, 0));
    expect(_strokes(t), hasLength(1));
  });
}
