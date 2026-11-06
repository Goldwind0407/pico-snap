import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/services/app_sounds.dart';
import 'package:pico_snap/theme.dart';
import 'package:pico_snap/widgets/sound_settings.dart';

class FakeSoundBackend implements SoundBackend {
  final played = <AppSound>[];
  final stopped = <AppSound?>[];
  Completer<void>? loading;
  Completer<void>? seeking;
  bool fail = false, disposed = false;

  @override
  Future<void> prepare(AppSound sound) async {
    if (sound == AppSound.shutter) await loading?.future;
    if (fail) throw StateError('Audio device unavailable');
  }

  @override
  Future<void> play(AppSound sound, bool Function() allowed) async {
    await seeking?.future;
    if (allowed()) played.add(sound);
  }

  @override
  Future<void> stop(AppSound? sound) async { stopped.add(sound); }

  @override
  Future<void> dispose() async { disposed = true; }
}

Future<void> flushAudio() async {
  for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppSounds> create(FakeSoundBackend backend, {File? settings}) async {
    final sounds = AppSounds(backend: backend, settingsFile: () async => settings);
    await sounds.initialize();
    sounds.didChangeAppLifecycleState(AppLifecycleState.resumed);
    return sounds;
  }

  test('muting while an effect loads cancels the pending playback', () async {
    final backend = FakeSoundBackend()..loading = Completer<void>();
    final sounds = await create(backend);
    sounds.play(AppSound.shutter);
    await sounds.setEnabled(false);
    backend.loading!.complete();
    await flushAudio();
    expect(backend.played, isEmpty);
    expect(backend.stopped, contains(null));
    await sounds.dispose();
  });

  test('backgrounding while an audio seek is pending cannot resume the sound', () async {
    final backend = FakeSoundBackend()..seeking = Completer<void>();
    final sounds = await create(backend);
    sounds.play(AppSound.feed);
    await flushAudio();
    sounds.didChangeAppLifecycleState(AppLifecycleState.inactive);
    backend.seeking!.complete();
    await flushAudio();
    expect(backend.played, isEmpty);
    sounds.play(AppSound.stamp);
    await flushAudio();
    expect(backend.played, isEmpty);
    await sounds.dispose();
  });

  test('stopping a route effect invalidates its preload and rapid taps are bounded', () async {
    final backend = FakeSoundBackend()..loading = Completer<void>();
    final sounds = await create(backend);
    sounds.play(AppSound.shutter);
    sounds.stop(AppSound.shutter);
    backend.loading!.complete();
    sounds.play(AppSound.stamp);
    sounds.play(AppSound.stamp);
    await flushAudio();
    expect(backend.played, [AppSound.stamp]);
    expect(backend.stopped, contains(AppSound.shutter));
    await sounds.dispose();
    expect(backend.disposed, isTrue);
  });

  test('a missing audio device cannot break an interaction', () async {
    final backend = FakeSoundBackend()..fail = true;
    final sounds = await create(backend);
    sounds.play(AppSound.shutter);
    await flushAudio();
    expect(backend.played, isEmpty);
    await sounds.dispose();
  });

  test('the master sound preference survives reopening the app', () async {
    final dir = await Directory.systemTemp.createTemp('picosnap_sound_test_');
    final file = File('${dir.path}/sounds.json');
    try {
      final first = await create(FakeSoundBackend(), settings: file);
      await first.setEnabled(false);
      await first.dispose();
      final backend = FakeSoundBackend();
      final second = await create(backend, settings: file);
      expect(second.enabled.value, isFalse);
      second.play(AppSound.complete);
      await flushAudio();
      expect(backend.played, isEmpty);
      await second.dispose();
    } finally {
      if (await file.exists()) await file.delete();
      await dir.delete();
    }
  });

  testWidgets('home button and camera switch share one sound preference', (t) async {
    final backend = FakeSoundBackend();
    final sounds = await create(backend);
    await t.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Column(children: [
      SoundToggleButton(sounds: sounds), SoundSettingsTile(sounds: sounds),
    ]))));
    await t.tap(find.byTooltip('關閉音效'));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(find.byTooltip('開啟音效'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(sounds.enabled.value, isTrue);
    expect(backend.played, [AppSound.stamp]);
    await t.pumpWidget(const SizedBox());
    await sounds.dispose();
  });

  test('all original audio assets are short, non-silent 16-bit PCM WAVs', () async {
    for (final sound in AppSound.values) {
      final wav = await rootBundle.load('assets/${sound.asset}');
      expect(String.fromCharCodes(wav.buffer.asUint8List(0, 4)), 'RIFF');
      expect(wav.getUint16(20, Endian.little), 1);
      expect(wav.getUint16(22, Endian.little), 1);
      expect(wav.getUint16(34, Endian.little), 16);
      final count = wav.getUint32(40, Endian.little) ~/ 2;
      expect(count / wav.getUint32(24, Endian.little), inInclusiveRange(.1, 2));
      var peak = 0;
      for (var i = 0; i < count; i++) {
        final value = wav.getInt16(44 + i * 2, Endian.little).abs();
        if (value > peak) peak = value;
      }
      expect(peak, inInclusiveRange(2000, 30000), reason: sound.name);
      expect(wav.getInt16(44, Endian.little), 0);
    }
  });
}
