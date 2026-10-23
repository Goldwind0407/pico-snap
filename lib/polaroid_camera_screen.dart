import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'editor_screen.dart';
import 'models.dart';
import 'services/photo_save_service.dart';
import 'theme.dart';

/// Camera body colours, like the pastel instant cameras.
const _bodyColors = [Color(0xFFF7B9C4), Color(0xFFB9E3D3), Color(0xFFB7D7F0), Color(0xFFF6E3A8)];

enum _Stage { aiming, ejecting, developing, done }

const _controlsHeight = 150.0;

class _Print {
  final Uint8List bytes;
  String caption;
  _Print(this.bytes, this.caption);
}

/// 拍立得相機：取景在鏡頭裡，按下快門後相片從上方的出片口慢慢吐出來，
/// 拿到前面之後從一片深色慢慢顯影。拍好的相片可以存到相簿，或放進拍立得拼貼。
class PolaroidCameraScreen extends StatefulWidget {
  const PolaroidCameraScreen({super.key, this.pickPhoto});

  /// Replaces the photo picker (tests).
  @visibleForTesting
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<PolaroidCameraScreen> createState() => _PolaroidCameraScreenState();
}

class _PolaroidCameraScreenState extends State<PolaroidCameraScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  int _lens = 0;
  String? _cameraError;

  // Motorised: the print comes out at a steady pace.
  late final _eject = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final _develop = AnimationController(vsync: this, duration: const Duration(seconds: 7))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && _stage == _Stage.developing) setState(() => _stage = _Stage.done);
    });
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  _Stage _stage = _Stage.aiming;
  _Print? _current;
  final _prints = <_Print>[];
  int _body = 0;
  bool _saving = false;
  final _printKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _eject.dispose();
    _lift.dispose();
    _develop.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera must be released while the app is in the background.
    if (state == AppLifecycleState.inactive) {
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _camera == null && _cameraError == null) {
      _openCamera();
    }
  }

  Future<void> _openCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = '這台裝置沒有相機，可以從相簿選照片');
        return;
      }
      final camera = CameraController(_cameras[_lens % _cameras.length], ResolutionPreset.high, enableAudio: false);
      await camera.initialize();
      if (!mounted) {
        camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      debugPrint('[CAMERA] $e');
      if (mounted) {
        setState(() => _cameraError = e.code.contains('AccessDenied') ? '沒有相機權限，可以到設定開啟，或從相簿選照片' : '相機打不開，可以從相簿選照片');
      }
    } catch (e) {
      debugPrint('[CAMERA] $e');
      if (mounted) setState(() => _cameraError = '相機打不開，可以從相簿選照片');
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _stage != _Stage.aiming) return;
    final old = _camera;
    setState(() {
      _camera = null;
      _lens++;
    });
    await old?.dispose();
    await _openCamera();
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
      if (mounted) await _printOut(bytes);
    } catch (e) {
      debugPrint('[CAMERA] 拍照失敗: $e');
      if (mounted) showMessage(context, '拍照失敗，請再試一次', error: true, above: _controlsHeight);
    }
  }

  Future<void> _fromGallery() async {
    if (_stage != _Stage.aiming) return;
    final Uint8List? bytes;
    if (widget.pickPhoto != null) {
      bytes = await widget.pickPhoto!();
    } else {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
      bytes = await file?.readAsBytes();
    }
    if (bytes != null && mounted) await _printOut(bytes);
  }

  String _today() {
    final d = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  /// The print comes out of the slot, is taken to the front and develops.
  Future<void> _printOut(Uint8List bytes) async {
    final print = _Print(bytes, _today());
    setState(() {
      _current = print;
      _stage = _Stage.ejecting;
    });
    _develop.value = 0;
    _lift.value = 0;
    // The motor whirs while the print comes out.
    final motor = Timer.periodic(const Duration(milliseconds: 280), (_) => HapticFeedback.selectionClick());
    await _eject.forward(from: 0);
    motor.cancel();
    if (!mounted) return;
    _prints.add(print);
    setState(() => _stage = _Stage.developing);
    _develop.forward(from: 0);
    await _lift.forward(from: 0);
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
    final error = await PhotoSaveService.saveBoundary(_printKey, longSide: 2000);
    if (!mounted) return;
    setState(() => _saving = false);
    showMessage(context, error ?? '已存到相簿 ♡', error: error != null, above: _controlsHeight);
  }

  Future<void> _editCaption() async {
    final print = _current;
    if (print == null || _stage != _Stage.done) return;
    final text = await showDialog<String>(context: context, builder: (_) => _CaptionDialog(initial: print.caption));
    if (text != null && mounted) setState(() => print.caption = text.trim());
  }

  void _collage() {
    if (_prints.isEmpty) return;
    final last = _prints.length > 4 ? _prints.sublist(_prints.length - 4) : _prints;
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(
      mode: EditorMode.polaroid,
      photos: [for (final p in last) p.bytes],
      captions: [for (final p in last) p.caption],
    )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: Stack(children: [
      SafeArea(child: Column(children: [
        _topBar(),
        Expanded(child: LayoutBuilder(builder: (context, c) => AnimatedBuilder(
          animation: Listenable.merge([_eject, _lift, _develop]),
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
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 26)),
      const Expanded(child: Text('Instant Camera', style: TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
      // Body colour.
      GestureDetector(
        onTap: () => setState(() => _body = (_body + 1) % _bodyColors.length),
        child: Container(
          width: 30, height: 30, margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: _bodyColors[_body], shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: ink.withValues(alpha: .2), blurRadius: 4)]),
        ),
      ),
      if (_cameras.length > 1)
        IconButton(onPressed: _stage == _Stage.aiming ? _flipCamera : null, icon: const Icon(Icons.cameraswitch_outlined), color: ink, disabledColor: line),
    ]),
  );

  Widget _stageView(Size size) {
    final cw = [size.width * .82, size.height * .66, 340.0].reduce(min);
    final ch = cw * .8;
    final camTop = size.height - ch - 8;
    final pw = cw * .5, ph = pw * 196 / 160;
    final slotY = camTop + 6;
    // Coming out of the slot, with a little motor shake.
    final e = _eject.value;
    final shake = _eject.isAnimating ? sin(e * 140) * .7 : 0.0;
    final ejected = Rect.fromLTWH((size.width - pw) / 2 + shake, slotY - e * ph * .9, pw, ph);
    // Taken to the front to watch it develop.
    final rw = min(size.width * .66, (size.height - 16) * .9 * 160 / 196);
    final rh = rw * 196 / 160;
    final review = Rect.fromLTWH((size.width - rw) / 2, max(8.0, (size.height - rh) / 2 - 4), rw, rh);
    final l = Curves.easeInOutCubic.transform(_lift.value);
    final rect = Rect.lerp(ejected, review, l)!;

    final print = _current;
    final printView = print == null ? null : Positioned.fromRect(rect: rect, child: Transform.rotate(
      angle: -.035 * l,
      child: GestureDetector(
        onTap: _stage == _Stage.developing ? _skipDeveloping : null,
        child: FittedBox(child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: ink.withValues(alpha: .1 + .15 * l), blurRadius: 8 + 14 * l, offset: Offset(0, 3 + 7 * l))]),
          child: RepaintBoundary(key: _printKey, child: InstantPrint(
            bytes: print.bytes, develop: _develop.value, caption: print.caption,
            onCaption: _stage == _Stage.done ? _editCaption : null,
          )),
        )),
      ),
    ));
    final camera = Positioned(
      left: (size.width - cw) / 2, top: camTop, width: cw, height: ch,
      child: IgnorePointer(
        ignoring: _stage != _Stage.aiming,
        child: Opacity(opacity: 1 - .82 * l, child: _CameraBody(color: _bodyColors[_body], lens: _viewfinder(), onShutter: _shoot)),
      ),
    );
    // Behind the camera while it comes out of the slot, in front once taken out.
    return Stack(clipBehavior: Clip.none, children: [
      if (printView != null && l < .5) printView,
      camera,
      if (printView != null && l >= .5) printView,
      if (_cameraError != null && _stage == _Stage.aiming)
        Positioned(left: 24, right: 24, top: max(0.0, camTop - 64), child: Text(_cameraError!, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.5, color: muted, fontWeight: FontWeight.w700))),
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

  Widget _bottom() => switch (_stage) {
    _Stage.aiming => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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
        Text('點白邊可以寫字', style: hand(20, color: muted)),
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

/// How instant film develops at [t] (0–1): a flat dark sheet, then a pale,
/// warm, low-contrast picture that gains colour and contrast.
@visibleForTesting
ColorFilter developFilter(double t) {
  t = t.clamp(0.0, 1.0);
  const blank = <double>[0, 0, 0, 0, 52, 0, 0, 0, 0, 56, 0, 0, 0, 0, 50, 0, 0, 0, 1, 0];
  final s = Curves.easeIn.transform(t);
  final sat = s, contrast = .5 + .5 * s, warm = 22 * (1 - s);
  const lum = [.2126, .7152, .0722];
  List<double> row(int i, double offset) {
    final r = [for (final l in lum) l * (1 - sat)];
    r[i] += sat;
    return [for (final v in r) contrast * v, 0, 128 * (1 - contrast) + offset];
  }

  final photo = [...row(0, warm), ...row(1, warm * .4), ...row(2, -warm * .6), 0, 0, 0, 1, 0];
  // The picture appears during the first three quarters.
  final k = Curves.easeInOut.transform((t / .75).clamp(0.0, 1.0));
  return ColorFilter.matrix([for (var i = 0; i < 20; i++) blank[i] + (photo[i] - blank[i]) * k]);
}

/// An instant print drawn at the same design size as PolaroidCard.
class InstantPrint extends StatelessWidget {
  final Uint8List bytes;
  final double develop;
  final String caption;
  final VoidCallback? onCaption;
  const InstantPrint({super.key, required this.bytes, required this.develop, required this.caption, this.onCaption});

  @override
  Widget build(BuildContext context) => Container(
    width: 160, height: 196,
    padding: const EdgeInsets.fromLTRB(9, 9, 9, 0),
    decoration: BoxDecoration(color: const Color(0xFFFFFDF9), border: Border.all(color: const Color(0xFFE9E3DA))),
    child: Column(children: [
      SizedBox(height: 142, width: double.infinity, child: ClipRect(child: ColorFiltered(
        colorFilter: developFilter(develop),
        child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ))),
      Expanded(child: GestureDetector(
        onTap: onCaption,
        behavior: HitTestBehavior.opaque,
        child: Center(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: hand(26))),
      )),
    ]),
  );
}

class _CameraBody extends StatelessWidget {
  final Color color;
  final Widget lens;
  final VoidCallback onShutter;
  const _CameraBody({required this.color, required this.lens, required this.onShutter});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final w = c.maxWidth, h = c.maxHeight;
    final dark = Color.lerp(color, ink, .3)!;
    final r = w * .27;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(color, Colors.white, .4)!, color]),
        borderRadius: BorderRadius.circular(w * .11),
        border: Border.all(color: dark, width: 2),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: .18), blurRadius: 18, offset: const Offset(0, 10))],
      ))),
      // Film slot.
      Positioned(top: 3, left: w * .22, right: w * .22, height: 7, child: DecoratedBox(decoration: BoxDecoration(color: ink.withValues(alpha: .75), borderRadius: BorderRadius.circular(4)))),
      // Flash window.
      Positioned(left: w * .08, top: h * .12, width: w * .26, height: h * .18, child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(w * .025), border: Border.all(color: dark, width: 2)),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < 4; i++) Container(height: 1.5, margin: EdgeInsets.symmetric(horizontal: w * .02), color: const Color(0xFFDADDE3)),
        ]),
      )),
      // Viewfinder.
      Positioned(right: w * .09, top: h * .12, width: w * .14, height: w * .14, child: Container(
        decoration: BoxDecoration(color: const Color(0xFF2B2D33), borderRadius: BorderRadius.circular(w * .03), border: Border.all(color: dark, width: 2)),
        alignment: Alignment.topLeft,
        child: Container(margin: EdgeInsets.all(w * .02), width: w * .03, height: w * .03, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
      )),
      // Lens with the live picture in it.
      Positioned(left: w / 2 - r, top: h * .56 - r, width: r * 2, height: r * 2, child: Container(
        padding: EdgeInsets.all(r * .13),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF7F7F9), Color(0xFFB4B7BF)]),
          border: Border.all(color: dark, width: 2),
        ),
        child: Container(
          padding: EdgeInsets.all(r * .09),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1C1D22)),
          child: ClipOval(child: Stack(fit: StackFit.expand, children: [
            lens,
            IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
              center: const Alignment(-.45, -.55), radius: .9,
              colors: [Colors.white.withValues(alpha: .28), Colors.transparent],
            )))),
          ])),
        ),
      )),
      // Shutter button on the body.
      Positioned(right: w * .07, bottom: h * .09, width: w * .13, height: w * .13, child: GestureDetector(
        onTap: onShutter,
        child: Container(decoration: BoxDecoration(
          shape: BoxShape.circle, color: coral, border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: .25), blurRadius: 4, offset: const Offset(0, 2))],
        )),
      )),
      Positioned(left: w * .08, bottom: h * .09, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('instant', style: hand(w * .065, color: Colors.white)),
        Text('PICO SNAP', style: TextStyle(fontSize: w * .045, letterSpacing: 2, fontWeight: FontWeight.w900, color: dark)),
      ])),
    ]);
  });
}

/// Writes on the print's white strip. Owns its controller so it lives as long
/// as the dialog, closing animation included.
class _CaptionDialog extends StatefulWidget {
  final String initial;
  const _CaptionDialog({required this.initial});

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: cream,
    title: const Text('在白邊寫字', style: TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900)),
    content: TextField(
      controller: _ctrl, autofocus: true, maxLength: 16, style: hand(26),
      decoration: const InputDecoration(hintText: 'say something ♡'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: muted))),
      TextButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('好', style: TextStyle(color: coral, fontWeight: FontWeight.w800))),
    ],
  );
}

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
              child: FittedBox(child: InstantPrint(bytes: p.bytes, develop: 1, caption: '')),
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
