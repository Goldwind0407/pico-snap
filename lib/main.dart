import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const ink = Color(0xFF342B2A);
const muted = Color(0xFF9A8983);
const cream = Color(0xFFFFFAF4);
const coral = Color(0xFFF27E72);
const blush = Color(0xFFFFE5DF);
const lilac = Color(0xFFE9E1F4);
const butter = Color(0xFFFFEDB9);
const sage = Color(0xFFE1EDE0);
const line = Color(0xFFF0E5DC);

void main() => runApp(const PicoSnapApp());

class PicoSnapApp extends StatelessWidget {
  const PicoSnapApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PICO SNAP',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: coral),
      fontFamily: 'Arial',
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  void _open(BuildContext context, String mode) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => EditorScreen(initialMode: mode)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(22, 17, 22, 18),
        sliver: SliverToBoxAdapter(child: Row(children: [
          Container(
            width: 45, height: 45,
            decoration: BoxDecoration(
              color: coral, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: coral.withOpacity(.22), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 11),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PICO SNAP', style: TextStyle(fontSize: 17, letterSpacing: 2.1, fontWeight: FontWeight.w900, color: ink)),
            SizedBox(height: 3),
            Text('little moments, lovely memories', style: TextStyle(fontSize: 10, color: muted)),
          ])),
          _RoundIcon(icon: Icons.photo_library_outlined, onTap: () => _open(context, 'Gallery')),
        ])),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFE2D8), Color(0xFFFFF0D9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(children: [
            const Positioned(right: -24, top: -27, child: _SoftOrb(size: 150, color: Color(0xFFFFD0C5))),
            const Positioned(right: 82, bottom: -50, child: _SoftOrb(size: 112, color: Color(0xFFFFE9B9))),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.72), borderRadius: BorderRadius.circular(30)),
                  child: const Text('YOUR POCKET PHOTO BOOTH', style: TextStyle(fontSize: 8, letterSpacing: 1.3, color: ink, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 15),
                const Text('Make today a\nlittle more lovely.', style: TextStyle(fontSize: 29, height: 1.12, letterSpacing: -.7, color: ink, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('把日常的小瞬間，變成喜歡的樣子。', style: TextStyle(fontSize: 11, color: Color(0xFF816B64))),
                const SizedBox(height: 17),
                FilledButton(
                  onPressed: () => _open(context, 'Four Cut'),
                  style: FilledButton.styleFrom(
                    backgroundColor: coral, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0,
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 17), SizedBox(width: 8),
                    Text('開始製作', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    SizedBox(width: 5), Icon(Icons.arrow_forward_rounded, size: 15),
                  ]),
                ),
                const SizedBox(height: 17),
                const _PrintCollage(),
              ]),
            ),
          ]),
        )),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(23, 27, 23, 13),
        sliver: SliverToBoxAdapter(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LET’S CREATE', style: TextStyle(fontSize: 9, letterSpacing: 1.6, color: muted, fontWeight: FontWeight.w800)),
            SizedBox(height: 5),
            Text('今天想做什麼？', style: TextStyle(fontSize: 21, color: ink, fontWeight: FontWeight.w900)),
          ])),
          const Text('3 MODES', style: TextStyle(fontSize: 9, letterSpacing: 1.2, color: muted, fontWeight: FontWeight.w800)),
        ])),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: Row(children: [
          Expanded(child: _ModeCard(title: '四格拍貼', subtitle: 'FOUR CUTS', icon: Icons.grid_view_rounded, color: blush, onTap: () => _open(context, 'Four Cut'))),
          const SizedBox(width: 10),
          Expanded(child: _ModeCard(title: '拍立得', subtitle: 'POLAROID', icon: Icons.photo_size_select_actual_outlined, color: butter, onTap: () => _open(context, 'Polaroid'))),
          const SizedBox(width: 10),
          Expanded(child: _ModeCard(title: '去背貼紙', subtitle: 'CUT-OUT', icon: Icons.auto_fix_high_rounded, color: sage, onTap: () => _open(context, 'Sticker'))),
        ])),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(23, 27, 23, 12),
        sliver: SliverToBoxAdapter(child: Row(children: [
          const Expanded(child: Text('挑一個今日風格', style: TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900))),
          TextButton(onPressed: () => _open(context, 'Four Cut'), child: const Text('全部風格  →', style: TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w700))),
        ])),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
        sliver: SliverToBoxAdapter(child: SizedBox(height: 150, child: ListView(
          scrollDirection: Axis.horizontal,
          children: const [
            _StyleCard(title: 'Soft Film', subtitle: '暖色底片感', tag: '01 / WARM', color: Color(0xFFF3D8C6), accent: coral),
            SizedBox(width: 12),
            _StyleCard(title: 'Sunday Club', subtitle: '甜甜的日常', tag: '02 / PLAYFUL', color: lilac, accent: Color(0xFF907FC0)),
            SizedBox(width: 12),
            _StyleCard(title: 'Little Garden', subtitle: '清新自然系', tag: '03 / FRESH', color: sage, accent: Color(0xFF6D9877)),
          ],
        ))),
      ),
    ])),
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(color: cream, border: Border(top: BorderSide(color: line))),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(27, 10, 27, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          _NavItem(icon: Icons.home_rounded, label: '首頁', selected: true),
          _NavItem(icon: Icons.auto_awesome_mosaic_outlined, label: '模板'),
          _NavItem(icon: Icons.photo_library_outlined, label: '作品'),
          _NavItem(icon: Icons.person_outline_rounded, label: '我的'),
        ]),
      )),
    ),
  );
}

class _SoftOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _SoftOrb({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(.65)),
  );
}

class _PrintCollage extends StatelessWidget {
  const _PrintCollage();
  @override
  Widget build(BuildContext context) => SizedBox(height: 108, child: Stack(clipBehavior: Clip.none, children: const [
    Positioned(left: 4, top: 9, child: Transform.rotate(angle: -.13, child: _MiniPrint(color: lilac, symbol: Icons.star_rounded, caption: 'good day'))),
    Positioned(left: 82, top: 0, child: Transform.rotate(angle: .025, child: _MiniPrint(color: Colors.white, symbol: Icons.favorite_rounded, caption: 'little joy'))),
    Positioned(left: 160, top: 9, child: Transform.rotate(angle: .12, child: _MiniPrint(color: butter, symbol: Icons.sunny, caption: 'sunny!'))),
    Positioned(right: 5, top: 14, child: Icon(Icons.auto_awesome_rounded, size: 25, color: Color(0xFFD9957C))),
  ]));
}

class _MiniPrint extends StatelessWidget {
  final Color color;
  final IconData symbol;
  final String caption;
  const _MiniPrint({required this.color, required this.symbol, required this.caption});
  @override
  Widget build(BuildContext context) => Container(
    width: 74, height: 98, padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: ink.withOpacity(.12), blurRadius: 9, offset: const Offset(0, 4))]),
    child: Column(children: [
      Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)), child: Icon(symbol, color: coral, size: 26))),
      const SizedBox(height: 4),
      Text(caption, style: const TextStyle(fontSize: 8, color: ink, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white, borderRadius: BorderRadius.circular(15),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: SizedBox(width: 44, height: 44, child: Icon(icon, color: ink, size: 21))),
  );
}

class _ModeCard extends StatelessWidget {
  final String title, subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _ModeCard({required this.title, required this.subtitle, required this.color, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white, borderRadius: BorderRadius.circular(21),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(21),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 13, 8, 13),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), border: Border.all(color: line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 39, height: 39, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)), child: Icon(icon, size: 20, color: ink)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 7, letterSpacing: .8, color: muted, fontWeight: FontWeight.w800)),
        ]),
      ),
    ),
  );
}

class _StyleCard extends StatelessWidget {
  final String title, subtitle, tag;
  final Color color, accent;
  const _StyleCard({required this.title, required this.subtitle, required this.tag, required this.color, required this.accent});
  @override
  Widget build(BuildContext context) => Container(
    width: 218, padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(23)),
    child: Stack(children: [
      Positioned(right: 5, top: 2, child: Transform.rotate(angle: .10, child: Container(
        width: 69, height: 91, padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: ink.withOpacity(.12), blurRadius: 8)]),
        child: Container(decoration: BoxDecoration(color: accent.withOpacity(.18), borderRadius: BorderRadius.circular(2)), child: Icon(Icons.favorite_rounded, color: accent, size: 26)),
      ))),
      Positioned(left: 0, bottom: 0, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tag, style: TextStyle(fontSize: 8, letterSpacing: 1.1, color: ink.withOpacity(.65), fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(title, style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(fontSize: 10, color: ink.withOpacity(.68))),
      ])),
    ]),
  );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem({required this.icon, required this.label, this.selected = false});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 21, color: selected ? coral : muted),
    const SizedBox(height: 4),
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
  final List<Color> _papers = const [cream, Color(0xFFFFE7E2), lilac, sage, Color(0xFF342F37)];
  final List<String> _templates = const ['Classic', 'Film', 'Sweet', 'Mono'];

  Future<void> _pickPhoto(int index) async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file != null && mounted) setState(() => _photos[index] = file);
  }

  @override
  Widget build(BuildContext context) {
    final isPolaroid = widget.initialMode == 'Polaroid';
    final isSticker = widget.initialMode == 'Sticker';
    final isGallery = widget.initialMode == 'Gallery';
    final textColor = _background == 4 ? Colors.white : ink;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
        title: Column(children: [
          Text(isPolaroid ? 'POLAROID STUDIO' : isSticker ? 'CUT-OUT STUDIO' : isGallery ? 'YOUR CREATIONS' : 'FOUR CUT STUDIO',
            style: const TextStyle(fontSize: 11, letterSpacing: 1.6, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          const Text('MAKE IT YOURS', style: TextStyle(fontSize: 8, letterSpacing: 1.6, color: muted)),
        ]),
        centerTitle: true,
        actions: [IconButton(onPressed: () => _toast(context, '復原'), icon: const Icon(Icons.undo_rounded))],
      ),
      body: Column(children: [
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(children: [
            Row(children: [
              const Expanded(child: Text('YOUR CREATION', style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: muted, fontWeight: FontWeight.w800))),
              Text(_photos.where((p) => p != null).length.toString() + '/4 PHOTOS', style: const TextStyle(fontSize: 9, letterSpacing: 1, color: muted, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 13),
            Center(child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              padding: EdgeInsets.all(_template == 1 ? 10 : 13),
              decoration: BoxDecoration(
                color: _papers[_background], borderRadius: BorderRadius.circular(_template == 1 ? 5 : 9),
                boxShadow: [BoxShadow(color: ink.withOpacity(.10), blurRadius: 22, offset: const Offset(0, 9))],
                border: _template == 1 ? Border.all(color: Colors.white, width: 4) : null,
              ),
              child: Column(children: [
                if (_template == 1) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('PICO FILM  •  2026', style: TextStyle(fontSize: 8, letterSpacing: 2, color: muted, fontWeight: FontWeight.w800))),
                if (isPolaroid) ...[
                  _photoCell(0, height: 275),
                  const SizedBox(height: 13),
                  Text('a little moment ♡', style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: textColor)),
                  const SizedBox(height: 4),
                ] else if (isSticker) ...[
                  Container(
                    height: 285, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(.55), borderRadius: BorderRadius.circular(5)),
                    child: _photos[0] == null
                      ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 38, color: muted),
                          SizedBox(height: 9),
                          Text('選一張照片開始', style: TextStyle(fontSize: 12, color: muted)),
                          SizedBox(height: 4),
                          Text('MAKE YOUR OWN STICKER', style: TextStyle(fontSize: 8, letterSpacing: 1.2, color: muted)),
                        ])
                      : Image.file(File(_photos[0]!.path), fit: BoxFit.contain),
                  ),
                ] else ...[
                  for (int i = 0; i < 4; i++) ...[
                    _photoCell(i, height: 112),
                    if (i != 3) const SizedBox(height: 7),
                  ],
                ],
                if (!isSticker) Padding(padding: const EdgeInsets.only(top: 11), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_template == 2 ? '♡ GOOD TIMES ♡' : _template == 3 ? 'GOOD TIMES / 26' : 'little moments',
                    style: TextStyle(fontSize: _template == 3 ? 8 : 10, letterSpacing: _template == 3 ? 2 : .7, color: textColor.withOpacity(.75), fontWeight: FontWeight.w700)),
                  if (_showSticker) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.auto_awesome, size: 13, color: coral)),
                ])),
              ]),
            )),
            const SizedBox(height: 17),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _SmallAction(icon: Icons.add_photo_alternate_outlined, label: '加入照片', onTap: () => _pickPhoto(_selectedCell)),
              const SizedBox(width: 9),
              _SmallAction(icon: Icons.refresh_rounded, label: '清空重來', onTap: () => setState(() {
                for (int i = 0; i < _photos.length; i++) { _photos[i] = null; }
              })),
            ]),
            const SizedBox(height: 21),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFFF3EAE2), borderRadius: BorderRadius.circular(17)),
              child: Row(children: [
                _EditTab(label: '模板', icon: Icons.grid_view_rounded, selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                _EditTab(label: '底色', icon: Icons.palette_outlined, selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
                _EditTab(label: '裝飾', icon: Icons.auto_awesome_outlined, selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
              ]),
            ),
            const SizedBox(height: 15),
            if (_tab == 0) SizedBox(height: 58, child: ListView(scrollDirection: Axis.horizontal, children: List.generate(_templates.length, (i) => Padding(
              padding: const EdgeInsets.only(right: 9),
              child: _ChoiceChip(label: _templates[i], selected: _template == i, onTap: () => setState(() => _template = i)),
            )))),
            if (_tab == 1) SizedBox(height: 66, child: ListView(scrollDirection: Axis.horizontal, children: List.generate(_papers.length, (i) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: InkWell(onTap: () => setState(() => _background = i), child: Column(children: [
                Container(width: 37, height: 37, decoration: BoxDecoration(
                  color: _papers[i], shape: BoxShape.circle,
                  border: Border.all(color: _background == i ? coral : const Color(0xFFE3D8CE), width: _background == i ? 3 : 1),
                ), child: _background == i ? Icon(Icons.check_rounded, size: 16, color: i == 4 ? Colors.white : ink) : null),
                const SizedBox(height: 5),
                Text(['Cream', 'Peach', 'Lilac', 'Sage', 'Night'][i], style: const TextStyle(fontSize: 9, color: muted)),
              ])),
            )))),
            if (_tab == 2) SizedBox(height: 58, child: Row(children: [
              Expanded(child: _ChoiceChip(label: _showSticker ? '✦ 貼紙已開啟' : '✦ 加上貼紙', selected: _showSticker, onTap: () => setState(() => _showSticker = !_showSticker))),
              const SizedBox(width: 9),
              Expanded(child: _ChoiceChip(label: 'Aa 文字風格', selected: _template == 2, onTap: () => setState(() => _template = 2))),
            ])),
          ]),
        )),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(_selectedCell), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('加照片'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink, side: const BorderSide(color: Color(0xFFE8D9D0)),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton.icon(
              onPressed: () => _toast(context, '儲存作品'), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('儲存作品'),
              style: FilledButton.styleFrom(
                backgroundColor: coral, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0,
              ),
            )),
          ]),
        )),
      ]),
    );
  }

  Widget _photoCell(int index, {double height = 112}) {
    final selected = _selectedCell == index;
    final photo = _photos[index];
    const cellColors = [blush, lilac, butter, sage];
    return GestureDetector(
      onTap: () { setState(() => _selectedCell = index); _pickPhoto(index); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: height, width: double.infinity,
        decoration: BoxDecoration(
          color: cellColors[index], borderRadius: BorderRadius.circular(_template == 1 ? 1 : 5),
          border: Border.all(color: selected ? coral : Colors.white.withOpacity(.85), width: selected ? 2.2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: photo == null
          ? Stack(children: [
              Positioned(left: 12, top: 10, child: Text('0' + (index + 1).toString(), style: TextStyle(fontSize: 10, letterSpacing: 1, color: ink.withOpacity(.5), fontWeight: FontWeight.w800))),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_a_photo_outlined, size: 22, color: ink.withOpacity(.55)),
                const SizedBox(height: 5),
                Text(selected ? '點這裡選照片' : '選擇照片', style: TextStyle(fontSize: 10, color: ink.withOpacity(.65), fontWeight: FontWeight.w600)),
              ])),
            ])
          : Image.file(File(photo.path), fit: BoxFit.cover, width: double.infinity, height: height),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white, borderRadius: BorderRadius.circular(13),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(13), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), border: Border.all(color: line)),
      child: Row(children: [
        Icon(icon, size: 15, color: muted), const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: ink, fontWeight: FontWeight.w700)),
      ]),
    )),
  );
}

class _EditTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _EditTab({required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(13),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(13),
        boxShadow: selected ? [BoxShadow(color: ink.withOpacity(.04), blurRadius: 5, offset: const Offset(0, 2))] : [],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: selected ? coral : muted), const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: selected ? ink : muted, fontWeight: FontWeight.w800)),
      ]),
    ),
  ));
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? ink : Colors.white, borderRadius: BorderRadius.circular(14),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? ink : const Color(0xFFE8DCD3))),
      child: Center(child: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : ink, fontWeight: FontWeight.w800))),
    )),
  );
}

void _toast(BuildContext context, String feature) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  content: Text('$feature：介面原型，功能之後再接入'),
  behavior: SnackBarBehavior.floating,
  backgroundColor: ink,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
));
