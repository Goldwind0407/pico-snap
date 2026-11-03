import 'dart:io';

/// Writes to the App's own files one at a time, each one whole or not at
/// all: written to a temporary file next to it and then renamed over it, so
/// a crash halfway leaves the old file, never half a file.
class FileWriter {
  Future<void> _queue = Future.value();

  /// Runs [op] after every write queued before it has finished.
  Future<T> run<T>(Future<T> Function() op) {
    final done = _queue.then((_) => op());
    _queue = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<void> writeString(File file, String text) => run(() => _replace(file, (tmp) => tmp.writeAsString(text, flush: true)));

  Future<void> writeBytes(File file, List<int> bytes) => run(() => _replace(file, (tmp) => tmp.writeAsBytes(bytes, flush: true)));

  static Future<void> _replace(File file, Future<void> Function(File tmp) write) async {
    final tmp = File('${file.path}.tmp');
    await write(tmp);
    // Windows briefly refuses to replace a file another program (antivirus,
    // indexer) has just looked at; try again a moment later.
    for (var attempt = 0;; attempt++) {
      try {
        await tmp.rename(file.path);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
      }
    }
  }
}

/// A file that wouldn't load is kept aside (name.bad) instead of being
/// overwritten with what's left in memory at the next save.
void keepAside(File file) {
  try {
    file.renameSync('${file.path}.bad');
  } catch (_) {}
}
