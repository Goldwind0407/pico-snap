import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'cutout/cutout_page.dart';
import 'editor_screen.dart';
import 'models.dart';
import 'services/my_library.dart';
import 'template_maker_screen.dart';
import 'theme.dart';
import 'widgets/frames.dart';

/// 「我的素材」：新增、刪除自己的貼紙和模板。編輯作品時只能使用，不能在那裡改。
class LibraryScreen extends StatefulWidget {
  /// Shown as the home page's「我的」tab: no back arrow, room for the tab bar.
  final bool embedded;
  const LibraryScreen({super.key, this.embedded = false});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;

  Future<void> _newSticker() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final png = await CutoutPage.open(context, bytes);
    if (png != null) MyLibrary.addSticker(png);
  }

  Future<void> _deleteSticker(String id) async {
    if (await confirmDelete(context, '刪除這張貼紙？', '已經存到相簿的作品不受影響；用到它的模板，那個位置會變空白。')) {
      MyLibrary.removeSticker(id);
    }
  }

  /// Open the four-cut editor with the user's template number [i].
  void _useTemplate(int i) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => EditorScreen(template: stripTemplates.length + i),
  ));

  void _editTemplate(CustomTemplate t) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => TemplateMakerScreen(initial: t),
  ));

  Future<void> _deleteTemplate(String id) async {
    if (await confirmDelete(context, '刪除這個模板？', '已經存到相簿的作品不受影響。')) MyLibrary.removeTemplate(id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: Row(children: [
          if (widget.embedded) const SizedBox(width: 12, height: 48)
          else IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
          const Text('我的素材', style: TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
          child: Row(children: [
            for (final (i, label) in const [(0, '貼紙'), (1, '模板')])
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _tab == i ? blush : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Text(label, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: ink, fontWeight: _tab == i ? FontWeight.w900 : FontWeight.w600)),
                ),
              )),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
        child: Text(
          _tab == 0 ? '把照片去背做成貼紙，編輯作品時在貼紙的「📷 我的」裡使用。' : '設計自己的四格模板，點一下就能直接用，按 ✎ 可以修改。',
          style: const TextStyle(fontSize: 12, height: 1.4, color: muted, fontWeight: FontWeight.w600),
        ),
      ),
      Expanded(child: ValueListenableBuilder<int>(
        valueListenable: MyLibrary.changes,
        builder: (context, _, __) => _tab == 0 ? _stickers() : _templates(),
      )),
    ])),
  );

  EdgeInsets get _gridPadding => EdgeInsets.fromLTRB(20, 8, 20, widget.embedded ? 130 : 24);

  Widget _stickers() => GridView.count(
    crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12,
    padding: _gridPadding,
    children: [
      _AddTile(icon: Icons.add_photo_alternate_outlined, label: '照片去背', onTap: _newSticker),
      for (final id in customStickers.keys.toList().reversed)
        _ItemTile(onDelete: () => _deleteSticker(id), child: Padding(padding: const EdgeInsets.all(12), child: StickerVisual(id, size: 96))),
    ],
  );

  Widget _templates() => GridView.count(
    crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .5,
    padding: _gridPadding,
    children: [
      _AddTile(icon: Icons.dashboard_customize_outlined, label: '新增模板', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TemplateMakerScreen()))),
      for (final (i, t) in customTemplates.indexed.toList().reversed)
        _ItemTile(onDelete: () => _deleteTemplate(t.id), onTap: () => _useTemplate(i), onEdit: () => _editTemplate(t), child: Padding(
          padding: const EdgeInsets.all(10),
          child: FittedBox(child: PhotoStrip(template: t.template, photos: samplePhotos)),
        )),
    ],
  );
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: blush, borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: blushLine, width: 1.4)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: coral, size: 30),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
        ]),
      ),
    ),
  );
}

class _ItemTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback? onTap, onEdit;
  const _ItemTile({required this.child, required this.onDelete, this.onTap, this.onEdit});

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
        child: Center(child: child),
      ),
    )),
    if (onEdit != null)
      Positioned(left: 4, top: 4, child: GestureDetector(
        onTap: onEdit,
        child: Container(
          width: 26, height: 26,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: line), boxShadow: [BoxShadow(color: ink.withValues(alpha: .15), blurRadius: 3)]),
          child: const Icon(Icons.edit_outlined, size: 15, color: ink),
        ),
      )),
    Positioned(right: 4, top: 4, child: GestureDetector(
      onTap: onDelete,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: line), boxShadow: [BoxShadow(color: ink.withValues(alpha: .15), blurRadius: 3)]),
        child: const Icon(Icons.close_rounded, size: 16, color: ink),
      ),
    )),
  ]);
}
