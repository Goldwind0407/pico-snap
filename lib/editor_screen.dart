import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'theme.dart';
import 'widgets/frames.dart';
import 'widgets/sticker_item.dart';

enum _Tool {
  template(Icons.vertical_split_outlined, '模板'),
  layout(Icons.dashboard_customize_outlined, '版面'),
  pattern(Icons.grid_4x4_rounded, '底紋'),
  sticker(Icons.emoji_emotions_outlined, '貼紙'),
  text(Icons.title_rounded, '文字'),
  brush(Icons.brush_outlined, '畫筆'),
  cutout(Icons.content_cut_rounded, '去背'),
  filter(Icons.filter_vintage_outlined, '濾鏡');

  /// Tools that are only placeholders for now.
  bool get comingSoon => this == brush || this == cutout || this == filter;

  final IconData icon;
  final String label;
  const _Tool(this.icon, this.label);
}

const _captionIdeas = ['cute caption ♡', 'best day ever', 'say cheese!', 'us ♡', 'good vibes'];

// Polaroid centres (normalised) and tilt, zig-zagging down the page like a photo album.
const _scatter = [(Offset(.31, .22), -.07), (Offset(.69, .38), .06), (Offset(.32, .61), -.05), (Offset(.68, .80), .07)];
const _tapes = [
  [Color(0xFFB9C9AE), Color(0xFFE3EBD9)],
  [Color(0xFFF4B183), Color(0xFFFCE3CF)],
  [Color(0xFFF59E95), Color(0xFFFFD9D4)],
  [Color(0xFF9FC3DE), Color(0xFFDDEBF5)],
];

class EditorScreen extends StatefulWidget {
  final EditorMode mode;
  final int template;
  const EditorScreen({super.key, this.mode = EditorMode.fourCut, this.template = 0});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _picker = ImagePicker();
  final _canvasKey = GlobalKey();
  final _textCtrl = TextEditingController();
  late final List<ImageProvider?> _photos = List<ImageProvider?>.filled(widget.mode == EditorMode.sticker ? 1 : 4, null);
  final _polaroidCaptions = ['good day', 'little joy', 'sunny!', 'us ♡'];
  late int _template = widget.template;
  late String _category = stripTemplates[widget.template].category;
  String? _stripCaption;
  String _bubble = 'DREAM';
  int _pack = 0;
  int _pattern = 0, _backdrop = 1, _format = 3, _selectedCell = 0;
  List<StickerData> _stickers = [];
  final List<List<StickerData>> _history = [];
  int? _selectedSticker;
  late _Tool _tool = _tools.first;

  List<_Tool> get _tools => switch (widget.mode) {
    EditorMode.fourCut => const [_Tool.template, _Tool.sticker, _Tool.text, _Tool.filter],
    EditorMode.polaroid => const [_Tool.layout, _Tool.sticker, _Tool.text, _Tool.filter],
    EditorMode.sticker => const [_Tool.sticker, _Tool.pattern, _Tool.text, _Tool.brush, _Tool.cutout],
  };

  String get _title => switch (widget.mode) {
    EditorMode.fourCut => 'Four Cut',
    EditorMode.polaroid => 'Polaroid',
    EditorMode.sticker => 'Sticker Editor',
  };

  double get _aspect => switch (widget.mode) {
    EditorMode.fourCut => stripTemplates[_template].designSize.aspectRatio,
    EditorMode.polaroid => formats[_format].$2,
    EditorMode.sticker => 4 / 5,
  };

  String get _text => switch (widget.mode) {
    EditorMode.fourCut => _stripCaption ?? stripTemplates[_template].caption,
    EditorMode.polaroid => _polaroidCaptions[_selectedCell],
    EditorMode.sticker => _bubble,
  };

  void _setText(String value) => setState(() {
    switch (widget.mode) {
      case EditorMode.fourCut: _stripCaption = value;
      case EditorMode.polaroid: _polaroidCaptions[_selectedCell] = value;
      case EditorMode.sticker: _bubble = value;
    }
  });

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto([int? index]) async {
    final i = index ?? _selectedCell;
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _photos[i] = MemoryImage(bytes));
  }

  void _tapCell(int i) {
    setState(() {
      _selectedCell = i;
      _selectedSticker = null;
      _textCtrl.text = _text;
    });
    _pickPhoto(i);
  }

  void _selectTool(_Tool tool) {
    if (tool.comingSoon) return showSoonToast(context, tool.label);
    setState(() {
      _tool = tool;
      if (tool == _Tool.text) _textCtrl.text = _text;
    });
  }

  void _remember() {
    _history.add(List.of(_stickers));
    if (_history.length > 30) _history.removeAt(0);
  }

  void _addSticker(String sticker) => setState(() {
    _remember();
    final n = _stickers.length;
    _stickers = [..._stickers, StickerData(sticker: sticker, center: Offset(.5 + (n % 3 - 1) * .14, .4 + (n % 2) * .12))];
    _selectedSticker = _stickers.length - 1;
  });

  void _undo() => setState(() {
    _stickers = _history.removeLast();
    _selectedSticker = null;
  });

  Offset _toCanvas(Offset global) => (_canvasKey.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(bottom: false, child: Column(children: [
      _topBar(),
      Expanded(child: Stack(children: [
        // Hand-drawn doodles scattered around the artwork.
        const Positioned(right: 54, top: 30, child: Sparkle(size: 22)),
        const Positioned(left: 40, bottom: 70, child: Sparkle(size: 24, fill: Color(0xFFF7D77C))),
        const Positioned(left: 64, bottom: 52, child: Sparkle(size: 13)),
        const Positioned(left: 58, bottom: 96, child: DoodleHeart(size: 13, color: Color(0xFFE8C6F0))),
        Positioned.fill(child: Padding(padding: const EdgeInsets.fromLTRB(28, 12, 28, 16), child: _canvas())),
        Positioned(right: 18, bottom: 16, child: _RoundButton(icon: Icons.undo_rounded, onTap: _history.isEmpty ? null : _undo)),
      ])),
      _sheet(),
    ])),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
    child: Row(children: [
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
      Expanded(child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
      if (widget.mode == EditorMode.fourCut) ...[
        _TopButton(label: '匯入', onTap: () => _pickPhoto()),
        const SizedBox(width: 8),
      ],
      _TopButton(label: '儲存', filled: true, onTap: () => showSoonToast(context, '儲存作品')),
    ]),
  );

  Widget _canvas() => Center(child: AspectRatio(aspectRatio: _aspect, child: LayoutBuilder(builder: (context, c) {
    final size = c.biggest;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Stack(key: _canvasKey, clipBehavior: Clip.none, children: [
        Positioned.fill(child: GestureDetector(
          onTap: () => setState(() => _selectedSticker = null),
          child: _artwork(size),
        )),
        for (var i = 0; i < _stickers.length; i++)
          StickerItem(
            data: _stickers[i],
            canvas: size,
            selected: _selectedSticker == i,
            toLocal: _toCanvas,
            onSelect: () => setState(() => _selectedSticker = i),
            onEditStart: () => setState(() {
              _remember();
              _selectedSticker = i;
            }),
            onChanged: (d) => setState(() => _stickers[i] = d),
            onDelete: () => setState(() {
              _remember();
              _stickers.removeAt(i);
              _selectedSticker = null;
            }),
          ),
      ]),
    );
  })));

  Widget _artwork(Size size) => switch (widget.mode) {
    EditorMode.fourCut => FittedBox(child: PhotoStrip(
      template: stripTemplates[_template], photos: _photos, caption: _stripCaption,
      placeholder: const AddPhotoHint(scale: 1.4), selected: _selectedCell, onTapCell: _tapCell,
    )),
    EditorMode.polaroid => _polaroidArtwork(size),
    EditorMode.sticker => _stickerArtwork(),
  };

  Widget _polaroidArtwork(Size size) {
    final w = min(size.width * .37, size.height * .26);
    final h = w * PolaroidCard.height / PolaroidCard.width;
    // Draw the selected print last so it sits on top.
    final order = [for (var i = 0; i < 4; i++) if (i != _selectedCell) i, _selectedCell];
    Widget doodle(double x, double y, Widget child) => Positioned(left: x * size.width, top: y * size.height, child: child);
    return Container(
      color: backdrops[_backdrop].$2,
      child: Stack(children: [
        doodle(.62, .07, const Sparkle(size: 16)),
        doodle(.70, .11, const Sparkle(size: 10)),
        doodle(.84, .17, const DoodleHeart(size: 13)),
        doodle(.08, .40, const Sparkle(size: 14, fill: Color(0xFFF7D77C))),
        doodle(.85, .55, const Sparkle(size: 16, fill: Color(0xFFF7D77C))),
        doodle(.78, .60, const Sparkle(size: 11, fill: Color(0xFFD9C3F0))),
        doodle(.55, .53, const DoodleHeart(size: 11, color: Color(0xFFD9C3F0))),
        doodle(.10, .86, const DoodleHeart(size: 13)),
        for (final i in order)
          Positioned(
            left: _scatter[i].$1.dx * size.width - w / 2, top: _scatter[i].$1.dy * size.height - h / 2, width: w, height: h,
            child: Transform.rotate(angle: _scatter[i].$2, child: FittedBox(child: PolaroidCard(
              image: _photos[i], caption: _polaroidCaptions[i], color: const [blush, lilac, butter, sky][i],
              placeholder: const AddPhotoHint(scale: 1.3), tape: _tapes[i], tapeRight: i.isOdd,
              selected: _selectedCell == i, onTap: () => _tapCell(i),
            ))),
          ),
      ]),
    );
  }

  Widget _stickerArtwork() => CustomPaint(
    painter: GinghamPainter(ginghamPatterns[_pattern].base, ginghamPatterns[_pattern].right),
    child: Stack(children: [
      // White die-cut border behind the photo.
      Positioned.fill(child: FractionallySizedBox(widthFactor: .84, heightFactor: .78, child: PhysicalShape(
        clipper: const BlobClipper(phase: 1.3), color: Colors.white, elevation: 5, shadowColor: ink.withValues(alpha: .5),
        child: const SizedBox.expand(),
      ))),
      Positioned.fill(child: FractionallySizedBox(widthFactor: .76, heightFactor: .70, child: ClipPath(
        clipper: const BlobClipper(phase: 1.3),
        child: PhotoSlot(image: _photos[0], color: const Color(0xFFFFF6F2), outlineWidth: 0, placeholder: const AddPhotoHint(scale: 1.3), onTap: () => _tapCell(0)),
      ))),
      if (_bubble.isNotEmpty)
        Positioned(right: 14, top: 14, child: Transform.rotate(angle: .06, child: SpeechBubble(_bubble))),
    ]),
  );

  Widget _sheet() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 20, offset: const Offset(0, -4))],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      Container(width: 38, height: 4, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(2))),
      SizedBox(height: 168, child: switch (_tool) {
        _Tool.template => _templateTool(),
        _Tool.layout => _layoutTool(),
        _Tool.pattern => _patternTool(),
        _Tool.sticker => _stickerTool(),
        _Tool.text || _Tool.brush || _Tool.cutout || _Tool.filter => _textTool(),
      }),
      Container(
        decoration: BoxDecoration(
          color: cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, -3))],
        ),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            for (final t in _tools) Expanded(child: _ToolTab(tool: t, selected: _tool == t, onTap: () => _selectTool(t))),
          ]),
        )),
      ),
    ]),
  );

  Widget _templateTool() {
    final visible = [for (var i = 0; i < stripTemplates.length; i++) if (stripTemplates[i].category == _category) i];
    return Column(children: [
      _CategoryRow(labels: stripCategories, selected: _category, onTap: (c) => setState(() => _category = c)),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, k) {
          final i = visible[k];
          return _TemplateThumb(template: stripTemplates[i], selected: _template == i, onTap: () => setState(() => _template = i));
        },
      )),
    ]);
  }

  Widget _layoutTool() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('比例', style: TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(16), border: Border.all(color: line, width: 1.3)),
        child: Row(children: [
          for (var i = 0; i < formats.length; i++)
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _format = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: _format == i ? blush : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                child: Text(formats[i].$1, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: ink, fontWeight: _format == i ? FontWeight.w900 : FontWeight.w600)),
              ),
            )),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        const Text('背景', style: TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800)),
        const Spacer(),
        for (var i = 0; i < backdrops.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: GestureDetector(
              onTap: () => setState(() => _backdrop = i),
              child: Container(
                width: 40, height: 40, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _backdrop == i ? outline.withValues(alpha: .6) : Colors.transparent, width: 2)),
                child: Container(decoration: BoxDecoration(color: backdrops[i].$2, shape: BoxShape.circle, border: Border.all(color: line, width: 1.3))),
              ),
            ),
          ),
      ]),
    ]),
  );

  Widget _patternTool() => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(22, 30, 22, 10),
    itemCount: ginghamPatterns.length,
    separatorBuilder: (_, __) => const SizedBox(width: 18),
    itemBuilder: (_, i) {
      final p = ginghamPatterns[i];
      final selected = _pattern == i;
      return GestureDetector(
        onTap: () => setState(() => _pattern = i),
        child: Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? coral : outline.withValues(alpha: .4), width: selected ? 3 : 1.2),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(13), child: CustomPaint(painter: GinghamPainter(p.base, p.right))),
          ),
          const SizedBox(height: 8),
          Text(p.name, style: hand(18, color: selected ? ink : muted)),
        ]),
      );
    },
  );

  Widget _stickerTool() {
    final pack = stickerPacks[_pack].$3;
    return Column(children: [
      SizedBox(height: 46, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: stickerPacks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (icon, label, _) = stickerPacks[i];
          final selected = _pack == i;
          return GestureDetector(
            onTap: () => setState(() => _pack = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? blush : cream, borderRadius: BorderRadius.circular(17),
                border: Border.all(color: selected ? blushLine : line),
              ),
              child: Text('$icon $label', style: TextStyle(fontSize: 13, color: ink, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
            ),
          );
        },
      )),
      Expanded(child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6),
        itemCount: pack.length,
        itemBuilder: (_, i) => InkWell(
          onTap: () => _addSticker(pack[i]),
          child: Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: line), right: BorderSide(color: line))),
            padding: const EdgeInsets.all(9),
            child: StickerVisual(pack[i]),
          ),
        ),
      )),
    ]);
  }

  Widget _textTool() => widget.mode == EditorMode.fourCut && stripTemplates[_template].art != null
    ? Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text('這款模板的文字是印好的，可以用貼紙裝飾，或換一款模板來寫字。', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: muted.withValues(alpha: .9), fontWeight: FontWeight.w700)),
      ))
    : Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(switch (widget.mode) {
        EditorMode.fourCut => '拍貼底部的手寫字',
        EditorMode.polaroid => '第 ${_selectedCell + 1} 張拍立得的手寫字',
        EditorMode.sticker => '對話泡泡',
      }, style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      TextField(
        controller: _textCtrl,
        maxLength: 20,
        onChanged: _setText,
        style: hand(24),
        decoration: InputDecoration(
          isDense: true, filled: true, fillColor: cream, counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: coral, width: 1.5)),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(height: 34, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _captionIdeas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            _textCtrl.text = _captionIdeas[i];
            _setText(_captionIdeas[i]);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: blush, borderRadius: BorderRadius.circular(17)),
            child: Text(_captionIdeas[i], style: hand(18)),
          ),
        ),
      )),
    ]),
  );
}

class _CategoryRow extends StatelessWidget {
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onTap;
  const _CategoryRow({required this.labels, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(height: 46, child: Row(children: [
    for (final l in labels)
      Expanded(child: GestureDetector(
        onTap: () => onTap(l),
        behavior: HitTestBehavior.opaque,
        child: Center(child: Text(l, style: TextStyle(
          fontSize: 17, color: l == selected ? ink : muted.withValues(alpha: .8), fontWeight: l == selected ? FontWeight.w900 : FontWeight.w700,
        ))),
      )),
  ]));
}

class _TemplateThumb extends StatelessWidget {
  final StripTemplate template;
  final bool selected;
  final VoidCallback onTap;
  const _TemplateThumb({required this.template, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 84,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? coral : Colors.transparent, width: 2.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(color: cream, child: FittedBox(child: PhotoStrip(template: template))),
      ),
    ),
  );
}

class _ToolTab extends StatelessWidget {
  final _Tool tool;
  final bool selected;
  final VoidCallback onTap;
  const _ToolTab({required this.tool, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? ink : muted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: selected ? blush : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(tool.icon, size: 24, color: color),
          const SizedBox(height: 3),
          Text(tool.label, style: TextStyle(fontSize: 12, color: color, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ]),
      )),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 10, offset: const Offset(0, 3))]),
    child: Material(
      color: Colors.white, shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap, customBorder: const CircleBorder(),
        child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 22, color: onTap == null ? line : ink)),
      ),
    ),
  );
}

class _TopButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _TopButton({required this.label, this.filled = false, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: filled ? coral : Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: filled ? BorderSide.none : const BorderSide(color: line, width: 1.3)),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Text(label, style: TextStyle(fontSize: 14, color: filled ? Colors.white : ink, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}
