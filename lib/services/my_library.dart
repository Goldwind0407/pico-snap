import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'file_store.dart';

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
    final Directory dir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}/my_library');
      await Directory('${dir.path}/stickers').create(recursive: true);
    } catch (e) {
      debugPrint('[LIBRARY] 沒有文件資料夾，這次只放在記憶體裡: $e');
      changes.value++;
      return;
    }
    _dir = dir;
    // 檔名是建立時間，排序之後就是做的順序
    try {
      final files = (await Directory('${dir.path}/stickers').list().toList()).whereType<File>().where((f) => f.path.endsWith('.png')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final id = 'my:${name.substring(0, name.length - 4)}';
        customStickerPaths[id] = f.path;
        customStickers.putIfAbsent(id, () => null);
      }
    } catch (e) {
      debugPrint('[LIBRARY] 讀取貼紙失敗: $e');
    }
    final sheets = File('${dir.path}/sheets.json');
    try {
      if (await sheets.exists()) {
        final j = (jsonDecode(await sheets.readAsString()) as Map).cast<String, Object?>();
        mySheets
          ..clear()
          ..addAll([for (final t in j['sheets'] as List) MySheet.fromJson((t as Map).cast<String, Object?>())]);
        stickerNames
          ..clear()
          ..addAll((j['names'] as Map).cast<String, String>());
      }
    } catch (e) {
      debugPrint('[LIBRARY] 貼紙紙檔壞掉了，先收到旁邊: $e');
      keepAside(sheets);
    }
    final json = File('${dir.path}/templates.json');
    try {
      if (await json.exists()) {
        final list = jsonDecode(await json.readAsString()) as List;
        customTemplates
          ..clear()
          ..addAll([for (final t in list) CustomTemplate.fromJson((t as Map).cast<String, Object?>())]);
      }
    } catch (e) {
      debugPrint('[LIBRARY] 模板檔壞掉了，先收到旁邊: $e');
      keepAside(json);
    }
    changes.value++;
  }

  static int _last = 0;

  /// 不重複的編號：建立時間（微秒），同一微秒做兩張就往後加一。
  static String newKey() {
    _last = max(_last + 1, DateTime.now().microsecondsSinceEpoch);
    return '$_last';
  }

  /// 新增貼紙，回傳它的 id。有 [sheet] 就放到那張貼紙紙最後面。
  static String addSticker(Uint8List png, {String? sheet, String name = ''}) {
    final key = newKey();
    final id = 'my:$key';
    customStickers[id] = png;
    if (name.trim().isNotEmpty) stickerNames[id] = name.trim();
    final i = mySheets.indexWhere((s) => s.id == sheet);
    if (i >= 0) mySheets[i] = mySheets[i].copyWith(stickers: [...mySheets[i].stickers, id]);
    _write(() => _writer.writeBytes(File('${_dir!.path}/stickers/$key.png'), png));
    _saveSheets();
    return id;
  }

  static void removeStickers(Iterable<String> ids) {
    final gone = ids.toSet();
    for (final id in gone) {
      customStickers.remove(id);
      customStickerPaths.remove(id);
      stickerNames.remove(id);
      _write(() => _writer.run(() => File('${_dir!.path}/stickers/${id.substring(3)}.png').delete()));
    }
    for (var i = 0; i < mySheets.length; i++) {
      mySheets[i] = mySheets[i].copyWith(stickers: [for (final s in mySheets[i].stickers) if (!gone.contains(s)) s]);
    }
    _saveSheets();
  }

  static void renameSticker(String id, String name) {
    name.trim().isEmpty ? stickerNames.remove(id) : stickerNames[id] = name.trim();
    _saveSheets();
  }

  /// 新增一張貼紙紙，回傳它的 id。
  static String addSheet(String name) {
    final id = newKey();
    mySheets.add(MySheet(id: id, name: name.trim()));
    _saveSheets();
    return id;
  }

  static void renameSheet(String id, String name) {
    final i = mySheets.indexWhere((s) => s.id == id);
    if (i < 0) return;
    mySheets[i] = mySheets[i].copyWith(name: name.trim());
    _saveSheets();
  }

  /// 刪掉貼紙紙；上面的貼紙不刪，回到「未分類」。
  static void removeSheet(String id) {
    mySheets.removeWhere((s) => s.id == id);
    _saveSheets();
  }

  /// 把 [ids] 移到貼紙紙 [sheet] 最後面（null：移回未分類）。
  static void moveStickers(Iterable<String> ids, String? sheet) {
    final move = ids.toSet();
    for (var i = 0; i < mySheets.length; i++) {
      mySheets[i] = mySheets[i].copyWith(stickers: [for (final s in mySheets[i].stickers) if (!move.contains(s)) s]);
    }
    final i = mySheets.indexWhere((s) => s.id == sheet);
    if (i >= 0) {
      mySheets[i] = mySheets[i].copyWith(stickers: [...mySheets[i].stickers, for (final id in ids) if (move.contains(id)) id]);
    }
    _saveSheets();
  }

  static void _saveSheets() {
    changes.value++;
    final json = jsonEncode({'sheets': [for (final s in mySheets) s.toJson()], 'names': stickerNames});
    _write(() => _writer.writeString(File('${_dir!.path}/sheets.json'), json));
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
    _write(() => _writer.writeString(File('${_dir!.path}/templates.json'), json));
  }

  /// 最近一次寫進手機有沒有成功（等它前面排隊的都寫完）。畫面上已經先
  /// 改好了，失敗的話呼叫的地方要告訴使用者：關掉 App 再打開就不見了。
  static Future<bool> lastWrite = Future.value(true);

  /// 一次寫一個：快速連改兩次模板，後面那次一定最後寫進去。
  static final _writer = FileWriter();

  static void _write(Future<void> Function() op) {
    lastWrite = () async {
      // 沒有文件資料夾（網頁版、測試）：本來就只放在記憶體裡
      if (_dir == null) return true;
      try {
        await op();
        return true;
      } catch (e) {
        debugPrint('[LIBRARY] 存檔失敗: $e');
        return false;
      }
    }();
  }
}
