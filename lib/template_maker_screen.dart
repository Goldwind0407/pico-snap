import 'package:flutter/material.dart';

import 'models.dart';
import 'services/my_library.dart';
import 'theme.dart';
import 'widgets/frames.dart';
import 'widgets/sticker_item.dart';

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

const _captionIdeas = ['my little day', 'best friends', 'happy birthday', 'say cheese!', 'good vibes'];

enum _Tab {
  start(Icons.auto_awesome_mosaic_outlined, '範本'),
  color(Icons.palette_outlined, '顏色'),
  pattern(Icons.grid_4x4_rounded, '圖案'),
  cell(Icons.crop_square_rounded, '照片格'),
  text(Icons.title_rounded, '文字'),
  sticker(Icons.emoji_emotions_outlined, '貼紙');

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
  late CustomTemplate _t = widget.initial ?? const CustomTemplate(id: '', caption: 'my little day', frame: Color(0xFFF9CACB));
  late final _caption = TextEditingController(text: _t.caption);
  final _canvasKey = GlobalKey();
  _Tab _tab = _Tab.color;
  int _pack = 0;
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

  void _addSticker(String id) {
    final n = _t.stickers.length;
    _update(_t.copyWith(stickers: [..._t.stickers, StickerData(sticker: id, center: Offset(.5 + (n % 3 - 1) * .2, .3 + (n % 4) * .12))]));
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
            IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close_rounded, color: ink)),
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
          child: FittedBox(child: PhotoStrip(template: strip, photos: samplePhotos)),
        )),
        for (var i = 0; i < _t.stickers.length; i++)
          StickerItem(
            data: _t.stickers[i],
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
      SizedBox(height: 150, child: switch (_tab) {
        _Tab.start => _startTool(),
        _Tab.color => _colorTool(),
        _Tab.pattern => _chips([for (final (p, l) in _patterns) (l, _t.pattern == p, () => _update(_t.copyWith(pattern: p)))]),
        _Tab.cell => _chips([for (final (c, l) in _cells) (l, _t.cellShape == c, () => _update(_t.copyWith(cellShape: c)))]),
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
    final starts = [for (final t in stripTemplates) if (t.art == null) t];
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

  Widget _stickerTool() {
    final mine = customStickers.isNotEmpty;
    // The user's own stickers come last so a built-in pack is shown first.
    final packs = [...stickerPacks, if (mine) ('📷', '我的', customStickers.keys.toList())];
    final pack = packs[_pack.clamp(0, packs.length - 1)].$3;
    return Column(children: [
      SizedBox(height: 44, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: packs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _Chip(label: '${packs[i].$1} ${packs[i].$2}', selected: _pack == i, onTap: () => setState(() => _pack = i)),
      )),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        itemCount: pack.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _addSticker(pack[i]),
          child: Container(
            width: 60, padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
            child: StickerVisual(pack[i]),
          ),
        ),
      )),
    ]);
  }
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
