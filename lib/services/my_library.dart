import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// 使用者在「我的素材」做的貼紙和模板。
///
/// 資料放在 [customStickers]、[customTemplates]，另外存成 App 文件資料夾裡
/// 的檔案（貼紙一張一個 PNG、模板一個 JSON），重開 App 還在。
/// 拿不到檔案系統（網頁版、測試）就只放在記憶體裡。
class MyLibrary {
  MyLibrary._();

  /// 每次新增或刪除都會加一，畫面聽這個重畫。
  static final changes = ValueNotifier<int>(0);

  static Directory? _dir;

  static Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/my_library');
      final stickers = Directory('${dir.path}/stickers');
      await stickers.create(recursive: true);
      _dir = dir;
      // 檔名是建立時間，排序之後就是做的順序
      final files = stickers.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        customStickers['my:${name.substring(0, name.length - 4)}'] = f.readAsBytesSync();
      }
      final json = File('${dir.path}/templates.json');
      if (json.existsSync()) {
        final list = jsonDecode(json.readAsStringSync()) as List;
        customTemplates
          ..clear()
          ..addAll([for (final t in list) CustomTemplate.fromJson((t as Map).cast<String, Object?>())]);
      }
    } catch (e) {
      debugPrint('[LIBRARY] 讀取我的素材失敗，這次只放在記憶體裡: $e');
    }
    changes.value++;
  }

  static int _last = 0;

  /// 不重複的編號：建立時間（微秒），同一微秒做兩張就往後加一。
  static String newKey() {
    _last = max(_last + 1, DateTime.now().microsecondsSinceEpoch);
    return '$_last';
  }

  /// 新增貼紙，回傳它的 id。
  static String addSticker(Uint8List png) {
    final key = newKey();
    final id = 'my:$key';
    customStickers[id] = png;
    changes.value++;
    _write(() => File('${_dir!.path}/stickers/$key.png').writeAsBytes(png));
    return id;
  }

  static void removeSticker(String id) {
    customStickers.remove(id);
    changes.value++;
    _write(() => File('${_dir!.path}/stickers/${id.substring(3)}.png').delete());
  }

  static void addTemplate(CustomTemplate template) {
    customTemplates.add(template);
    _saveTemplates();
  }

  /// Replace the template with the same id (after editing it).
  static void updateTemplate(CustomTemplate template) {
    final i = customTemplates.indexWhere((t) => t.id == template.id);
    if (i < 0) return addTemplate(template);
    customTemplates[i] = template;
    _saveTemplates();
  }

  static void removeTemplate(String id) {
    customTemplates.removeWhere((t) => t.id == id);
    _saveTemplates();
  }

  static void _saveTemplates() {
    changes.value++;
    final json = jsonEncode([for (final t in customTemplates) t.toJson()]);
    _write(() => File('${_dir!.path}/templates.json').writeAsString(json));
  }

  static Future<void> _write(Future<void> Function() op) async {
    if (_dir == null) return;
    try {
      await op();
    } catch (e) {
      debugPrint('[LIBRARY] 存檔失敗: $e');
    }
  }
}
