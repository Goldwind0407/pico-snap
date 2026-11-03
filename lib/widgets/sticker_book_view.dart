import 'package:flutter/material.dart';

import '../sticker_book.dart';
import '../theme.dart';

/// The sticker book: one page per sheet, swiped sideways (the chips above
/// jump to a page). Each page is the sheet itself; tap a sticker and it
/// lifts off the sheet onto the piece. [mine] is the first page, the user's
/// own stickers.
class StickerBookView extends StatefulWidget {
  final Widget mine;
  /// [scale] keeps big stickers on the sheet bigger on the piece too.
  final void Function(String sticker, double scale) onPick;
  const StickerBookView({super.key, required this.mine, required this.onPick});

  @override
  State<StickerBookView> createState() => _StickerBookViewState();
}

class _StickerBookViewState extends State<StickerBookView> with SingleTickerProviderStateMixin {
  // Opens on the first sheet; 我的 is one page back.
  final _pages = PageController(initialPage: 1);
  int _page = 1;
  late final AnimationController _lift;
  /// The sticker lifting off, and the sheet it's on.
  (int, SheetSticker)? _lifting;

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => Column(children: [
    SizedBox(height: 46, child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      itemCount: stickerBooks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final selected = _page == i;
        return GestureDetector(
          onTap: () => _go(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? blush : cream, borderRadius: BorderRadius.circular(17),
              border: Border.all(color: selected ? blushLine : line),
            ),
            child: Text(i == 0 ? '📷 我的' : stickerBooks[i - 1].label,
              style: TextStyle(fontSize: 13, color: ink, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          ),
        );
      },
    )),
    Expanded(child: PageView.builder(
      controller: _pages,
      itemCount: stickerBooks.length + 1,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (_, i) => i == 0 ? widget.mine : _sheet(i - 1),
    )),
  ]);

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
