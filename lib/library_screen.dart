import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'cutout/cutout_page.dart';
import 'booth_screen.dart';
import 'models.dart';
import 'services/my_library.dart';
import 'template_maker_screen.dart';
import 'theme.dart';
import 'widgets/frames.dart';
import 'widgets/my_sheet_view.dart';

/// 「我的素材」：新增、刪除自己的貼紙和模板。編輯作品時只能使用，不能在那裡改。
class LibraryScreen extends StatefulWidget {
  /// Shown as the home page's「素材」tab: no back arrow, room for the tab bar.
  final bool embedded;
  const LibraryScreen({super.key, this.embedded = false});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;
  /// Stickers picked to move, name or delete together (long-press one to
  /// start, tap more).
  final _picked = <String>{};
  String _search = '';

  /// Cut a photo into a sticker and put it on [sheet] (null: 未分類).
  Future<void> _newSticker([String? sheet]) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final png = await CutoutPage.open(context, bytes);
    if (png == null || !mounted) return;
    final name = await _askName('幫貼紙取個名字', '例如：我家貓咪（可以不填）');
    MyLibrary.addSticker(png, sheet: sheet, name: name ?? '');
    await _checkWrite();
  }

  Future<String?> _askName(String title, String hint, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showGlassDialog<String>(context, (context) => GlassDialog(
      title: title,
      actions: [
        GlassAction('取消', () => Navigator.pop(context)),
        GlassAction('好', () => Navigator.pop(context, ctrl.text)),
      ],
      child: TextField(
        controller: ctrl, autofocus: true, maxLength: 20,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        cursorColor: blush,
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: GlassDialog.subtle), counterStyle: const TextStyle(color: GlassDialog.subtle),
          filled: true, fillColor: Colors.white.withValues(alpha: .12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
    ));
  }

  Future<void> _newSheet() async {
    final name = await _askName('新增貼紙紙', '例如：旅行、我家貓咪');
    if (name == null || name.trim().isEmpty) return;
    MyLibrary.addSheet(name);
    await _checkWrite();
  }

  Future<void> _sheetMenu(MySheet sheet) async {
    final pick = await showModalBottomSheet<String>(
      context: context, backgroundColor: cream, showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.add_photo_alternate_outlined), title: const Text('在這張紙上做新貼紙'), onTap: () => Navigator.pop(context, 'add')),
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('改名字'), onTap: () => Navigator.pop(context, 'rename')),
        ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB4483C)), title: const Text('刪除這張紙（貼紙會留在未分類）'), onTap: () => Navigator.pop(context, 'delete')),
      ])),
    );
    if (!mounted) return;
    switch (pick) {
      case 'add':
        await _newSticker(sheet.id);
      case 'rename':
        final name = await _askName('貼紙紙的名字', '', initial: sheet.name);
        if (name != null && name.trim().isNotEmpty) MyLibrary.renameSheet(sheet.id, name);
      case 'delete':
        if (await confirmDelete(context, '刪除「${sheet.name}」？', '上面的貼紙不會刪掉，會放回「未分類」。')) MyLibrary.removeSheet(sheet.id);
    }
    await _checkWrite();
  }

  void _toggle(String id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  Future<void> _movePicked() async {
    final sheets = mySheets.toList();
    final pick = await showModalBottomSheet<String>(
      context: context, backgroundColor: cream, showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('把 ${_picked.length} 張貼紙移到', style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800))),
        for (final s in sheets) ListTile(leading: const Icon(Icons.style_outlined), title: Text(s.name), onTap: () => Navigator.pop(context, s.id)),
        ListTile(leading: const Icon(Icons.add_rounded), title: const Text('新的貼紙紙…'), onTap: () => Navigator.pop(context, '+')),
        ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text(unsortedSheet), onTap: () => Navigator.pop(context, '')),
      ])),
    );
    if (pick == null || !mounted) return;
    var target = pick;
    if (pick == '+') {
      final name = await _askName('新增貼紙紙', '例如：旅行、我家貓咪');
      if (name == null || name.trim().isEmpty) return;
      target = MyLibrary.addSheet(name);
    }
    MyLibrary.moveStickers(_picked, target.isEmpty ? null : target);
    setState(_picked.clear);
    await _checkWrite();
  }

  Future<void> _renamePicked() async {
    final id = _picked.single;
    final name = await _askName('貼紙的名字', '', initial: stickerNames[id] ?? '');
    if (name == null) return;
    MyLibrary.renameSticker(id, name);
    setState(_picked.clear);
    await _checkWrite();
  }

  Future<void> _deletePicked() async {
    if (await confirmDelete(context, '刪除 ${_picked.length} 張貼紙？', '已經存到相簿的作品不受影響；用到它的模板，那個位置會變空白。')) {
      MyLibrary.removeStickers(_picked);
      setState(_picked.clear);
      await _checkWrite();
    }
  }

  Future<void> _checkWrite() async {
    if (!await MyLibrary.lastWrite && mounted) {
      showMessage(context, '沒有存進手機（空間可能不夠），關掉 App 後這個改動會不見', error: true);
    }
  }

  /// Shoot four cuts with the user's template number [i].
  void _useTemplate(int i) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => BoothScreen(template: stripTemplates.length + i),
  ));

  void _editTemplate(CustomTemplate t) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => TemplateMakerScreen(initial: t),
  ));

  Future<void> _deleteTemplate(String id) async {
    if (await confirmDelete(context, '刪除這個模板？', '已經存到相簿的作品不受影響。')) {
      MyLibrary.removeTemplate(id);
      await _checkWrite();
    }
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
          _tab == 0 ? '每張貼紙紙會變成貼紙本裡的一頁。長按貼紙可以一次選很多張，移到別張紙、取名字或刪除。' : '設計自己的四格模板，點一下就能直接用，按 ✎ 可以修改。',
          style: const TextStyle(fontSize: 12, height: 1.4, color: muted, fontWeight: FontWeight.w600),
        ),
      ),
      Expanded(child: ValueListenableBuilder<int>(
        valueListenable: MyLibrary.changes,
        builder: (context, _, __) => _tab == 0 ? _stickers() : _templates(),
      )),
      if (_tab == 0 && _picked.isNotEmpty) _pickBar(),
    ])),
  );

  EdgeInsets get _gridPadding => EdgeInsets.fromLTRB(20, 8, 20, widget.embedded ? 130 : 24);

  Widget _stickers() {
    final q = _search.trim().toLowerCase();
    bool match(String id) => q.isEmpty || (stickerNames[id] ?? '').toLowerCase().contains(q);
    final sheets = [
      for (final s in shownSheets)
        // A sheet whose name matches shows whole; otherwise just the matches.
        if (q.isEmpty || s.name.toLowerCase().contains(q)) s
        else if (s.stickers.any(match)) s.copyWith(stickers: s.stickers.where(match).toList()),
    ];
    return ListView(padding: _gridPadding, children: [
      Row(children: [
        Expanded(child: _AddTile(icon: Icons.add_photo_alternate_outlined, label: '照片去背', onTap: () => _newSticker(mySheets.isEmpty ? null : mySheets.last.id), height: 64)),
        const SizedBox(width: 12),
        Expanded(child: _AddTile(icon: Icons.style_outlined, label: '新增貼紙紙', onTap: _newSheet, height: 64)),
      ]),
      if (customStickers.isNotEmpty) ...[
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: '搜尋貼紙或貼紙紙的名字', prefixIcon: const Icon(Icons.search_rounded), isDense: true,
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
          ),
        ),
      ],
      for (final sheet in sheets) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text(sheet.name, style: const TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w900))),
          Text('${sheet.stickers.length} 張', style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700)),
          if (sheet.id.isNotEmpty) IconButton(tooltip: '貼紙紙選項', onPressed: () => _sheetMenu(sheet), icon: const Icon(Icons.more_horiz_rounded, color: ink)),
        ]),
        const SizedBox(height: 4),
        MySheetView(
          sheet: sheet, selected: _picked,
          onLongPress: _toggle,
          // Once picking, a tap picks more.
          onTap: _picked.isEmpty ? null : _toggle,
        ),
      ],
      if (sheets.isEmpty && q.isNotEmpty)
        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('找不到這個名字的貼紙', style: TextStyle(color: muted, fontWeight: FontWeight.w700)))),
    ]);
  }

  Widget _pickBar() => SafeArea(top: false, child: Container(
    margin: EdgeInsets.fromLTRB(16, 4, 16, widget.embedded ? 104 : 12),
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(18)),
    child: Row(children: [
      Expanded(child: Text('已選 ${_picked.length} 張', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
      IconButton(tooltip: '移到貼紙紙', onPressed: _movePicked, icon: const Icon(Icons.drive_file_move_outline, color: Colors.white)),
      if (_picked.length == 1) IconButton(tooltip: '取名字', onPressed: _renamePicked, icon: const Icon(Icons.edit_outlined, color: Colors.white)),
      IconButton(tooltip: '刪除', onPressed: _deletePicked, icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF8A8A))),
      IconButton(tooltip: '取消選取', onPressed: () => setState(_picked.clear), icon: const Icon(Icons.close_rounded, color: Colors.white)),
    ]),
  ));

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
  /// A short, wide button with the icon beside the label, instead of a tile.
  final double? height;
  const _AddTile({required this.icon, required this.label, required this.onTap, this.height});

  @override
  Widget build(BuildContext context) => Material(
    color: blush, borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(18),
      child: Container(
        height: height,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: blushLine, width: 1.4)),
        child: height != null
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: coral, size: 24),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
            ])
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
