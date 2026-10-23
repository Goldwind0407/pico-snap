import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'library_screen.dart';
import 'polaroid_camera_screen.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets/frames.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, EditorMode mode, [int template = 0]) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => EditorScreen(mode: mode, template: template)),
  );

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    extendBody: true,
    body: SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(0, 10, 0, 120), children: [
      _pad(_Header(onGallery: () => showSoonToast(context, '作品集'))),
      const SizedBox(height: 22),
      _pad(_HeroCard(onStart: () => _open(context, EditorMode.fourCut))),
      const SizedBox(height: 30),
      _pad(const _SectionTitle(title: 'Create', note: '選一種玩法')),
      const SizedBox(height: 14),
      _pad(Row(children: [
        Expanded(child: _ModeCard(
          label: 'Four Cuts', sub: '四格拍貼', color: blush, border: blushLine,
          art: const _FourCutsArt(), onTap: () => _open(context, EditorMode.fourCut),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ModeCard(
          label: 'Polaroid', sub: '拍立得', color: lilac, border: lilacLine,
          art: const _PolaroidArt(), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PolaroidCameraScreen())),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ModeCard(
          label: 'Sticker', sub: '貼紙裝飾', color: butter, border: butterLine,
          art: const _StickerArt(), onTap: () => _open(context, EditorMode.sticker),
        )),
      ])),
      const SizedBox(height: 30),
      _pad(const _SectionTitle(title: "Today's styles", note: '今日風格')),
      const SizedBox(height: 14),
      SizedBox(height: 210, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stripTemplates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _StyleCard(index: i, onTap: () => _open(context, EditorMode.fourCut, i)),
      )),
    ])),
    bottomNavigationBar: _BottomBar(
      onCamera: () => _open(context, EditorMode.fourCut),
      onSoon: (label) => showSoonToast(context, label),
      onMine: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())),
    ),
  );
}

class _Header extends StatelessWidget {
  final VoidCallback onGallery;
  const _Header({required this.onGallery});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
      alignment: Alignment.center,
      child: const Text('PICO\nSNAP', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9, height: 1.05, color: coral, fontWeight: FontWeight.w900)),
    ),
    const Expanded(child: Text.rich(
      TextSpan(children: [
        TextSpan(text: 'PICO ', style: TextStyle(color: coral)),
        TextSpan(text: 'SNAP', style: TextStyle(color: ink)),
      ]),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 26, letterSpacing: .5, fontWeight: FontWeight.w900),
    )),
    IconButton(onPressed: onGallery, icon: const Icon(Icons.photo_outlined, size: 30, color: ink)),
  ]);
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
            template: stripTemplates.firstWhere((t) => t.name == 'Coral'), photos: samplePhotos,
            captionWidget: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 30),
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
      height: 140,
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18), border: Border.all(color: border, width: 1.6)),
      child: Column(children: [
        Expanded(child: Center(child: FittedBox(child: art))),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800)),
        Text(sub, style: const TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w700)),
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
    // Every other card shows sample photos so the row feels alive.
    final photos = index.isEven ? samplePhotos : const <ImageProvider>[];
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
            child: PhotoStrip(template: t, photos: photos),
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
  final VoidCallback onCamera;
  final ValueChanged<String> onSoon;
  final VoidCallback onMine;
  const _BottomBar({required this.onCamera, required this.onSoon, required this.onMine});

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
          const Expanded(child: _NavItem(icon: Icons.home_rounded, label: '首頁', selected: true)),
          Expanded(child: _NavItem(icon: Icons.menu_book_outlined, label: '日記', onTap: () => onSoon('日記'))),
          const SizedBox(width: 72),
          Expanded(child: _NavItem(icon: Icons.shopping_bag_outlined, label: '商店', onTap: () => onSoon('商店'))),
          Expanded(child: _NavItem(icon: Icons.person_outline_rounded, label: '我的', onTap: onMine)),
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
          child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 28),
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
