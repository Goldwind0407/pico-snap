import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'filters.dart';
import 'models.dart';
import 'services/my_works.dart';
import 'services/photo_save_service.dart';
import 'theme.dart';
import 'widgets/doodle.dart';
import 'widgets/filter_thumbs.dart';
import 'widgets/instant_print.dart';
import 'widgets/sticker_book_view.dart';
import 'widgets/sticker_item.dart';

/// Geometry of the camera photos (all the same model), as fractions of the
/// photo's width (x, radius) and height (y), measured on the cream one.
abstract final class _Cam {
  static const lens = Offset(.62773, .62523), lensR = .21455;
  static const slot = Offset(.58201, .02097);
  static const shutter = Offset(.19709, .39279), shutterR = .07143;
  static const logo = Rect.fromLTWH(.70833, .06356, .19180, .09567);
  /// Film width relative to the camera.
  static const film = .42;
}

/// Camera body colours: the photo, its width / height, and the colour of our
/// name printed where the maker's logo was.
enum _Body {
  cream('assets/instant/camera_front.png', .99083, Color(0xFF55504A), Color(0xFFF2E9D6)),
  blue('assets/instant/camera_blue.png', 1.0016, Color(0xFF3F5566), Color(0xFFBBD4E0)),
  pink('assets/instant/camera_pink.png', 1.0048, Color(0xFF7A4A45), Color(0xFFEFBBB4)),
  mint('assets/instant/camera_mint.png', .9937, Color(0xFF3F5245), Color(0xFFB4C4B3)),
  black('assets/instant/camera_black.png', .9921, Color(0xFFE6E6EA), Color(0xFF43464D));

  final String asset;
  final double aspect;
  final Color text, swatch;
  const _Body(this.asset, this.aspect, this.text, this.swatch);

  String get label => switch (this) {
    _Body.cream => '奶油',
    _Body.blue => '天藍',
    _Body.pink => '粉紅',
    _Body.mint => '薄荷',
    _Body.black => '黑',
  };
}

/// Like the four-cut booth: pick the film, shoot, watch it develop, then
/// write or stick stickers on it and save.
enum _Stage { pick, aiming, ejecting, developing, done }

/// Decorating the developed print: nothing, writing, or stickers.
enum _Decor { none, filter, write, stickers }

const _controlsHeight = 196.0;

/// While shooting only the shutter row is below the camera.
const _shootingControlsHeight = 118.0;

/// Pens for writing on a print; each film starts with its own ([FilmStock.pen]).
const _handColors = [Color(0xFF1E1E20), Color(0xFFD4AF5A), Colors.white, coral, Color(0xFFFF8FB1), Color(0xFF86BBD8)];

/// 細、粗：佔相片寬度的比例。
const _handWidths = [.014, .026];

class _Print {
  final Uint8List bytes;
  final ImageProvider image;
  final FilmStock film;
  /// Picked after it develops, seeing the photo; starts as 原圖.
  PhotoFilter filter = photoFilters.first;
  /// Finger writing on the print; blank until the user writes.
  final handwriting = <Stroke>[];
  /// Stickers on the print, in fractions of the print.
  final stickers = <StickerData>[];
  bool saved = false;
  _Print(this.bytes, this.film) : image = photoImage(bytes);
}

/// 拍立得相機，流程跟四格拍貼一樣：先選底片，再拍照（這時只有大大的取景框
/// 和快門），相片從出片口吐出來、拿到前面慢慢顯影，接著看著相片選濾鏡、手寫
/// 或貼貼紙，最後存到相簿。機身顏色在右上角的設定裡換。
class PolaroidCameraScreen extends StatefulWidget {
  const PolaroidCameraScreen({super.key, this.pickPhoto, this.motion});

  /// Replaces the photo picker (tests).
  @visibleForTesting
  final Future<Uint8List?> Function()? pickPhoto;

  /// Replaces the phone's accelerometer (tests).
  @visibleForTesting
  final Stream<UserAccelerometerEvent>? motion;

  @override
  State<PolaroidCameraScreen> createState() => _PolaroidCameraScreenState();
}

class _PolaroidCameraScreenState extends State<PolaroidCameraScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  /// The camera in use, and its zoom (below 1 reaches the ultra-wide lens on
  /// Android); [_minZoom] is how far out it goes.
  CameraDescription? _device;
  double _zoom = 1, _minZoom = 1;
  /// Bumped whenever the camera should be (re)opened or let go, so an
  /// opening that finishes late (after going to the background, switching
  /// lenses, leaving) closes itself instead of taking over.
  int _cameraGen = 0;
  bool _inBackground = false;
  bool _picking = false;
  /// Opening and letting go of the camera run one after another: the
  /// plugin can't open one while another is still opening or closing
  /// (tapping flip quickly would break the camera).
  Future<void> _cameraQueue = Future.value();
  bool _switching = false;

  Future<void> _serial(Future<void> Function() op) =>
      _cameraQueue = _cameraQueue.then((_) => op()).catchError((Object e) => debugPrint('[CAMERA] $e'));

  /// Haptic ticks while the film comes out.
  Timer? _motor;
  String? _cameraError;

  // Motorised: the print comes out at a steady pace.
  // Real instax: a short pause while the motor spins up, then the film comes
  // out of the top at a steady pace and stops abruptly.
  late final _eject = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  // Real instant film takes minutes; shaking the phone (like shaking the
  // print) speeds it up. Deliberately not explained in the UI.
  late final _develop = AnimationController(vsync: this, duration: const Duration(seconds: 20))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && _stage == _Stage.developing) {
        _motion?.cancel();
        _motion = null;
        setState(() => _stage = _Stage.done);
      }
    });
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  // The print wiggles in your hand while you shake it.
  late final _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  /// The print grows to fill the stage while you write on it.
  late final _enlarge = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  StreamSubscription<UserAccelerometerEvent>? _motion;
  DateTime _lastShake = DateTime(0);

  /// How much each shake develops the print, and how hard a shake must be
  /// (m/s², gravity removed).
  static const _shakeBoost = .035, _shakeForce = 12.0;

  _Stage _stage = _Stage.pick;
  _Decor _decor = _Decor.none;
  int? _selectedSticker;
  final _stickerLayerKey = GlobalKey();
  _Print? _current;
  final _prints = <_Print>[];
  bool _saving = false;
  Color _pen = FilmStock.white.pen;
  int _penWidth = 0;
  int _inkVersion = 0;
  /// Ticks as a stroke grows: repaints the ink without rebuilding the screen.
  final _inkTick = ValueNotifier(0);
  final _printKey = GlobalKey();
  /// Body, film and filter last used, picked again next time the camera opens.
  static _Body _lastBody = _Body.cream;
  static FilmStock _lastFilm = FilmStock.white;
  late String _series = _film.group;
  _Body _body = _lastBody;
  FilmStock _film = _lastFilm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serial(_openCamera);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inkTick.dispose();
    _cameraGen++;
    _motor?.cancel();
    _camera?.dispose();
    _eject.dispose();
    _lift.dispose();
    _develop.dispose();
    _flash.dispose();
    _wiggle.dispose();
    _enlarge.dispose();
    _motion?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera must be released while the app is in the background.
    if (state == AppLifecycleState.inactive) {
      _inBackground = true;
      _cameraGen++;
      _serial(_releaseCamera);
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      _serial(() async {
        if (_camera == null && _cameraError == null && !_inBackground && mounted) await _openCamera();
      });
    }
  }

  /// Takes the preview off the screen first, then lets the camera go:
  /// disposing it while its last frame is still drawn crashes Android.
  Future<void> _releaseCamera() async {
    final old = _camera;
    if (old == null) return;
    if (mounted) setState(() => _camera = null);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await old.dispose();
  }

  Future<void> _openCamera() async {
    final gen = ++_cameraGen;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = '這台裝置沒有相機，可以從相簿選照片');
        return;
      }
      final device = _device ??= mainCamera(_cameras, CameraLensDirection.back) ?? _cameras.first;
      final camera = CameraController(device, ResolutionPreset.high, enableAudio: false);
      await camera.initialize();
      var minZoom = 1.0;
      try {
        minZoom = await camera.getMinZoomLevel();
        if (_zoom != 1) await camera.setZoomLevel(max(_zoom, minZoom));
      } catch (e) {
        debugPrint('[CAMERA] zoom: $e');
      }
      if (!mounted || gen != _cameraGen || _inBackground) {
        camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _minZoom = minZoom;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      debugPrint('[CAMERA] $e');
      if (mounted && gen == _cameraGen) {
        setState(() => _cameraError = e.code.contains('AccessDenied') ? '沒有相機權限，可以到設定開啟，或從相簿選照片' : '相機打不開，可以從相簿選照片');
      }
    } catch (e) {
      debugPrint('[CAMERA] $e');
      if (mounted && gen == _cameraGen) setState(() => _cameraError = '相機打不開，可以從相簿選照片');
    }
  }

  bool get _canFlip => mainCamera(_cameras, CameraLensDirection.back) != null && mainCamera(_cameras, CameraLensDirection.front) != null;

  Future<void> _flipCamera() async {
    if (!_canFlip || _stage != _Stage.aiming) return;
    final back = _device?.lensDirection != CameraLensDirection.front;
    await _switchTo(mainCamera(_cameras, back ? CameraLensDirection.front : CameraLensDirection.back)!);
  }

  Future<void> _switchTo(CameraDescription device, [double zoom = 1]) async {
    if (_switching) return;
    _switching = true;
    setState(() {
      _device = device;
      _zoom = zoom;
      _minZoom = 1;
    });
    try {
      await _serial(() async {
        await _releaseCamera();
        if (mounted) await _openCamera();
      });
    } finally {
      _switching = false;
    }
  }

  /// The lenses to choose from for the way the camera is facing.
  List<LensChoice> get _lenses {
    final device = _device;
    return device == null ? const [] : lensChoices(_cameras, device.lensDirection, minZoom: _minZoom);
  }

  Future<void> _pickLens(LensChoice lens) async {
    if (_stage != _Stage.aiming) return;
    HapticFeedback.selectionClick();
    final camera = _camera;
    if (lens.camera == _device && camera != null) {
      setState(() => _zoom = lens.zoom);
      try {
        await camera.setZoomLevel(lens.zoom);
      } catch (e) {
        debugPrint('[CAMERA] zoom: $e');
      }
      return;
    }
    await _switchTo(lens.camera, lens.zoom);
  }

  Future<void> _shoot() async {
    if (_stage != _Stage.aiming) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || camera.value.isTakingPicture) return _fromGallery();
    HapticFeedback.heavyImpact();
    _flash.forward(from: 0);
    try {
      final file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      // The plugin leaves each shot in the cache; we keep the bytes.
      File(file.path).delete().ignore();
      if (mounted) await _printOut(bytes);
    } catch (e) {
      debugPrint('[CAMERA] 拍照失敗: $e');
      if (mounted) showMessage(context, '拍照失敗，請再試一次', error: true, above: _controlsHeight);
    }
  }

  Future<void> _fromGallery() async {
    // One picker at a time: a second tap while it opens would start another.
    if (_stage != _Stage.aiming || _picking) return;
    _picking = true;
    Uint8List? bytes;
    try {
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!();
      } else {
        final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
        bytes = await file?.readAsBytes();
      }
    } catch (e) {
      debugPrint('[CAMERA] 選照片失敗: $e');
      if (mounted) showMessage(context, '打不開相簿，請再試一次', error: true, above: _controlsHeight);
    } finally {
      _picking = false;
    }
    if (bytes != null && mounted && _stage == _Stage.aiming) await _printOut(bytes);
  }

  /// The print comes out of the slot, is taken to the front and develops.
  Future<void> _printOut(Uint8List bytes) async {
    final print = _Print(bytes, _film);
    setState(() {
      _current = print;
      _stage = _Stage.ejecting;
    });
    _develop.value = 0;
    _lift.value = 0;
    // The motor whirs while the film is moving.
    _motor?.cancel();
    _motor = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final e = _eject.value;
      if (e > _emergeStart && e < _emergeEnd) HapticFeedback.selectionClick();
    });
    try {
      // orCancel: leaving mid-print cancels the ticker; a plain await would
      // then never return and the motor would tick on forever.
      await _eject.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    } finally {
      _motor?.cancel();
      _motor = null;
    }
    HapticFeedback.lightImpact(); // stops with a little clunk
    if (!mounted) return;
    // Nobody is looking through the camera until the next shot; keep it
    // from heating the phone.
    _serial(() async {
      final c = _camera;
      if (_stage != _Stage.aiming && c != null && c.value.isInitialized && !c.value.isPreviewPaused) await c.pausePreview();
    });
    _prints.add(print);
    setState(() => _stage = _Stage.developing);
    _develop.forward(from: 0);
    _listenForShakes();
    await _lift.forward(from: 0);
  }

  void _listenForShakes() {
    _motion?.cancel();
    try {
      _motion = (widget.motion ?? userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)).listen(
        (e) {
          if (_stage != _Stage.developing) return;
          if (e.x * e.x + e.y * e.y + e.z * e.z < _shakeForce * _shakeForce) return;
          final now = DateTime.now();
          if (now.difference(_lastShake) < const Duration(milliseconds: 90)) return;
          _lastShake = now;
          _develop.value = min(1, _develop.value + _shakeBoost);
          if (_develop.value < 1) _develop.forward();
          _wiggle.forward(from: 0);
        },
        onError: (Object e) => debugPrint('[CAMERA] 讀不到動作感測器: $e'),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[CAMERA] 讀不到動作感測器: $e');
    }
  }

  void _skipDeveloping() {
    if (_stage == _Stage.developing) _develop.animateTo(1, duration: const Duration(milliseconds: 600));
  }

  void _again() {
    _serial(() async {
      final c = _camera;
      if (c != null && c.value.isInitialized && c.value.isPreviewPaused) await c.resumePreview();
    });
    _eject.value = 0;
    _lift.value = 0;
    _develop.value = 0;
    setState(() {
      _current = null;
      _stage = _Stage.aiming;
      _decor = _Decor.none;
      _selectedSticker = null;
    });
    _enlarge.value = 0;
  }

  /// Step 1 → 2: the film is picked, shoot.
  void _start() => setState(() => _stage = _Stage.aiming);

  /// Back from shooting to picking the film.
  void _backToPick() => setState(() => _stage = _Stage.pick);

  /// Camera colour: a setting, not part of every shot.
  Future<void> _settings() => showModalBottomSheet<void>(
    context: context, backgroundColor: cream, showDragHandle: true,
    builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('相機顏色', style: TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final b in _Body.values)
            GestureDetector(
              onTap: () {
                setState(() => _lastBody = _body = b);
                setSheet(() {});
              },
              child: Column(children: [
                Container(
                  width: 54, height: 54, padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _body == b ? coral : Colors.transparent, width: 3)),
                  child: ClipOval(child: Image.asset(b.asset, fit: BoxFit.cover)),
                ),
                const SizedBox(height: 6),
                Text(b.label, style: TextStyle(fontSize: 12, color: ink, fontWeight: _body == b ? FontWeight.w900 : FontWeight.w600)),
              ]),
            ),
        ]),
      ]),
    ))),
  );

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _selectedSticker = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_develop.value < 1) await _develop.animateTo(1, duration: const Duration(milliseconds: 400));
    final error = await PhotoSaveService.saveBoundary(_printKey, longSide: 2000, keep: WorkKind.instant);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) _current?.saved = true;
    });
    showMessage(context, error ?? '已存到相簿 ♡', error: error != null, above: _controlsHeight);
  }

  void _startWriting() {
    final print = _current;
    if (print == null || _stage != _Stage.done || _decor != _Decor.none) return;
    setState(() {
      _decor = _Decor.write;
      if (print.handwriting.isEmpty) _pen = print.film.pen;
    });
    _enlarge.forward();
  }

  void _startStickers() => _startDecor(_Decor.stickers);

  void _startFilter() => _startDecor(_Decor.filter);

  void _startDecor(_Decor decor) {
    if (_current == null || _stage != _Stage.done || _decor != _Decor.none) return;
    setState(() => _decor = decor);
    _enlarge.forward();
  }

  /// Done writing or sticking: the print goes back to its place.
  void _stopDecorating() {
    setState(() {
      _decor = _Decor.none;
      _selectedSticker = null;
    });
    _enlarge.reverse();
  }

  void _addSticker(String sticker, [double scale = 1]) => setState(() {
    final stickers = _current!.stickers;
    final n = stickers.length;
    stickers.add(StickerData(sticker: sticker, scale: scale, center: Offset(.5 + (n % 3 - 1) * .18, .38 + (n % 2) * .14)));
    _selectedSticker = stickers.length - 1;
    _current!.saved = false;
  });

  Offset _toPrint(Offset global) => (_stickerLayerKey.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _penDown(Offset at, Size size) => setState(() {
    _current!.saved = false;
    _current!.handwriting.add(Stroke(points: [normalise(at, size)], color: _pen, width: _handWidths[_penWidth], style: PenStyle.pen));
    _inkVersion++;
  });

  void _penMove(Offset at, Size size) {
    final p = normalise(at, size), last = _current!.handwriting.last.points;
    if ((p - last.last).distance * size.width < 1) return;
    last.add(p);
    _inkTick.value++;
  }

  void _editInk(void Function(List<Stroke> strokes) edit) => setState(() {
    _current!.saved = false;
    edit(_current!.handwriting);
    _inkVersion++;
  });

  /// Prints that would be lost by leaving: unsaved ones, or one coming out.
  bool get _unsaved => _stage == _Stage.ejecting || _stage == _Stage.developing || _prints.any((p) => !p.saved);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _stage == _Stage.pick && !_unsaved,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (_stage == _Stage.aiming) return _backToPick();
      if (_decor != _Decor.none) return _stopDecorating();
      if (_stage == _Stage.pick && !_unsaved) return Navigator.of(context).pop();
      final navigator = Navigator.of(context);
      if (await confirmLeave(context, '拍好的相片還沒存到相簿，離開就會不見喔。', stay: '留下來')) navigator.pop();
    },
    child: _page(),
  );

  Widget _page() => Scaffold(
    backgroundColor: cream,
    body: Stack(children: [
      SafeArea(child: Column(children: [
        _topBar(),
        if (_stage == _Stage.pick) Expanded(child: _pickView())
        else ...[
          Expanded(child: LayoutBuilder(builder: (context, c) => AnimatedBuilder(
            animation: Listenable.merge([_eject, _lift, _develop, _wiggle, _enlarge]),
            builder: (context, _) => _stageView(c.biggest),
          ))),
          SizedBox(height: _bottomHeight, child: _bottom()),
        ],
      ])),
      // Flash.
      IgnorePointer(child: AnimatedBuilder(
        animation: _flash,
        builder: (context, _) => Opacity(
          opacity: _flash.status == AnimationStatus.forward ? (1 - Curves.easeOut.transform(_flash.value)) * .9 : 0,
          child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
        ),
      )),
    ]),
  );

  double get _bottomHeight => switch (_stage) {
    _Stage.aiming => _shootingControlsHeight,
    _Stage.done when _decor == _Decor.stickers => max(_controlsHeight, MediaQuery.sizeOf(context).height * .36),
    _ => _controlsHeight,
  };

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(children: [
      IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(CupertinoIcons.back, color: ink, size: 26)),
      Expanded(child: Text(switch (_stage) {
        _Stage.pick => '選底片',
        _Stage.aiming => _film.label,
        _ => '拍立得',
      }, style: const TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
      if (_canFlip && _stage == _Stage.aiming)
        IconButton(tooltip: '切換鏡頭', onPressed: _flipCamera, icon: const Icon(CupertinoIcons.camera_rotate), color: ink),
      if (_stage == _Stage.pick || _stage == _Stage.aiming)
        IconButton(tooltip: '設定', onPressed: _settings, icon: const Icon(CupertinoIcons.gear), color: ink),
    ]),
  );

  /// Step 1: the film, big.
  Widget _pickView() => Column(children: [
    Expanded(child: Padding(
      padding: const EdgeInsets.fromLTRB(40, 16, 40, 16),
      // Fills the room, so the film is shown big.
      child: FittedBox(child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .16), blurRadius: 18, offset: const Offset(0, 8))]),
        child: InstantPrint(film: _film, caption: ''),
      )),
    )),
    _seriesTabs(),
    const SizedBox(height: 8),
    _filmRow(),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _start,
        icon: const Icon(CupertinoIcons.camera_fill),
        label: const Text('開始拍照', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      )),
    ),
  ]);

  /// 基本 / 三麗鷗 / 寶可夢 / 聯名: which films the row below shows.
  Widget _seriesTabs() => SizedBox(height: 34, child: ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    itemCount: FilmStock.series.length,
    separatorBuilder: (_, __) => const SizedBox(width: 8),
    itemBuilder: (_, i) {
      final g = FilmStock.series[i], on = g == _series;
      return GestureDetector(
        onTap: () => setState(() => _series = g),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? ink : Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: on ? ink : line)),
          child: Text(g, style: TextStyle(fontSize: 13, color: on ? Colors.white : ink, fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
        ),
      );
    },
  ));

  /// The films of the chosen series, each a small picture of the card.
  Widget _filmRow() {
    final films = [for (final f in FilmStock.values) if (f.group == _series) f];
    return SizedBox(height: 96, child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: films.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) {
        final f = films[i], on = f == _film;
        return GestureDetector(
          onTap: () => setState(() => _lastFilm = _film = f),
          child: SizedBox(width: 72, child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 54, height: 72, padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: on ? coral : Colors.transparent, width: 2)),
              child: DecoratedBox(
                decoration: BoxDecoration(color: const Color(0xFFDCE3EA), boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 4, offset: const Offset(0, 2))]),
                child: Image.asset(f.asset, fit: BoxFit.fill, cacheWidth: 150, filterQuality: FilterQuality.medium),
              ),
            ),
            const SizedBox(height: 4),
            Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: ink, fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
          ])),
        );
      },
    ));
  }

  static const _emergeStart = .16, _emergeEnd = .9;

  /// How far the film is out of the slot (0–1) at eject progress [e].
  static double _emerged(double e) {
    if (e <= _emergeStart) return 0;
    if (e >= _emergeEnd) return 1;
    final t = (e - _emergeStart) / (_emergeEnd - _emergeStart);
    // Steady motor with a faint gear ripple.
    return (t + sin(t * pi * 34) * .004).clamp(0.0, 1.0);
  }

  Widget _stageView(Size size) {
    // While shooting there is nothing else below: the camera and the
    // viewfinder above it get the room.
    final cw = [size.width * (_stage == _Stage.aiming ? .7 : .8), size.height * (_stage == _Stage.aiming ? .42 : .5), 360.0].reduce(min);
    final ch = cw / _body.aspect;
    final camLeft = (size.width - cw) / 2, camTop = size.height - ch - 4;
    final aspect = (_current?.film ?? _film).aspect;
    final pw = cw * _Cam.film, ph = pw / aspect;
    final slotX = camLeft + _Cam.slot.dx * cw, slotY = camTop + _Cam.slot.dy * ch + 10;
    // Coming out of the slot; the tail stays in the slot like the real thing.
    final e = _eject.value;
    final out = _emerged(e);
    final moving = e > _emergeStart && e < _emergeEnd;
    final jitter = moving ? sin(e * 900) * .6 : 0.0;
    final ejected = Rect.fromLTWH(slotX - pw / 2 + jitter, slotY - out * ph * .9, pw, ph);
    // Taken to the front to watch it develop.
    final rw = min(size.width * .72, (size.height - 16) * .92 * aspect);
    final rh = rw / aspect;
    final review = Rect.fromLTWH((size.width - rw) / 2, max(8.0, (size.height - rh) / 2 - 4), rw, rh);
    final l = Curves.easeInOutCubic.transform(_lift.value);
    // Writing: as big as the stage allows, straightened.
    final bw = min(size.width - 16, (size.height - 12) * aspect), bh = bw / aspect;
    final big = Rect.fromLTWH((size.width - bw) / 2, (size.height - bh) / 2, bw, bh);
    final z = Curves.easeOutCubic.transform(_enlarge.value);
    final rect = Rect.lerp(Rect.lerp(ejected, review, l)!, big, z)!;

    final print = _current;
    final printSize = Size(InstantPrint.width, InstantPrint.heightOf(print?.film ?? _film));
    final printView = print == null ? null : Positioned.fromRect(rect: rect, child: Transform.rotate(
      angle: -.035 * l * (1 - z) + (_wiggle.isAnimating ? sin(_wiggle.value * pi * 4) * .06 * (1 - _wiggle.value) : 0),
      child: GestureDetector(
        onTap: _stage == _Stage.developing ? _skipDeveloping : null,
        child: FittedBox(child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .1 + .15 * l), blurRadius: 8 + 14 * l, offset: Offset(0, 3 + 7 * l))]),
          child: Stack(children: [
            PhotoCapture(key: _printKey, child: SizedBox.fromSize(size: printSize, child: Stack(key: _stickerLayerKey, clipBehavior: Clip.none, children: [
              Positioned.fill(child: InstantPrint(
                image: print.image, film: print.film, filter: print.filter, develop: _develop.value, caption: '',
                handwriting: print.handwriting, handwritingVersion: _inkVersion, handwritingRepaint: _inkTick,
                onCaption: _stage == _Stage.done && _decor == _Decor.none ? _startWriting : null,
              )),
              // Only movable while sticking; the layer is the print's size.
              Positioned.fill(child: IgnorePointer(ignoring: _decor != _Decor.stickers, child: Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < print.stickers.length; i++)
                StickerItem(
                  data: print.stickers[i],
                  animatePlacement: _selectedSticker == i,
                  animationsEnabled: !_saving,
                  canvas: printSize,
                  zoom: rect.width / printSize.width,
                  selected: _decor == _Decor.stickers && _selectedSticker == i,
                  toLocal: _toPrint,
                  onSelect: () => setState(() => _selectedSticker = i),
                  onEditStart: () => setState(() {
                    _selectedSticker = i;
                    print.saved = false;
                  }),
                  onChanged: (d) => setState(() => print.stickers[i] = d),
                  onFlip: () => setState(() => print.stickers[i] = print.stickers[i].copyWith(flipped: !print.stickers[i].flipped)),
                  onDelete: () => setState(() {
                    print.stickers.removeAt(i);
                    _selectedSticker = null;
                  }),
                ),
              ]))),
            ]))),
            if (_decor == _Decor.write) Positioned.fill(child: DoodleInput(onStart: _penDown, onMove: _penMove, onEnd: () {})),
          ]),
        )),
      ),
    ));
    final camera = Positioned(
      left: camLeft, top: camTop, width: cw, height: ch,
      child: IgnorePointer(
        ignoring: _stage != _Stage.aiming,
        child: Opacity(opacity: (1 - .82 * l) * (1 - z), child: _CameraBody(body: _body, lens: _viewfinder(), onShutter: _shoot)),
      ),
    );
    // A big viewfinder above the camera, the shape of the print's window, so
    // you see exactly what will be printed. Fades while the motor spins up.
    final win = _film.window;
    final winAspect = win.width * _film.aspect / win.height;
    final vh = min(camTop - 28, size.width * (_stage == _Stage.aiming ? .86 : .66) / winAspect);
    final vw = vh * winAspect;
    final finderOpacity = _stage == _Stage.aiming ? 1.0 : (1 - e / _emergeStart).clamp(0.0, 1.0);
    final finder = vh < 60 || finderOpacity == 0 ? null : Positioned(
      left: (size.width - vw) / 2, top: max(6.0, (camTop - vh) / 2 - 4), width: vw, height: vh,
      child: IgnorePointer(child: Opacity(opacity: finderOpacity, child: _Finder(
        error: _cameraError,
        child: _camera?.value.isInitialized == true ? SizedBox.expand(child: _viewfinder()) : null,
      ))),
    );
    final lenses = _lenses;
    final lensRow = finder == null || lenses.length < 2 || _camera == null ? null : Positioned(
      left: (size.width - vw) / 2, width: vw, top: max(6.0, (camTop - vh) / 2 - 4) + vh - 44, height: 34,
      child: Opacity(opacity: finderOpacity, child: Center(child: _LensPicker(
        lenses: lenses,
        selected: lenses.indexWhere((l) => l.camera == _device && (l.zoom - _zoom).abs() < .01),
        onPick: _stage == _Stage.aiming ? _pickLens : null,
      ))),
    );
    // Behind the camera while it comes out of the slot, in front once taken out.
    return Stack(clipBehavior: Clip.none, children: [
      if (finder != null) finder,
      if (lensRow != null) lensRow,
      if (printView != null && l < .5) printView,
      camera,
      if (printView != null && l >= .5) printView,
    ]);
  }

  Widget _viewfinder() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return ColoredBox(
        color: const Color(0xFF26282E),
        child: Center(child: Icon(_cameraError != null ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.camera, color: Colors.white38, size: 34)),
      );
    }
    final s = camera.value.previewSize!;
    // The preview size is landscape; fill the round lens.
    return FittedBox(fit: BoxFit.cover, child: SizedBox(width: s.height, height: s.width, child: CameraPreview(camera)));
  }

  /// The photo under every filter; tap one to put it on the print.
  Widget _filterBar() => Column(children: [
    Expanded(child: FilterThumbs(
      image: _current!.image, selected: _current!.filter.id,
      onPick: (f) => setState(() => _current!.filter = f),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    )),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _stopDecorating,
        style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 12)),
        child: const Text('選好了', style: TextStyle(fontWeight: FontWeight.w800)),
      )),
    ),
  ]);

  Widget _controls() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _SideButton(icon: CupertinoIcons.rectangle_stack, label: '換底片', onTap: _backToPick),
    GestureDetector(
      onTap: _shoot,
      child: Container(
        width: 78, height: 78,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: coral.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 6))]),
        padding: const EdgeInsets.all(6),
        child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: coral), child: const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 32)),
      ),
    ),
    _SideButton(icon: CupertinoIcons.photo_on_rectangle, label: '從相簿', onTap: _fromGallery),
  ]);

  Widget _bottom() => switch (_stage) {
    _Stage.pick => const SizedBox.shrink(),
    _Stage.aiming => _controls(),
    _Stage.ejecting => const Center(child: Text('出片中…', style: TextStyle(fontSize: 15, color: muted, fontWeight: FontWeight.w800))),
    _Stage.developing => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('顯影中…', style: TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text('輕點照片可以跳過', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
    ])),
    _Stage.done when _decor == _Decor.filter => _filterBar(),
    _Stage.done when _decor == _Decor.write => _penBar(),
    _Stage.done when _decor == _Decor.stickers => _stickerBar(),
    _Stage.done => _doneBar(),
  };

  /// Write or stick stickers on the print, then shoot again or save.
  Widget _doneBar() {
    final inked = _current?.handwriting.isNotEmpty ?? false;
    final stuck = _current?.stickers.isNotEmpty ?? false;
    final filtered = _current != null && _current!.filter.id != photoFilters.first.id;
    final saved = _current?.saved ?? false;
    ButtonStyle decor(Color color, Color border) => OutlinedButton.styleFrom(
      foregroundColor: ink, backgroundColor: color, side: BorderSide(color: border),
      padding: const EdgeInsets.symmetric(vertical: 12), shape: const StadiumBorder(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _startFilter, icon: const Icon(CupertinoIcons.sparkles, size: 18),
            label: Text(filtered ? _current!.filter.name : '濾鏡', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            style: decor(lilac, lilacLine),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: _startWriting, icon: const Icon(CupertinoIcons.pencil, size: 18),
            label: Text(inked ? '修改手寫' : '手寫', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: decor(blush, blushLine),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: _startStickers, icon: const Icon(CupertinoIcons.smiley, size: 18),
            label: Text(stuck ? '修改貼紙' : '貼貼紙', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: decor(butter, butterLine),
          )),
        ]),
        const SizedBox(height: 6),
        const Text('換個濾鏡、簽名寫日期，或貼幾張貼紙', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _again, icon: const Icon(CupertinoIcons.camera, size: 18), label: const Text('再拍一張', style: TextStyle(fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(foregroundColor: ink, side: const BorderSide(color: line, width: 1.4), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          )),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(
            onPressed: saved || _saving ? null : _save,
            icon: Icon(saved ? CupertinoIcons.checkmark : CupertinoIcons.arrow_down_to_line, size: 18),
            label: Text(_saving ? '儲存中…' : saved ? '已存到相簿' : '存到相簿', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: coral, disabledBackgroundColor: saved ? sage : null, disabledForegroundColor: saved ? ink : null,
              padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )),
        ]),
      ]),
    );
  }

  /// The handwriting tools, in place of the buttons while writing.
  Widget _penBar() {
    final strokes = _current?.handwriting ?? const <Stroke>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final c in _handColors)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: GestureDetector(
              onTap: () => setState(() => _pen = c),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle,
                  border: Border.all(color: _pen == c ? coral : line, width: _pen == c ? 3 : 1.4),
                ),
              ),
            )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (final (i, label) in ['細', '粗'].indexed)
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
              label: Text(label), selected: _penWidth == i, onSelected: (_) => setState(() => _penWidth = i),
              selectedColor: blush, showCheckmark: false,
            )),
          const Spacer(),
          IconButton(
            tooltip: '復原', icon: const Icon(CupertinoIcons.arrow_uturn_left),
            onPressed: strokes.isEmpty ? null : () => _editInk((s) => s.removeLast()),
          ),
          IconButton(
            tooltip: '全部清掉', icon: const Icon(CupertinoIcons.trash),
            onPressed: strokes.isEmpty ? null : () => _editInk((s) => s.clear()),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _stopDecorating,
            style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
            child: const Text('寫好了', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ]),
    );
  }

  /// The sticker book, in place of the buttons while sticking.
  Widget _stickerBar() => Column(children: [
    Expanded(child: StickerBookView(onPick: _addSticker, used: {for (final s in _current?.stickers ?? const <StickerData>[]) s.sticker})),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _stopDecorating,
        style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 12)),
        child: const Text('貼好了', style: TextStyle(fontWeight: FontWeight.w800)),
      )),
    ),
  ]);
}

/// The instant camera photo with the live picture in its lens, our own name
/// where the maker's logo was, and a working shutter.
/// A focal length to shoot at: its own lens (iOS lists each one as a
/// camera), or the main camera zoomed (Android reaches its ultra-wide by
/// zooming below 1×). Never a digital crop.
typedef LensChoice = ({String label, CameraDescription camera, double zoom});

/// The main camera facing [facing]: the standard wide lens.
CameraDescription? mainCamera(List<CameraDescription> cameras, CameraLensDirection facing) {
  final mine = cameras.where((c) => c.lensDirection == facing);
  return mine.where((c) => c.lensType == CameraLensType.wide).firstOrNull ??
      mine.where((c) => c.lensType != CameraLensType.ultraWide && c.lensType != CameraLensType.telephoto).firstOrNull ??
      mine.firstOrNull;
}

/// The lenses to offer for [facing], widest first. [minZoom] is the main
/// camera's: below 1 it has an ultra-wide behind it.
List<LensChoice> lensChoices(List<CameraDescription> cameras, CameraLensDirection facing, {double minZoom = 1}) {
  final main = mainCamera(cameras, facing);
  if (main == null) return const [];
  CameraDescription? of(CameraLensType t) => cameras.where((c) => c.lensDirection == facing && c.lensType == t).firstOrNull;
  final ultra = of(CameraLensType.ultraWide), tele = of(CameraLensType.telephoto);
  String x(double z) => '${(z * 10).round() / 10}'.replaceAll(RegExp(r'\.0$'), '');
  return [
    if (ultra != null) (label: '0.5×', camera: ultra, zoom: 1.0)
    else if (minZoom < .95) (label: '${x(minZoom)}×', camera: main, zoom: minZoom),
    (label: '1×', camera: main, zoom: 1.0),
    if (tele != null) (label: '長焦', camera: tele, zoom: 1.0),
  ];
}

/// Focal lengths as a pill over the viewfinder, like a phone camera.
class _LensPicker extends StatelessWidget {
  final List<LensChoice> lenses;
  final int selected;
  final ValueChanged<LensChoice>? onPick;
  const _LensPicker({required this.lenses, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .35), borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < lenses.length; i++)
          GestureDetector(
            onTap: onPick == null ? null : () => onPick!(lenses[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: i == selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(14)),
              child: Text(lenses[i].label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: i == selected ? ink : Colors.white)),
            ),
          ),
      ]),
    ),
  );
}

class _CameraBody extends StatelessWidget {
  final _Body body;
  final Widget lens;
  final VoidCallback onShutter;
  const _CameraBody({required this.body, required this.lens, required this.onShutter});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final w = c.maxWidth, h = c.maxHeight;
    final r = _Cam.lensR * w;
    final lc = Offset(_Cam.lens.dx * w, _Cam.lens.dy * h);
    final sr = _Cam.shutterR * w;
    final sc = Offset(_Cam.shutter.dx * w, _Cam.shutter.dy * h);
    final logo = Rect.fromLTWH(_Cam.logo.left * w, _Cam.logo.top * h, _Cam.logo.width * w, _Cam.logo.height * h);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: Image.asset(body.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true)),
      Positioned.fromRect(rect: Rect.fromCircle(center: lc, radius: r), child: ClipOval(child: Stack(fit: StackFit.expand, children: [
        lens,
        // Glass: a highlight and a dark rim.
        IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-.4, -.5), radius: 1, colors: [Colors.white.withValues(alpha: .26), Colors.transparent, Colors.black.withValues(alpha: .35)], stops: const [0, .55, 1]),
        ))),
      ]))),
      Positioned.fromRect(rect: logo, child: FittedBox(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text('快趣拍', style: TextStyle(fontSize: 40, height: 1, letterSpacing: 4, color: body.text, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Instant Camera', style: TextStyle(fontSize: 20, height: 1, color: body.text.withValues(alpha: .9), fontWeight: FontWeight.w700)),
      ]))),
      // The red shutter button on the body works too.
      Positioned.fromRect(rect: Rect.fromCircle(center: sc, radius: sr), child: GestureDetector(
        onTap: onShutter,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      )),
    ]);
  });
}

/// The big viewfinder: the live picture with framing corners, or why there is none.
class _Finder extends StatelessWidget {
  final Widget? child;
  final String? error;
  const _Finder({this.child, this.error});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF26282E), borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .16), blurRadius: 14, offset: const Offset(0, 6))],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Stack(fit: StackFit.expand, children: [
      if (child != null) child!
      else Center(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(error != null ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.camera, color: Colors.white38, size: 34),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70, fontWeight: FontWeight.w700)),
          ],
        ]),
      )),
      const CustomPaint(painter: _CornersPainter()),
    ])),
  );
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const m = 14.0, l = 22.0;
    for (final (x, y, dx, dy) in [(m, m, 1.0, 1.0), (size.width - m, m, -1.0, 1.0), (m, size.height - m, 1.0, -1.0), (size.width - m, size.height - m, -1.0, -1.0)]) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * l, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * l), p);
    }
  }

  @override
  bool shouldRepaint(_CornersPainter oldDelegate) => false;
}

/// Writes on the print's white strip. Owns its controller so it lives as long
/// as the dialog, closing animation included.
class _SideButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SideButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(width: 74, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: line)),
        child: Icon(icon, color: ink),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w800)),
    ])),
  );
}
