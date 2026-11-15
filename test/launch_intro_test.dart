import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/widgets/launch_intro.dart';

void main() {
  Widget app({bool enabled = true}) => MaterialApp(
    builder: (context, child) => LaunchIntro(enabled: enabled, child: child!),
    home: const Scaffold(body: Center(child: Text('home'))),
  );

  testWidgets('開場動畫蓋在 App 上面，播完就拿掉', (t) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShaderMask), findsWidgets, reason: '簽名正在寫');
    expect(find.text('home'), findsOneWidget, reason: '底下的畫面同時載入');
    // The controller starts on its first frame after the artwork is ready.
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(LaunchIntro.duration);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(GestureDetector), findsNothing, reason: '不再擋住點擊');
  });

  testWidgets('點一下跳過：直接淡出', (t) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 300));
    await t.tapAt(const Offset(200, 300));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('關掉時直接是 App', (t) async {
    await t.pumpWidget(app(enabled: false));
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
