import 'package:flutter/material.dart';

import 'services/my_works.dart';
import 'services/photo_save_service.dart';
import 'theme.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// '10月28日 星期三'
String dayLabel(DateTime d) => '${d.month}月${d.day}日 星期${_weekdays[d.weekday - 1]}';

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 「作品集」：存到相簿過的作品，新的在前面。
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
              const Expanded(child: Text('作品集', style: TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
              if (MyWorks.works.isNotEmpty)
                Text('${MyWorks.works.length} 件', style: const TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w700)),
            ]),
          ),
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
  Widget build(BuildContext context) => const Center(child: Padding(
    padding: EdgeInsets.fromLTRB(40, 0, 40, 80),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.photo_library_outlined, size: 54, color: blushLine),
      SizedBox(height: 14),
      Text('還沒有作品', style: TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w900)),
      SizedBox(height: 6),
      Text('拍好、做好的作品存到相簿時，\n會自動收一份在這裡 ♡', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, height: 1.5, color: muted, fontWeight: FontWeight.w600)),
    ]),
  ));
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
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

/// 全螢幕看作品：左右滑換一件，可以再存一次到相簿或從作品集刪掉。
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
      error = await PhotoSaveService.saveBytes(work.bytes ?? await work.file!.readAsBytes());
    } catch (e) {
      error = '讀不到這件作品，請再試一次';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(context, error ?? '已存到相簿 ♡', error: error != null);
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
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('刪除', style: TextStyle(fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB4483C), backgroundColor: Colors.white,
              side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: FilledButton.icon(
            onPressed: _busy ? null : _saveAgain,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_busy ? '儲存中…' : '再存一次到相簿', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )),
        ]),
      ),
    ])),
  );
}
