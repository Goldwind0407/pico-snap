import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'models.dart';
import 'services/my_library.dart';
import 'theme.dart';
import 'widgets/frames.dart';
import 'widgets/sticker_book_view.dart';
import 'widgets/sticker_item.dart';

const _palette = [
  Color(0xFFF9CACB), Color(0xFFF2867B), Color(0xFFF7B6C2), Color(0xFFE3D3F1), Color(0xFFC9B6EE), Color(0xFF9FD0EE),
  Color(0xFFC8DDEA), Color(0xFFCDE9D9), Color(0xFFB9C9AE), Color(0xFFFBE7A6), Color(0xFFFFF4E4), Color(0xFFD9BFA8),
  Color(0xFF1F4D3A), Color(0xFF1F1D2B),
];

const _patterns = [
  (FramePattern.none, '無'), (FramePattern.dots, '點點'), (FramePattern.paws, '貓掌'),
  (FramePattern.confetti, '碎紙花'), (FramePattern.stripes, '條紋'), (FramePattern.gingham, '格紋'),
  (FramePattern.hearts, '愛心'), (FramePattern.stars, '星星'), (FramePattern.flowers, '小花'),
  (FramePattern.checker, '棋盤格'), (FramePattern.waves, '波浪'),
];

const _cells = [(CellShape.square, '方形'), (CellShape.rounded, '圓角'), (CellShape.cloud, '雲朵'), (CellShape.wavy, '波浪邊'), (CellShape.heart, '愛心'), (CellShape.star, '星星')];

const _footers = [(FooterStyle.caption, '手寫字'), (FooterStyle.logoDate, '標誌＋日期'), (FooterStyle.title, '大標題')];

const _captionIdeas = ['my little day', 'best friends', 'happy birthday', 'say cheese!', 'good vibes'];

enum _Tab {
  start(CupertinoIcons.rectangle_3_offgrid, '範本'),
  color(CupertinoIcons.drop, '顏色'),
  pattern(CupertinoIcons.circle_grid_3x3, '圖案'),
  cell(CupertinoIcons.square, '照片格'),
  text(CupertinoIcons.textformat, '文字'),
  sticker(CupertinoIcons.smiley, '貼紙');

  final IconData icon;
  final String label;
  const _Tab(this.icon, this.label);
}

/// 設計（或修改）一個自己的四格模板，存到「我的素材」。
///
/// 上面是放大的即時預覽，貼紙直接在預覽上拖曳、縮放、旋轉、翻轉；
/// 下面一次只顯示一組選項。
class TemplateMakerScreen extends StatefulWidget {
  /// The template to edit; null starts a new one.
  final CustomTemplate? initial;
  const TemplateMakerScreen({super.key, this.initial});

  @override
  State<TemplateMakerScreen> createState() => _TemplateMakerScreenState();
}

class _TemplateMakerScreenState extends State<TemplateMakerScreen> {
  late CustomTemplate _t = widget.initial ?? CustomTemplate(id: '', caption: 'my little day', frame: Color(0xFFF9CACB));
  late final _caption = TextEditingController(text: _t.caption);
  final _canvasKey = GlobalKey();
  _Tab _tab = _Tab.color;
  int? _selected;
  bool _edited = false;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _update(CustomTemplate t) => setState(() {
    _t = t;
    _edited = true;
  });

  Future<void> _save() async {
    if (_editing) {
      MyLibrary.updateTemplate(_t);
    } else {
      MyLibrary.addTemplate(_t.copyWith(id: MyLibrary.newKey()));
    }
    _edited = false;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    if (!await MyLibrary.lastWrite) {
      messenger.showSnackBar(const SnackBar(
        content: Text('模板沒有存進手機（空間可能不夠），關掉 App 後會不見'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFB4483C),
      ));
    }
  }

  void _startFrom(StripTemplate t) {
    final c = CustomTemplate.from(t);
    _caption.text = c.caption;
    _selected = null;
    _update(c.copyWith(id: _t.id));
  }

  void _addSticker(String id, [double scale = 1]) {
    final n = _t.stickers.length;
    _update(_t.copyWith(stickers: [..._t.stickers, StickerData(sticker: id, scale: scale, center: Offset(.5 + (n % 3 - 1) * .2, .3 + (n % 4) * .12))]));
    _selected = _t.stickers.length - 1;
  }

  void _setSticker(int i, StickerData d) => _update(_t.copyWith(stickers: [..._t.stickers]..[i] = d));

  Offset _toCanvas(Offset global) => (_canvasKey.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_edited,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final navigator = Navigator.of(context);
      if (await confirmLeave(context, '還沒儲存的模板會不見喔。')) navigator.pop();
    },
    child: Scaffold(
      backgroundColor: cream,
      body: SafeArea(bottom: false, child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(CupertinoIcons.xmark, color: ink)),
            Expanded(child: Text(_editing ? '修改模板' : '設計模板', style: const TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900))),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('儲存', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 12), child: _preview())),
        _sheet(),
      ])),
    ),
  );

  /// The strip with sample photos; stickers are placed right on it.
  Widget _preview() => Center(child: AspectRatio(aspectRatio: 200 / 620, child: LayoutBuilder(builder: (context, c) {
    final size = c.biggest;
    // Stickers are drawn by StickerItem here, not by the strip.
    final strip = _t.copyWith(stickers: const []).template;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Stack(key: _canvasKey, clipBehavior: Clip.none, children: [
        Positioned.fill(child: GestureDetector(
          onTap: () => setState(() => _selected = null),
          // On the 照片格 tab a window can be tapped to shape just that one.
          child: FittedBox(child: PhotoStrip(
            template: strip,
            selected: _tab == _Tab.cell ? _cellTarget : null,
            onTapCell: _tab == _Tab.cell ? (i) => setState(() => _cellTarget = _cellTarget == i ? null : i) : null,
          )),
        )),
        for (var i = 0; i < _t.stickers.length; i++)
          StickerItem(
            data: _t.stickers[i],
            animatePlacement: _selected == i,
            canvas: size,
            selected: _selected == i,
            toLocal: _toCanvas,
            onSelect: () => setState(() => _selected = i),
            onEditStart: () => setState(() => _selected = i),
            onChanged: (d) => _setSticker(i, d),
            onFlip: () => _setSticker(i, _t.stickers[i].copyWith(flipped: !_t.stickers[i].flipped)),
            onDelete: () {
              _selected = null;
              _update(_t.copyWith(stickers: [..._t.stickers]..removeAt(i)));
            },
          ),
      ]),
    );
  })));

  Widget _sheet() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 20, offset: const Offset(0, -4))],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // The sticker book wants room to show part of a sheet.
      SizedBox(height: switch (_tab) { _Tab.sticker => 230, _Tab.cell => 180, _ => 150 }, child: switch (_tab) {
        _Tab.start => _startTool(),
        _Tab.color => _colorTool(),
        _Tab.pattern => _chips([for (final (p, l) in _patterns) (l, _t.pattern == p, () => _update(_t.copyWith(pattern: p)))]),
        _Tab.cell => _cellTool(),
        _Tab.text => _textTool(),
        _Tab.sticker => _stickerTool(),
      }),
      Container(
        decoration: BoxDecoration(
          color: cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, -3))],
        ),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Row(children: [
            for (final t in _Tab.values)
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _tab = t),
                behavior: HitTestBehavior.opaque,
                child: Center(child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: _tab == t ? blush : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.icon, size: 22, color: _tab == t ? ink : muted),
                    const SizedBox(height: 2),
                    Text(t.label, style: TextStyle(fontSize: 11, color: _tab == t ? ink : muted, fontWeight: _tab == t ? FontWeight.w800 : FontWeight.w600)),
                  ]),
                )),
              )),
          ]),
        )),
      ),
    ]),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    child: Text(text, style: TextStyle(fontSize: 12, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600)),
  );

  /// Start from one of the built-in drawn templates.
  Widget _startTool() {
    const starts = drawnTemplates;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _hint('從內建樣式開始，再慢慢改成自己的'),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        itemCount: starts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _startFrom(starts[i]),
          child: Container(
            width: 48, padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
            child: FittedBox(child: PhotoStrip(template: starts[i])),
          ),
        ),
      )),
    ]);
  }

  Widget _colorTool() {
    final gradient = _t.frame2 != null;
    Widget swatches(String? label, Color? selected, ValueChanged<Color> onTap) => SizedBox(height: 40, child: Row(children: [
      if (label != null) Padding(padding: const EdgeInsets.only(left: 20), child: Text(label, style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w800))),
      Expanded(child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(left: label == null ? 20 : 8, right: 20),
      itemCount: _palette.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (_, i) => _Swatch(color: _palette[i], selected: selected == _palette[i], onTap: () => onTap(_palette[i])),
    )),
    ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: Row(children: [
          _Chip(label: '單色', selected: !gradient, onTap: () => _update(_t.copyWith(frame2: () => null))),
          const SizedBox(width: 8),
          _Chip(label: '漸層', selected: gradient, onTap: () {
            if (!gradient) _update(_t.copyWith(frame2: () => _palette[(_palette.indexOf(_t.frame) + 3) % _palette.length]));
          }),
        ]),
      ),
      swatches(gradient ? '上' : null, _t.frame, (c) => _update(_t.copyWith(frame: c))),
      if (gradient) ...[
        const SizedBox(height: 6),
        swatches('下', _t.frame2, (c) => _update(_t.copyWith(frame2: () => c))),
      ],
    ]);
  }

  /// Which window a shape goes to: null for all four.
  int? _cellTarget;

  /// The windows' shapes: for all four at once, or one at a time (pick it
  /// here or tap it on the strip).
  Widget _cellTool() {
    final shapes = _t.cellShapes;
    bool on(CellShape c) => _cellTarget == null ? shapes.every((s) => s == c) : shapes[_cellTarget!] == c;
    void apply(CellShape c) => _update(_t.copyWith(cellShapes: [
      for (var i = 0; i < 4; i++) _cellTarget == null || _cellTarget == i ? c : shapes[i],
    ]));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('哪一格', style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final (i, l) in [(null, '全部'), (0, '1'), (1, '2'), (2, '3'), (3, '4')]) Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Chip(label: l, selected: _cellTarget == i, onTap: () => setState(() => _cellTarget = i)),
            ),
          ]))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final (c, l) in _cells) _Chip(label: l, selected: on(c), onTap: () => apply(c))]),
      ]),
    );
  }

  Widget _chips(List<(String, bool, VoidCallback)> items) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Wrap(spacing: 8, runSpacing: 8, children: [for (final (l, s, f) in items) _Chip(label: l, selected: s, onTap: f)]),
  );

  Widget _textTool() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final (f, l) in _footers) ...[
          _Chip(label: l, selected: _t.footer == f, onTap: () => _update(_t.copyWith(footer: f))),
          const SizedBox(width: 6),
        ],
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _caption,
        maxLength: 18,
        onChanged: (v) => _update(_t.copyWith(caption: v.trim())),
        style: const TextStyle(fontSize: 15, color: ink),
        decoration: InputDecoration(
          isDense: true, filled: true, fillColor: cream, counterText: '',
          hintText: _t.footer == FooterStyle.logoDate ? '留空會顯示今天的日期' : '寫點什麼',
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: coral, width: 1.5)),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(height: 30, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _captionIdeas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            _caption.text = _captionIdeas[i];
            _update(_t.copyWith(caption: _captionIdeas[i]));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: blush, borderRadius: BorderRadius.circular(15)),
            child: Text(_captionIdeas[i], style: hand(17)),
          ),
        ),
      )),
    ]),
  );

  Widget _stickerTool() => StickerBookView(onPick: _addSticker, used: {for (final s in _t.stickers) s.sticker});
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
      width: 40, height: 40, padding: const EdgeInsets.all(3),
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
