import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../editor_document.dart';
import '../models.dart';
import 'file_store.dart';

class EditorDraft {
  final String id;
  final EditorMode mode;
  final DateTime updated;
  /// A small picture of the piece, if one was saved.
  final File? thumb;
  const EditorDraft(this.id, this.mode, this.updated, [this.thumb]);
  String get label => switch (mode) {
        EditorMode.fourCut => '四格拍貼',
        EditorMode.polaroid => '拍立得拼貼',
        EditorMode.sticker => '貼紙裝飾',
      };
}

/// A draft's JSON is committed last, after its immutable photo files. Earlier
/// checkpoints therefore remain readable when a photo write fails.
abstract final class EditorDrafts {
  static final changes = ValueNotifier<int>(0);
  static final entries = <EditorDraft>[];
  static final _writer = FileWriter();
  static Directory? _root;
  static int _serial = 0;
  static final _assets = <String, Map<Uint8List, String>>{};
  static bool get enabled => _root != null;
  @visibleForTesting
  static void reset() {
    _root = null;
    entries.clear();
    _assets.clear();
  }

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_serial++}';

  static Future<void> load({Directory? directory}) async {
    try {
      _root = await (directory ??
              Directory(
                  '${(await getApplicationDocumentsDirectory()).path}/drafts'))
          .create(recursive: true);
      entries.clear();
      _assets.clear();
      await for (final dir in _root!.list()) {
        if (dir is! Directory) continue;
        final id = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^\d+_\d+$').hasMatch(id)) continue;
        try {
          final json =
              jsonDecode(await File('${dir.path}/draft.json').readAsString())
                  as Map<String, dynamic>;
          if (json['version'] != 1) continue;
          final thumb = File('${dir.path}/thumb.png');
          entries.add(EditorDraft(
              id,
              EditorMode.values.byName(json['mode'] as String),
              DateTime.fromMillisecondsSinceEpoch(json['updated'] as int),
              thumb.existsSync() ? thumb : null));
        } catch (e) {
          debugPrint('[DRAFT] skipped unreadable draft $id: $e');
        }
      }
      _notify();
    } catch (e) {
      _root = null;
      debugPrint('[DRAFT] storage unavailable: $e');
    }
  }

  static Directory _directory(String id) {
    if (!RegExp(r'^\d+_\d+$').hasMatch(id)) {
      throw ArgumentError('Invalid draft id');
    }
    return Directory('${_root!.path}/$id');
  }

  /// [thumb] (PNG) replaces the draft's picture; without one the last
  /// picture stays.
  static Future<bool> save(String id, EditorDocument document, {Uint8List? thumb}) =>
      _writer.run(() async {
        if (!enabled) return false;
        try {
          final dir = await _directory(id).create(recursive: true);
          final known = _assets.putIfAbsent(id, () => Map.identity());
          Future<String?> asset(Uint8List? bytes) async {
            if (bytes == null) return null;
            if (known[bytes] case final name?) return name;
            final name =
                'image_${DateTime.now().microsecondsSinceEpoch}_${_serial++}.bin';
            await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
            known[bytes] = name;
            return name;
          }

          final photos = <String?>[];
          for (final bytes in document.photos) {
            photos.add(await asset(bytes));
          }
          final json = document.toJson(photos, await asset(document.subject));
          final now = DateTime.now();
          json['updated'] = now.millisecondsSinceEpoch;
          final thumbFile = File('${dir.path}/thumb.png');
          if (thumb != null) {
            await File('${dir.path}/thumb.png.tmp').writeAsBytes(thumb, flush: true);
            await File('${dir.path}/thumb.png.tmp').rename(thumbFile.path);
            await FileImage(thumbFile).evict();
          }
          final encoded = await compute(jsonEncode, json);
          final temp = File('${dir.path}/draft.json.tmp');
          await temp.writeAsString(encoded, flush: true);
          await temp.rename('${dir.path}/draft.json');
          entries.removeWhere((d) => d.id == id);
          entries.add(EditorDraft(id, document.mode, now, await thumbFile.exists() ? thumbFile : null));
          _notify();
          return true;
        } catch (e) {
          debugPrint('[DRAFT] save failed: $e');
          return false;
        }
      });

  static Future<EditorDocument> read(String id) => _writer.run(() async {
        final dir = _directory(id);
        final json =
            jsonDecode(await File('${dir.path}/draft.json').readAsString())
                as Map<String, dynamic>;
        Future<Uint8List?> asset(Object? value) async {
          if (value == null) return null;
          final name = value as String;
          if (!RegExp(r'^image_\d+_\d+\.bin$').hasMatch(name)) {
            throw const FormatException('Invalid draft asset');
          }
          final bytes = await File('${dir.path}/$name').readAsBytes();
          _assets.putIfAbsent(id, () => Map.identity())[bytes] = name;
          return bytes;
        }

        final photos = <Uint8List?>[];
        for (final file in json['photos'] as List) {
          photos.add(await asset(file));
        }
        return EditorDocument.fromJson(
            json, photos, await asset(json['subject']));
      });

  static Future<void> remove(String id) => _writer.run(() async {
        if (!enabled) return;
        final dir = _directory(id);
        if (await dir.exists()) await dir.delete(recursive: true);
        entries.removeWhere((d) => d.id == id);
        _assets.remove(id);
        _notify();
      });

  static void release(String id) => _assets.remove(id);

  static void _notify() {
    entries.sort((a, b) => b.updated.compareTo(a.updated));
    changes.value++;
  }
}
