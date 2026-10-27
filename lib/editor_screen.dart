import 'dart:math';
import 'dart:typed_data';

import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import 'cutout/cutout_page.dart';
import 'filters.dart';
import 'models.dart';
import 'services/photo_save_service.dart';
import 'services/timelapse_recorder.dart';
import 'theme.dart';
import 'widgets/frames.dart';
import 'widgets/instant_print.dart';
import 'widgets/sticker_item.dart';

enum _Tool {
  template(Icons.vertical_split_outlined, '模板'),
  layout(Icons.dashboard_customize_outlined, '版面'),
  pattern(Icons.grid_4x4_rounded, '底紋'),
  sticker(Icons.emoji_emotions_outlined, '貼紙'),
  text(Icons.title_rounded, '文字'),
  brush(Icons.brush_outlined, '畫筆'),
  cutout(Icons.content_cut_rounded, '去背'),
  filter(Icons.filter_vintage_outlined, '濾鏡'),
  /// Adjusting the selected photo; opened by tapping a photo, not a tab.
  photo(Icons.photo_outlined, '照片');

  /// Tools that are only placeholders for now.
  bool get comingSoon => this == brush;

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
  /// Photos (and Polaroid captions and film) to start with, e.g. from the
  /// instant camera.
  final List<Uint8List> photos;
  final List<String> captions;
  final List<FilmStock> films;
  final List<PhotoFilter> filters;
  const EditorScreen({super.key, this.mode = EditorMode.fourCut, this.template = 0, this.photos = const [], this.captions = const [], this.films = const [], this.filters = const []});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _picker = ImagePicker();
  final _canvasKey = GlobalKey();
  /// What gets saved: the canvas without the shadow around it.
  final _shotKey = GlobalKey();
  final _textCtrl = TextEditingController();
  late final int _cells = widget.mode == EditorMode.sticker ? 1 : 4;
  late final List<ImageProvider?> _photos = List<ImageProvider?>.filled(_cells, null);
  /// Original files of [_photos], for cutting out.
  late final List<Uint8List?> _photoBytes = List<Uint8List?>.filled(_cells, null);
  /// How each photo sits in its cell, and its width / height (for moving it).
  late final List<PhotoFit> _fits = List<PhotoFit>.filled(_cells, const PhotoFit());
  late final List<double?> _aspects = List<double?>.filled(_cells, null);
  /// Polaroid mode: white or black film per print.
  late final List<FilmStock> _films = [for (var i = 0; i < 4; i++) i < widget.films.length ? widget.films[i] : FilmStock.white];
  /// Filter per photo (photos only; frames and stickers aren't filtered).
  late final List<PhotoFilter> _filters = [for (var i = 0; i < _cells; i++) i < widget.filters.length ? widget.filters[i] : photoFilters.first];
  /// Sticker mode: the cut-out subject (PNG with a white die-cut border).
  Uint8List? _subject;
  /// While saving: hide hints, selection outlines and sticker handles.
  bool _capturing = false, _saving = false;
  /// Something was changed since opening or the last save.
  bool _edited = false;
  /// Records the editing for the timelapse video.
  final _recorder = TimelapseRecorder();
  bool _withVideo = true;
  final _polaroidCaptions = ['good day', 'little joy', 'sunny!', 'us ♡'];
  late int _template = widget.template;
  late String _category = allStripTemplates[widget.template].category;
  String? _stripCaption;
  String _bubble = 'DREAM';
  int _pack = 1;
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
    EditorMode.fourCut => allStripTemplates[_template].designSize.aspectRatio,
    EditorMode.polaroid => formats[_format].$2,
    EditorMode.sticker => 4 / 5,
  };

  String get _text => switch (widget.mode) {
    EditorMode.fourCut => _stripCaption ?? allStripTemplates[_template].caption,
    EditorMode.polaroid => _polaroidCaptions[_selectedCell],
    EditorMode.sticker => _bubble,
  };

  void _setText(String value) => setState(() {
    _edited = true;
    switch (widget.mode) {
      case EditorMode.fourCut: _stripCaption = value;
      case EditorMode.polaroid: _polaroidCaptions[_selectedCell] = value;
      case EditorMode.sticker: _bubble = value;
    }
  });

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.photos.length && i < _cells; i++) {
      _photoBytes[i] = widget.photos[i];
      _photos[i] = MemoryImage(widget.photos[i]);
      _measure(i);
    }
    for (var i = 0; i < widget.captions.length && i < _polaroidCaptions.length; i++) {
      _polaroidCaptions[i] = widget.captions[i];
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// Size of photo [i] as it is shown (EXIF orientation applied).
  void _measure(int i) {
    final image = _photos[i];
    if (image == null) return;
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (mounted && _photos[i] == image) setState(() => _aspects[i] = info.image.width / info.image.height);
    }, onError: (_, __) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  void _removePhoto() => setState(() {
    final i = _selectedCell;
    _photos[i] = null;
    _photoBytes[i] = null;
    _fits[i] = const PhotoFit();
    _aspects[i] = null;
    if (widget.mode == EditorMode.sticker) _subject = null;
    _edited = true;
    _tool = _tools.first;
  });

  Future<void> _pickPhoto([int? index]) async {
    final i = index ?? _selectedCell;
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (widget.mode != EditorMode.sticker) _tool = _Tool.photo;
    setState(() {
      _edited = true;
      _photos[i] = MemoryImage(bytes);
      _photoBytes[i] = bytes;
      _fits[i] = const PhotoFit();
      _aspects[i] = null;
      if (widget.mode == EditorMode.sticker) {
        // New photo: the old cut-out no longer matches; offer to cut this one.
        _subject = null;
        _tool = _Tool.cutout;
      }
    });
    _measure(i);
  }

  /// Sticker mode: cut the subject out of the photo.
  Future<void> _cutSubject() async {
    final bytes = _photoBytes[0];
    if (bytes == null) return _pickPhoto(0);
    final png = await CutoutPage.open(context, bytes, recorder: _recorder);
    if (png != null && mounted) {
      setState(() {
        _subject = png;
        _edited = true;
      });
    }
  }

  /// One timelapse frame: the canvas as it looks now (handles and all).
  Future<ui.Image?> _snapshot() async {
    final b = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (!mounted || b == null || !b.attached || b.size.isEmpty) return null;
    return b.toImage(pixelRatio: 1000 / b.size.longestSide);
  }

  /// Ask whether to save the timelapse too, then save.
  Future<void> _askSave() async {
    if (_saving) return;
    if (_photos.every((p) => p == null) && _subject == null) {
      return showMessage(context, '先放一張照片再儲存喔');
    }
    final canVideo = _recorder.frameCount >= 3;
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('存到相簿', style: TextStyle(fontSize: 19, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('作品圖片會存成高畫質 PNG。', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: canVideo ? () => setSheet(() => _withVideo = !_withVideo) : null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: canVideo && _withVideo ? blush : cream, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: canVideo && _withVideo ? blushLine : line),
              ),
              child: Row(children: [
                Icon(Icons.movie_filter_outlined, color: canVideo ? coral : muted),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('同時存「製作過程」縮時影片', style: TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(canVideo ? '你放照片、去背、貼貼紙的過程，約 ${_recorder.seconds} 秒，適合發 Reels、TikTok' : '多編輯一下就能做成影片',
                    style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                ])),
                Checkbox(value: canVideo && _withVideo, activeColor: coral, onChanged: canVideo ? (v) => setSheet(() => _withVideo = v ?? false) : null),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('存到相簿', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ]),
      ))),
    );
    if (go == true && mounted) await _save(video: canVideo && _withVideo);
  }

  Future<void> _save({bool video = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _capturing = true;
      _selectedSticker = null;
    });
    // Let the frame without hints and handles paint before capturing it.
    await WidgetsBinding.instance.endOfFrame;
    var error = await PhotoSaveService.saveBoundary(_shotKey);
    var saved = '已存到相簿 ♡';
    if (error == null && video) {
      // The clean finished piece ends the video.
      final finished = await _snapshot();
      if (mounted) setState(() => _capturing = false);
      final path = finished == null ? null : await _recorder.render(finished);
      error = path == null ? '圖片已存好，但縮時影片做不出來' : await PhotoSaveService.saveVideo(path);
      if (error == null) saved = '已存到相簿 ♡ 圖片和縮時影片';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _capturing = false;
      if (error == null) _edited = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? saved),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error == null ? ink : const Color(0xFFB4483C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  void _tapCell(int i) {
    setState(() {
      _selectedCell = i;
      _selectedSticker = null;
      _textCtrl.text = _text;
      if (_photos[i] != null) _tool = _Tool.photo;
    });
    if (_photos[i] == null) _pickPhoto(i);
  }

  /// The cell whose photo can be dragged and pinched right now.
  int? get _adjusting => !_capturing && _tool == _Tool.photo && _photos[_selectedCell] != null ? _selectedCell : null;

  void _setFit(int i, PhotoFit fit) => setState(() {
    _fits[i] = fit;
    _edited = true;
  });

  void _selectTool(_Tool tool) {
    if (tool.comingSoon) return showSoonToast(context, tool.label);
    setState(() {
      _tool = tool;
      if (tool == _Tool.text) _textCtrl.text = _text;
    });
  }

  void _remember() {
    _edited = true;
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
  Widget build(BuildContext context) {
    // Every rebuild means something changed: record it for the timelapse.
    if (!_capturing) WidgetsBinding.instance.addPostFrameCallback((_) => _recorder.request(_snapshot));
    return _scaffold();
  }

  Widget _scaffold() => PopScope(
    canPop: !_edited,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final navigator = Navigator.of(context);
      if (await confirmLeave(context, '還沒儲存的作品會不見喔。')) navigator.pop();
    },
    child: _page(),
  );

  Widget _page() => Scaffold(
    backgroundColor: cream,
    body: SafeArea(bottom: false, child: Column(children: [
      _topBar(),
      Expanded(child: Stack(children: [
        // Hand-drawn doodles beside the narrow strip (wider canvases cover them).
        if (widget.mode == EditorMode.fourCut) ...const [
          Positioned(right: 54, top: 30, child: Sparkle(size: 22)),
          Positioned(left: 40, bottom: 70, child: Sparkle(size: 24, fill: Color(0xFFF7D77C))),
          Positioned(left: 64, bottom: 52, child: Sparkle(size: 13)),
          Positioned(left: 58, bottom: 96, child: DoodleHeart(size: 13, color: Color(0xFFE8C6F0))),
        ],
        Positioned.fill(child: Padding(padding: const EdgeInsets.fromLTRB(28, 12, 28, 16), child: _canvas())),
        Positioned(right: 18, bottom: 16, child: _RoundButton(icon: Icons.undo_rounded, onTap: _history.isEmpty ? null : _undo)),
      ])),
      _sheet(),
    ])),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
    child: Row(children: [
      IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
      Expanded(child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
      if (widget.mode == EditorMode.fourCut) ...[
        _TopButton(label: '匯入', onTap: () => _pickPhoto()),
        const SizedBox(width: 8),
      ],
      _TopButton(label: _saving ? '儲存中…' : '儲存', filled: true, onTap: _askSave),
    ]),
  );

  Widget _canvas() => Center(child: AspectRatio(aspectRatio: _aspect, child: LayoutBuilder(builder: (context, c) {
    final size = c.biggest;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 8))]),
      child: RepaintBoundary(key: _shotKey, child: Stack(key: _canvasKey, clipBehavior: Clip.none, children: [
        Positioned.fill(child: GestureDetector(
          onTap: () => setState(() => _selectedSticker = null),
          child: _artwork(size),
        )),
        for (var i = 0; i < _stickers.length; i++)
          StickerItem(
            data: _stickers[i],
            canvas: size,
            selected: !_capturing && _selectedSticker == i,
            toLocal: _toCanvas,
            onSelect: () => setState(() => _selectedSticker = i),
            onEditStart: () => setState(() {
              _remember();
              _selectedSticker = i;
            }),
            onChanged: (d) => setState(() => _stickers[i] = d),
            onFlip: () => setState(() {
              _remember();
              _stickers[i] = _stickers[i].copyWith(flipped: !_stickers[i].flipped);
            }),
            onDelete: () => setState(() {
              _remember();
              _stickers.removeAt(i);
              _selectedSticker = null;
            }),
          ),
      ])),
    );
  })));

  Widget _artwork(Size size) => switch (widget.mode) {
    EditorMode.fourCut => FittedBox(child: PhotoStrip(
      template: allStripTemplates[_template], photos: _photos, caption: _stripCaption,
      placeholder: _capturing ? null : const AddPhotoHint(scale: 1.4), selected: _capturing ? null : _selectedCell, onTapCell: _tapCell,
      fits: _fits, aspects: _aspects, adjusting: _adjusting, onFit: _setFit, filters: _filters,
    )),
    EditorMode.polaroid => _polaroidArtwork(size),
    EditorMode.sticker => _stickerArtwork(),
  };

  Widget _polaroidArtwork(Size size) {
    final w = min(size.width * .37, size.height * .26);
    final h = w * InstantPrint.height / InstantPrint.width;
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
            child: Transform.rotate(angle: _scatter[i].$2, child: FittedBox(child: SizedBox(
              width: InstantPrint.width, height: InstantPrint.height,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .16), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: InstantPrint(
                    image: _photos[i], film: _films[i], caption: _polaroidCaptions[i],
                    placeholder: _capturing ? null : const AddPhotoHint(scale: 1.3),
                    selected: !_capturing && _selectedCell == i, onTap: () => _tapCell(i),
                    onCaption: () => setState(() {
                      _selectedCell = i;
                      _tool = _Tool.text;
                      _textCtrl.text = _polaroidCaptions[i];
                    }),
                    fit: _fits[i], aspect: _aspects[i], onFit: _adjusting == i ? (f) => _setFit(i, f) : null, filter: _filters[i],
                  ),
                )),
                Positioned(top: -4, left: i.isOdd ? null : -22, right: i.isOdd ? -22 : null,
                  child: WashiTape(width: 64, height: 22, angle: i.isOdd ? .75 : -.75, colors: _tapes[i])),
              ]),
            ))),
          ),
      ]),
    );
  }

  Widget _stickerArtwork() => CustomPaint(
    painter: GinghamPainter(ginghamPatterns[_pattern].base, ginghamPatterns[_pattern].right),
    child: Stack(children: [
      if (_subject != null)
        // The cut-out subject, with a soft shadow under its white border.
        Positioned.fill(child: FractionallySizedBox(widthFactor: .88, heightFactor: .84, alignment: const Alignment(0, .3), child: GestureDetector(
          onTap: () => setState(() => _tool = _Tool.cutout),
          child: Stack(fit: StackFit.expand, children: [
            Transform.translate(offset: const Offset(0, 4), child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x40000000), BlendMode.srcIn), child: Image.memory(_subject!, fit: BoxFit.contain, gaplessPlayback: true)),
            )),
            Image.memory(_subject!, fit: BoxFit.contain, gaplessPlayback: true),
          ]),
        )))
      else ...[
        // White die-cut border behind the photo.
        Positioned.fill(child: FractionallySizedBox(widthFactor: .84, heightFactor: .78, child: PhysicalShape(
          clipper: const BlobClipper(phase: 1.3), color: Colors.white, elevation: 5, shadowColor: ink.withValues(alpha: .5),
          child: const SizedBox.expand(),
        ))),
        Positioned.fill(child: FractionallySizedBox(widthFactor: .76, heightFactor: .70, child: ClipPath(
          clipper: const BlobClipper(phase: 1.3),
          child: PhotoSlot(
            image: _photos[0], color: const Color(0xFFFFF6F2), outlineWidth: 0, placeholder: _capturing ? null : const AddPhotoHint(scale: 1.3), onTap: () => _tapCell(0),
            fit: _fits[0], aspect: _aspects[0], onFit: _adjusting == 0 ? (f) => _setFit(0, f) : null,
          ),
        ))),
      ],
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
        _Tool.cutout => _cutoutTool(),
        _Tool.photo => _photoTool(),
        _Tool.filter => _filterTool(),
        _Tool.text || _Tool.brush => _textTool(),
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
    final visible = [for (var i = 0; i < allStripTemplates.length; i++) if (allStripTemplates[i].category == _category) i];
    return Column(children: [
      _CategoryRow(labels: [if (customTemplates.isNotEmpty) myCategory, ...stripCategories], selected: _category, onTap: (c) => setState(() => _category = c)),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, k) {
          final i = visible[k];
          return _TemplateThumb(template: allStripTemplates[i], selected: _template == i, onTap: () => setState(() => _template = i));
        },
      )),
    ]);
  }

  Widget _layoutTool() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
      const SizedBox(width: 44, child: Text('比例', style: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800))),
      Expanded(child: Container(
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
                  style: TextStyle(fontSize: 14, color: ink, fontWeight: _format == i ? FontWeight.w900 : FontWeight.w600)),
              ),
            )),
        ]),
      )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        const SizedBox(width: 44, child: Text('背景', style: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800))),
        for (var i = 0; i < backdrops.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => _backdrop = i),
              child: Container(
                width: 36, height: 36, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _backdrop == i ? outline.withValues(alpha: .6) : Colors.transparent, width: 2)),
                child: Container(decoration: BoxDecoration(color: backdrops[i].$2, shape: BoxShape.circle, border: Border.all(color: line, width: 1.3))),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        const SizedBox(width: 44, child: Text('底片', style: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800))),
        for (final f in FilmStock.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                for (var i = 0; i < _films.length; i++) {
                  _films[i] = f;
                }
                _edited = true;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _films.every((x) => x == f) ? blush : cream, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _films.every((x) => x == f) ? blushLine : line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 11, height: 13, decoration: BoxDecoration(color: f.swatch, borderRadius: BorderRadius.circular(2), border: Border.all(color: line))),
                  const SizedBox(width: 6),
                  Text(f.label, style: TextStyle(fontSize: 13, color: ink, fontWeight: _films.every((x) => x == f) ? FontWeight.w900 : FontWeight.w600)),
                ]),
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
    final packs = [('📷', '我的', customStickers.keys.toList()), ...stickerPacks];
    final mine = _pack == 0;
    final pack = packs[_pack].$3;
    return Column(children: [
      SizedBox(height: 46, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: packs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (icon, label, _) = packs[i];
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
      if (mine && pack.isEmpty)
        const Expanded(child: Center(child: Text('還沒有自己的貼紙\n可以到首頁的「我的」把照片做成貼紙', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.6, color: muted, fontWeight: FontWeight.w600))))
      else Expanded(child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6),
        itemCount: pack.length,
        itemBuilder: (_, k) => InkWell(
          onTap: () => _addSticker(pack[k]),
          child: Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: line), right: BorderSide(color: line))),
            padding: const EdgeInsets.all(9),
            child: StickerVisual(pack[k]),
          ),
        ),
      )),
    ]);
  }

  void _setFilter(PhotoFilter f, {bool all = false}) => setState(() {
    for (var i = 0; i < _filters.length; i++) {
      if (all || i == _selectedCell) _filters[i] = f;
    }
    _edited = true;
  });

  Widget _filterTool() {
    final cell = _selectedCell.clamp(0, _cells - 1);
    final ImageProvider image = _photos[cell] ?? _photos.firstWhere((p) => p != null, orElse: () => null) ?? samplePhotos.first;
    final current = _filters[cell];
    final allSame = _filters.every((f) => f.id == current.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
        child: Row(children: [
          Expanded(child: Text(_cells > 1 ? '第 ${cell + 1} 張照片的濾鏡' : '照片濾鏡',
            style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800))),
          if (_cells > 1)
            TextButton(
              onPressed: allSame ? null : () => _setFilter(current, all: true),
              style: TextButton.styleFrom(foregroundColor: coral, visualDensity: VisualDensity.compact),
              child: Text(allSame ? '已套用到全部' : '套用到全部照片', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        itemCount: photoFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = photoFilters[i];
          final on = f.id == current.id;
          return GestureDetector(
            onTap: () => _setFilter(f),
            child: Column(children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? coral : Colors.transparent, width: 2.5)),
                padding: const EdgeInsets.all(2),
                child: ClipRRect(borderRadius: BorderRadius.circular(9), child: FilterLayer(filter: f, child: Image(image: image, fit: BoxFit.cover, width: 60, height: 60, gaplessPlayback: true))),
              ),
              const SizedBox(height: 4),
              Text(f.name, style: TextStyle(fontSize: 11, color: on ? ink : muted, fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
            ]),
          );
        },
      )),
    ]);
  }

  Widget _photoTool() {
    Widget button(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => Expanded(child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? const Color(0xFFB4483C) : ink, backgroundColor: cream,
        side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.mode == EditorMode.sticker ? '照片' : '第 ${_selectedCell + 1} 張照片', style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('在照片上拖曳可以移動，兩指可以放大縮小', style: TextStyle(fontSize: 12, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600)),
        const Spacer(),
        Row(children: [
          button(Icons.swap_horiz_rounded, '換照片', () => _pickPhoto()),
          const SizedBox(width: 8),
          button(Icons.center_focus_strong_outlined, '置中', () => _setFit(_selectedCell, const PhotoFit())),
          const SizedBox(width: 8),
          button(Icons.delete_outline_rounded, '移除', _removePhoto, danger: true),
        ]),
      ]),
    );
  }

  Widget _cutoutTool() {
    final hasPhoto = _photoBytes[0] != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('去背', style: TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          hasPhoto
            ? '先用手機內建 AI 去背，認不出來會改用手動去背；也可以自己換方法、用筆刷修邊。'
            : '先放一張照片，再把人或東西去背，做成貼紙。',
          style: TextStyle(fontSize: 12, height: 1.4, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: _cutSubject,
            icon: Icon(hasPhoto ? Icons.content_cut_rounded : Icons.add_photo_alternate_outlined, size: 18),
            label: Text(!hasPhoto ? '選照片' : _subject == null ? '開始去背' : '重新去背', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )),
          if (_subject != null) ...[
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => setState(() => _subject = null),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('還原照片', style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink, side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
          ],
        ]),
      ]),
    );
  }

  Widget _textTool() => widget.mode == EditorMode.fourCut && allStripTemplates[_template].art != null
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
