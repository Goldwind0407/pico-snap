import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'file_store.dart';

enum AppSound {
  tick(.55), ready(.6), shutter(.65), feed(.5), peel(.6), stamp(.6), complete(.6),
  /// Choosing something to make.
  pop(.5),
  /// Picking an option: a filter, film, tool, tab, colour.
  select(.35),
  /// A cut-out finished.
  snip(.6),
  /// A shiny finish or a template landing.
  sparkle(.5),
  undo(.45), redo(.45),
  /// 刪除, after the user confirmed.
  trash(.5),
  /// Sending a piece off to share.
  whoosh(.35),
  /// Turning a page: 日記 months, 貼紙本 pages.
  flip(.4),
  /// Something didn't work: soft, never alarming.
  oops(.5);
  final double volume;
  const AppSound(this.volume);
  String get asset => 'audio/$name.wav';
}

abstract class SoundBackend {
  Future<void> prepare(AppSound sound);
  Future<void> play(AppSound sound, bool Function() allowed);
  Future<void> stop(AppSound? sound);
  Future<void> dispose();
}

class _AudioBackend implements SoundBackend {
  final _players = <AppSound, AudioPlayer>{};
  // Ambient audio follows the silent switch and mixes with music on iOS.
  // Android's ringtone usage follows ringer mode; no audio focus is taken.
  final _context = AudioContext(
    android: const AudioContextAndroid(contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationRingtone, audioFocus: AndroidAudioFocus.none),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  @override
  Future<void> prepare(AppSound sound) async {
    final player = AudioPlayer();
    try {
      await player.setAudioContext(_context);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(sound.volume);
      await player.setSource(AssetSource(sound.asset));
      _players[sound] = player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  @override
  Future<void> play(AppSound sound, bool Function() allowed) async {
    final player = _players[sound];
    if (player == null || !allowed()) return;
    await player.seek(Duration.zero);
    if (allowed()) await player.resume();
  }

  @override
  Future<void> stop(AppSound? sound) => Future.wait([
    for (final entry in _players.entries)
      if (sound == null || entry.key == sound) entry.value.stop(),
  ]);

  @override
  Future<void> dispose() async {
    await Future.wait([for (final player in _players.values) player.dispose()]);
    _players.clear();
  }
}

/// Short offline UI sounds. Every playback is optional and failure-safe: the
/// camera and editor never wait for the audio device to respond.
class AppSounds with WidgetsBindingObserver {
  static final shared = AppSounds();
  final enabled = ValueNotifier<bool>(true);
  final SoundBackend _backend;
  final Future<File?> Function() _settingsFile;
  final _writer = FileWriter();
  final _prepared = <AppSound, Future<void>>{};
  final _lastPlay = <AppSound, DateTime>{};
  final _versions = <AppSound, int>{};
  Future<void>? _initializing;
  File? _file;
  int _generation = 0;
  bool _ready = false, _active = true, _disposed = false;

  AppSounds({SoundBackend? backend, Future<File?> Function()? settingsFile})
    : _backend = backend ?? _AudioBackend(), _settingsFile = settingsFile ?? _defaultFile;

  static Future<File?> _defaultFile() async => File('${(await getApplicationDocumentsDirectory()).path}/sound_settings.json');

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      _file = await _settingsFile();
      final file = _file;
      if (file != null && await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (!_disposed && data is Map && data['enabled'] is bool) enabled.value = data['enabled'] as bool;
      }
    } catch (e) {
      debugPrint('[SOUND] settings unavailable: $e');
    }
    if (_disposed) return;
    _active = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _ready = true;
    WidgetsBinding.instance.addObserver(this);
    if (enabled.value) _warmUp();
  }

  Future<void> _prepare(AppSound sound) => _prepared.putIfAbsent(sound, () => _backend.prepare(sound).catchError((Object e, StackTrace stack) {
    _prepared.remove(sound);
    Error.throwWithStackTrace(e, stack);
  }));

  void _warmUp() {
    for (final sound in AppSound.values) {
      unawaited(_prepare(sound).catchError((Object e) { debugPrint('[SOUND] ${sound.name} unavailable: $e'); }));
    }
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (_disposed || enabled.value == value) return;
    enabled.value = value;
    if (!value) { stop(); } else { _warmUp(); }
    final file = _file;
    if (file != null) {
      try { await _writer.writeString(file, jsonEncode({'enabled': value})); }
      catch (e) { debugPrint('[SOUND] settings save failed: $e'); }
    }
  }

  void play(AppSound sound) {
    if (!_ready || !enabled.value || !_active || _disposed) return;
    final now = DateTime.now(), last = _lastPlay[sound];
    if (last != null && now.difference(last).inMilliseconds < 90) return;
    _lastPlay[sound] = now;
    final generation = _generation;
    final version = _versions[sound] ?? 0;
    bool allowed() => !_disposed && _ready && enabled.value && _active &&
      generation == _generation && version == (_versions[sound] ?? 0);
    unawaited(() async {
      try {
        await _prepare(sound);
        // Never play an old shutter/tick after a slow device finishes loading.
        if (allowed() && DateTime.now().difference(now).inMilliseconds < 300) await _backend.play(sound, allowed);
      } catch (e) { debugPrint('[SOUND] ${sound.name} failed: $e'); }
    }());
  }

  void stop([AppSound? sound]) {
    if (sound == null) { _generation++; } else { _versions[sound] = (_versions[sound] ?? 0) + 1; }
    unawaited(_backend.stop(sound).catchError((Object e) { debugPrint('[SOUND] stop failed: $e'); }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) stop();
  }

  Future<void> dispose() async {
    _disposed = true;
    _ready = false;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    // Do not let an in-flight preload leave a player behind after disposal.
    await Future.wait([for (final future in _prepared.values) future.catchError((Object _) {})]);
    await _backend.dispose();
    enabled.dispose();
  }
}
