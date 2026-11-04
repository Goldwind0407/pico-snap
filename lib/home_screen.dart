import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'booth_screen.dart';
import 'diary_screen.dart';
import 'editor_screen.dart';
import 'services/editor_drafts.dart';
import 'lut_files.dart';
import 'gallery_screen.dart';
import 'library_screen.dart';
import 'polaroid_camera_screen.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets/frames.dart';

/// Whether the drafts list on the home screen is open.
final _draftsOpen = ValueNotifier(false);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 0 = 首頁, 1 = 素材, 2 = 日記, 3 = 作品集.
  int _tab = 0;

  void _open(BuildContext context, EditorMode mode, [int template = 0]) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => mode == EditorMode.fourCut ? BoothScreen(template: template) : EditorScreen(mode: mode, template: template)),
  );

  void _camera(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const PolaroidCameraScreen()));

  /// The camera button and 開始製作 both ask which way to play, the same
  /// four as the cards.
  Future<void> _choose(BuildContext context) async {
    final pick = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('選一種玩法', style: TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          for (final (i, icon, color, label, note) in const [
            (0, CupertinoIcons.square_split_1x2, blush, '四格拍貼', '像拍貼機，倒數連拍 4 張'),
            (1, CupertinoIcons.camera, lilac, '拍立得', '拍一張，看它慢慢顯影'),
            (2, CupertinoIcons.square_grid_2x2, sky, '拍立得拼貼', '從相簿選照片，排成一頁'),
            (3, CupertinoIcons.smiley, butter, '貼紙裝飾', '一張照片，貼滿貼紙'),
          ]) Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: line)),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                onTap: () => Navigator.pop(context, i),
                child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: ink, size: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(note, style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700)),
                  ])),
                  const Icon(CupertinoIcons.chevron_right, size: 18, color: muted),
                ])),
              ),
            ),
          ),
        ]),
      )),
    );
    if (!context.mounted) return;
    switch (pick) {
      case 0: _open(context, EditorMode.fourCut);
      case 1: _camera(context);
      case 2: _open(context, EditorMode.polaroid);
      case 3: _open(context, EditorMode.sticker);
    }
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  @override
  Widget build(BuildContext context) => PopScope(
    // Back on the other tabs goes to 首頁 first.
    canPop: _tab == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _tab = 0);
    },
    child: Scaffold(
      backgroundColor: cream,
      extendBody: true,
      body: IndexedStack(index: _tab, children: [
        _home(context), const LibraryScreen(embedded: true), const DiaryScreen(), const GalleryScreen(embedded: true),
      ]),
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        onCamera: () => _choose(context),
        onTab: (t) => setState(() => _tab = t),
      ),
    ),
  );

  Widget _home(BuildContext context) => SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(0, 10, 0, 120), children: [
      _pad(const _Header()),
      ValueListenableBuilder<int>(valueListenable: EditorDrafts.changes, builder: (context, _, child) {
        if (EditorDrafts.entries.isEmpty) return const SizedBox.shrink();
        // A rounded card like the others, without the tile's divider lines.
        return _pad(Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)),
          child: ExpansionTile(title: Text('繼續編輯草稿（${EditorDrafts.entries.length}）', style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800)),
          leading: const Icon(CupertinoIcons.square_pencil, color: coral),
          shape: const Border(), collapsedShape: const Border(),
          // iOS chevron that turns down when open, in place of Material's arrow.
          onExpansionChanged: (open) => _draftsOpen.value = open,
          trailing: ValueListenableBuilder<bool>(valueListenable: _draftsOpen, builder: (_, open, __) => AnimatedRotation(
            turns: open ? .25 : 0, duration: const Duration(milliseconds: 200),
            child: const Icon(CupertinoIcons.chevron_right, size: 18, color: muted),
          )),
          children: [
          for (final draft in List.of(EditorDrafts.entries)) ListTile(
            leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Container(
              width: 40, height: 50, color: cream,
              child: draft.thumb == null
                  ? const Icon(CupertinoIcons.photo, size: 18, color: muted)
                  : Image.file(draft.thumb!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.photo, size: 18, color: muted)),
            )),
            title: Text(draft.label), subtitle: Text('${draft.updated.month}/${draft.updated.day} ${draft.updated.hour.toString().padLeft(2, '0')}:${draft.updated.minute.toString().padLeft(2, '0')}'),
            onTap: () async {
              try {
                await LutFiles.load();
                final document = await EditorDrafts.read(draft.id);
                if (!context.mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(mode: document.mode, draft: document, draftId: draft.id)));
              } catch (_) {
                EditorDrafts.release(draft.id);
                if (context.mounted) showMessage(context, '無法讀取這份草稿');
              }
            },
            trailing: IconButton(tooltip: '刪除草稿', icon: const Icon(CupertinoIcons.trash), onPressed: () async {
              if (await confirmDelete(context, '刪除這份草稿？', '刪掉之後就不能再接著編輯了。')) {
                try { await EditorDrafts.remove(draft.id); } catch (_) {
                  if (context.mounted) showMessage(context, '草稿刪除失敗');
                }
              }
            }),
          ),
        ])));
      }),
      const SizedBox(height: 22),
      _pad(_HeroCard(onStart: () => _choose(context))),
      const SizedBox(height: 30),
      _pad(const _SectionTitle(title: '選一種玩法', note: 'Create')),
      const SizedBox(height: 14),
      // Two by two (four in a row on a wide screen); each row's cards share
      // a height and grow with large text.
      Builder(builder: (context) {
        final cards = [
          _ModeCard(
            label: '四格拍貼', sub: 'Four Cuts', color: blush, border: blushLine,
            art: const _FourCutsArt(), onTap: () => _open(context, EditorMode.fourCut),
          ),
          _ModeCard(
            label: '拍立得', sub: 'Polaroid', color: lilac, border: lilacLine,
            art: const _PolaroidArt(), onTap: () => _camera(context),
          ),
          _ModeCard(
            label: '拍立得拼貼', sub: 'Collage', color: sky, border: const Color(0xFF9DC0D6),
            art: const _CollageArt(), onTap: () => _open(context, EditorMode.polaroid),
          ),
          _ModeCard(
            label: '貼紙裝飾', sub: 'Sticker', color: butter, border: butterLine,
            art: const _StickerArt(), onTap: () => _open(context, EditorMode.sticker),
          ),
        ];
        Widget row(List<Widget> cards) => _pad(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: c)],
        ])));
        if (MediaQuery.sizeOf(context).width >= 700) return row(cards);
        return Column(children: [row(cards.sublist(0, 2)), const SizedBox(height: 12), row(cards.sublist(2))]);
      }),
      const SizedBox(height: 30),
      _pad(const _SectionTitle(title: '今日風格', note: "Today's styles")),
      const SizedBox(height: 14),
      SizedBox(height: 210, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stripTemplates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _StyleCard(index: i, onTap: () => _open(context, EditorMode.fourCut, i)),
      )),
    ]));
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 44, child: Center(child: Text.rich(
    TextSpan(children: [
      TextSpan(text: '快趣', style: TextStyle(color: coral)),
      TextSpan(text: '拍', style: TextStyle(color: ink)),
    ]),
    style: TextStyle(fontSize: 26, letterSpacing: 3, fontWeight: FontWeight.w900),
  )));
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onStart;
  const _HeroCard({required this.onStart});

  @override
  Widget build(BuildContext context) => Container(
    height: 236,
    decoration: BoxDecoration(
      color: paperCard, borderRadius: BorderRadius.circular(26),
      border: Border.all(color: line),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .06), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final textLeft = w * .47;
      return Stack(clipBehavior: Clip.none, children: [
        const Positioned(left: -18, top: -6, child: WashiTape(width: 80, height: 22, angle: -.5)),
        const Positioned(right: -20, top: -4, child: WashiTape(width: 84, height: 22, angle: .55, colors: [Color(0xFFB9C9AE), Color(0xFFF4D98B)])),
        Positioned(left: 74, top: 46, child: Transform.rotate(angle: .12, child: const SizedBox(width: 82, child: FittedBox(child: PolaroidCard(
          image: sampleDuo, caption: '', color: blush,
        ))))),
        Positioned(left: 22, top: 22, child: Transform.rotate(angle: -.18, child: SizedBox(
          width: 62, height: 192,
          child: FittedBox(child: PhotoStrip(
            template: drawnTemplates.firstWhere((t) => t.name == 'Coral'), photos: samplePhotos,
            captionWidget: const Icon(CupertinoIcons.camera, color: Colors.white, size: 30),
          )),
        ))),
        const Positioned(left: 50, top: 20, child: Sparkle(size: 15)),
        const Positioned(left: 98, top: 30, child: DoodleHeart(size: 15)),
        const Positioned(left: 30, bottom: 18, child: Sparkle(size: 20)),
        const Positioned(left: 136, bottom: 30, child: Sparkle(size: 17, fill: Color(0xFFF7D77C))),
        const Positioned(left: 150, bottom: 52, child: DoodleHeart(size: 12)),
        Positioned(right: 24, top: 30, child: Transform.rotate(angle: .1, child: Text('make today a ↘', style: hand(17)))),
        Positioned(left: textLeft, right: 18, top: 72, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Make today a\nlittle more lovely.', style: TextStyle(fontSize: 19, height: 1.25, color: ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 44, child: FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: coral, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('開始製作', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ])),
      ]);
    }),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title, note;
  const _SectionTitle({required this.title, required this.note});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
    Text(title, style: const TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w800)),
    const SizedBox(width: 8),
    Flexible(child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700))),
  ]);
}

class _ModeCard extends StatelessWidget {
  final String label, sub;
  final Color color, border;
  final Widget art;
  final VoidCallback onTap;
  const _ModeCard({required this.label, required this.sub, required this.color, required this.border, required this.art, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18), border: Border.all(color: border, width: 1.6)),
      // The drawing keeps its size; with large text the card grows instead.
      child: Column(children: [
        SizedBox(height: 78, child: Center(child: FittedBox(child: art))),
        const Spacer(),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800)),
        Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _FourCutsArt extends StatelessWidget {
  const _FourCutsArt();

  Widget _frame(List<ImageProvider> photos, double angle) => Transform.rotate(angle: angle, child: Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: outline, width: 1.2)),
    child: Column(children: [
      for (final p in photos) Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: SizedBox(width: 30, height: 23, child: PhotoSlot(image: p, color: blush, outlineWidth: 1, radius: 1)),
      ),
    ]),
  ));

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text('Four Cuts', style: hand(14)),
    Row(mainAxisSize: MainAxisSize.min, children: [
      _frame(samplePhotos.sublist(0, 2), -.05),
      const SizedBox(width: 2),
      _frame(samplePhotos.sublist(2, 4), .05),
    ]),
  ]);
}

class _PolaroidArt extends StatelessWidget {
  const _PolaroidArt();

  @override
  Widget build(BuildContext context) => SizedBox(width: 76, height: 70, child: Stack(clipBehavior: Clip.none, children: [
    Positioned(left: 10, top: 6, child: Transform.rotate(angle: .14, child: const SizedBox(width: 54, child: FittedBox(child: PolaroidCard(caption: '', color: Colors.white))))),
    Positioned(left: 6, top: 0, child: Transform.rotate(angle: -.08, child: SizedBox(width: 56, child: FittedBox(child: PolaroidCard(image: samplePhotos[1], caption: '', color: blush))))),
    const Positioned(right: -6, top: 4, child: Sparkle(size: 11)),
    const Positioned(left: -6, bottom: 8, child: Sparkle(size: 9)),
  ]));
}

/// Prints laid out in a zigzag with tape, like the collage.
class _CollageArt extends StatelessWidget {
  const _CollageArt();

  Widget _print(int photo, double angle) => Transform.rotate(angle: angle, child: SizedBox(
    width: 40, child: FittedBox(child: PolaroidCard(image: samplePhotos[photo], caption: '', color: Colors.white)),
  ));

  @override
  Widget build(BuildContext context) => SizedBox(width: 108, height: 74, child: Stack(clipBehavior: Clip.none, children: [
    Positioned(left: 0, top: 2, child: _print(0, -.12)),
    Positioned(left: 34, top: 12, child: _print(2, .08)),
    Positioned(left: 68, top: 0, child: _print(3, -.06)),
    const Positioned(left: 44, top: 6, child: WashiTape(width: 22, height: 8, angle: .1)),
    const Positioned(right: -4, bottom: 2, child: Sparkle(size: 10)),
  ]));
}

class _StickerArt extends StatelessWidget {
  const _StickerArt();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 76, height: 70, child: Stack(clipBehavior: Clip.none, children: [
    Center(child: EmojiSticker('😉', size: 44)),
    Positioned(left: 0, top: 2, child: Sparkle(size: 14)),
    Positioned(right: 2, top: 0, child: DoodleHeart(size: 14)),
    Positioned(right: 4, bottom: 4, child: Sparkle(size: 11)),
  ]));
}

class _StyleCard extends StatelessWidget {
  final int index;
  final VoidCallback onTap;
  const _StyleCard({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = stripTemplates[index];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Color.lerp(t.frame, Colors.white, .55), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 22, top: 16, bottom: 34, child: Transform.rotate(angle: index.isEven ? -.06 : .05, child: FittedBox(
            child: PhotoStrip(template: t, photos: samplePhotos),
          ))),
          Positioned(left: 14, top: 8, child: WashiTape(width: 46, height: 16, angle: -.5, colors: index.isEven
            ? const [Color(0xFFF59E95), Color(0xFFFFD9D4)]
            : const [Color(0xFFB9C9AE), Color(0xFFF4D98B)])),
          if (index.isOdd) const Positioned(right: 16, top: 30, child: Sparkle(size: 14, fill: Color(0xFFF7D77C))),
          if (index.isOdd) const Positioned(right: 26, top: 56, child: DoodleHeart(size: 11)),
          Positioned(left: 0, right: 0, bottom: 6, child: Text(t.name, textAlign: TextAlign.center, style: hand(20))),
        ]),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int tab;
  final VoidCallback onCamera;
  final ValueChanged<int> onTab;
  const _BottomBar({required this.tab, required this.onCamera, required this.onTab});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 98 + MediaQuery.paddingOf(context).bottom,
    child: Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 0, right: 0, bottom: 0, top: 20, child: Container(
        decoration: BoxDecoration(
          color: cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .08), blurRadius: 18, offset: const Offset(0, -4))],
        ),
        child: SafeArea(top: false, child: Row(children: [
          Expanded(child: _NavItem(icon: tab == 0 ? CupertinoIcons.house_fill : CupertinoIcons.house, label: '首頁', selected: tab == 0, onTap: () => onTab(0))),
          Expanded(child: _NavItem(icon: tab == 3 ? CupertinoIcons.photo_fill_on_rectangle_fill : CupertinoIcons.photo_on_rectangle, label: '作品集', selected: tab == 3, onTap: () => onTab(3))),
          const SizedBox(width: 72),
          Expanded(child: _NavItem(icon: tab == 2 ? CupertinoIcons.book_fill : CupertinoIcons.book, label: '日記', selected: tab == 2, onTap: () => onTab(2))),
          Expanded(child: _NavItem(icon: tab == 1 ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark, label: '素材', selected: tab == 1, onTap: () => onTab(1))),
        ])),
      )),
      Positioned(top: 0, left: 0, right: 0, child: Center(child: GestureDetector(
        onTap: onCamera,
        child: Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: coral, shape: BoxShape.circle,
            border: Border.all(color: cream, width: 4),
            boxShadow: [BoxShadow(color: coral.withValues(alpha: .4), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 28),
        ),
      ))),
    ]),
  );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _NavItem({required this.icon, required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 26, color: selected ? ink : muted),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );
}
