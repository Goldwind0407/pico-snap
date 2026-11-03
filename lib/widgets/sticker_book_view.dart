import 'package:flutter/material.dart';

import '../models.dart';
import '../services/my_library.dart';
import '../sticker_book.dart';
import '../theme.dart';
import 'frames.dart';
import 'my_sheet_view.dart';

/// The sticker book: the user's own sheets first, then the built-in ones,
/// one page each, swiped sideways (the chips above jump to a page). A
/// built-in page is the sheet itself; tap a sticker and it lifts off the
/// sheet onto the piece. The search box finds the user's stickers by their
/// name or their sheet's.
class StickerBookView extends StatefulWidget {
  /// [scale] keeps big stickers on the sheet bigger on the piece too.
  final void Function(String sticker, double scale) onPick;
  const StickerBookView({super.key, required this.onPick});

  @override
  State<StickerBookView> createState() => _StickerBookViewState();
}

class _StickerBookViewState extends State<StickerBookView> with SingleTickerProviderStateMixin {
  late PageController _pages;
  int _page = 0;
  late final AnimationController _lift;
  /// The sticker lifting off, and the sheet it's on.
  (int, SheetSticker)? _lifting;
  bool _searching = false;
  String _query = '';

  /// The user's own sheets as shown; at least one page (it says how to
  /// make stickers when there are none).
  List<MySheet> get _mine {
    final s = shownSheets;
    return s.isEmpty ? [const MySheet(id: '', name: '📷 我的')] : s;
  }

  @override
  void initState() {
    super.initState();
    // Opens on the first built-in sheet when the user has no stickers yet.
    _page = customStickers.isEmpty ? _mine.length : 0;
    _pages = PageController(initialPage: _page);
    // Made now, not on first use: a lazy one would first be made in dispose().
    _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  }

  @override
  void dispose() {
    _pages.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _go(int page) {
    setState(() => _page = page);
    _pages.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _tap(int sheet, Offset at) {
    final s = stickerBooks[sheet];
    // The smallest sticker under the finger: a little one may sit in a big
    // one's bounding box.
    SheetSticker? hit;
    for (final k in s.stickers) {
      if (!k.rect.contains(at)) continue;
      if (hit == null || k.rect.width * k.rect.height < hit.rect.width * hit.rect.height) hit = k;
    }
    if (hit == null) return;
    final widths = [for (final k in s.stickers) k.rect.width]..sort();
    final scale = (hit.rect.width / widths[widths.length ~/ 2]).clamp(.6, 1.8);
    widget.onPick(hit.asset, scale);
    setState(() => _lifting = (sheet, hit!));
    _lift.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: MyLibrary.changes,
    builder: (context, _, __) {
      final mine = _mine;
      final labels = [for (final s in mine) s.name, for (final b in stickerBooks) b.label];
      return Column(children: [
        SizedBox(height: 46, child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: IconButton(
              tooltip: '搜尋我的貼紙',
              onPressed: () => setState(() {
                _searching = !_searching;
                _query = '';
              }),
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: ink),
            ),
          ),
          Expanded(child: _searching
            ? Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 16, 6),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '貼紙或貼紙紙的名字', isDense: true, filled: true, fillColor: cream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: line)),
                  ),
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(0, 6, 16, 6),
                itemCount: labels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = _page == i;
                  return GestureDetector(
                    onTap: () => _go(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? blush : (i < mine.length ? butter : cream), borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: selected ? blushLine : (i < mine.length ? butterLine : line)),
                      ),
                      child: Text(labels[i], style: TextStyle(fontSize: 13, color: ink, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                    ),
                  );
                },
              )),
        ])),
        Expanded(child: _searching
          ? _results()
          : PageView.builder(
              controller: _pages,
              itemCount: labels.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => i < mine.length ? _mySheet(mine[i]) : _sheet(i - mine.length),
            )),
      ]);
    },
  );

  Widget _mySheet(MySheet sheet) => sheet.stickers.isEmpty && customStickers.isEmpty
    ? const Center(child: Text('還沒有自己的貼紙' '\n' '可以到首頁下方的「素材」把照片做成貼紙', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 1.6, color: muted, fontWeight: FontWeight.w600)))
    : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
        child: MySheetView(sheet: sheet, onTap: (id) => widget.onPick(id, 1)),
      );

  /// The user's stickers whose name, or whose sheet's name, has [_query].
  Widget _results() {
    final q = _query.trim().toLowerCase();
    final hits = <String>[];
    for (final s in shownSheets) {
      final sheetHit = q.isNotEmpty && s.name.toLowerCase().contains(q);
      for (final id in s.stickers) {
        if (sheetHit || (q.isNotEmpty && (stickerNames[id] ?? '').toLowerCase().contains(q))) hits.add(id);
      }
    }
    if (hits.isEmpty) {
      return Center(child: Text(q.isEmpty ? '打字找自己的貼紙' : '找不到「$_query」', style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)));
    }
    return GridView.count(
      crossAxisCount: 5, padding: const EdgeInsets.fromLTRB(12, 2, 12, 16), mainAxisSpacing: 6, crossAxisSpacing: 6,
      children: [
        for (final id in hits)
          GestureDetector(
            onTap: () => widget.onPick(id, 1),
            child: Column(children: [
              Expanded(child: FittedBox(child: StickerVisual(id, size: 96))),
              if (stickerNames[id] case final name?)
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w700)),
            ]),
          ),
      ],
    );
  }

  Widget _sheet(int index) {
    final s = stickerBooks[index];
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth - 24, h = w / s.aspect;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
        child: GestureDetector(
          onTapUp: (d) => _tap(index, Offset(d.localPosition.dx / w, d.localPosition.dy / h)),
          child: Container(
            width: w, height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: ink.withValues(alpha: .18), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: Image.asset(s.sheet, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
              if (_lifting case (final sheet, final k) when sheet == index)
                // Lifting off the sheet: rises, grows and fades as it lands
                // on the piece.
                AnimatedBuilder(
                  animation: _lift,
                  builder: (context, child) {
                    final t = Curves.easeOut.transform(_lift.value);
                    if (_lift.isCompleted) return const SizedBox.shrink();
                    return Positioned(
                      left: k.rect.left * w, top: k.rect.top * h - 14 * t, width: k.rect.width * w, height: k.rect.height * h,
                      child: Opacity(opacity: 1 - t, child: Transform.scale(scale: 1 + .35 * t, child: child)),
                    );
                  },
                  child: Image.asset(k.asset, fit: BoxFit.contain),
                ),
            ]),
          ),
        ),
      );
    });
  }
}
