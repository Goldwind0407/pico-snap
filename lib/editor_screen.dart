import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import 'collage_templates.dart';
import 'cutout/cutout_page.dart';
import 'cutout/photo_sticker.dart';
import 'cutout/sticker_shape.dart';
import 'filters.dart';
import 'editor_document.dart';
import 'gallery_screen.dart';
import 'services/editor_drafts.dart';
import 'services/my_library.dart';
import 'models.dart';
import 'services/my_works.dart';
import 'services/photo_save_service.dart';
import 'services/timelapse_recorder.dart';
import 'theme.dart';
import 'widgets/backdrop.dart';
import 'widgets/collage_layout.dart';
import 'widgets/doodle.dart';
import 'widgets/filter_thumbs.dart';
import 'widgets/frames.dart';
import 'widgets/instant_print.dart';
import 'widgets/page_texture.dart';
import 'widgets/print_item.dart';
import 'widgets/sticker_book_view.dart';
import 'widgets/sticker_item.dart';

enum _Tool {
  template(CupertinoIcons.square_split_1x2, '模板'),
  layout(CupertinoIcons.square_grid_2x2, '版面'),
  backdrop(CupertinoIcons.square_stack_3d_down_right, '背景'),
  sticker(CupertinoIcons.smiley, '貼紙'),
  text(CupertinoIcons.textformat, '文字'),
  brush(CupertinoIcons.paintbrush, '畫筆'),
  cutout(CupertinoIcons.scissors, '去背'),
  /// 照片貼紙: the border, finish and motion of the cut-out stickers.
  effect(CupertinoIcons.sparkles, '效果'),
  film(CupertinoIcons.film, '底片'),
  filter(CupertinoIcons.color_filter, '濾鏡'),
  /// Adjusting the selected photo; opened by tapping a photo, not a tab.
  photo(CupertinoIcons.photo, '照片');

  final IconData icon;
  final String label;
  const _Tool(this.icon, this.label);
}

const _captionIdeas = ['cute caption ♡', 'best day ever', 'say cheese!', 'us ♡', 'good vibes'];

const _tapes = [
  [Color(0xFFB9C9AE), Color(0xFFE3EBD9)],
  [Color(0xFFF4B183), Color(0xFFFCE3CF)],
  [Color(0xFFF59E95), Color(0xFFFFD9D4)],
  [Color(0xFF9FC3DE), Color(0xFFDDEBF5)],
  [Color(0xFFD3B8E8), Color(0xFFF0E6F8)],
  [Color(0xFFF2D27A), Color(0xFFFBF0CF)],
];

class EditorScreen extends StatefulWidget {
  final EditorDocument? draft;
  final String? draftId;
  final EditorMode mode;
  final int template;
  /// Photos (and Polaroid captions and film) to start with, e.g. from the
  /// instant camera.
  final List<Uint8List> photos;
  final List<String> captions;
  /// Finger writing on each Polaroid's bottom border.
  final List<List<Stroke>> handwriting;
  final List<FilmStock> films;
  final List<PhotoFilter> filters;
  /// Opened to decorate a finished piece: starts on the stickers.
  final bool decorate;
  /// The piece as it opens is already in the gallery: leaving it untouched
  /// keeps no draft.
  final bool saved;
  const EditorScreen({super.key, this.draft, this.draftId, this.mode = EditorMode.fourCut, this.template = 0, this.photos = const [], this.captions = const [], this.handwriting = const [], this.films = const [], this.filters = const [], this.decorate = false, this.saved = false});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  final _canvasKey = GlobalKey();
  /// What gets saved: the canvas without the shadow around it.
  final _shotKey = GlobalKey();
  final _textCtrl = TextEditingController();
  late final int _cells = EditorDocument.cellsOf(widget.mode);
  late final List<ImageProvider?> _photos = List<ImageProvider?>.filled(_cells, null);
  /// Original files of [_photos], for cutting out.
  late final List<Uint8List?> _photoBytes = List<Uint8List?>.filled(_cells, null);
  /// How each photo sits in its cell, and its width / height (for moving it).
  late final List<PhotoFit> _fits = List<PhotoFit>.filled(_cells, const PhotoFit());
  late final List<double?> _aspects = List<double?>.filled(_cells, null);
  /// Polaroid mode: the film of each print.
  late final List<FilmStock> _films = [for (var i = 0; i < max(4, _cells); i++) i < widget.films.length ? widget.films[i] : FilmStock.white];
  /// 拍立得拼貼: how many prints show (1–6), and how they lie.
  late int _count = widget.photos.length > 4 ? min(6, widget.photos.length) : 4;
  CollageArrangement _arrangement = CollageArrangement.scatter;
  BackdropPattern _backdropPattern = BackdropPattern.plain;
  /// Where each print was moved to; null: where the arrangement puts it.
  final List<PrintPlace?> _places = List.filled(6, null);
  /// Moving the photo inside the chosen print rather than the print.
  bool _cropping = false;
  /// A background photo of its own (else the first print's), and whether
  /// it is blurred.
  Uint8List? _backdropBytes;
  ImageProvider? _backdropImage;
  bool _backdropBlur = true;
  /// A built-in background picture, when one is chosen.
  String? _backdropScene;
  /// The look over the whole page, and the filter tab showing it rather
  /// than the photo filters.
  PageTexture _texture = PageTexture.none;
  double _textureStrength = .7;
  bool _pageLook = false;
  /// Snapping guides shown while a print moves.
  List<double> _guideX = const [], _guideY = const [];
  /// Where tapping a photo came from: closing the photo tool goes back there.
  _Tool? _backTool;
  /// Filter per photo (photos only; frames and stickers aren't filtered).
  late final List<PhotoFilter> _filters = [for (var i = 0; i < _cells; i++) i < widget.filters.length ? widget.filters[i] : photoFilters.first];
  /// Sticker mode: the cut-out subject (PNG with a white die-cut border).
  /// Pieces from before 照片貼紙 only; it becomes a photo sticker.
  Uint8List? _subject;
  /// 照片貼紙: the stickers cut out of photos, by sticker id; a cutting line
  /// around each; no background.
  Map<String, PhotoSticker> _cutouts = const {};
  bool _cutLines = false, _clearPage = false;
  /// Cutting photos out right now: what to say meanwhile.
  String? _cutting;
  /// While saving: hide hints, selection outlines and sticker handles.
  bool _capturing = false, _saving = false;
  /// What the piece looked like when opened or last saved.
  Object? _savedKey;
  /// What the timelapse last recorded.
  Object? _recordedKey;

  /// Compare edit values so restoring a checkpoint also restores the saved
  /// state. Immutable photo bytes retain their identity across checkpoints.
  Object _contentKey() => Object.hashAll([
    Object.hashAll(_photoBytes), Object.hashAll(_fits.map((f) => Object.hash(f.scale, f.align))), Object.hashAll(_films), Object.hashAll([for (final f in _filters) f.id]),
    _template, _format, _pattern, _backdrop, _count, _arrangement, _backdropPattern, Object.hashAll(_places), _backdropBytes, _backdropBlur, _backdropScene, _texture, _textureStrength, _stripCaption, Object.hashAll(_polaroidCaptions), _bubble, _subject,
    Object.hashAll(_cutouts.entries.map((e) => Object.hash(e.key, e.value))), _cutLines, _clearPage,
    Object.hashAll(_stickers.map((s) => Object.hash(s.sticker, s.center, s.scale, s.rotation, s.flipped))), Object.hashAll(_strokes.map((s) => Object.hash(s.color, s.width, s.style, Object.hashAll(s.points)))), _strokes.isEmpty ? 0 : _strokes.last.points.length,
  ]);

  /// Something was changed since opening or the last save.
  bool get _edited => _contentKey() != _savedKey;
  /// Records the editing for the timelapse video.
  final _recorder = TimelapseRecorder();
  bool _withVideo = true;
  /// 完成 also saves to the phone's album: off unless asked, remembered.
  static bool _toAlbum = false;
  /// The making-of video at real speed rather than sped up; remembered.
  static bool _realVideo = false;
  final _polaroidCaptions = List.of(EditorDocument.collageCaptions);
  late int _template = widget.template;
  late String _category = allStripTemplates[widget.template].category;
  String? _stripCaption;
  late String _bubble = widget.mode == EditorMode.sticker ? '' : 'DREAM';
  int _pattern = 0, _backdrop = 1, _format = 3, _selectedCell = 0;
  List<StickerData> _stickers = [];
  /// Brush lines, drawn over everything.
  List<Stroke> _strokes = [];
  /// Ticks as a line grows: repaints the ink without rebuilding the screen.
  final _inkTick = ValueNotifier(0);
  PenStyle _pen = PenStyle.pen;
  /// The pen before the last change, for Apple Pencil's double-tap.
  PenStyle _lastPen = PenStyle.pen;
  StreamSubscription<String>? _pencil;

  void _setPen(PenStyle s) {
    if (s == _pen) return;
    _lastPen = _pen;
    _pen = s;
  }

  /// Apple Pencil double-tap while drawing: what the iPad is set to do.
  void _pencilTap(String action) {
    if (!mounted || _tool != _Tool.brush) return;
    setState(() {
      switch (action) {
        case 'eraser':
          _setPen(_pen == PenStyle.eraser ? (_lastPen == PenStyle.eraser ? PenStyle.pen : _lastPen) : PenStyle.eraser);
        case 'previous':
          _setPen(_lastPen);
        case 'palette':
          // Next colour round the palette.
          final i = penColors.indexOf(_penColor);
          _penColor = penColors[(i + 1) % penColors.length];
          if (_pen == PenStyle.eraser) _setPen(_lastPen);
      }
    });
  }
  Color _penColor = coral;
  int _penWidth = 1;
  /// The eraser already saved an undo step for this swipe.
  bool _erased = false;
  final List<EditorDocument> _history = [], _redoHistory = [];
  late List<List<Stroke>> _handwriting = widget.handwriting;
  late final String _draftId = widget.draftId ?? EditorDrafts.newId();
  Timer? _draftTimer;
  Object? _draftKey;
  String? _historyGroup;
  DateTime? _historyAt;
  late bool _exported = widget.saved;
  /// The text tool adds words as a sticker, rather than editing the
  /// piece's own text; and how the next words look.
  bool _wordSticker = false;
  TextLook _wordLook = TextLook.hand;
  Color _wordColor = ink;

  EditorDocument _document() => EditorDocument(mode: widget.mode, photos: _photoBytes,
    fits: _fits, films: _films, filters: [for (final f in _filters) f.id],
    captions: _polaroidCaptions, stickers: _stickers, strokes: _strokes,
    handwriting: _handwriting, templateKey: EditorDocument.keyForTemplate(_template),
    format: _format, pattern: _pattern, backdrop: _backdrop, bubble: _bubble,
    stripCaption: _stripCaption, subject: _subject, count: _count, arrangement: _arrangement, backdropPattern: _backdropPattern, places: _places,
    backdropPhoto: _backdropBytes, backdropBlur: _backdropBlur, backdropScene: _backdropScene, texture: _texture, textureStrength: _textureStrength,
    cutouts: _cutouts, cutLines: _cutLines, clearPage: _clearPage);

  void _restore(EditorDocument d) {
    _photoBytes.setAll(0, d.photos);
    _photos.setAll(0, d.photos.map((b) => b == null ? null : photoImage(b)));
    _fits.setAll(0, d.fits); _films.setAll(0, d.films);
    _filters.setAll(0, d.filters.map((id) => photoFilters.where((f) => f.id == id).firstOrNull ?? photoFilters.first));
    _polaroidCaptions.setAll(0, d.captions);
    _stickers = List.of(d.stickers); _strokes = EditorDocument.copyStrokes(d.strokes);
    _handwriting = d.handwriting; _template = d.templateIndex;
    _category = allStripTemplates[_template].category;
    _format = d.format; _pattern = d.pattern; _backdrop = d.backdrop;
    _count = d.count; _arrangement = d.arrangement; _backdropPattern = d.backdropPattern;
    if (d.places.isNotEmpty) _places.setAll(0, d.places);
    if (d.backdropPhoto != _backdropBytes) {
      _backdropBytes = d.backdropPhoto;
      _backdropImage = d.backdropPhoto == null ? null : photoImage(d.backdropPhoto!);
    }
    _backdropBlur = d.backdropBlur; _backdropScene = d.backdropScene; _texture = d.texture; _textureStrength = d.textureStrength;
    if (widget.mode == EditorMode.polaroid) _selectedCell = min(_selectedCell, _count - 1);
    _bubble = d.bubble; _stripCaption = d.stripCaption; _subject = d.subject;
    _cutouts = Map.of(d.cutouts); _cutLines = d.cutLines; _clearPage = d.clearPage;
    _selectedSticker = null; _textCtrl.text = _text;
    for (var i = 0; i < _cells; i++) { _aspects[i] = null; _measure(i); }
    _inkTick.value++;
  }

  Future<bool> _writeDraft() async {
    _draftTimer?.cancel();
    if (!EditorDrafts.enabled || (_exported && !_edited)) return true;
    if (!_edited && _photoBytes.every((p) => p == null)) return true;
    final key = _contentKey();
    if (_draftKey == key) return true;
    final saved = await EditorDrafts.save(_draftId, _document(), thumb: await _thumb());
    if (saved) _draftKey = key;
    return saved;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_writeDraft());
  }
  int? _selectedSticker;
  late _Tool _tool = widget.decorate ? _Tool.sticker : _tools.first;

  List<_Tool> get _tools => switch (widget.mode) {
    EditorMode.fourCut => const [_Tool.template, _Tool.sticker, _Tool.text, _Tool.brush, _Tool.filter],
    EditorMode.polaroid => const [_Tool.template, _Tool.layout, _Tool.backdrop, _Tool.film, _Tool.sticker, _Tool.text, _Tool.brush, _Tool.filter],
    EditorMode.sticker => const [_Tool.cutout, _Tool.effect, _Tool.backdrop, _Tool.sticker, _Tool.text, _Tool.brush],
  };

  String get _title => switch (widget.mode) {
    EditorMode.fourCut => '四格拍貼',
    EditorMode.polaroid => '拍立得拼貼',
    EditorMode.sticker => '照片貼紙',
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
    _remember(group: "text:$_selectedCell");
    switch (widget.mode) {
      case EditorMode.fourCut: _stripCaption = value;
      case EditorMode.polaroid: _polaroidCaptions[_selectedCell] = value;
      case EditorMode.sticker: _bubble = value;
    }
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A new photo-sticker page starts pink gingham, like sticker paper.
    if (widget.mode == EditorMode.sticker) {
      _backdropPattern = BackdropPattern.gingham;
      _backdrop = backdrops.indexWhere((b) => b.$1 == 'Pink');
    }
    for (var i = 0; i < widget.photos.length && i < _cells; i++) {
      _photoBytes[i] = widget.photos[i];
      _photos[i] = photoImage(widget.photos[i]);
      _measure(i);
    }
    for (var i = 0; i < widget.captions.length && i < _polaroidCaptions.length; i++) {
      _polaroidCaptions[i] = widget.captions[i];
    }
    if (widget.draft case final draft?) _restore(draft);
    if (widget.mode == EditorMode.sticker) _upgradeStickerPiece();
    _pencil = PencilTaps.taps.listen(_pencilTap);
    _savedKey = widget.draft == null || widget.saved ? _contentKey() : null;
  }

  /// A sticker piece from before 照片貼紙: its cut-out (or photo) becomes a
  /// photo sticker, its speech bubble words.
  void _upgradeStickerPiece() {
    final old = _subject ?? _photoBytes[0];
    if (_cutouts.isEmpty && old != null) {
      final id = PhotoStickers.newId();
      // A cut-out from then has its white border already.
      _cutouts = {id: PhotoSticker(cut: old, source: _photoBytes[0], edge: _subject != null ? StickerEdge.none : StickerEdge.thick)};
      _stickers = [StickerData(sticker: id, center: const Offset(.5, .54), scale: 3.6), ..._stickers];
    }
    _subject = null;
    _photoBytes[0] = null;
    _photos[0] = null;
    if (_bubble.isNotEmpty) {
      _stickers = [..._stickers, StickerData(sticker: TypedWords(_bubble).id, center: const Offset(.72, .12), scale: 1.6, rotation: .06)];
      _bubble = '';
    }
  }

  @override
  void dispose() {
    if (widget.mode == EditorMode.sticker) PhotoStickers.sync(const {}, cutLines: false);
    WidgetsBinding.instance.removeObserver(this);
    _pencil?.cancel();
    _draftTimer?.cancel();
    unawaited(_writeDraft().whenComplete(() => EditorDrafts.release(_draftId)));
    _recorder.dispose();
    _inkTick.dispose();
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
      info.dispose();
    }, onError: (_, __) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  void _removePhoto() => setState(() {
    _remember();
    final i = _selectedCell;
    _photos[i] = null;
    _photoBytes[i] = null;
    _fits[i] = const PhotoFit();
    _aspects[i] = null;
    if (widget.mode == EditorMode.sticker) _subject = null;
    _closePhoto();
  });

  /// 拍立得拼貼: the prints with photos move up in order and the count
  /// shrinks to them; the blank ones wait beyond it, as when the count is
  /// turned down.
  void _dropBlank() => setState(() {
    _remember();
    final filled = [for (var i = 0; i < _count; i++) if (_photos[i] != null) i];
    _keepPrints(filled);
  });

  /// Takes print [i] off the page: the ones after it move up.
  void _deletePrint(int i) {
    if (_count <= 1) return showMessage(context, '至少要留一張拍立得');
    setState(() => _dropPrint(i));
  }

  void _dropPrint(int i) {
    _remember();
    _keepPrints([for (var k = 0; k < _count; k++) if (k != i) k]);
    _closePhoto();
  }

  /// Only the prints [kept] stay, in that order; the rest wait beyond the
  /// count, as when the count is turned down.
  void _keepPrints(List<int> kept) {
    final order = [...kept, for (var i = 0; i < _cells; i++) if (!kept.contains(i)) i];
    List<T> moved<T>(List<T> list) => [for (final i in order) list[i]];
    _photos.setAll(0, moved(_photos));
    _photoBytes.setAll(0, moved(_photoBytes));
    _fits.setAll(0, moved(_fits));
    _aspects.setAll(0, moved(_aspects));
    _filters.setAll(0, moved(_filters));
    _films.setRange(0, _cells, moved(_films));
    _polaroidCaptions.setRange(0, _cells, moved(_polaroidCaptions));
    _handwriting = moved([for (var i = 0; i < _cells; i++) i < _handwriting.length ? _handwriting[i] : const <Stroke>[]]);
    _places.setAll(0, moved(_places));
    _count = kept.length;
    _selectedCell = min(_selectedCell, _count - 1);
  }

  /// Leave the photo tool for the tool it was opened from.
  void _closePhoto() {
    _cropping = false;
    if (_tool == _Tool.photo) _tool = _backTool ?? _tools.first;
  }

  /// Tapping a print (not its photo): select it, and in a tool that works
  /// on the whole piece, open the print's own tools.
  void _selectPrint(int i) => setState(() {
    final perPhoto = _tool == _Tool.film || _tool == _Tool.filter || _tool == _Tool.text;
    if (_selectedCell != i) _cropping = false;
    _selectedCell = i;
    _selectedSticker = null;
    _textCtrl.text = _text;
    if (!perPhoto && _tool != _Tool.photo) {
      _backTool = _tool;
      _tool = _Tool.photo;
    }
  });

  /// How many photo windows the piece shows.
  int get _slots => switch (widget.mode) {
    EditorMode.fourCut => min(_cells, allStripTemplates[_template].art?.cells.length ?? 4),
    EditorMode.polaroid => _count,
    EditorMode.sticker => 1,
  };

  /// Pick photos for every empty window at once, filled in order. A
  /// collage takes as many as were picked (up to six) when it is blank or
  /// all its prints are full (the photos are swapped).
  Future<void> _pickMany() async {
    final collage = widget.mode == EditorMode.polaroid;
    final fresh = collage && (_photos.every((p) => p == null) || _photos.take(_count).every((p) => p != null));
    final empty = fresh ? [for (var i = 0; i < _cells; i++) i] : [for (var i = 0; i < _slots; i++) if (_photos[i] == null) i];
    if (empty.length < 2) return _pickPhoto(empty.firstOrNull);
    final files = await _picker.pickMultiImage(imageQuality: 95, limit: empty.length);
    if (files.isEmpty) return;
    final bytes = await Future.wait([for (final f in files.take(empty.length)) f.readAsBytes()]);
    if (!mounted) return;
    setState(() {
      _remember();
      if (fresh) {
        _count = bytes.length;
        _selectedCell = min(_selectedCell, _count - 1);
      }
      for (final (k, b) in bytes.indexed) {
        final i = empty[k];
        _photos[i] = photoImage(b);
        _photoBytes[i] = b;
        _fits[i] = const PhotoFit();
        _aspects[i] = null;
      }
    });
    for (var k = 0; k < bytes.length; k++) {
      _measure(empty[k]);
    }
  }

  Future<void> _pickPhoto([int? index]) async {
    final i = index ?? _selectedCell;
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (widget.mode != EditorMode.sticker && _tool != _Tool.photo) {
      _backTool = _tool;
      _tool = _Tool.photo;
    }
    setState(() {
      _remember();
      _photos[i] = photoImage(bytes);
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

  /// 照片貼紙: pick photos; everyone in them is cut out by itself and put
  /// on the page as a sticker.
  Future<void> _addCutPhotos() async {
    if (_cutting != null) return;
    final files = await _picker.pickMultiImage(imageQuality: 95, limit: 6);
    if (files.isEmpty || !mounted) return;
    setState(() => _cutting = '去背中…');
    final made = <(Uint8List, Uint8List)>[];
    try {
      final photos = await Future.wait([for (final f in files) f.readAsBytes()]);
      for (final (k, photo) in photos.indexed) {
        if (!mounted) return;
        if (photos.length > 1) setState(() => _cutting = '去背中… ${k + 1}/${photos.length}');
        for (final cut in await autoCutouts(photo)) {
          made.add((cut, photo));
        }
      }
    } catch (e) {
      debugPrint('[STICKER] 去背失敗: $e');
    }
    if (!mounted) return;
    if (made.isEmpty) {
      setState(() => _cutting = null);
      return showMessage(context, '這次沒有剪出來，換一張照片試試', error: true);
    }
    setState(() {
      _cutting = null;
      _remember();
      final n = made.length;
      final cols = n == 1 ? 1 : n <= 4 ? 2 : 3;
      final rows = (n / cols).ceil();
      final scale = min(3.6, (1 / cols) * .95 / .2);
      final cutouts = Map.of(_cutouts);
      final added = <StickerData>[];
      for (final (k, (cut, photo)) in made.indexed) {
        final id = PhotoStickers.newId();
        cutouts[id] = PhotoSticker(cut: cut, source: photo);
        final col = k % cols, row = k ~/ cols;
        added.add(StickerData(
          sticker: id, scale: scale, rotation: n == 1 ? 0 : (k.isEven ? -.06 : .06),
          center: Offset((col + .5) / cols, .08 + .84 * (row + .5) / rows),
        ));
      }
      _cutouts = cutouts;
      _stickers = [..._stickers, ...added];
      _selectedSticker = null;
      if (_tool == _Tool.cutout) _tool = _Tool.effect;
    });
  }

  /// The photo sticker selected, if one is.
  String? get _selectedCut {
    final i = _selectedSticker;
    if (i == null || i >= _stickers.length) return null;
    final id = _stickers[i].sticker;
    return _cutouts.containsKey(id) ? id : null;
  }

  /// Fix the selected sticker's edge by hand, on the photo it came from.
  Future<void> _fixEdge() async {
    final id = _selectedCut;
    final source = id == null ? null : _cutouts[id]?.source;
    if (id == null || source == null) return showMessage(context, '先點一張剪好的貼紙');
    final png = await CutoutPage.open(context, source, recorder: _recorder, raw: true);
    if (png == null || !mounted || !_cutouts.containsKey(id)) return;
    setState(() {
      _remember();
      _cutouts = {..._cutouts, id: _cutouts[id]!.copyWith(cut: png)};
    });
  }

  /// Change the selected photo sticker's look, or every one's.
  void _styleCuts(PhotoSticker Function(PhotoSticker) change) => setState(() {
    _remember();
    final only = _selectedCut;
    _cutouts = {
      for (final MapEntry(key: id, value: c) in _cutouts.entries) id: only == null || only == id ? change(c) : c,
    };
  });

  /// A sticker sheet to print: white paper, everything in rows with room to
  /// cut around, cutting lines on.
  void _arrangeSheet() => setState(() {
    _remember();
    _clearPage = false;
    _backdropPattern = BackdropPattern.plain;
    _backdrop = 0;
    _cutLines = true;
    _selectedSticker = null;
    final n = _stickers.length;
    if (n == 0) return;
    final cols = n == 1 ? 1 : n <= 4 ? 2 : n <= 9 ? 3 : 4;
    final rows = (n / cols).ceil();
    final cell = min(1 / cols, 1 / rows / _aspect);
    final scale = cell * .84 / .2;
    _stickers = [
      for (final (k, st) in _stickers.indexed)
        st.copyWith(center: Offset((k % cols + .5) / cols, (k ~/ cols + .5) / rows), scale: scale, rotation: 0),
    ];
  });

  /// The selected sticker (or every one) into the sticker book's 我的;
  /// what happened, to tell.
  Future<String> _keepCuts({String? only}) async {
    final ids = only != null ? [only] : [for (final s in _stickers) if (_cutouts.containsKey(s.sticker)) s.sticker];
    var kept = 0;
    for (final id in ids.toSet()) {
      final png = await PhotoStickers.png(id);
      if (png == null) continue;
      MyLibrary.addSticker(png);
      kept++;
    }
    return kept == 0 ? '沒有可以收的貼紙' : '$kept 張收進貼紙本的「我的」了 ♡';
  }

  /// The selected sticker (or every one) to the album as a picture with a
  /// transparent background, for chat apps; what happened, and whether it
  /// went wrong.
  Future<(String, bool)> _exportCuts({String? only}) async {
    final ids = only != null ? [only] : [for (final s in _stickers) if (_cutouts.containsKey(s.sticker)) s.sticker];
    String? error;
    var saved = 0;
    for (final id in ids.toSet()) {
      final png = await PhotoStickers.png(id);
      if (png == null) continue;
      error = await PhotoSaveService.saveBytes(png);
      if (error != null) break;
      saved++;
    }
    return (error ?? (saved == 0 ? '沒有可以存的貼紙' : '$saved 張透明貼圖存到相簿了'), error != null);
  }

  /// Some photo sticker moves: 完成 can make a video of them.
  bool get _moving => _stickers.any((s) => (_cutouts[s.sticker]?.motion ?? StickerMotion.none) != StickerMotion.none);

  /// The page with its stickers moving, one [motionLoop] played twice: a video file
  /// and the recorder holding it (to dispose once it is copied).
  Future<(String?, TimelapseRecorder)> _motionVideo() async {
    final rec = TimelapseRecorder(subtitle: 'my photo stickers ♡');
    final frames = (motionLoop.inMilliseconds * TimelapseRecorder.fps / 1000).round();
    for (var k = 0; k < frames; k++) {
      PhotoStickers.clock.value = k / frames;
      await WidgetsBinding.instance.endOfFrame;
      final shot = await _snapshot();
      if (shot != null) await rec.add(shot);
    }
    rec.loop(2);
    PhotoStickers.clock.value = 0;
    await WidgetsBinding.instance.endOfFrame;
    final still = await _snapshot();
    return (still == null ? null : await rec.render(still), rec);
  }

  /// One timelapse frame: the canvas as it looks now (handles and all).
  Future<ui.Image?> _snapshot() async {
    final b = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (!mounted || b == null || !b.attached || b.size.isEmpty) return null;
    return b.toImage(pixelRatio: 1000 / b.size.longestSide);
  }

  /// A small picture of the piece for the drafts list.
  Future<Uint8List?> _thumb() async {
    try {
      final b = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (!mounted || b == null || !b.attached || b.size.isEmpty) return null;
      final image = await b.toImage(pixelRatio: 200 / b.size.longestSide);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Nothing to show yet: photos (or photo stickers) come first.
  bool get _blank => widget.mode == EditorMode.sticker ? _cutouts.isEmpty && _stickers.isEmpty : _photos.every((p) => p == null);

  /// Ask whether to save the timelapse too, then save.
  Future<void> _askSave() async {
    if (_saving) return;
    if (_blank) {
      return showMessage(context, '先放一張照片再儲存喔');
    }
    // A collage with prints still blank: take them away, keep them, or go fill them.
    final blank = widget.mode == EditorMode.polaroid ? [for (var i = 0; i < _count; i++) if (_photos[i] == null) i] : const <int>[];
    if (blank.isNotEmpty) {
      final choice = await showGlassDialog<String>(context, (context) => GlassDialog(
        title: '還有 ${blank.length} 張沒放照片',
        message: '空白的拍立得會照樣存進作品裡。要拿掉，變成 ${_count - blank.length} 張嗎？',
        actions: [
          GlassAction('去放照片', () => Navigator.pop(context)),
          GlassAction('留著空白', () => Navigator.pop(context, 'keep')),
          GlassAction('拿掉空白的', () => Navigator.pop(context, 'trim')),
        ],
      ));
      if (!mounted || choice == null) return;
      if (choice == 'trim') _dropBlank();
    }
    // Moving stickers: the video is them moving, not the making of.
    final motion = widget.mode == EditorMode.sticker && _moving;
    // Even a quick piece (photos in, a template) makes a video: a short
    // one holds each frame longer.
    final canVideo = motion || _recorder.frameCount >= 1;
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('完成！', style: TextStyle(fontSize: 19, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('作品會收進作品集，之後可以再編輯、分享；要不要存到手機相簿你決定。', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
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
                Icon(CupertinoIcons.film, color: canVideo ? coral : muted),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(motion ? '同時做「動態貼紙」影片' : '同時做「製作過程」影片', style: const TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(motion ? '會動的貼紙錄成約 8 秒的影片，適合發限動、Reels' : canVideo ? '你放照片、去背、貼貼紙的過程，適合發 Reels、TikTok' : '多編輯一下就能做成影片',
                    style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                ])),
                Checkbox(value: canVideo && _withVideo, activeColor: coral, onChanged: canVideo ? (v) => setSheet(() => _withVideo = v ?? false) : null),
              ]),
            ),
          ),
          // Sped up, or as it happened (long pauses shortened).
          if (canVideo && _withVideo && !motion) ...[
            const SizedBox(height: 8),
            Row(children: [
              for (final (real, label, note) in [
                (false, '縮時', '約 ${_recorder.seconds} 秒，快速看完'),
                (true, '完整', '約 ${_recorder.realSeconds} 秒，照實際速度'),
              ]) Expanded(child: Padding(
                padding: EdgeInsets.only(right: real ? 0 : 8),
                child: GestureDetector(
                  onTap: () => setSheet(() => _realVideo = real),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: _realVideo == real ? Colors.white : cream, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _realVideo == real ? coral : line, width: _realVideo == real ? 2 : 1.2),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: TextStyle(fontSize: 14, color: ink, fontWeight: _realVideo == real ? FontWeight.w900 : FontWeight.w700)),
                      const SizedBox(height: 1),
                      Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              )),
            ]),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setSheet(() => _toAlbum = !_toAlbum),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              decoration: BoxDecoration(
                color: _toAlbum ? blush : cream, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _toAlbum ? blushLine : line),
              ),
              child: Row(children: [
                const Icon(CupertinoIcons.arrow_down_to_line, color: coral),
                const SizedBox(width: 12),
                const Expanded(child: Text('也存到手機相簿', style: TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800))),
                Checkbox(value: _toAlbum, activeColor: coral, onChanged: (v) => setSheet(() => _toAlbum = v ?? false)),
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
            child: const Text('完成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ]),
      ))),
    );
    if (go == true && mounted) await _save(video: canVideo && _withVideo, album: _toAlbum, motion: motion);
  }

  /// Into the gallery, and the phone's album too if [album].
  Future<void> _save({bool video = false, bool album = false, bool motion = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _capturing = true;
      _selectedSticker = null;
    });
    // Photo stickers still and drawn in their latest look.
    PhotoStickers.clock.value = 0;
    await PhotoStickers.settle();
    // Let the frame without hints and handles paint before capturing it.
    await WidgetsBinding.instance.endOfFrame;
    final piece = _document();
    MyWorks.lastAdded = null;
    final clear = widget.mode == EditorMode.sticker && _clearPage;
    var error = await PhotoSaveService.saveBoundary(_shotKey, album: album, background: clear ? const Color(0x00000000) : const Color(0xFFFFFFFF), keep: switch (widget.mode) {
      EditorMode.fourCut => WorkKind.fourCut,
      EditorMode.polaroid => WorkKind.collage,
      EditorMode.sticker => WorkKind.sticker,
    });
    var saved = album ? '收進作品集，也存到相簿了 ♡' : '收進作品集了 ♡';
    // The gallery keeps the piece, to open it again.
    final kept = error == null ? MyWorks.lastAdded : null;
    if (kept != null) await MyWorks.keepPiece(kept, piece);
    if (error == null && video && motion) {
      final (path, rec) = await _motionVideo();
      if (path == null) {
        error = '圖片已收好，但動態影片做不出來';
      } else {
        if (kept != null) await MyWorks.keepVideo(kept, path);
        if (album) error = await PhotoSaveService.saveVideo(path);
      }
      rec.dispose();
      if (mounted) setState(() => _capturing = false);
    } else if (error == null && video) {
      // The clean finished piece ends the video.
      final finished = await _snapshot();
      if (mounted) setState(() => _capturing = false);
      final path = finished == null ? null : await _recorder.render(finished, real: _realVideo);
      if (path == null) {
        error = '圖片已收好，但縮時影片做不出來';
      } else {
        if (kept != null) await MyWorks.keepVideo(kept, path);
        if (album) error = await PhotoSaveService.saveVideo(path);
      }
    }
    PhotoStickers.clock.value = null;
    if (error == null) {
      _exported = true;
      _draftTimer?.cancel();
      try { await EditorDrafts.remove(_draftId); } catch (e) { debugPrint('[DRAFT] cleanup failed: $e'); }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _capturing = false;
      if (error == null) _savedKey = _contentKey();
    });
    final work = kept == null ? null : MyWorks.works.where((w) => w.id == kept.id).firstOrNull;
    // Done: show the piece and where to go from here.
    if (error == null && work != null) return _showDone(work, album: album);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? saved),
      // Changed one's mind: the album, from right here.
      action: error == null && !album && work != null ? SnackBarAction(label: '存到相簿', textColor: blush, onPressed: () async {
        final failed = await PhotoSaveService.saveWork(MyWorks.works.firstWhere((w) => w.id == work.id, orElse: () => work));
        messenger.showSnackBar(SnackBar(content: Text(failed ?? '已存到相簿 ♡'), behavior: SnackBarBehavior.floating));
      }) : null,
      // With an action it would stay until dismissed, over the tool tabs.
      persist: false,
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error == null ? ink : const Color(0xFFB4483C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  /// After 完成: the piece as it went into the gallery, and what next.
  Future<void> _showDone(Work work, {required bool album}) async {
    var inAlbum = album, busy = false;
    String? exported, keptCuts;
    final next = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('收進作品集了 ♡', style: TextStyle(fontSize: 19, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(inAlbum ? '手機相簿裡也有一張' : '在作品集可以分享、再編輯；想留在手機相簿就按「存到相簿」',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: min(240, MediaQuery.sizeOf(context).height * .3)),
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .14), blurRadius: 14, offset: const Offset(0, 6))]),
              child: Image(image: work.image, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: inAlbum || busy ? null : () async {
                setSheet(() => busy = true);
                final failed = await PhotoSaveService.saveWork(MyWorks.works.firstWhere((w) => w.id == work.id, orElse: () => work));
                if (!context.mounted) return;
                setSheet(() { busy = false; inAlbum = failed == null; });
                if (failed != null) showMessage(context, failed, error: true);
              },
              icon: Icon(inAlbum ? CupertinoIcons.checkmark_alt : CupertinoIcons.arrow_down_to_line, size: 18),
              label: Text(inAlbum ? '已在相簿' : busy ? '存檔中…' : '存到相簿', style: const TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink, side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'view'),
              icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
              label: const Text('看作品、分享', style: TextStyle(fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
          ]),
          if (widget.mode == EditorMode.sticker && _cutouts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: exported != null ? null : () async {
                  final (said, failed) = await _exportCuts();
                  if (!context.mounted) return;
                  if (failed) return showMessage(context, said, error: true);
                  setSheet(() => exported = said);
                },
                icon: Icon(exported != null ? CupertinoIcons.checkmark_alt : CupertinoIcons.chat_bubble_2, size: 18),
                label: FittedBox(child: Text(exported ?? '貼紙存成透明貼圖', style: const TextStyle(fontWeight: FontWeight.w800))),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink, side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: keptCuts != null ? null : () async {
                  final said = await _keepCuts();
                  if (context.mounted) setSheet(() => keptCuts = said);
                },
                icon: Icon(keptCuts != null ? CupertinoIcons.checkmark_alt : CupertinoIcons.book, size: 18),
                label: FittedBox(child: Text(keptCuts != null ? '已收進我的貼紙' : '收進我的貼紙', style: const TextStyle(fontWeight: FontWeight.w800))),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink, side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              )),
            ]),
          ],
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(onPressed: () => Navigator.pop(context), style: TextButton.styleFrom(foregroundColor: muted),
              child: const Text('繼續編輯', style: TextStyle(fontWeight: FontWeight.w800))),
            const Text('·', style: TextStyle(color: muted)),
            TextButton(onPressed: () => Navigator.pop(context, 'home'), style: TextButton.styleFrom(foregroundColor: muted),
              child: const Text('回首頁', style: TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ]),
      ))),
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    switch (next) {
      case 'view':
        final works = MyWorks.works;
        final i = works.indexWhere((w) => w.id == work.id);
        await navigator.pushReplacement(MaterialPageRoute(builder: (_) => WorkViewer(works: List.of(works), initial: max(0, i))));
      case 'home':
        navigator.popUntil((route) => route.isFirst);
    }
  }

  void _tapCell(int i) {
    // These tools work on one photo at a time: tapping one picks which.
    final perPhoto = _tool == _Tool.film || _tool == _Tool.filter || (_tool == _Tool.text && widget.mode == EditorMode.polaroid);
    setState(() {
      _selectedCell = i;
      _selectedSticker = null;
      _textCtrl.text = _text;
      if (_photos[i] != null && !perPhoto) {
        if (_tool != _Tool.photo) _backTool = _tool;
        _tool = _Tool.photo;
      }
    });
    if (_photos[i] == null && _tool != _Tool.film) _pickPhoto(i);
  }

  /// Outline the chosen photo only while a tool works on one photo.
  bool get _showCell => !_capturing && (_tool == _Tool.photo || (_tool == _Tool.filter && !_pageLook) || _tool == _Tool.film);
  /// The collage's text tool: outline the chosen print's caption instead.
  bool get _showCaption => !_capturing && _tool == _Tool.text && widget.mode == EditorMode.polaroid && !_wordSticker;

  /// The template prints its own words: typed text goes on as a sticker.
  bool get _printedText => widget.mode == EditorMode.sticker || (widget.mode == EditorMode.fourCut && allStripTemplates[_template].art != null);

  void _addText(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    _addSticker(TypedWords(text, look: _wordLook, color: _wordColor).id);
    // Words fill the width of a sticker's square: start them wide enough to read.
    setState(() => _stickers.last = _stickers.last.copyWith(scale: 2.2, center: Offset(.5, _stickers.last.center.dy)));
  }

  /// The cell whose photo can be dragged and pinched right now.
  int? get _adjusting => !_capturing && _tool == _Tool.photo && _photos[_selectedCell] != null && (_cropping || widget.mode != EditorMode.polaroid) ? _selectedCell : null;

  void _setFit(int i, PhotoFit fit) => setState(() {
    _remember(group: "fit:$i");
    _fits[i] = fit;
  });

  void _selectTool(_Tool tool) => setState(() {
    _tool = tool;
    _backTool = null;
    if (tool == _Tool.text) _textCtrl.text = _text;
    if (tool == _Tool.brush) _selectedSticker = null;
  });

  void _remember({String? group}) {
    final now = DateTime.now();
    if (group == null || group != _historyGroup || _historyAt == null || now.difference(_historyAt!).inMilliseconds > 700) {
      _history.add(_document());
      if (_history.length > 30) _history.removeAt(0);
    }
    _historyGroup = group; _historyAt = now;
    _redoHistory.clear();
  }

  /// This line erases: the eraser tool, or a pen's eraser end or button.
  bool _erasing = false;

  void _penDown(Offset at, Size size, PenTouch touch) => setState(() {
    _erasing = _pen == PenStyle.eraser || touch.erase;
    if (_erasing) {
      _erased = false;
      return _erase(at, size);
    }
    _remember();
    _strokes = [..._strokes, Stroke(points: [normalise(at, size)], color: _penColor, width: penWidths[_penWidth], style: _pen,
      pressures: touch.pressure == null ? null : [touch.pressure!])];
  });

  void _penMove(Offset at, Size size, PenTouch touch) {
    if (_erasing) return setState(() => _erase(at, size));
    if (_strokes.isEmpty) return;
    final stroke = _strokes.last, points = stroke.points;
    final p = normalise(at, size);
    // Skip points closer than about a pixel; they only make the path heavier.
    final last = points.last;
    if (Offset((p.dx - last.dx) * size.width, (p.dy - last.dy) * size.height).distance < 1.5) return;
    points.add(p);
    stroke.pressures?.add(touch.pressure ?? stroke.pressures!.last);
    _inkTick.value++;
  }

  /// Wipe out every line the finger touches; one undo step per swipe.
  void _erase(Offset at, Size size) {
    final radius = size.width * .03;
    final kept = [for (final s in _strokes) if (!s.touches(at, radius, size)) s];
    if (kept.length == _strokes.length) return;
    if (!_erased) {
      _remember();
      _erased = true;
    }
    _strokes = kept;
  }

  void _clearInk() => setState(() {
    _remember();
    _strokes = [];
  });

  void _addSticker(String sticker, [double scale = 1]) => setState(() {
    _remember();
    final n = _stickers.length;
    _stickers = [..._stickers, StickerData(sticker: sticker, scale: scale, center: Offset(.5 + (n % 3 - 1) * .14, .4 + (n % 2) * .12))];
    _selectedSticker = _stickers.length - 1;
  });

  void _undo() => setState(() {
    if (_history.isEmpty) return;
    _redoHistory.add(_document()); _restore(_history.removeLast()); _historyGroup = null;
  });

  void _redo() => setState(() {
    if (_redoHistory.isEmpty) return;
    _history.add(_document()); _restore(_redoHistory.removeLast()); _historyGroup = null;
  });

  Offset _toCanvas(Offset global) => (_canvasKey.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  @override
  Widget build(BuildContext context) {
    if (widget.mode == EditorMode.sticker) {
      final cutouts = _cutouts, lines = _cutLines;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) PhotoStickers.sync(cutouts, cutLines: lines);
      });
    }
    // Record the piece for the timelapse when it changed, not on every
    // rebuild (picking a tool, selecting a sticker).
    final key = _contentKey();
    if (EditorDrafts.enabled && key != _draftKey && !(_exported && !_edited)) {
      _draftTimer?.cancel();
      _draftTimer = Timer(const Duration(milliseconds: 700), () { unawaited(_writeDraft()); });
    }
    if (!_capturing && key != _recordedKey) {
      _recordedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recorder.request(_snapshot));
    }
    return _scaffold();
  }

  Widget _scaffold() => PopScope(
    canPop: !_saving && !_edited,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _saving) return;
      final navigator = Navigator.of(context);
      if (await confirmLeave(context, EditorDrafts.enabled ? '作品會保留為草稿，下次可以繼續編輯。' : '還沒儲存的作品會不見喔。')) {
        final saved = await _writeDraft();
        if (!mounted) return;
        if (saved) { navigator.pop(); } else { showMessage(context, '草稿儲存失敗，請稍後再試'); }
      }
    },
    child: AbsorbPointer(absorbing: _saving, child: _page()),
  );

  /// A wide screen (a foldable opened, a tablet): the tools beside the
  /// piece rather than under it.
  bool get _wide {
    final size = MediaQuery.sizeOf(context);
    return size.width >= 700 && size.width > size.height * .7;
  }

  Widget _page() {
    final stage = _stage();
    return Scaffold(
      backgroundColor: cream,
      body: SafeArea(bottom: false, child: Column(children: [
        _topBar(),
        if (_wide) Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: stage),
          SizedBox(width: 400, child: _sheet(side: true)),
        ])) else ...[
          Expanded(child: stage),
          _sheet(),
        ],
      ])),
    );
  }

  /// The piece, with what floats around it.
  Widget _stage() => Stack(children: [
        // Hand-drawn doodles beside the narrow strip (wider canvases cover them).
        if (widget.mode == EditorMode.fourCut) ...const [
          Positioned(right: 54, top: 30, child: Sparkle(size: 22)),
          Positioned(left: 40, bottom: 70, child: Sparkle(size: 24, fill: Color(0xFFF7D77C))),
          Positioned(left: 64, bottom: 52, child: Sparkle(size: 13)),
          Positioned(left: 58, bottom: 96, child: DoodleHeart(size: 13, color: Color(0xFFE8C6F0))),
        ],
        // A blank collage or sticker piece leaves room under it for the
        // 選照片 button (it would hide a photo); the four-cut strip's bottom
        // is only its caption, and the strip is narrow enough already.
        Positioned.fill(child: Padding(padding: EdgeInsets.fromLTRB(28, 12, 28, widget.mode != EditorMode.fourCut && !_capturing && _blank ? 84 : 16), child: _canvas())),
        // A blank piece: photos first, then decorating.
        if (!_capturing && _blank && _cutting == null)
          Positioned(left: 0, right: 0, bottom: 28, child: Center(child: FilledButton.icon(
            onPressed: widget.mode == EditorMode.sticker ? _addCutPhotos : _pickMany,
            icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 20),
            label: Text(widget.mode == EditorMode.sticker ? '選照片，自動剪成貼紙' : widget.mode == EditorMode.polaroid ? '選照片（1～6 張）' : _slots > 1 ? '選照片（一次可以選 $_slots 張）' : '先選一張照片', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            style: FilledButton.styleFrom(
              backgroundColor: coral, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: const StadiumBorder(), elevation: 3, shadowColor: ink.withValues(alpha: .3),
            ),
          ))),
        if (_cutting case final message?)
          Positioned.fill(child: ColoredBox(color: cream.withValues(alpha: .55), child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: line),
              boxShadow: [BoxShadow(color: ink.withValues(alpha: .1), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: coral)),
              const SizedBox(width: 12),
              Text(message, style: const TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
            ]),
          )))),
      ]);

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
    child: Row(children: [
      IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(CupertinoIcons.back, color: ink, size: 26)),
      Expanded(child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w900))),
      _IconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: '復原', onTap: _history.isEmpty ? null : _undo),
      _IconButton(icon: CupertinoIcons.arrow_uturn_right, tooltip: '重做', onTap: _redoHistory.isEmpty ? null : _redo),
      if (widget.mode != EditorMode.sticker) _IconButton(icon: CupertinoIcons.photo_on_rectangle, tooltip: '從相簿選照片', onTap: _pickMany),
      const SizedBox(width: 6),
      _TopButton(label: _saving ? '儲存中…' : '完成', filled: true, onTap: _askSave),
    ]),
  );

  Widget _canvas() => Center(child: AspectRatio(aspectRatio: _aspect, child: LayoutBuilder(builder: (context, c) {
    final size = c.biggest;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 8))]),
      child: PhotoCapture(key: _shotKey, child: TexturedPage(texture: widget.mode == EditorMode.polaroid ? _texture : PageTexture.none, strength: _textureStrength, child: Stack(key: _canvasKey, clipBehavior: Clip.none, children: [
        Positioned.fill(child: GestureDetector(
          // Tapping the page beside the photos puts the photo tool away.
          onTap: () => setState(() { _selectedSticker = null; _closePhoto(); }),
          child: _artwork(size),
        )),
        for (var i = 0; i < _stickers.length; i++)
          StickerItem(
            data: _stickers[i],
            animatePlacement: _selectedSticker == i,
            animationsEnabled: !_capturing,
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
              final gone = _stickers.removeAt(i).sticker;
              if (_cutouts.containsKey(gone) && !_stickers.any((s) => s.sticker == gone)) {
                _cutouts = {..._cutouts}..remove(gone);
              }
              _selectedSticker = null;
            }),
          ),
        // Always there: adding it on the first line would rebuild the input below mid-stroke.
        Positioned.fill(child: InkLayer(strokes: _strokes, repaint: _inkTick)),
        if (_tool == _Tool.brush && !_capturing)
          Positioned.fill(child: DoodleInput(onStart: _penDown, onMove: _penMove, onEnd: () => setState(() => _erased = false))),
      ]))),
    );
  })));

  Widget _artwork(Size size) => switch (widget.mode) {
    EditorMode.fourCut => FittedBox(child: PhotoStrip(
      template: allStripTemplates[_template], photos: _photos, caption: _stripCaption,
      placeholder: _capturing ? null : const AddPhotoHint(scale: 1.4), selected: _showCell ? _selectedCell : null, onTapCell: _tapCell,
      fits: _fits, aspects: _aspects, adjusting: _adjusting, onFit: _setFit, filters: _filters,
    )),
    EditorMode.polaroid => _polaroidArtwork(size),
    EditorMode.sticker => _stickerArtwork(),
  };

  Widget _polaroidArtwork(Size size) {
    final laid = collageLayout(_count, _arrangement, size.aspectRatio);
    final places = [for (var i = 0; i < _count; i++) _places[i] ?? laid[i]];
    // Draw the selected print last so it sits on top.
    final order = [for (var i = 0; i < _count; i++) if (i != _selectedCell) i, if (_selectedCell < _count) _selectedCell];
    Widget doodle(double x, double y, Widget child) => Positioned(left: x * size.width, top: y * size.height, child: child);
    return Backdrop(
      color: backdrops[_backdrop].$2, pattern: _backdropPattern, photo: _backdropPhoto, blur: _backdropBlur,
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
          PrintItem(
            key: ValueKey('print-$i'),
            place: places[i], heightRatio: 1 / _films[i].aspect, canvas: size, toLocal: _toCanvas,
            selected: !_capturing && _tool == _Tool.photo && _selectedCell == i,
            movable: !_capturing && !(_cropping && _selectedCell == i) && _tool != _Tool.brush,
            onSelect: () => _selectPrint(i),
            onEditStart: () => setState(() {
              _remember(group: 'place:$i');
              _selectedCell = i;
              _selectedSticker = null;
              _places[i] = places[i];
            }),
            onChanged: (p) => setState(() {
              final snapped = snapPrint(p, [for (var k = 0; k < _count; k++) if (k != i) places[k]], size);
              _places[i] = snapped.place;
              _guideX = snapped.xs; _guideY = snapped.ys;
            }),
            onEditEnd: () => setState(() { _guideX = const []; _guideY = const []; }),
            onDelete: () => _deletePrint(i),
            child: FittedBox(child: SizedBox(
              width: InstantPrint.width, height: InstantPrint.heightOf(_films[i]),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .16), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: InstantPrint(
                    image: _photos[i], film: _films[i], caption: _polaroidCaptions[i],
                    handwriting: i < _handwriting.length ? _handwriting[i] : const [],
                    placeholder: _capturing ? null : const AddPhotoHint(scale: 1.3),
                    selected: _showCell && _selectedCell == i && (_tool != _Tool.photo || _cropping), onTap: () => _tapCell(i),
                    captionSelected: _showCaption && _selectedCell == i,
                    onCaption: () => setState(() {
                      _wordSticker = false;
                      _selectedCell = i;
                      _tool = _Tool.text;
                      _textCtrl.text = _polaroidCaptions[i];
                    }),
                    fit: _fits[i], aspect: _aspects[i], onFit: _adjusting == i ? (f) => _setFit(i, f) : null, filter: _filters[i],
                  ),
                )),
                Positioned(top: -4, left: i.isOdd ? null : -22, right: i.isOdd ? -22 : null,
                  child: WashiTape(width: 64, height: 22, angle: i.isOdd ? .75 : -.75, colors: _tapes[i % _tapes.length])),
              ]),
            )),
          ),
        if (_guideX.isNotEmpty || _guideY.isNotEmpty)
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: GuidePainter(_guideX, _guideY)))),
      ]),
    );
  }

  /// 照片貼紙's page: the background, or (clear) a checkerboard on screen
  /// and nothing in the saved picture.
  Widget _stickerArtwork() => _clearPage
    ? (_capturing ? const SizedBox.expand() : const CustomPaint(painter: _ClearPainter(), child: SizedBox.expand()))
    : Backdrop(color: backdrops[_backdrop].$2, pattern: _backdropPattern, photo: _backdropPhoto, blur: _backdropBlur, child: const SizedBox.expand());

  /// The tools: under the piece, or beside it ([side]) on a wide screen,
  /// where each tool gets the full height.
  Widget _sheet({bool side = false}) => Container(
    margin: side ? const EdgeInsets.fromLTRB(0, 8, 16, 0) : null,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .07), blurRadius: 20, offset: Offset(0, side ? 4 : -4))],
    ),
    child: Column(mainAxisSize: side ? MainAxisSize.max : MainAxisSize.min, children: [
      if (!side) ...[
        const SizedBox(height: 8),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(2))),
      ],
      if (side) Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: _toolView())) else
      // The sticker book wants room to show a good part of a sheet; a bit
      // less beside the narrow four-cut strip, which shouldn't get thinner.
      SizedBox(
        height: _tool == _Tool.sticker ? max(168.0, MediaQuery.sizeOf(context).height * (widget.mode == EditorMode.fourCut ? .3 : .36))
            // The collage's tools are all one height: the page doesn't jump between them.
            : widget.mode != EditorMode.fourCut ? 216
            : _tool == _Tool.text ? (_printedText ? 168 : 206) : 168,
        child: _toolView(),
      ),
      Container(
        decoration: BoxDecoration(
          color: cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, -3))],
        ),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            for (final t in _tools) Expanded(child: _ToolTab(tool: t, selected: _tool == t, compact: _tools.length > 6, onTap: () => _selectTool(t))),
          ]),
        )),
      ),
    ]),
  );

  Widget _toolView() => switch (_tool) {
    _Tool.template => widget.mode == EditorMode.polaroid ? _collageTemplateTool() : _templateTool(),
    _Tool.layout => _layoutTool(),
    _Tool.backdrop => _backdropTool(),
    _Tool.sticker => _stickerTool(),
    _Tool.cutout => _cutTool(),
    _Tool.effect => _effectTool(),
    _Tool.photo => _photoTool(),
    _Tool.film => _filmTool(),
    _Tool.filter => _filterTool(),
    _Tool.text => _textTool(),
    _Tool.brush => _brushTool(),
  };

  /// Puts the collage into [t]: its page, prints, paper bits and look; the
  /// photos stay. null: back to a plain page.
  void _applyTemplate(CollageTemplate? t) => setState(() {
    _remember();
    _closePhoto();
    _selectedCell = 0;
    _selectedSticker = null;
    _places.fillRange(0, _places.length, null);
    _backdropBytes = null; _backdropImage = null;
    if (t == null) {
      _count = 4; _format = 3; _arrangement = CollageArrangement.scatter;
      _backdrop = 1; _backdropPattern = BackdropPattern.plain; _backdropScene = null; _backdropBlur = true;
      _texture = PageTexture.none;
      _films.fillRange(0, _films.length, FilmStock.white);
      _polaroidCaptions.setAll(0, EditorDocument.collageCaptions);
      _stickers = [for (final s in _stickers) if (!s.sticker.startsWith('deco:')) s];
      return;
    }
    _format = formats.indexWhere((f) => f.$1 == '9:16');
    _count = t.places.length;
    _places.setAll(0, t.places);
    _films.setAll(0, t.films);
    _polaroidCaptions.setAll(0, t.captions);
    _backdropPattern = BackdropPattern.photo; _backdropScene = t.backdrop; _backdropBlur = false;
    _texture = t.texture; _textureStrength = t.strength;
    // The user's own stickers stay; the last template's paper bits go.
    _stickers = [for (final s in _stickers) if (!s.sticker.startsWith('deco:')) s, ...t.stickers];
  });

  Widget _collageTemplateTool() => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
    itemCount: collageTemplates.length + 1,
    separatorBuilder: (_, __) => const SizedBox(width: 12),
    itemBuilder: (_, i) {
      final t = i == 0 ? null : collageTemplates[i - 1];
      return GestureDetector(
        onTap: () => _applyTemplate(t),
        child: Column(children: [
          Expanded(child: AspectRatio(aspectRatio: 9 / 16, child: Container(
            decoration: BoxDecoration(
              color: backdrops[1].$2, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: line, width: 1.3),
              boxShadow: [BoxShadow(color: ink.withValues(alpha: .08), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            clipBehavior: Clip.antiAlias,
            child: t == null
              ? const Center(child: Icon(CupertinoIcons.plus, color: muted))
              : _TemplatePreview(template: t),
          ))),
          const SizedBox(height: 5),
          Text(t?.name ?? '空白', style: const TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w800)),
        ]),
      );
    },
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
          return _TemplateThumb(template: allStripTemplates[i], selected: _template == i, onTap: () => setState(() { _remember(); _template = i; }));
        },
      )),
    ]);
  }

  /// A row of the layout tool: a label and its choices.
  Widget _layoutRow(String label, Widget choices) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 44, child: Text(label, style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800))),
      Expanded(child: choices),
    ]),
  );

  /// One choice of several, side by side.
  Widget _segments(List<String> labels, int selected, ValueChanged<int> onTap) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(14), border: Border.all(color: line, width: 1.3)),
    child: Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(child: GestureDetector(
          onTap: () => onTap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: selected == i ? blush : Colors.transparent, borderRadius: BorderRadius.circular(11)),
            child: Text(labels[i], textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: ink, fontWeight: selected == i ? FontWeight.w900 : FontWeight.w600)),
          ),
        )),
    ]),
  );

  void _setCount(int n) => setState(() {
    _remember();
    _count = n;
    _selectedCell = min(_selectedCell, n - 1);
  });

  Widget _layoutTool() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _layoutRow('張數', _segments(const ['1', '2', '3', '4', '5', '6'], _count - 1, (i) => _setCount(i + 1))),
      _layoutRow('排法', _segments([for (final a in CollageArrangement.values) a.label], _arrangement.index,
        // Picking one (even the same again) puts moved prints back in it.
        (i) => setState(() { _remember(); _arrangement = CollageArrangement.values[i]; _places.fillRange(0, _places.length, null); }))),
      _layoutRow('比例', _segments([for (final f in formats) f.$1], _format, (i) => setState(() { _remember(); _format = i; }))),
    ]),
  );

  /// The 照片 backdrop: one picked for it, else the first print's photo.
  ImageProvider? get _backdropPhoto {
    if (_backdropImage case final image?) return image;
    if (sceneBackdrop(_backdropScene) case final scene?) return AssetImage(scene.asset);
    if (widget.mode == EditorMode.sticker) return _firstSource;
    return _photos.take(_count).nonNulls.firstOrNull;
  }

  Future<void> _pickBackdrop() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _remember();
      _backdropBytes = bytes;
      _backdropImage = photoImage(bytes);
      _backdropScene = null;
      _backdropPattern = BackdropPattern.photo;
      _clearPage = false;
    });
  }

  /// The collage's paper: a pattern, then its colour.
  Widget _backdropTool() {
    final color = backdrops[_backdrop].$2;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 112, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        itemCount: BackdropPattern.values.length + sceneBackdrops.length + (widget.mode == EditorMode.sticker ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (widget.mode == EditorMode.sticker) {
            if (i == 0) {
              return GestureDetector(
                onTap: () => setState(() { _remember(); _clearPage = true; }),
                child: Column(children: [
                  Container(
                    width: 60, height: 66, padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _clearPage ? coral : line, width: _clearPage ? 2.5 : 1.3)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(11), child: const CustomPaint(painter: _ClearPainter(cell: 7), child: SizedBox.expand())),
                  ),
                  const SizedBox(height: 4),
                  Text('透明', style: TextStyle(fontSize: 11, color: _clearPage ? ink : muted, fontWeight: _clearPage ? FontWeight.w900 : FontWeight.w700)),
                ]),
              );
            }
            i--;
          }
          if (i >= BackdropPattern.values.length) {
            final scene = sceneBackdrops[i - BackdropPattern.values.length];
            final selected = !_clearPage && _backdropPattern == BackdropPattern.photo && _backdropScene == scene.id && _backdropBytes == null;
            return GestureDetector(
              onTap: () => setState(() {
                _remember();
                _clearPage = false;
                _backdropPattern = BackdropPattern.photo;
                _backdropScene = scene.id;
                _backdropBytes = null; _backdropImage = null;
                _backdropBlur = false;
              }),
              child: Column(children: [
                Container(
                  width: 60, height: 66, padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? coral : line, width: selected ? 2.5 : 1.3)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(11), child: Image(image: scene.thumb, fit: BoxFit.cover)),
                ),
                const SizedBox(height: 4),
                Text(scene.label, style: TextStyle(fontSize: 11, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
              ]),
            );
          }
          final p = BackdropPattern.values[i];
          // 照片 is the user's own photo; a scene shows as its own item.
          final selected = !_clearPage && _backdropPattern == p && (p != BackdropPattern.photo || _backdropScene == null || _backdropBytes != null);
          return GestureDetector(
            onTap: () => setState(() {
              _remember();
              _clearPage = false;
              _backdropPattern = p;
              if (p == BackdropPattern.photo) _backdropScene = null;
            }),
            child: Column(children: [
              Container(
                width: 60, height: 66, padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? coral : line, width: selected ? 2.5 : 1.3),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(11), child: Backdrop(
                  color: color, pattern: p, cells: 7, blur: _backdropBlur,
                  photo: (_backdropScene == null ? _backdropPhoto : _backdropImage ?? _photos.take(_count).nonNulls.firstOrNull) ?? samplePhotos.first,
                )),
              ),
              const SizedBox(height: 4),
              Text(p.label, style: TextStyle(fontSize: 11, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
            ]),
          );
        },
      )),
      if (_backdropPattern == BackdropPattern.photo && !_clearPage)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Row(children: [
            OutlinedButton.icon(
              onPressed: _pickBackdrop,
              icon: const Icon(CupertinoIcons.photo, size: 16),
              label: Text(_backdropBytes == null ? '從相簿選背景' : '換背景照片', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink, backgroundColor: cream, side: const BorderSide(color: line, width: 1.3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _segments(const ['模糊', '清楚'], _backdropBlur ? 0 : 1, (i) => setState(() { _remember(); _backdropBlur = i == 0; }))),
          ]),
        ),
      // The colour tints a blurred photo; a sharp one is shown as it is.
      if (!_clearPage && (_backdropPattern != BackdropPattern.photo || _backdropBlur))
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        itemCount: backdrops.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => setState(() { _remember(); _backdrop = i; _clearPage = false; }),
          child: Container(
            width: 40, height: 40, padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _backdrop == i ? outline.withValues(alpha: .6) : Colors.transparent, width: 2)),
            child: Container(decoration: BoxDecoration(color: backdrops[i].$2, shape: BoxShape.circle, border: Border.all(color: line, width: 1.3))),
          ),
        ),
      )),
    ]);
  }

  void _setFilm(FilmStock f, {bool all = false}) => setState(() {
    _remember();
    for (var i = 0; i < _films.length; i++) {
      if (all || i == _selectedCell) _films[i] = f;
    }
  });

  /// Film for each print: the chosen one's photo shown in every stock.
  Widget _filmTool() {
    final cell = _selectedCell.clamp(0, _count - 1);
    final current = _films[cell];
    final allSame = _films.take(_count).every((f) => f == current);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
        child: Row(children: [
          Expanded(child: Text(_count > 1 ? '第 ${cell + 1} 張的底片（點畫面上的照片換一張）' : '底片',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800))),
          if (_count > 1)
            TextButton(
              onPressed: allSame ? null : () => _setFilm(current, all: true),
              style: TextButton.styleFrom(foregroundColor: coral, visualDensity: VisualDensity.compact),
              child: Text(allSame ? '已套用到全部' : '套用到全部', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
      Expanded(child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        children: [
          for (final f in FilmStock.values) ...[
            // Each series starts with its name.
            if (f == FilmStock.values.firstWhere((x) => x.group == f.group))
              Padding(
                padding: EdgeInsets.only(left: f.index == 0 ? 0 : 6, right: 6, top: 30),
                child: Text(f.group, style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w800)),
              ),
            _FilmThumb(
              film: f, image: _photos[cell], fit: _fits[cell], aspect: _aspects[cell],
              selected: current == f, onTap: () => _setFilm(f),
            ),
          ],
        ],
      )),
    ]);
  }

  Widget _stickerTool() => StickerBookView(onPick: _addSticker, used: {for (final s in _stickers) s.sticker});

  void _setFilter(PhotoFilter f, {bool all = false}) => setState(() {
    _remember();
    if (_saving) return;
    for (var i = 0; i < _filters.length; i++) {
      if (all || i == _selectedCell) _filters[i] = f;
    }
  });

  Widget _filterTool() {
    if (widget.mode != EditorMode.polaroid) return _photoFilterTool();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: _segments(const ['照片濾鏡', '整頁質感'], _pageLook ? 1 : 0, (i) => setState(() => _pageLook = i == 1)),
      ),
      Expanded(child: _pageLook ? _textureTool() : _photoFilterTool()),
    ]);
  }

  /// The look over the whole collage, and how strong.
  Widget _textureTool() {
    final sample = _backdropPhoto ?? _photos.nonNulls.firstOrNull ?? samplePhotos.first;
    return Column(children: [
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
        itemCount: PageTexture.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = PageTexture.values[i];
          final selected = _texture == t;
          return GestureDetector(
            onTap: () => setState(() { _remember(); _texture = t; }),
            child: Column(children: [
              Container(
                width: 56, height: 62, padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? coral : line, width: selected ? 2.5 : 1.3)),
                child: ClipRRect(borderRadius: BorderRadius.circular(9), child: TexturedPage(
                  texture: t, strength: 1,
                  child: SizedBox.expand(child: Image(image: sample, fit: BoxFit.cover, gaplessPlayback: true)),
                )),
              ),
              const SizedBox(height: 3),
              Text(t.label, style: TextStyle(fontSize: 11, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
            ]),
          );
        },
      )),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
        child: Row(children: [
          Text('強度', style: TextStyle(fontSize: 13, color: _texture == PageTexture.none ? muted : ink, fontWeight: FontWeight.w800)),
          Expanded(child: Slider(
            value: _textureStrength, activeColor: coral,
            onChangeStart: _texture == PageTexture.none ? null : (_) => _remember(group: 'texture'),
            onChanged: _texture == PageTexture.none ? null : (v) => setState(() => _textureStrength = v),
          )),
        ]),
      ),
    ]);
  }

  Widget _photoFilterTool() {
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
      Expanded(child: FilterThumbs(image: image, selected: current.id, onPick: _setFilter, padding: const EdgeInsets.fromLTRB(16, 6, 16, 10))),
    ]);
  }

  /// 拍立得拼貼: the chosen print's tools.
  Widget _printTool() {
    final i = _selectedCell, has = _photos[i] != null;
    Widget button(IconData icon, String label, VoidCallback onTap, {bool danger = false, bool on = false}) => Expanded(child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? const Color(0xFFB4483C) : ink, backgroundColor: on ? blush : cream,
        side: BorderSide(color: on ? blushLine : line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('第 ${i + 1} 張拍立得', style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800))),
          TextButton.icon(
            onPressed: () => setState(_closePhoto),
            icon: const Icon(CupertinoIcons.chevron_down, size: 16),
            label: const Text('收起', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            style: TextButton.styleFrom(foregroundColor: muted, visualDensity: VisualDensity.compact),
          ),
        ]),
        const SizedBox(height: 2),
        Text(_cropping ? '在照片上拖曳移動、兩指放大縮小；好了按「調好了」' : '拖曳拍立得移動，兩指或右下角把手放大、旋轉',
          style: TextStyle(fontSize: 12, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600)),
        const Spacer(),
        Row(children: [
          button(has ? CupertinoIcons.arrow_right_arrow_left : CupertinoIcons.photo, has ? '換照片' : '放照片', () => _pickPhoto()),
          const SizedBox(width: 8),
          if (has) ...[
            button(CupertinoIcons.crop, _cropping ? '調好了' : '調整', () => setState(() => _cropping = !_cropping), on: _cropping),
            const SizedBox(width: 8),
          ],
          button(CupertinoIcons.arrow_counterclockwise, '擺正', () => setState(() {
            _remember();
            final laid = collageLayout(_count, _arrangement, _aspect)[i];
            final p = _places[i] ?? laid;
            _places[i] = (center: p.center, width: p.width, angle: 0);
          })),
          const SizedBox(width: 8),
          button(CupertinoIcons.trash, '拿掉', () => _deletePrint(i), danger: true),
        ]),
      ]),
    );
  }

  Widget _photoTool() {
    if (widget.mode == EditorMode.polaroid) return _printTool();
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
        Row(children: [
          Expanded(child: Text(widget.mode == EditorMode.sticker ? '照片' : '第 ${_selectedCell + 1} 張照片', style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800))),
          if (widget.mode != EditorMode.sticker)
            TextButton.icon(
              onPressed: () => setState(_closePhoto),
              icon: const Icon(CupertinoIcons.chevron_down, size: 16),
              label: const Text('收起', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              style: TextButton.styleFrom(foregroundColor: muted, visualDensity: VisualDensity.compact),
            ),
        ]),
        const SizedBox(height: 4),
        Text('在照片上拖曳可以移動，兩指可以放大縮小', style: TextStyle(fontSize: 12, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600)),
        const Spacer(),
        Row(children: [
          button(CupertinoIcons.arrow_right_arrow_left, '換照片', () => _pickPhoto()),
          const SizedBox(width: 8),
          button(CupertinoIcons.viewfinder, '置中', () => _setFit(_selectedCell, const PhotoFit())),
          const SizedBox(width: 8),
          button(CupertinoIcons.trash, '移除', _removePhoto, danger: true),
        ]),
      ]),
    );
  }

  /// The photo the first photo sticker was cut from, as a background.
  ImageProvider? get _firstSource {
    final bytes = _cutouts.values.map((c) => c.source).nonNulls.firstOrNull;
    if (bytes == null) return null;
    if (!identical(bytes, _firstSourceBytes)) {
      _firstSourceBytes = bytes;
      _firstSourceImage = photoImage(bytes);
    }
    return _firstSourceImage;
  }
  Uint8List? _firstSourceBytes;
  ImageProvider? _firstSourceImage;

  /// 照片貼紙's 去背: more photos, fixing an edge, a sheet to print.
  Widget _cutTool() {
    final selected = _selectedCut;
    final canFix = selected != null && _cutouts[selected]?.source != null;
    ButtonStyle outlined() => OutlinedButton.styleFrom(
      foregroundColor: ink, side: const BorderSide(color: line, width: 1.3), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: _cutting == null ? _addCutPhotos : null,
            icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
            label: const FittedBox(child: Text('加照片，自動去背', style: TextStyle(fontWeight: FontWeight.w800))),
            style: FilledButton.styleFrom(
              backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            onPressed: canFix ? _fixEdge : null,
            icon: const Icon(CupertinoIcons.scissors, size: 18),
            label: const FittedBox(child: Text('修這張的邊', style: TextStyle(fontWeight: FontWeight.w800))),
            style: outlined(),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _stickers.isEmpty ? null : _arrangeSheet,
            icon: const Icon(CupertinoIcons.square_grid_2x2, size: 18),
            label: const FittedBox(child: Text('排成貼紙單', style: TextStyle(fontWeight: FontWeight.w800))),
            style: outlined(),
          )),
          const SizedBox(width: 10),
          Expanded(child: GestureDetector(
            onTap: () => setState(() { _remember(); _cutLines = !_cutLines; }),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
              decoration: BoxDecoration(color: _cutLines ? blush : cream, borderRadius: BorderRadius.circular(14), border: Border.all(color: _cutLines ? blushLine : line, width: 1.3)),
              child: Row(children: [
                const Expanded(child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text('裁切線', style: TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)))),
                Switch(value: _cutLines, activeTrackColor: coral, onChanged: (v) => setState(() { _remember(); _cutLines = v; })),
              ]),
            ),
          )),
        ]),
        const Spacer(),
        Text(
          selected != null ? '點「修這張的邊」可以擦掉多的、補回少的。'
            : _cutouts.isEmpty ? '選好照片，裡面的人、寵物、東西會自動剪下來，一個一個變成貼紙。'
            : '點一張貼紙可以修邊；排成貼紙單加上裁切線，印出來就能剪。',
          style: TextStyle(fontSize: 12, height: 1.4, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  /// 照片貼紙's 效果: border, finish and motion of the selected sticker (or
  /// every one), and taking it out of the piece.
  Widget _effectTool() {
    final only = _selectedCut;
    final current = only != null ? _cutouts[only] : _stickers.map((s) => _cutouts[s.sticker]).nonNulls.firstOrNull;
    if (current == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('先在「去背」選照片，剪好的貼紙可以在這裡換白邊、材質，還能讓它動起來。', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: muted, fontWeight: FontWeight.w700)),
      ));
    }
    Widget row(String label, List<Widget> items) => SizedBox(height: 40, child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        SizedBox(width: 38, child: Center(child: Text(label, style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)))),
        const SizedBox(width: 6),
        for (final w in items) Padding(padding: const EdgeInsets.only(right: 6), child: Center(child: w)),
      ],
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
        child: Row(children: [
          Expanded(child: Text(only != null ? '這張貼紙（點空白處改全部）' : '全部的貼紙（點一張只改那張）', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w800))),
          if (only != null) ...[
            _MiniAction(icon: CupertinoIcons.book, label: '收進我的', onTap: () async {
              final said = await _keepCuts(only: only);
              if (mounted) showMessage(context, said);
            }),
            _MiniAction(icon: CupertinoIcons.chat_bubble_2, label: '存貼圖', onTap: () async {
              final (said, failed) = await _exportCuts(only: only);
              if (mounted) showMessage(context, said, error: failed);
            }),
          ],
        ]),
      ),
      row('白邊', [
        for (final e in StickerEdge.values)
          _Chip(label: e.label, selected: current.edge == e, onTap: () => _styleCuts((c) => c.copyWith(edge: e))),
        const SizedBox(width: 4),
        for (final (i, color) in stickerEdgeColors.indexed)
          GestureDetector(
            onTap: () => _styleCuts((c) => c.copyWith(color: i, edge: c.edge == StickerEdge.none ? StickerEdge.thick : c.edge)),
            child: Container(
              width: 30, height: 30, padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: current.color == i && current.edge != StickerEdge.none ? coral : Colors.transparent, width: 2)),
              child: Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: line, width: 1.2))),
            ),
          ),
      ]),
      row('材質', [
        for (final f in StickerFinish.values)
          _Chip(label: f.label, icon: f.icon, selected: current.finish == f, onTap: () => _styleCuts((c) => c.copyWith(finish: f))),
      ]),
      row('動態', [
        for (final m in StickerMotion.values)
          _Chip(label: m.label, icon: m.icon, selected: current.motion == m, onTap: () => _styleCuts((c) => c.copyWith(motion: m))),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
        child: Text(
          current.finish != StickerFinish.matte ? '傾斜手機，光會在貼紙上移動' : current.motion != StickerMotion.none ? '按「完成」可以做成會動的影片' : '亮片、雷射、寶石、膨膨會跟著手機傾斜反光',
          style: TextStyle(fontSize: 11, color: muted.withValues(alpha: .9), fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }

  Widget _brushTool() {
    final erasing = _pen == PenStyle.eraser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (final s in PenStyle.values)
            Expanded(child: Padding(
              padding: EdgeInsets.only(right: s == PenStyle.values.last ? 0 : 6),
              child: GestureDetector(
                onTap: () => setState(() => _setPen(s)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: _pen == s ? blush : cream, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _pen == s ? blushLine : line),
                  ),
                  child: Column(children: [
                    Icon(s.icon, size: 18, color: _pen == s ? ink : muted),
                    const SizedBox(height: 2),
                    Text(s.label, style: TextStyle(fontSize: 11, color: ink, fontWeight: _pen == s ? FontWeight.w900 : FontWeight.w600)),
                  ]),
                ),
              ),
            )),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 34, child: erasing
          ? Align(alignment: Alignment.centerLeft, child: Text('在線上抹過去就會擦掉，擦錯了按右上角的復原',
              style: TextStyle(fontSize: 12, color: muted.withValues(alpha: .95), fontWeight: FontWeight.w600)))
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: penColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = penColors[i];
                final on = c == _penColor;
                return GestureDetector(
                  onTap: () => setState(() => _penColor = c),
                  child: Container(
                    width: 34, height: 34, padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? coral : Colors.transparent, width: 2.2)),
                    child: Container(decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: line, width: 1.3))),
                  ),
                );
              },
            )),
        const Spacer(),
        Row(children: [
          if (!erasing)
            for (var i = 0; i < penWidths.length; i++)
              GestureDetector(
                onTap: () => setState(() => _penWidth = i),
                child: Container(
                  width: 40, height: 34, margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _penWidth == i ? blush : cream, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _penWidth == i ? blushLine : line),
                  ),
                  alignment: Alignment.center,
                  child: Container(width: 6.0 + i * 6, height: 6.0 + i * 6,
                    decoration: BoxDecoration(color: _penColor == Colors.white ? muted : _penColor, shape: BoxShape.circle)),
                ),
              ),
          const Spacer(),
          TextButton.icon(
            onPressed: _strokes.isEmpty ? null : _clearInk,
            icon: const Icon(CupertinoIcons.square_stack_3d_up_slash, size: 18),
            label: const Text('全部清掉', style: TextStyle(fontWeight: FontWeight.w800)),
            style: TextButton.styleFrom(foregroundColor: coral),
          ),
        ]),
      ]),
    );
  }

  /// Text on the piece itself (the strip's caption, a Polaroid's, the
  /// bubble), or words as a sticker in a look and colour. Pieces with
  /// printed text (illustrated strips) only have the words.
  Widget _textTool() {
    final words = _printedText || _wordSticker;
    return Column(children: [
      if (!_printedText) Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Row(children: [
          for (final (on, label) in [(false, switch (widget.mode) {
            EditorMode.fourCut => '底部的字',
            EditorMode.polaroid => '相片上的字',
            EditorMode.sticker => '對話泡泡',
          }), (true, '文字貼紙')])
            Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () => setState(() {
                _wordSticker = on;
                _textCtrl.text = on ? '' : _text;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: words == on ? ink : Colors.white, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: words == on ? ink : line, width: 1.3),
                ),
                child: Text(label, style: TextStyle(fontSize: 13, color: words == on ? Colors.white : ink, fontWeight: FontWeight.w800)),
              ),
            )),
        ]),
      ),
      Expanded(child: words ? _wordsTool() : _captionTool()),
    ]);
  }

  /// The selected sticker's words, if it is words.
  TypedWords? get _selectedWords {
    final i = _selectedSticker;
    return i == null || i >= _stickers.length ? null : TypedWords.parse(_stickers[i].sticker);
  }

  /// A look or colour for the next words, and for the selected words.
  void _styleWords({TextLook? look, Color? color}) => setState(() {
    _wordLook = look ?? _wordLook;
    _wordColor = color ?? _wordColor;
    final i = _selectedSticker;
    final old = _selectedWords;
    if (i == null || old == null) return;
    _remember(group: 'words:$i');
    _stickers[i] = _stickers[i].copyWith(sticker: TypedWords(old.text, look: _wordLook, color: _wordColor).id);
  });

  Widget _wordsTool() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: TextField(
          controller: _textCtrl,
          maxLength: 20,
          onSubmitted: _addText,
          style: switch (_wordLook) {
            TextLook.hand => hand(24),
            TextLook.luoyan => const TextStyle(fontFamily: 'ChenYuluoyan', fontSize: 22, color: ink),
            _ => const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
          },
          decoration: InputDecoration(
            isDense: true, filled: true, fillColor: cream, counterText: '', hintText: '想說的話…（可以拖曳、縮放）',
            hintStyle: const TextStyle(fontSize: 14, color: muted, fontFamily: 'Nunito'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: coral, width: 1.5)),
          ),
        )),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => _addText(_textCtrl.text),
          style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('加上去', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 10),
      // Looks, then colours; they also restyle the selected words.
      Row(children: [
        for (final look in TextLook.values) Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
          onTap: () => _styleWords(look: look),
          child: Container(
            height: 34, padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _wordLook == look ? blush : Colors.white, borderRadius: BorderRadius.circular(17),
              border: Border.all(color: _wordLook == look ? coral : line, width: 1.5),
            ),
            child: SizedBox(height: 24, child: FittedBox(child: TextSticker(TypedWords(look.label, look: look, color: _wordColor)))),
          ),
        ))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (final c in textColors) Expanded(child: GestureDetector(
          onTap: () => _styleWords(color: c),
          child: Center(child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: c, shape: BoxShape.circle,
              border: Border.all(color: _wordColor == c ? coral : line, width: _wordColor == c ? 3 : 1.5),
            ),
          )),
        )),
      ]),
    ]),
  );

  Widget _captionTool() => Padding(
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
  Widget build(BuildContext context) => SizedBox(height: 50, child: ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
    children: [
      for (final l in labels) Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
        onTap: () => onTap(l),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: l == selected ? ink : Colors.white, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: l == selected ? ink : line, width: 1.3),
          ),
          child: Text(l, style: TextStyle(fontSize: 13, color: l == selected ? Colors.white : ink, fontWeight: FontWeight.w800)),
        ),
      )),
    ],
  ));
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
  /// Many tabs: narrower padding.
  final bool compact;
  final VoidCallback onTap;
  const _ToolTab({required this.tool, required this.selected, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = selected ? ink : muted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12, vertical: 6),
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

/// A choice in the 效果 tool.
class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? blush : cream, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? blushLine : line, width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: selected ? ink : muted), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12.5, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
      ]),
    ),
  );
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 15),
    label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
    style: TextButton.styleFrom(foregroundColor: coral, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
  );
}

/// A transparent page on screen: a light checkerboard.
class _ClearPainter extends CustomPainter {
  final double cell;
  const _ClearPainter({this.cell = 14});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grey = Paint()..color = const Color(0xFFEDE8E3);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), grey);
      }
    }
  }

  @override
  bool shouldRepaint(_ClearPainter old) => old.cell != cell;
}

/// A collage template in little: its background and where its prints lie.
class _TemplatePreview extends StatelessWidget {
  final CollageTemplate template;
  const _TemplatePreview({required this.template});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => Stack(fit: StackFit.expand, children: [
    Image(image: template.scene.thumb, fit: BoxFit.cover),
    for (final (i, p) in template.places.indexed)
      Positioned(
        left: p.center.dx * c.maxWidth - p.width * c.maxWidth / 2,
        top: p.center.dy * c.maxHeight - p.width * c.maxWidth / .75 / 2,
        width: p.width * c.maxWidth, height: p.width * c.maxWidth / .75,
        child: Transform.rotate(angle: p.angle, child: Container(
          padding: EdgeInsets.fromLTRB(p.width * c.maxWidth * .1, p.width * c.maxWidth * .1, p.width * c.maxWidth * .1, p.width * c.maxWidth * .32),
          decoration: BoxDecoration(
            color: template.films[i].dark ? const Color(0xFF1E1E20) : Colors.white,
            boxShadow: [BoxShadow(color: ink.withValues(alpha: .25), blurRadius: 3, offset: const Offset(0, 1))],
          ),
          child: const ColoredBox(color: Color(0xFFCFC8C0)),
        )),
      ),
  ]));
}

/// One film stock in the film tool: a little print with the photo in it.
class _FilmThumb extends StatelessWidget {
  final FilmStock film;
  final ImageProvider? image;
  final PhotoFit fit;
  final double? aspect;
  final bool selected;
  final VoidCallback onTap;
  const _FilmThumb({required this.film, required this.image, required this.fit, required this.aspect, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(children: [
        Container(
          width: 66, height: 88, padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? coral : Colors.transparent, width: 2.5),
          ),
          child: IgnorePointer(child: FittedBox(child: InstantPrint(image: image, film: film, caption: '', fit: fit, aspect: aspect))),
        ),
        const SizedBox(height: 4),
        Text(film.label, style: TextStyle(fontSize: 11, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
      ]),
    ),
  );
}

/// A plain icon in the top bar, greyed out when it can't be used.
class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _IconButton({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip, onPressed: onTap, visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 22, color: onTap == null ? line : ink),
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
