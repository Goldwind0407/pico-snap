import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const ink = Color(0xFF342B2A), muted = Color(0xFF8D7C78), cream = Color(0xFFFFF9F0);
const coral = Color(0xFFF27E72), pink = Color(0xFFF7D7D0), lilac = Color(0xFFE8DFF4);
const butter = Color(0xFFF8E7A8), mint = Color(0xFFDDEBE0);

void main() => runApp(const PicoSnapApp());

class PicoSnapApp extends StatelessWidget {
  const PicoSnapApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PICO SNAP', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: coral), fontFamily: 'Arial'),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  void open(BuildContext context, String mode) => Navigator.push(context,
    MaterialPageRoute(builder: (_) => EditorScreen(initialMode: mode)));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: CustomScrollView(slivers: [
      SliverPadding(padding: const EdgeInsets.fromLTRB(23, 18, 23, 12),
        sliver: SliverToBoxAdapter(child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: coral, borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 25)),
          const SizedBox(width: 11),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PICO SNAP', style: TextStyle(fontSize: 18, letterSpacing: 2.2, fontWeight: FontWeight.w900, color: ink)),
            Text('little moments, lovely memories', style: TextStyle(fontSize: 10, color: muted)),
          ]),
          const Spacer(),
          IconButton(onPressed: () => _toast(context, '作品集'), icon: const Icon(Icons.photo_library_outlined, color: ink),
            style: IconButton.styleFrom(backgroundColor: Colors.white, fixedSize: const Size(44, 44))),
        ]))),
      SliverPadding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
        sliver: SliverToBoxAdapter(child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE5D9), Color(0xFFFFF0D9)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(30)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(.75), borderRadius: BorderRadius.circular(30)),
              child: const Text('YOUR POCKET PHOTO BOOTH', style: TextStyle(fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: ink))),
            const SizedBox(height: 15),
            const Text('Make today\na little more lovely.', style: TextStyle(fontSize: 30, height: 1.12, fontWeight: FontWeight.w900, color: ink, letterSpacing: -.8)),
            const SizedBox(height: 9),
            const Text('拍下日常，做成值得收藏的小作品。', style: TextStyle(fontSize: 12, color: Color(0xFF806B65))),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => open(context, 'Four Cut'), icon: const Icon(Icons.auto_awesome_rounded, size: 18), label: const Text('開始拍貼'),
                style: FilledButton.styleFrom(backgroundColor: coral, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
              const SizedBox(width: 10),
              Container(width: 51, height: 51, decoration: BoxDecoration(color: Colors.white.withOpacity(.8), borderRadius: BorderRadius.circular(16)),
                child: IconButton(onPressed: () => open(context, 'Polaroid'), icon: const Icon(Icons.camera_alt_outlined, color: ink))),
            ]),
            const SizedBox(height: 17),
            const _HeroPrints(),
          ]),
        ))),
      SliverPadding(padding: const EdgeInsets.fromLTRB(24, 27, 24, 12),
        sliver: SliverToBoxAdapter(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: const [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MAKE SOMETHING CUTE', style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: muted, fontWeight: FontWeight.w800)),
            SizedBox(height: 5), Text('今天想做什麼？', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: ink)),
          ])),
          Text('3 MODES', style: TextStyle(fontSize: 9, letterSpacing: 1.1, color: muted, fontWeight: FontWeight.w700)),
        ]))),
      SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 22),
        sliver: SliverToBoxAdapter(child: Row(children: [
          Expanded(child: _ModeCard(title: '四格拍貼', subtitle: 'FOUR CUTS', color: pink, icon: Icons.grid_view_rounded, onTap: () => open(context, 'Four Cut'))),
          const SizedBox(width: 10),
          Expanded(child: _ModeCard(title: '拍立得', subtitle: 'POLAROID', color: butter, icon: Icons.photo_size_select_actual_outlined, onTap: () => open(context, 'Polaroid'))),
          const SizedBox(width: 10),
          Expanded(child: _ModeCard(title: '去背貼紙', subtitle: 'CUT-OUT', color: mint, icon: Icons.auto_fix_high_rounded, onTap: () => open(context, 'Sticker'))),
        ]))),
      SliverPadding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 10),
        sliver: SliverToBoxAdapter(child: Row(children: const [
          Expanded(child: Text('挑一個今日風格', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink))),
          Text('VIEW ALL  →', style: TextStyle(fontSize: 9, letterSpacing: 1, color: muted, fontWeight: FontWeight.w800)),
        ]))),
      SliverPadding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        sliver: SliverToBoxAdapter(child: SizedBox(height: 145, child: ListView(scrollDirection: Axis.horizontal, children: const [
          _StyleCard(title: 'Soft Film', tag: '01 / WARM', color: Color(0xFFF4D9C5), accent: coral),
          SizedBox(width: 12), _StyleCard(title: 'Sunday Club', tag: '02 / PLAYFUL', color: Color(0xFFE2DDF3), accent: Color(0xFF8F7CC0)),
          SizedBox(width: 12), _StyleCard(title: 'Little Garden', tag: '03 / FRESH', color: Color(0xFFDCE9D9), accent: Color(0xFF6D9976)),
        ])))),
    ])),
    bottomNavigationBar: Container(decoration: const BoxDecoration(color: cream, border: Border(top: BorderSide(color: Color(0xFFF0E7DD)))),
      child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(28, 10, 28, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          _NavItem(icon: Icons.home_rounded, label: '首頁', selected: true), _NavItem(icon: Icons.auto_awesome_mosaic_outlined, label: '模板'),
          _NavItem(icon: Icons.photo_library_outlined, label: '作品'), _NavItem(icon: Icons.person_outline_rounded, label: '我的'),
        ])))),
  );
}

class _HeroPrints extends StatelessWidget {
  const _HeroPrints();
  @override
  Widget build(BuildContext context) => SizedBox(height: 105, child: Stack(clipBehavior: Clip.none, children: [
    Positioned(left: 4, top: 7, child: Transform.rotate(angle: -.12, child: const _MiniPrint(color: lilac, icon: Icons.star_rounded, label: 'good day'))),
    Positioned(left: 83, top: 0, child: Transform.rotate(angle: .04, child: const _MiniPrint(color: Colors.white, icon: Icons.favorite_rounded, label: 'little joy'))),
    Positioned(left: 163, top: 8, child: Transform.rotate(angle: .12, child: const _MiniPrint(color: butter, icon: Icons.sunny, label: 'sunny!'))),
    const Positioned(right: 3, top: 8, child: Icon(Icons.auto_awesome, size: 27, color: Color(0xFFDE987C))),
  ]));
}

class _MiniPrint extends StatelessWidget {
  final Color color; final IconData icon; final String label;
  const _MiniPrint({required this.color, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(width: 75, height: 99, padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: ink.withOpacity(.10), blurRadius: 9, offset: const Offset(0, 4))]),
    child: Column(children: [Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)), child: Icon(icon, color: coral, size: 27))),
      const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 8, color: ink, fontWeight: FontWeight.w700))]));
}

class _ModeCard extends StatelessWidget {
  final String title, subtitle; final Color color; final IconData icon; final VoidCallback onTap;
  const _ModeCard({required this.title, required this.subtitle, required this.color, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(21),
    child: Container(padding: const EdgeInsets.fromLTRB(10, 13, 10, 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(21), border: Border.all(color: const Color(0xFFF1E7DF))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 39, height: 39, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: ink, size: 20)),
        const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: ink)),
        const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 8, letterSpacing: .8, color: muted, fontWeight: FontWeight.w700)),
      ])));
}

class _StyleCard extends StatelessWidget {
  final String title, tag; final Color color, accent;
  const _StyleCard({required this.title, required this.tag, required this.color, required this.accent});
  @override
  Widget build(BuildContext context) => Container(width: 210, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(23)),
    child: Stack(children: [
      Positioned(right: 5, top: 4, child: Transform.rotate(angle: .12, child: Container(width: 65, height: 86,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: ink.withOpacity(.12), blurRadius: 8)]),
        padding: const EdgeInsets.all(5), child: Container(decoration: BoxDecoration(color: accent.withOpacity(.22), borderRadius: BorderRadius.circular(2)), child: Icon(Icons.favorite_rounded, color: accent, size: 25))))),
      Positioned(left: 0, bottom: 0, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tag, style: TextStyle(fontSize: 8, letterSpacing: 1.2, color: ink.withOpacity(.65), fontWeight: FontWeight.w800)),
        const SizedBox(height: 4), Text(title, style: const TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900)),
      ])),
    ]));
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label; final bool selected;
  const _NavItem({required this.icon, required this.label, this.selected = false});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 21, color: selected ? coral : muted), const SizedBox(height: 4),
    Text(label, style: TextStyle(fontSize: 10, color: selected ? coral : muted, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
  ]);
}

class EditorScreen extends StatefulWidget {
  final String initialMode;
  const EditorScreen({super.key, this.initialMode = 'Four Cut'});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile?> _photos = List<XFile?>.filled(4, null);
  int _selectedCell = 0, _tab = 0, _template = 0, _background = 0;
  bool _showSticker = true;
  final List<Color> _papers = const [cream, Color(0xFFFFE7E2), Color(0xFFEAE4F6), Color(0xFFE2EDE0), Color(0xFF2F2B34)];
  final List<String> _templates = const ['Classic', 'Film', 'Sweet', 'Mono'];

  Future<void> _pickPhoto(int index) async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file != null && mounted) setState(() => _photos[index] = file);
  }

  @override
  Widget build(BuildContext context) {
    final isPolaroid = widget.initialMode == 'Polaroid', isSticker = widget.initialMode == 'Sticker';
    final textColor = _background == 4 ? Colors.white : ink;
    return Scaffold(
      appBar: AppBar(backgroundColor: cream, surfaceTintColor: Colors.transparent,
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink)),
        title: Column(children: [
          Text(isPolaroid ? 'POLAROID STUDIO' : isSticker ? 'CUT-OUT STUDIO' : 'FOUR CUT STUDIO', style: const TextStyle(fontSize: 12, letterSpacing: 1.7, color: ink, fontWeight: FontWeight.w900)),
          const Text('MAKE IT YOURS', style: TextStyle(fontSize: 8, letterSpacing: 1.5, color: muted)),
        ]), centerTitle: true,
        actions: [IconButton(onPressed: () => _toast(context, '復原功能'), icon: const Icon(Icons.undo_rounded, color: ink))]),
      body: Column(children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Column(children: [
          Row(children: [
            const Expanded(child: Text('YOUR CREATION', style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: muted, fontWeight: FontWeight.w800))),
            Text(_photos.where((p) => p != null).length.toString() + '/4 PHOTOS', style: const TextStyle(fontSize: 9, letterSpacing: 1, color: muted, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Center(child: Container(constraints: const BoxConstraints(maxWidth: 310), padding: EdgeInsets.all(_template == 1 ? 9 : 13),
            decoration: BoxDecoration(color: _papers[_background], borderRadius: BorderRadius.circular(_template == 1 ? 5 : 8),
              boxShadow: [BoxShadow(color: ink.withOpacity(.10), blurRadius: 22, offset: const Offset(0, 10))],
              border: _template == 1 ? Border.all(color: Colors.white, width: 4) : null),
            child: Column(children: [
              if (_template == 1) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('PICO FILM   •   2026', style: TextStyle(fontSize: 8, letterSpacing: 2, color: muted, fontWeight: FontWeight.w800))),
              if (isPolaroid) ...[
                _photoCell(0, height: 230), const SizedBox(height: 11),
                Text('a little moment ♡', style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: textColor)),
              ] else if (isSticker) ...[
                Container(height: 250, width: double.infinity, decoration: BoxDecoration(color: Colors.white.withOpacity(.5), borderRadius: BorderRadius.circular(5)),
                  child: _photos[0] == null ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, size: 36, color: muted), SizedBox(height: 8), Text('選一張照片開始去背', style: TextStyle(fontSize: 12, color: muted))]) : Image.file(File(_photos[0]!.path), fit: BoxFit.contain)),
              ] else ...[
                for (int i = 0; i < 4; i++) ...[_photoCell(i, height: 115), if (i != 3) const SizedBox(height: 7)],
              ],
              if (!isSticker) Padding(padding: const EdgeInsets.only(top: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_template == 2 ? '♡ GOOD TIMES ♡' : _template == 3 ? 'GOOD TIMES / 26' : 'little moments',
                  style: TextStyle(fontSize: _template == 3 ? 8 : 10, letterSpacing: _template == 3 ? 2 : .7, color: textColor.withOpacity(.75), fontWeight: FontWeight.w700)),
                if (_showSticker) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.auto_awesome, size: 13, color: coral)),
              ])),
            ]))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _SmallAction(icon: Icons.add_photo_alternate_outlined, label: '加入照片', onTap: () => _pickPhoto(_selectedCell)),
            const SizedBox(width: 10),
            _SmallAction(icon: Icons.refresh_rounded, label: '清空重來', onTap: () => setState(() { for (int i = 0; i < _photos.length; i++) { _photos[i] = null; } })),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            _EditTab(label: '模板', icon: Icons.grid_view_rounded, selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
            _EditTab(label: '底色', icon: Icons.palette_outlined, selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
            _EditTab(label: '裝飾', icon: Icons.auto_awesome_outlined, selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
          ]),
          const SizedBox(height: 12),
          if (_tab == 0) SizedBox(height: 67, child: ListView(scrollDirection: Axis.horizontal, children: List.generate(_templates.length, (i) => Padding(padding: const EdgeInsets.only(right: 9), child: _ChoiceChip(label: _templates[i], selected: _template == i, onTap: () => setState(() => _template = i)))))),
          if (_tab == 1) SizedBox(height: 67, child: ListView(scrollDirection: Axis.horizontal, children: List.generate(_papers.length, (i) => Padding(padding: const EdgeInsets.only(right: 13), child: InkWell(onTap: () => setState(() => _background = i), child: Column(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: _papers[i], shape: BoxShape.circle, border: Border.all(color: _background == i ? coral : const Color(0xFFE3D8CE), width: _background == i ? 3 : 1))),
            const SizedBox(height: 5), Text(['Cream', 'Peach', 'Lilac', 'Sage', 'Night'][i], style: const TextStyle(fontSize: 9, color: muted)),
          ])))))),
          if (_tab == 2) SizedBox(height: 67, child: Row(children: [
            Expanded(child: _ChoiceChip(label: _showSticker ? '✦ 貼紙已開啟' : '✦ 加上貼紙', selected: _showSticker, onTap: () => setState(() => _showSticker = !_showSticker))),
            const SizedBox(width: 10), Expanded(child: _ChoiceChip(label: 'Aa 文字風格', selected: _template == 2, onTap: () => setState(() => _template = 2))),
          ])),
        ]))),
        SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFF0E7DD)))),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pickPhoto(_selectedCell), icon: const Icon(Icons.add_rounded), label: const Text('加照片'),
              style: OutlinedButton.styleFrom(foregroundColor: ink, side: const BorderSide(color: Color(0xFFE8D9D0)), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton.icon(onPressed: () => _toast(context, '高畫質匯出'),
              icon: const Icon(Icons.download_rounded), label: const Text('儲存作品'),
              style: FilledButton.styleFrom(backgroundColor: coral, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
          ]))),
      ]),
    );
  }

  Widget _photoCell(int index, {double height = 115}) {
    final selected = _selectedCell == index, photo = _photos[index];
    return GestureDetector(onTap: () { setState(() => _selectedCell = index); _pickPhoto(index); },
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), height: height, width: double.infinity,
        decoration: BoxDecoration(color: [pink, lilac, butter, mint][index], borderRadius: BorderRadius.circular(_template == 1 ? 1 : 5),
          border: Border.all(color: selected ? coral : Colors.white.withOpacity(.85), width: selected ? 2.2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: photo == null ? Stack(children: [
          Positioned(left: 12, top: 12, child: Text('0' + (index + 1).toString(), style: TextStyle(fontSize: 10, letterSpacing: 1, color: ink.withOpacity(.5), fontWeight: FontWeight.w800))),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_a_photo_outlined, size: 23, color: ink.withOpacity(.55)), const SizedBox(height: 5),
            Text(selected ? '點這裡選照片' : '選擇照片', style: TextStyle(fontSize: 10, color: ink.withOpacity(.65), fontWeight: FontWeight.w600)),
          ])),
        ]) : Image.file(File(photo.path), fit: BoxFit.cover, width: double.infinity, height: height)));
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(13),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFF0E6DE))),
      child: Row(children: [Icon(icon, size: 15, color: muted), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 10, color: ink, fontWeight: FontWeight.w700))])));
}

class _EditTab extends StatelessWidget {
  final String label; final IconData icon; final bool selected; final VoidCallback onTap;
  const _EditTab({required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
    child: Container(padding: const EdgeInsets.symmetric(vertical: 11), decoration: BoxDecoration(color: selected ? const Color(0xFFFBE3DD) : Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: selected ? coral : muted), const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: selected ? ink : muted, fontWeight: FontWeight.w800))]))));
}

class _ChoiceChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _ChoiceChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: selected ? ink : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: selected ? ink : const Color(0xFFE8DCD3))),
      child: Center(child: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : ink, fontWeight: FontWeight.w800)))));
}

void _toast(BuildContext context, String feature) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  content: Text('$feature：下一階段接入'), behavior: SnackBarBehavior.floating, backgroundColor: ink,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
));
