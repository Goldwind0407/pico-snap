import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'editor_screen.dart';
import 'filters.dart';
import 'live_filter.dart';
import 'models.dart';
import 'services/my_works.dart';
import 'services/photo_save_service.dart';
import 'theme.dart';
import 'widgets/doodle.dart';
import 'widgets/handwriting_pad.dart';
import 'widgets/instant_print.dart';

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
}

enum _Stage { aiming, ejecting, developing, done }

const _controlsHeight = 196.0;

class _Print {
  final Uint8List bytes;
  final ImageProvider image;
  final FilmStock film;
  final PhotoFilter filter;
  /// Finger writing on the bottom border; blank until the user writes.
  List<Stroke> handwriting = const [];
  bool saved = false;
  _Print(this.bytes, this.film, this.filter) : image = MemoryImage(bytes);
}

/// 拍立得相機：取景在鏡頭裡，按下快門後相片從上方的出片口慢慢吐出來，
/// 拿到前面之後從淡灰藍的空白慢慢顯影。可以換機身顏色、白底片或黑底片；
/// 拍好的相片可以存到相簿，或放進拍立得拼貼。
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
  StreamSubscription<UserAccelerometerEvent>? _motion;
  DateTime _lastShake = DateTime(0);

  /// How much each shake develops the print, and how hard a shake must be
  /// (m/s², gravity removed).
  static const _shakeBoost = .035, _shakeForce = 12.0;

  _Stage _stage = _Stage.aiming;
  _Print? _current;
  final _prints = <_Print>[];
  bool _saving = false;
  final _printKey = GlobalKey();
  _Body _body = _Body.cream;
  FilmStock _film = FilmStock.white;
  PhotoFilter _filter = photoFilters.first;
  /// The filter row is rebuilt after each shot; it starts where it was left.
  double _filterOffset = 0;
  ScrollController? _filterScroll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serial(_openCamera);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGen++;
    _motor?.cancel();
    _camera?.dispose();
    _eject.dispose();
    _lift.dispose();
    _develop.dispose();
    _flash.dispose();
    _wiggle.dispose();
    _filterScroll?.dispose();
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
    final print = _Print(bytes, _film, _filter);
    // The row goes away while printing; a new controller picks up the offset.
    final old = _filterScroll;
    _filterScroll = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
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
    _eject.value = 0;
    _lift.value = 0;
    _develop.value = 0;
    setState(() {
      _current = null;
      _stage = _Stage.aiming;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    if (_develop.value < 1) await _develop.animateTo(1, duration: const Duration(milliseconds: 400));
    final error = await PhotoSaveService.saveBoundary(_printKey, longSide: 2000, keep: WorkKind.instant);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) _current?.saved = true;
    });
    showMessage(context, error ?? '已存到相簿 ♡', error: error != null, above: _controlsHeight);
  }

  Future<void> _handwrite() async {
    final print = _current;
    if (print == null || _stage != _Stage.done) return;
    final area = InstantPrint.captionArea(print.film);
    final strokes = await showHandwritingPad(context,
      initial: print.handwriting, aspect: area.width / area.height, paper: print.film.swatch, pen: print.film.text);
    if (strokes != null && mounted) setState(() => print.handwriting = strokes);
  }

  void _collage() {
    if (_prints.isEmpty) return showMessage(context, '先拍一張，再做成拼貼', above: _controlsHeight);
    final last = _prints.length > 4 ? _prints.sublist(_prints.length - 4) : _prints;
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(
      mode: EditorMode.polaroid,
      photos: [for (final p in last) p.bytes],
      // Handwritten instead of typed: no sample captions on top of it.
      captions: [for (final _ in last) ''],
      handwriting: [for (final p in last) p.handwriting],
      films: [for (final p in last) p.film],
      filters: [for (final p in last) p.filter],
    )));
  }

  /// Prints that would be lost by leaving: unsaved ones, or one coming out.
  bool get _unsaved => _stage == _Stage.ejecting || _stage == _Stage.developing || _prints.any((p) => !p.saved);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_unsaved,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
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
        Expanded(child: LayoutBuilder(builder: (context, c) => AnimatedBuilder(
          animation: Listenable.merge([_eject, _lift, _develop, _wiggle]),
          builder: (context, _) => _stageView(c.biggest),
        ))),
        SizedBox(height: _controlsHeight, child: _bottom()),
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

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
    child: Row(children: [
      IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
      const Expanded(child: Text('Instant Camera', style: TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
      if (_canFlip)
        IconButton(onPressed: _stage == _Stage.aiming ? _flipCamera : null, icon: const Icon(Icons.cameraswitch_outlined), color: ink, disabledColor: line),
    ]),
  );

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
    final cw = [size.width * .8, size.height * .5, 360.0].reduce(min);
    final ch = cw / _body.aspect;
    final camLeft = (size.width - cw) / 2, camTop = size.height - ch - 4;
    final pw = cw * _Cam.film, ph = pw / FilmStock.aspect;
    final slotX = camLeft + _Cam.slot.dx * cw, slotY = camTop + _Cam.slot.dy * ch + 10;
    // Coming out of the slot; the tail stays in the slot like the real thing.
    final e = _eject.value;
    final out = _emerged(e);
    final moving = e > _emergeStart && e < _emergeEnd;
    final jitter = moving ? sin(e * 900) * .6 : 0.0;
    final ejected = Rect.fromLTWH(slotX - pw / 2 + jitter, slotY - out * ph * .9, pw, ph);
    // Taken to the front to watch it develop.
    final rw = min(size.width * .72, (size.height - 16) * .92 * FilmStock.aspect);
    final rh = rw / FilmStock.aspect;
    final review = Rect.fromLTWH((size.width - rw) / 2, max(8.0, (size.height - rh) / 2 - 4), rw, rh);
    final l = Curves.easeInOutCubic.transform(_lift.value);
    final rect = Rect.lerp(ejected, review, l)!;

    final print = _current;
    final printView = print == null ? null : Positioned.fromRect(rect: rect, child: Transform.rotate(
      angle: -.035 * l + (_wiggle.isAnimating ? sin(_wiggle.value * pi * 4) * .06 * (1 - _wiggle.value) : 0),
      child: GestureDetector(
        onTap: _stage == _Stage.developing ? _skipDeveloping : null,
        child: FittedBox(child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .1 + .15 * l), blurRadius: 8 + 14 * l, offset: Offset(0, 3 + 7 * l))]),
          child: RepaintBoundary(key: _printKey, child: InstantPrint(
            image: print.image, film: print.film, filter: print.filter, develop: _develop.value, caption: '', handwriting: print.handwriting,
            onCaption: _stage == _Stage.done ? _handwrite : null,
          )),
        )),
      ),
    ));
    final camera = Positioned(
      left: camLeft, top: camTop, width: cw, height: ch,
      child: IgnorePointer(
        ignoring: _stage != _Stage.aiming,
        child: Opacity(opacity: 1 - .82 * l, child: _CameraBody(body: _body, lens: ColorFiltered(colorFilter: _filter.previewFilter, child: _viewfinder()), onShutter: _shoot)),
      ),
    );
    // A big viewfinder above the camera, the shape of the print's window, so
    // you see exactly what will be printed. Fades while the motor spins up.
    final win = _film.window;
    final winAspect = win.width * FilmStock.aspect / win.height;
    final vh = min(camTop - 28, size.width * .66 / winAspect);
    final vw = vh * winAspect;
    final finderOpacity = _stage == _Stage.aiming ? 1.0 : (1 - e / _emergeStart).clamp(0.0, 1.0);
    final finder = vh < 60 || finderOpacity == 0 ? null : Positioned(
      left: (size.width - vw) / 2, top: max(6.0, (camTop - vh) / 2 - 4), width: vw, height: vh,
      child: IgnorePointer(child: Opacity(opacity: finderOpacity, child: _Finder(
        error: _cameraError,
        child: _camera?.value.isInitialized == true ? FilterLayer(filter: _filter, child: SizedBox.expand(child: _viewfinder())) : null,
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
        child: Center(child: Icon(_cameraError != null ? Icons.no_photography_outlined : Icons.camera_alt_outlined, color: Colors.white38, size: 34)),
      );
    }
    final s = camera.value.previewSize!;
    // The preview size is landscape; fill the round lens.
    return FittedBox(fit: BoxFit.cover, child: SizedBox(width: s.height, height: s.width, child: CameraPreview(camera)));
  }

  /// Body colour and film stock.
  ScrollController _filterController() {
    final existing = _filterScroll;
    if (existing != null) return existing;
    // keepScrollOffset off: PageStorage would put back a stale offset.
    final c = ScrollController(initialScrollOffset: _filterOffset, keepScrollOffset: false);
    c.addListener(() => _filterOffset = c.offset);
    return _filterScroll = c;
  }

  /// Filter chips; the viewfinder shows the chosen one live.
  Widget _filterRow() => SizedBox(height: 32, child: ListView.separated(
    controller: _filterController(),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    itemCount: photoFilters.length,
    separatorBuilder: (_, __) => const SizedBox(width: 6),
    itemBuilder: (_, i) {
      final f = photoFilters[i];
      final on = f.id == _filter.id;
      return GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? ink : Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? ink : line),
          ),
          child: Text(f.name, style: TextStyle(fontSize: 12, color: on ? Colors.white : ink, fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
        ),
      );
    },
  ));

  Widget _options() => SizedBox(height: 34, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    for (final b in _Body.values)
      GestureDetector(
        onTap: () => setState(() => _body = b),
        child: Container(
          width: 26, height: 26, margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: b.swatch, shape: BoxShape.circle,
            border: Border.all(color: _body == b ? coral : Colors.white, width: _body == b ? 3 : 2),
            boxShadow: [BoxShadow(color: ink.withValues(alpha: .18), blurRadius: 3)],
          ),
        ),
      ),
    Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 10), color: line),
    for (final f in FilmStock.values)
      GestureDetector(
        onTap: () => setState(() => _film = f),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _film == f ? blush : Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _film == f ? blushLine : line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 12, decoration: BoxDecoration(color: f.swatch, borderRadius: BorderRadius.circular(2), border: Border.all(color: line))),
            const SizedBox(width: 5),
            Text(f.label, style: TextStyle(fontSize: 12, color: ink, fontWeight: _film == f ? FontWeight.w900 : FontWeight.w600)),
          ]),
        ),
      ),
  ]));

  Widget _controls() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _Tray(prints: _prints, onTap: _collage),
    GestureDetector(
      onTap: _shoot,
      child: Container(
        width: 78, height: 78,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: coral.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 6))]),
        padding: const EdgeInsets.all(6),
        child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: coral), child: const Icon(Icons.camera_rounded, color: Colors.white, size: 32)),
      ),
    ),
    _SideButton(icon: Icons.photo_library_outlined, label: '從相簿', onTap: _fromGallery),
  ]);

  Widget _bottom() => switch (_stage) {
    _Stage.aiming => Column(children: [
      _options(),
      const SizedBox(height: 6),
      _filterRow(),
      Expanded(child: _controls()),
    ]),
    _Stage.ejecting => const Center(child: Text('出片中…', style: TextStyle(fontSize: 15, color: muted, fontWeight: FontWeight.w800))),
    _Stage.developing => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('顯影中…', style: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('輕點照片可以跳過', style: hand(20, color: muted)),
    ])),
    _Stage.done => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('點相片下方可以手寫', style: hand(20, color: muted)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _again, icon: const Icon(Icons.camera_alt_outlined, size: 18), label: const Text('再拍一張', style: TextStyle(fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(foregroundColor: ink, side: const BorderSide(color: line, width: 1.4), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          )),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(
            onPressed: _save, icon: const Icon(Icons.download_rounded, size: 18), label: Text(_saving ? '儲存中…' : '存到相簿', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          )),
        ]),
      ]),
    ),
  };
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
        Text('PICO SNAP', style: TextStyle(fontSize: 40, height: 1, letterSpacing: 1.5, color: body.text, fontWeight: FontWeight.w900)),
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
          Icon(error != null ? Icons.no_photography_outlined : Icons.camera_alt_outlined, color: Colors.white38, size: 34),
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
/// Prints taken so far; tap to make a collage of the last four.
class _Tray extends StatelessWidget {
  final List<_Print> prints;
  final VoidCallback onTap;
  const _Tray({required this.prints, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(width: 74, child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 56, height: 56, child: Stack(clipBehavior: Clip.none, children: [
        if (prints.isEmpty)
          Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: line)))
        else
          for (final (i, p) in prints.reversed.take(3).toList().reversed.indexed)
            Positioned.fill(child: Transform.rotate(
              angle: (i - 1) * .12,
              child: FittedBox(child: InstantPrint(image: p.image, film: p.film, filter: p.filter, caption: '')),
            )),
        if (prints.isNotEmpty)
          Positioned(right: -6, top: -6, child: Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: const BoxDecoration(color: coral, shape: BoxShape.circle),
            child: Text('${prints.length}', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w900)),
          )),
      ])),
      const SizedBox(height: 6),
      Text('做成拼貼', style: TextStyle(fontSize: 11, color: prints.isEmpty ? muted : ink, fontWeight: FontWeight.w800)),
    ])),
  );
}

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
