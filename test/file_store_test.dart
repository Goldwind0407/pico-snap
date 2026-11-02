import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pico_snap/services/file_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('file_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('連續快速寫 100 次：檔案一定是最後一次的內容', () async {
    final writer = FileWriter();
    final file = File('${tmp.path}/templates.json');
    await Future.wait([for (var i = 0; i < 100; i++) writer.writeString(file, '{"n":$i}${' ' * (100 - i) * 50}')]);
    expect(file.readAsStringSync().trim(), '{"n":99}');
    expect(File('${file.path}.tmp').existsSync(), isFalse, reason: '暫存檔換上去了');
  });

  test('前面一次寫失敗，不會擋住後面的', () async {
    final writer = FileWriter();
    final file = File('${tmp.path}/a.json');
    final bad = writer.writeString(File('${tmp.path}/missing/dir/a.json'), 'x');
    final good = writer.writeString(file, 'ok');
    await expectLater(bad, throwsA(isA<FileSystemException>()));
    await good;
    expect(file.readAsStringSync(), 'ok');
  });

  test('讀不了的檔案收到旁邊，不會被下次存檔蓋掉', () {
    final file = File('${tmp.path}/diary.json')..writeAsStringSync('{broken');
    keepAside(file);
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.bad').readAsStringSync(), '{broken');
  });
}
