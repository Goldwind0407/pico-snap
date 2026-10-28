import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'editor_screen.dart';
import 'filters.dart';
import 'models.dart';
import 'polaroid_camera_screen.dart' show mainCamera;
import 'services/photo_save_service.dart';
import 'services/timelapse_recorder.dart';
import 'theme.dart';
import 'widgets/frames.dart';

/// Photo window [i] of [t], in PhotoStrip design units.
Rect cellRect(StripTemplate t, int i) {
  final art = t.art;
  // Drawn strips: 200 wide, 12 padding each side, cells 128 high, 10 apart,
  // starting 14 from the top.
  if (art == null) return Rect.fromLTWH(12, 14 + i * 138.0, 176, 128);
  final s = t.designSize, r = art.cells[i];
  return Rect.fromLTWH(r.left * s.width, r.top * s.height, r.width * s.width, r.height * s.height);
}

/// Width / height of photo window [i] of [t].
double cellAspect(StripTemplate t, int i) => cellRect(t, i).size.aspectRatio;

/// How many photos [t] takes.
int shotCount(StripTemplate t) => t.art?.cells.length ?? 4;

enum _Stage { pick, shooting, filter, done }

/// Four cuts like a real photo booth: pick a frame, then the camera counts
/// down and takes the photos one after another, then pick a filter and save
/// (with a live video of the shoot if wanted).
class BoothScreen extends StatefulWidget {
  final int template;
  /// Takes the picture instead of the camera (tests).
  @visibleForTesting
  final Future<Uint8List?> Function()? shoot;
  const BoothScreen({super.key, this.template = 0, this.shoot});

  @override
  State<BoothScreen> createState() => _BoothScreenState();
}

class _BoothScreenState extends State<BoothScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  _Stage _stage = _Stage.pick;
  late int _template = widget.template.clamp(0, allStripTemplates.length - 1);
  late String _category = allStripTemplates[_template].category;
  /// Countdown before each photo.
  int _seconds = 5;

  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  CameraDescription? _device;
  String? _cameraError;

  /// The photos taken so far as shot; selfies are shown mirrored right away
  /// and the mirrored file is made in the background ([_ready]).
  final _takes = <({Uint8List bytes, bool mirror})>[];
  final _ready = <Future<Uint8List>>[];
  /// The finished photos, once shooting is over.
  final _photos = <Uint8List>[];
  List<ImageProvider> _providers = [];
  /// The moments before each photo, from the viewfinder, for the video.
  final _clips = <List<ui.Image>>[];
  var _clip = <ui.Image>[];
  Timer? _clipTimer;
  bool _grabbing = false;
  /// The number on screen while counting down.
  int? _count;
  /// The photo just taken, held in the viewfinder for a moment.
  ({Uint8List bytes, bool mirror})? _frozen;
  /// Bumped when shooting stops, so a countdown in progress gives up.
  int _session = 0;
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  final _finderKey = GlobalKey();

  PhotoFilter _filter = photoFilters.first;
  final _stripKey = GlobalKey();
  bool _withVideo = true, _saving = false, _saved = false;
  /// While making the video: the frames shown in the strip, and progress.
  List<ImageProvider>? _playing;
  double? _progress;
  TimelapseRecorder? _video;

  StripTemplate get _t => allStripTemplates[_template];
  int get _shots => shotCount(_t);
  bool get _canVideo => _clips.length == _shots && _clips.every((c) => c.length >= 4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session++;
    _clipTimer?.cancel();
    _camera?.dispose();
    _flash.dispose();
    _pop.dispose();
    _dropClips();
    _video?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera must be released while the app is in the background.
    if (state == AppLifecycleState.inactive) {
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _stage == _Stage.shooting && _camera == null && widget.shoot == null) {
      _openCamera();
    }
  }

  void _dropClips() {
    for (final c in [..._clips, _clip]) {
      for (final f in c) {
        f.dispose();
      }
    }
    _clips.clear();
    _clip = [];
  }

  Future<void> _openCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'no camera');
      // A photo booth faces you.
      final device = _device ??= mainCamera(_cameras, CameraLensDirection.front) ?? mainCamera(_cameras, CameraLensDirection.back)!;
      final camera = CameraController(device, ResolutionPreset.veryHigh, enableAudio: false);
      await camera.initialize();
      if (!mounted || _stage != _Stage.shooting) {
        camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _cameraError = null;
      });
    } catch (e) {
      debugPrint('[BOOTH] camera: $e');
      if (mounted) {
        setState(() => _cameraError = e is CameraException && e.code.contains('AccessDenied') ? '沒有相機權限，可以到設定開啟' : '相機打不開');
      }
    }
  }

  /// Takes the preview off the screen first: disposing the camera while its
  /// last frame is still being drawn crashes the Android engine.
  void _closeCamera() {
    final old = _camera;
    if (old == null) return;
    if (mounted) setState(() => _camera = null);
    Future<void>.delayed(const Duration(milliseconds: 500), old.dispose);
  }

  bool get _canFlip => mainCamera(_cameras, CameraLensDirection.back) != null && mainCamera(_cameras, CameraLensDirection.front) != null;

  Future<void> _flipCamera() async {
    if (!_canFlip) return;
    final front = _device?.lensDirection == CameraLensDirection.front;
    final old = _camera;
    setState(() {
      _camera = null;
      _device = mainCamera(_cameras, front ? CameraLensDirection.back : CameraLensDirection.front);
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await old?.dispose();
    await _openCamera();
  }

  /// Step 2: into the booth; the countdown starts once the camera is on.
  Future<void> _start() async {
    _dropClips();
    setState(() {
      _stage = _Stage.shooting;
      _photos.clear();
      _takes.clear();
      _ready.clear();
      _providers = [];
      _frozen = null;
      _count = null;
      _saved = false;
      _cameraError = null;
    });
    if (widget.shoot == null) await _openCamera();
    if (!mounted || _stage != _Stage.shooting) return;
    if (_camera == null && widget.shoot == null) return; // the error is on screen
    _shootNext(_session);
  }

  bool _alive(int session) => mounted && session == _session && _stage == _Stage.shooting;

  /// Count down, take the next photo, hold it a moment, go on.
  Future<void> _shootNext(int session) async {
    _clip = [];
    _clipTimer?.cancel();
    if (_camera != null) _clipTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _grab(session));
    for (var n = _seconds; n > 0; n--) {
      if (!_alive(session)) return;
      setState(() => _count = n);
      _pop.forward(from: 0);
      SystemSound.play(SystemSoundType.click);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!_alive(session)) return;
    setState(() => _count = null);
    final take = await _take();
    _clipTimer?.cancel();
    if (!_alive(session) || !mounted) return;
    if (take == null) {
      showMessage(context, '這張沒拍到，再來一次', error: true);
      for (final f in _clip) {
        f.dispose();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_alive(session)) _shootNext(session);
      return;
    }
    _takes.add(take);
    _ready.add(take.mirror ? _mirror(take.bytes) : Future.value(take.bytes));
    _clips.add(_clip);
    _clip = [];
    setState(() => _frozen = take);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!_alive(session)) return;
    setState(() => _frozen = null);
    if (_takes.length < _shots) return _shootNext(session);
    // Step 5: done shooting, pick a filter.
    _closeCamera();
    final photos = await Future.wait(_ready);
    if (!_alive(session)) return;
    _photos
      ..clear()
      ..addAll(photos);
    setState(() {
      _providers = [for (final p in _photos) MemoryImage(p)];
      _stage = _Stage.filter;
    });
  }

  Future<({Uint8List bytes, bool mirror})?> _take() async {
    HapticFeedback.heavyImpact();
    _flash.forward(from: 0);
    final shoot = widget.shoot;
    if (shoot != null) {
      final bytes = await shoot();
      return bytes == null ? null : (bytes: bytes, mirror: false);
    }
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || camera.value.isTakingPicture) return null;
    try {
      final bytes = await (await camera.takePicture()).readAsBytes();
      // The viewfinder is a mirror; the photo matches what you saw.
      return (bytes: bytes, mirror: camera.description.lensDirection == CameraLensDirection.front);
    } catch (e) {
      debugPrint('[BOOTH] take: $e');
      return null;
    }
  }

  static Future<Uint8List> _mirror(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final w = image.width.toDouble();
    final rec = ui.PictureRecorder();
    ui.Canvas(rec)
      ..translate(w, 0)
      ..scale(-1, 1)
      ..drawImage(image, Offset.zero, Paint());
    final out = await rec.endRecording().toImage(image.width, image.height);
    image.dispose();
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    return png!.buffer.asUint8List();
  }

  /// One frame of the viewfinder for the video; the last few seconds are kept.
  Future<void> _grab(int session) async {
    if (_grabbing || !_alive(session) || _frozen != null) return;
    final b = _finderKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null || !b.attached || b.size.isEmpty) return;
    _grabbing = true;
    try {
      final image = await b.toImage(pixelRatio: 480 / b.size.longestSide);
      if (!_alive(session)) return image.dispose();
      _clip.add(image);
      if (_clip.length > 30) _clip.removeAt(0).dispose();
    } catch (e) {
      debugPrint('[BOOTH] grab: $e');
    } finally {
      _grabbing = false;
    }
  }

  /// Mostly transparent or one flat colour: not a real camera frame (the
  /// preview texture sometimes comes back empty). Checked when making the
  /// video, not while grabbing: reading pixels back is slow.
  static Future<bool> _blank(ui.Image image) async {
    final data = await image.toByteData();
    if (data == null) return true;
    final px = data.buffer.asUint8List();
    var clear = 0, n = 0;
    var lo = 255, hi = 0;
    for (var i = 0; i < px.length; i += 4 * 97) {
      n++;
      if (px[i + 3] < 16) clear++;
      final l = (px[i] * 2 + px[i + 1] * 5 + px[i + 2]) >> 3;
      lo = min(lo, l);
      hi = max(hi, l);
    }
    return clear > n * .5 || hi - lo < 6;
  }

  void _stopShooting() {
    _session++;
    _clipTimer?.cancel();
    _closeCamera();
  }

  Future<void> _back() async {
    switch (_stage) {
      case _Stage.pick:
        Navigator.pop(context);
      case _Stage.done when !_saved:
        setState(() => _stage = _Stage.filter);
      case _Stage.done:
        Navigator.pop(context);
      case _Stage.shooting:
      case _Stage.filter:
        final navigator = Navigator.of(context);
        if (await confirmLeave(context, '拍好的照片會不見喔。', stay: '繼續')) {
          _stopShooting();
          navigator.pop();
        }
    }
  }

  void _retake() {
    _stopShooting();
    _start();
  }

  /// Step 6: save the strip, and the live video if wanted.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await WidgetsBinding.instance.endOfFrame;
    var error = await PhotoSaveService.saveBoundary(_stripKey);
    var done = '已存到相簿 ♡';
    if (error == null && _withVideo && _canVideo) {
      final path = await _renderVideo();
      error = path == null ? '圖片已存好，但影片做不出來' : await PhotoSaveService.saveVideo(path);
      if (error == null) done = '已存到相簿 ♡ 圖片和影片';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _playing = null;
      _progress = null;
      if (error == null) _saved = true;
    });
    showMessage(context, error ?? done, error: error != null, above: 150);
  }

  Future<ui.Image?> _stripShot() async {
    final b = _stripKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (!mounted || b == null || !b.attached) return null;
    return b.toImage(pixelRatio: 1000 / b.size.longestSide);
  }

  /// A live four-cuts video: every window plays its moment before the
  /// shutter, twice, then the finished strip holds.
  Future<String?> _renderVideo() async {
    _video?.dispose();
    final video = _video = TimelapseRecorder(subtitle: 'live four cuts ♡');
    final cache = PaintingBinding.instance.imageCache;
    // Each window's real frames; one with none shows its photo, still.
    final clips = <List<ImageProvider>>[];
    for (var i = 0; i < _clips.length; i++) {
      final good = <ImageProvider>[
        for (final f in _clips[i])
          if (!await _blank(f)) _FrameImage(f),
      ];
      clips.add(good.isEmpty ? [_providers[i]] : good);
    }
    final len = clips.map((c) => c.length).reduce(max);
    final total = len * 2;
    List<ImageProvider> shown = [];
    try {
      for (var k = 0; k < total; k++) {
        if (!mounted) return null;
        final frames = [for (final c in clips) c[(k % len) * c.length ~/ len]];
        // Graded like the photos, before they're shown.
        await Future.wait([for (final f in frames) precacheImage(filtered(f, _filter), context)]);
        if (!mounted) return null;
        for (final f in shown.whereType<_FrameImage>()) {
          cache.evict(filtered(f, _filter));
        }
        setState(() {
          _playing = shown = frames;
          _progress = k / total;
        });
        await WidgetsBinding.instance.endOfFrame;
        final shot = await _stripShot();
        if (shot != null) await video.add(shot);
      }
      if (!mounted) return null;
      setState(() => _playing = null);
      await WidgetsBinding.instance.endOfFrame;
      final finished = await _stripShot();
      return finished == null ? null : await video.render(finished);
    } catch (e) {
      debugPrint('[BOOTH] video: $e');
      return null;
    } finally {
      for (final f in shown.whereType<_FrameImage>()) {
        cache.evict(filtered(f, _filter));
      }
    }
  }

  void _decorate() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EditorScreen(
    template: _template, photos: List.of(_photos), filters: List.filled(_shots, _filter),
  )));

  void _fromAlbum() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EditorScreen(template: _template)));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _stage == _Stage.pick || (_stage == _Stage.done && _saved),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: cream,
      body: Stack(children: [
        SafeArea(child: switch (_stage) {
          _Stage.pick => _pickView(),
          _Stage.shooting => _shootingView(),
          _Stage.filter || _Stage.done => _resultView(),
        }),
        IgnorePointer(child: AnimatedBuilder(
          animation: _flash,
          builder: (context, _) => Opacity(
            opacity: _flash.status == AnimationStatus.forward ? (1 - Curves.easeOut.transform(_flash.value)) * .9 : 0,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
          ),
        )),
      ]),
    ),
  );

  Widget _topBar(String title, {List<Widget> actions = const []}) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
    child: Row(children: [
      IconButton(onPressed: _saving ? null : _back, icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
      Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
      ...actions,
    ]),
  );

  // Step 1: pick the frame.
  Widget _pickView() {
    final visible = [for (var i = 0; i < allStripTemplates.length; i++) if (allStripTemplates[i].category == _category) i];
    return Column(children: [
      _topBar('Four Cuts', actions: [TextButton(onPressed: _fromAlbum, child: const Text('從相簿選照片', style: TextStyle(color: coral, fontWeight: FontWeight.w800)))]),
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: Center(child: FittedBox(child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 8))]),
          child: PhotoStrip(template: _t),
        ))),
      )),
      SizedBox(height: 40, child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in [if (customTemplates.isNotEmpty) myCategory, ...stripCategories])
            Padding(padding: const EdgeInsets.only(right: 8), child: _Chip(label: c, selected: c == _category, onTap: () => setState(() => _category = c))),
        ],
      )),
      const SizedBox(height: 8),
      SizedBox(height: 118, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, k) {
          final i = visible[k];
          return GestureDetector(
            onTap: () => setState(() => _template = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _template == i ? coral : line, width: _template == i ? 2.5 : 1.3),
              ),
              child: FittedBox(child: PhotoStrip(template: allStripTemplates[i])),
            ),
          );
        },
      )),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          const Text('每張倒數', style: TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          for (final s in const [3, 5, 10])
            Padding(padding: const EdgeInsets.only(right: 8), child: _Chip(label: '$s 秒', selected: _seconds == s, onTap: () => setState(() => _seconds = s))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.photo_camera_rounded),
          label: Text('開始拍照（$_shots 張）', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          style: FilledButton.styleFrom(
            backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        )),
      ),
    ]);
  }

  // Steps 2–4: the countdown and the photos one by one.
  Widget _shootingView() {
    final frozen = _frozen;
    // While the photo just taken is held, stay on its window.
    final i = frozen != null ? _takes.length - 1 : min(_takes.length, _shots - 1);
    return Column(children: [
      _topBar('第 ${i + 1} / $_shots 張', actions: [
        if (_canFlip && widget.shoot == null)
          IconButton(onPressed: _flipCamera, icon: const Icon(Icons.cameraswitch_outlined), color: ink),
      ]),
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Center(child: Stack(alignment: Alignment.center, children: [
            _framedFinder(i, live: frozen == null),
            if (_count != null) AnimatedBuilder(
              animation: _pop,
              builder: (context, _) {
                final t = Curves.easeOutBack.transform(_pop.value.clamp(0.0, 1.0));
                return Transform.scale(scale: 1.5 - .5 * t, child: Text('$_count', style: TextStyle(
                  fontSize: 120, color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Nunito',
                  shadows: [Shadow(color: ink.withValues(alpha: .45), blurRadius: 16)],
                )));
              },
            ),
        ])),
      )),
      SizedBox(height: 74, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var k = 0; k < _shots; k++)
          Flexible(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AspectRatio(aspectRatio: cellAspect(_t, k), child: Container(
              decoration: BoxDecoration(
                color: _t.cell, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: k == _takes.length ? coral : line, width: k == _takes.length ? 2.5 : 1.3),
              ),
              clipBehavior: Clip.antiAlias,
              child: k < _takes.length
                  ? Transform.flip(flipX: _takes[k].mirror, child: Image.memory(_takes[k].bytes, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 200))
                  : Center(child: Text('${k + 1}', style: const TextStyle(color: muted, fontWeight: FontWeight.w900))),
            )),
          )),
      ]))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Text(
          _cameraError != null ? '$_cameraError，可以改從相簿選照片' : _frozen != null ? '拍好了 ♡' : '看鏡頭，倒數結束自動拍照',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: muted, fontWeight: FontWeight.w700),
        ),
      ),
      if (_cameraError != null)
        Padding(padding: const EdgeInsets.only(bottom: 16), child: OutlinedButton(onPressed: _fromAlbum, child: const Text('從相簿選照片'))),
    ]);
  }

  /// The template zoomed in on window [i]: the camera ([live]) or the photo
  /// just taken in it, the frame's drawings on and around it, the photos
  /// already taken in the others. So you can pose with the decorations.
  Widget _framedFinder(int i, {required bool live}) {
    final design = _t.designSize, cell = cellRect(_t, i);
    final m = cell.shortestSide * .18;
    final view = Rect.fromLTRB(
      max(0, cell.left - m), max(0, cell.top - m), min(design.width, cell.right + m), min(design.height, cell.bottom + m),
    );
    Widget still(({Uint8List bytes, bool mirror}) p) => SizedBox.expand(child: Transform.flip(
      flipX: p.mirror,
      child: Image.memory(p.bytes, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 900),
    ));
    final cells = <int, Widget>{
      for (var k = 0; k < _takes.length; k++) k: still(_takes[k]),
      if (live) i: SizedBox.expand(child: RepaintBoundary(key: _finderKey, child: _preview())),
    };
    return AspectRatio(
      aspectRatio: view.size.aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: ink.withValues(alpha: .14), blurRadius: 16, offset: const Offset(0, 6))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: FittedBox(child: SizedBox.fromSize(size: view.size, child: ClipRect(child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: design.width, maxWidth: design.width, minHeight: design.height, maxHeight: design.height,
            child: Transform.translate(offset: -view.topLeft, child: PhotoStrip(template: _t, live: cells)),
          )))),
        ),
      ),
    );
  }

  Widget _preview() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return ColoredBox(
        color: const Color(0xFF26282E),
        child: Center(child: Icon(_cameraError != null ? Icons.no_photography_outlined : Icons.camera_alt_outlined, color: Colors.white38, size: 40)),
      );
    }
    final s = camera.value.previewSize!;
    // The preview size is landscape; fill the window like the photo will.
    return FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: s.height, height: s.width, child: CameraPreview(camera)));
  }

  // Steps 5–6: filter, then save.
  Widget _resultView() {
    final filtering = _stage == _Stage.filter;
    return Column(children: [
      _topBar(filtering ? '挑濾鏡' : '完成！'),
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: Stack(alignment: Alignment.center, children: [
          FittedBox(child: DecoratedBox(
            decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 8))]),
            child: RepaintBoundary(key: _stripKey, child: PhotoStrip(
              template: _t, photos: _playing ?? _providers, filters: List.filled(_shots, _filter),
            )),
          )),
          if (_progress != null)
            Positioned(bottom: 0, child: DecoratedBox(
              decoration: BoxDecoration(color: ink.withValues(alpha: .75), borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text('影片製作中 ${(_progress! * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            )),
        ]),
      )),
      if (filtering) ..._filterControls() else ..._saveControls(),
    ]);
  }

  List<Widget> _filterControls() => [
    SizedBox(height: 44, child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final f in photoFilters)
          Padding(padding: const EdgeInsets.only(right: 8), child: _Chip(label: f.name, selected: f.id == _filter.id, onTap: () => setState(() => _filter = f))),
      ],
    )),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(children: [
        OutlinedButton(
          onPressed: _retake,
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('全部重拍', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(child: FilledButton(
          onPressed: () => setState(() => _stage = _Stage.done),
          style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('下一步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        )),
      ]),
    ),
  ];

  List<Widget> _saveControls() => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _canVideo && !_saving ? () => setState(() => _withVideo = !_withVideo) : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            color: _canVideo && _withVideo ? blush : Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _canVideo && _withVideo ? blushLine : line),
          ),
          child: Row(children: [
            Icon(Icons.movie_filter_outlined, color: _canVideo ? coral : muted),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('同時存拍攝影片', style: TextStyle(fontSize: 14, color: ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(_canVideo ? '每一格播放按下快門前的那幾秒，像拍貼機的動態照片' : '這次沒有錄到畫面，只能存圖片',
                style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
            ])),
            Checkbox(value: _canVideo && _withVideo, activeColor: coral, onChanged: _canVideo && !_saving ? (v) => setState(() => _withVideo = v ?? false) : null),
          ]),
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: _saved
          ? Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: _decorate,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('加貼紙裝飾', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(
                onPressed: _retake,
                style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('再拍一組', style: TextStyle(fontWeight: FontWeight.w900)),
              )),
            ])
          : SizedBox(width: double.infinity, child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(_saving ? '儲存中…' : '存到相簿', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            )),
    ),
  ];
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
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? ink : Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? ink : line, width: 1.3),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : ink, fontWeight: FontWeight.w800)),
    ),
  );
}

/// A frame of a clip, shown right away (no decoding).
class _FrameImage extends ImageProvider<_FrameImage> {
  final ui.Image image;
  const _FrameImage(this.image);

  @override
  Future<_FrameImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_FrameImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone())));

  @override
  bool operator ==(Object other) => other is _FrameImage && identical(other.image, image);

  @override
  int get hashCode => identityHashCode(image);
}
