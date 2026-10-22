import 'package:flutter/material.dart';

import 'models.dart';
import 'services/my_library.dart';
import 'theme.dart';
import 'widgets/frames.dart';

const _palette = [
  Color(0xFFF9CACB), Color(0xFFF2867B), Color(0xFFF7B6C2), Color(0xFFE3D3F1), Color(0xFFC9B6EE), Color(0xFF9FD0EE),
  Color(0xFFC8DDEA), Color(0xFFCDE9D9), Color(0xFFB9C9AE), Color(0xFFFBE7A6), Color(0xFFFFF4E4), Color(0xFFD9BFA8),
  Color(0xFF1F4D3A), Color(0xFF1F1D2B),
];

const _patterns = [
  (FramePattern.none, '無'), (FramePattern.dots, '點點'), (FramePattern.paws, '貓掌'),
  (FramePattern.confetti, '碎紙花'), (FramePattern.stripes, '條紋'),
];

const _cells = [(CellShape.square, '方形'), (CellShape.rounded, '圓角'), (CellShape.cloud, '雲朵'), (CellShape.wavy, '波浪邊')];

const _footers = [(FooterStyle.caption, '手寫字'), (FooterStyle.logoDate, '標誌＋日期'), (FooterStyle.title, '大標題')];

/// 設計一個自己的四格模板，存到「我的素材」。
class TemplateMakerScreen extends StatefulWidget {
  const TemplateMakerScreen({super.key});

  @override
  State<TemplateMakerScreen> createState() => _TemplateMakerScreenState();
}

class _TemplateMakerScreenState extends State<TemplateMakerScreen> {
  final _caption = TextEditingController(text: 'my little day');
  Color _frame = _palette.first;
  Color? _frame2;
  FramePattern _pattern = FramePattern.none;
  CellShape _cell = CellShape.square;
  FooterStyle _footer = FooterStyle.caption;
  final _stickers = <String>[];

  CustomTemplate _spec(String id) => CustomTemplate(
    id: id, caption: _caption.text.trim(), frame: _frame, frame2: _frame2,
    pattern: _pattern, cellShape: _cell, footer: _footer, stickers: List.of(_stickers),
  );

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _save() {
    MyLibrary.addTemplate(_spec(MyLibrary.newKey()));
    Navigator.pop(context);
  }

  void _toggleSticker(String id) => setState(() {
    if (_stickers.remove(id)) return;
    if (_stickers.length >= CustomTemplate.decoSpots.length) _stickers.removeAt(0);
    _stickers.add(id);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: ink)),
          const Expanded(child: Text('設計模板', style: TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900))),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(backgroundColor: coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('儲存', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      // Live preview with sample photos.
      SizedBox(height: 250, width: double.infinity, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FittedBox(child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 16, offset: const Offset(0, 6))]),
          child: PhotoStrip(template: _spec('').template, photos: samplePhotos),
        )),
      )),
      Expanded(child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 18, offset: const Offset(0, -4))],
        ),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 32), children: [
          _section('外框顏色', Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in _palette) _Swatch(color: c, selected: _frame == c, onTap: () => setState(() => _frame = c)),
          ])),
          _section('漸層（下半部的顏色）', Wrap(spacing: 10, runSpacing: 10, children: [
            _Chip(label: '不要', selected: _frame2 == null, onTap: () => setState(() => _frame2 = null)),
            for (final c in _palette) _Swatch(color: c, selected: _frame2 == c, onTap: () => setState(() => _frame2 = c)),
          ])),
          _section('圖案', Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (p, label) in _patterns) _Chip(label: label, selected: _pattern == p, onTap: () => setState(() => _pattern = p)),
          ])),
          _section('照片格', Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (c, label) in _cells) _Chip(label: label, selected: _cell == c, onTap: () => setState(() => _cell = c)),
          ])),
          _section('底部', Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (f, label) in _footers) _Chip(label: label, selected: _footer == f, onTap: () => setState(() => _footer = f)),
          ])),
          _section('文字', TextField(
            controller: _caption,
            maxLength: 18,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15, color: ink),
            decoration: InputDecoration(
              isDense: true, filled: true, fillColor: cream,
              hintText: _footer == FooterStyle.logoDate ? '留空會顯示今天的日期' : '寫點什麼',
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: coral, width: 1.5)),
            ),
          )),
          _section('裝飾貼紙（最多 ${CustomTemplate.decoSpots.length} 張）', Wrap(spacing: 8, runSpacing: 8, children: [
            for (final id in [...stickerPacks.first.$3, ...customStickers.keys])
              _StickerChoice(id: id, order: _stickers.indexOf(id), onTap: () => _toggleSticker(id)),
          ])),
        ]),
      )),
    ])),
  );

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      child,
    ]),
  );
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36, padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? coral : Colors.transparent, width: 2.5)),
      child: Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: line))),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? blush : cream, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? blushLine : line),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: ink, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
    ),
  );
}

class _StickerChoice extends StatelessWidget {
  final String id;
  /// Position among the chosen stickers, or -1.
  final int order;
  final VoidCallback onTap;
  const _StickerChoice({required this.id, required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 52, height: 52, padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: order >= 0 ? blush : cream, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: order >= 0 ? coral : line, width: order >= 0 ? 2 : 1),
        ),
        child: StickerVisual(id),
      ),
      if (order >= 0)
        Positioned(right: -4, top: -4, child: Container(
          width: 18, height: 18, alignment: Alignment.center,
          decoration: const BoxDecoration(color: coral, shape: BoxShape.circle),
          child: Text('${order + 1}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w900)),
        )),
    ]),
  );
}
