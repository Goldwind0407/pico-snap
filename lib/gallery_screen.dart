import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'editor_screen.dart';
import 'lut_files.dart';
import 'services/app_sounds.dart';
import 'services/editor_drafts.dart';
import 'services/my_works.dart';
import 'services/photo_save_service.dart';
import 'theme.dart';
import 'widgets/studio_chrome.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// '10月28日 星期三'
String dayLabel(DateTime d) => '${d.month}月${d.day}日 星期${_weekdays[d.weekday - 1]}';

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 「作品集」：存到相簿過的作品，新的在前面。
class GalleryScreen extends StatefulWidget {
  /// Shown as the home page's「作品集」tab: no back arrow, room for the tab bar.
  final bool embedded;
  const GalleryScreen({super.key, this.embedded = false});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  /// null = 全部。
  WorkKind? _kind;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: ValueListenableBuilder<int>(
      valueListenable: MyWorks.changes,
      builder: (context, _, __) {
        final kinds = {for (final w in MyWorks.works) w.kind};
        final kind = kinds.contains(_kind) ? _kind : null;
        final shown = [for (final w in MyWorks.works) if (kind == null || w.kind == kind) w];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StudioHeader(title: '作品集', eyebrow: 'YOUR MOMENTS, COLLECTED', subtitle: '把日常裡的小喜歡，留在這裡。',
            onBack: widget.embedded ? null : () => Navigator.pop(context),
            trailing: MyWorks.works.isEmpty ? null : Text('${MyWorks.works.length} 件', style: const TextStyle(fontSize: 13, color: muted))),
          if (kinds.length > 1)
            SizedBox(height: 50, child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              children: [
                for (final k in [null, ...WorkKind.values.where(kinds.contains)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(label: k?.label ?? '全部', selected: kind == k, onTap: () => setState(() => _kind = k)),
                  ),
              ],
            )),
          Expanded(child: shown.isEmpty ? const _Empty() : GridView.builder(
            padding: EdgeInsets.fromLTRB(20, 10, 20, widget.embedded ? 130 : 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .72),
            itemCount: shown.length,
            itemBuilder: (_, i) => WorkTile(work: shown[i], onTap: () => WorkViewer.open(context, shown, i)),
          )),
        ]);
      },
    )),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.fromLTRB(28, 0, 28, 100),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34), decoration: studioSurface(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: paperCard, borderRadius: BorderRadius.circular(24)),
        child: const Icon(CupertinoIcons.photo_on_rectangle, size: 36, color: actionCoral)),
      const SizedBox(height: 22),
      const Text('還沒有作品', style: TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('拍好、做好的作品存到相簿時，\n會自動收一份在這裡 ♡', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, height: 1.7, color: muted, fontWeight: FontWeight.w500)),
    ]),
  )));
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      if (!selected) AppSounds.shared.play(AppSound.select);
      onTap();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? blush : Colors.white, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? blushLine : line),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: ink, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
    ),
  );
}

/// 一件作品的小卡：白底圓角，作品整張放進去。
class WorkTile extends StatelessWidget {
  final Work work;
  final VoidCallback onTap;
  const WorkTile({super.key, required this.work, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: .05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Image(image: ResizeImage(work.image, height: 360, policy: ResizeImagePolicy.fit), fit: BoxFit.contain, gaplessPlayback: true),
    ),
  );
}

/// 全螢幕看作品：左右滑換一件，可以分享、再編輯、看影片、再存一次到相簿或從作品集刪掉。
class WorkViewer extends StatefulWidget {
  final List<Work> works;
  final int initial;
  const WorkViewer({super.key, required this.works, required this.initial});

  static Future<void> open(BuildContext context, List<Work> works, int index) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => WorkViewer(works: List.of(works), initial: index),
  ));

  @override
  State<WorkViewer> createState() => _WorkViewerState();
}

class _WorkViewerState extends State<WorkViewer> {
  late final List<Work> _works = widget.works;
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Work get _work => _works[_index];

  Future<void> _saveAgain() async {
    if (_busy) return;
    setState(() => _busy = true);
    final work = _work;
    String? error;
    try {
      error = await PhotoSaveService.saveBytes(await work.exportBytes());
    } catch (e) {
      error = '讀不到這件作品，請再試一次';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(context, error ?? (work.hasOriginal ? '原尺寸作品已存到相簿 ♡' : '預覽版本已存到相簿 ♡'), error: error != null);
  }

  Future<void> _share() async {
    AppSounds.shared.play(AppSound.whoosh);
    setState(() => _busy = true);
    final work = _work;
    try {
      final dir = await getTemporaryDirectory();
      final f = await File('${dir.path}/pico_snap_${work.id}.png').writeAsBytes(await work.exportBytes(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')]));
    } catch (e) {
      debugPrint('[WORKS] share: $e');
      if (mounted) showMessage(context, '分享不了，請再試一次', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Opens the piece in the editor again; saving makes a new work.
  Future<void> _edit() async {
    final work = _work;
    try {
      await LutFiles.load();
      final piece = await EditorDrafts.readFrom(work.piece!);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(mode: piece.mode, draft: piece, saved: true)));
    } catch (e) {
      debugPrint('[WORKS] edit: $e');
      if (mounted) showMessage(context, '打不開這件作品', error: true);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, '從作品集刪掉？', '只會從 App 裡拿掉，手機相簿裡的那張不受影響。')) return;
    final work = _work;
    await MyWorks.remove(work.id);
    if (!mounted) return;
    if (_works.length == 1) return Navigator.pop(context);
    setState(() {
      _works.removeAt(_index);
      _index = _index.clamp(0, _works.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.back, color: ink, size: 26)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_work.kind.label, style: const TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900)),
            Text('${_work.created.year}年${dayLabel(_work.created)} ${_time(_work.created)}',
              style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700)),
          ])),
          Text('${_index + 1} / ${_works.length}', style: const TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w700)),
        ]),
      ),
      Expanded(child: PageView.builder(
        controller: _pages,
        itemCount: _works.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Center(child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 8))]),
              child: Image(image: _works[i].image, fit: BoxFit.contain, gaplessPlayback: true),
            )),
          ),
        ),
      )),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(children: [
          _Action(CupertinoIcons.share, '分享', _busy ? null : _share, main: true),
          if (_work.piece != null) _Action(CupertinoIcons.pencil, '再編輯', _edit),
          if (_work.video != null) _Action(CupertinoIcons.play_circle, '看影片', () => VideoViewer.open(context, _work.video!)),
          // Older works kept only the preview (1400px).
          _Action(CupertinoIcons.arrow_down_to_line, _busy ? '儲存中…' : _work.hasOriginal ? '存到相簿' : '存預覽版', _busy ? null : _saveAgain),
          _Action(CupertinoIcons.trash, '刪除', _delete, danger: true),
        ]),
      ),
    ])),
  );
}

/// One of the viewer's actions: an icon with its name under it.
class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool main, danger;
  const _Action(this.icon, this.label, this.onTap, {this.main = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? muted : danger ? const Color(0xFFB4483C) : main ? Colors.white : ink;
    return Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: main ? coral : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: main ? BorderSide.none : const BorderSide(color: line, width: 1.3)),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    ));
  }
}

/// A work's live video, playing over and over; tap to pause.
class VideoViewer extends StatefulWidget {
  final File file;
  const VideoViewer({super.key, required this.file});

  static Future<void> open(BuildContext context, File file) => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoViewer(file: file)));

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  late final _video = VideoPlayerController.file(widget.file);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video.setLooping(true);
    _video.initialize().then((_) {
      if (mounted) setState(() {});
      _video.play();
    }, onError: (Object e) {
      debugPrint('[WORKS] video: $e');
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    AppSounds.shared.play(AppSound.whoosh);
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(widget.file.path, mimeType: 'video/mp4')]));
    } catch (e) {
      if (mounted) showMessage(context, '分享不了，請再試一次', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.back, color: ink, size: 26)),
          const Expanded(child: Text('影片', style: TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900))),
          IconButton(tooltip: '分享', onPressed: _share, icon: const Icon(CupertinoIcons.share, color: ink)),
        ]),
      ),
      Expanded(child: Center(child: _failed
          ? const Text('這段影片播不了', style: TextStyle(color: muted, fontWeight: FontWeight.w700))
          : !_video.value.isInitialized
              ? const CircularProgressIndicator(color: coral)
              : GestureDetector(
                  onTap: () {
                    _video.value.isPlaying ? _video.pause() : _video.play();
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AspectRatio(aspectRatio: _video.value.aspectRatio, child: Stack(fit: StackFit.expand, children: [
                      VideoPlayer(_video),
                      if (!_video.value.isPlaying) const Center(child: Icon(CupertinoIcons.play_circle_fill, size: 64, color: Colors.white)),
                    ])),
                  ),
                ))),
    ])),
  );
}
