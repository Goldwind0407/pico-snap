import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// 作品是用哪一種玩法做的。
enum WorkKind {
  fourCut('四格拍貼'),
  collage('拍立得拼貼'),
  sticker('貼紙'),
  instant('拍立得');

  final String label;
  const WorkKind(this.label);
}

/// 存到相簿過的一件作品（App 自己留一份看的版本，不是相簿裡的原檔）。
class Work {
  final String id;
  final WorkKind kind;
  final DateTime created;
  /// 放在檔案裡的話是 [file]，拿不到檔案系統（網頁版、測試）就是 [bytes]。
  final File? file;
  final Uint8List? bytes;
  const Work({required this.id, required this.kind, required this.created, this.file, this.bytes});

  ImageProvider get image => file != null ? FileImage(file!) as ImageProvider : MemoryImage(bytes!);

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 't': created.millisecondsSinceEpoch};
}

/// 「作品集」和「日記」的資料：每次存到相簿就收一份進來，另外每天可以寫一句日記。
///
/// 存在 App 文件資料夾的 works/ 裡：一件作品一個 PNG，清單是 works.json，
/// 日記是 diary.json。拿不到檔案系統就只放在記憶體裡。
class MyWorks {
  MyWorks._();

  /// 新到舊。
  static final List<Work> works = [];
  /// 'yyyy-mm-dd' → 那天的日記。
  static final Map<String, String> notes = {};
  /// 每次有改動都會加一，畫面聽這個重畫。
  static final changes = ValueNotifier<int>(0);

  static Directory? _dir;

  static Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/works');
      await dir.create(recursive: true);
      _dir = dir;
      final list = File('${dir.path}/works.json');
      if (list.existsSync()) {
        works
          ..clear()
          ..addAll([
            for (final w in jsonDecode(list.readAsStringSync()) as List)
              if (WorkKind.values.asNameMap()[(w as Map)['kind']] case final kind?)
                if (File('${dir.path}/${w['id']}.png') case final f when f.existsSync())
                  Work(id: '${w['id']}', kind: kind, created: DateTime.fromMillisecondsSinceEpoch(w['t'] as int), file: f),
          ]);
      }
      final diary = File('${dir.path}/diary.json');
      if (diary.existsSync()) {
        notes
          ..clear()
          ..addAll((jsonDecode(diary.readAsStringSync()) as Map).cast<String, String>());
      }
    } catch (e) {
      debugPrint('[WORKS] 讀取作品集失敗，這次只放在記憶體裡: $e');
    }
    changes.value++;
  }

  /// 測試用：清空，回到只放在記憶體裡。
  @visibleForTesting
  static void reset() {
    _dir = null;
    works.clear();
    notes.clear();
    changes.value++;
  }

  static int _last = 0;

  /// 收進一件作品（[png] 是給 App 裡看的縮小版）。
  static Future<Work> add(Uint8List png, WorkKind kind, {DateTime? at}) async {
    _last = max(_last + 1, DateTime.now().microsecondsSinceEpoch);
    final id = '$_last';
    final created = at ?? DateTime.now();
    Work work = Work(id: id, kind: kind, created: created, bytes: png);
    if (_dir case final dir?) {
      try {
        final f = File('${dir.path}/$id.png');
        await f.writeAsBytes(png);
        work = Work(id: id, kind: kind, created: created, file: f);
      } catch (e) {
        debugPrint('[WORKS] 存作品失敗，這次只放在記憶體裡: $e');
      }
    }
    works.insert(0, work);
    await _saveList();
    return work;
  }

  /// 從作品集拿掉（相簿裡的那份不會動）。
  static Future<void> remove(String id) async {
    final i = works.indexWhere((w) => w.id == id);
    if (i < 0) return;
    final work = works.removeAt(i);
    await _saveList();
    try {
      await work.file?.delete();
    } catch (e) {
      debugPrint('[WORKS] 刪作品檔失敗: $e');
    }
  }

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<Work> on(DateTime day) => [for (final w in works) if (dayKey(w.created) == dayKey(day)) w];

  static String noteOn(DateTime day) => notes[dayKey(day)] ?? '';

  /// 寫那天的日記；空白就刪掉。
  static Future<bool> setNote(DateTime day, String text) async {
    final key = dayKey(day);
    if (text.trim().isEmpty) {
      notes.remove(key);
    } else {
      notes[key] = text.trim();
    }
    changes.value++;
    return _write('diary.json', jsonEncode(notes));
  }

  static Future<bool> _saveList() {
    changes.value++;
    return _write('works.json', jsonEncode([for (final w in works) w.toJson()]));
  }

  static Future<bool> _write(String name, String json) async {
    final dir = _dir;
    if (dir == null) return true;
    try {
      await File('${dir.path}/$name').writeAsString(json);
      return true;
    } catch (e) {
      debugPrint('[WORKS] 存檔失敗: $e');
      return false;
    }
  }
}
