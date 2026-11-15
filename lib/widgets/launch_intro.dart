import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_sounds.dart';

/// 開 App 時的開場動畫:工作室的「Goldwind」簽名寫在羊皮紙上。
///
///   1. 紙微微落定,簽名的墨跡從左寫到右(約 1.7 秒)
///   2. 寫完,旁邊那顆小星星轉著彈出來,後面炸開一圈金光
///   3. 一道金光沿著墨跡掃過(只亮在有墨的地方)
///   4. 整片淡出,露出底下的登入頁或主畫面
///
/// 動畫是疊在整個 App 上面的一層,底下的畫面照常同時載入(作品集、草稿、
/// 音效),所以動畫結束時底下通常已經準備好了。點一下畫面直接跳到淡出。
///
/// 系統的開場畫面(Android 的 launch_background / values-v31 的 LaunchTheme、
/// iOS 的 LaunchScreen.storyboard)設成跟這裡一樣的羊皮紙色、沒有圖,
/// 兩段才接得起來,不會閃一下別的顏色。
///
/// 簽名的圖和動畫跟工作室另外兩個 App(拍啥咪、阿瓦隆)的開場是同一套。
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// 測試時關掉,直接顯示 [child]。
  final bool enabled;

  static const String signatureAsset = 'assets/branding/signature.webp';
  static const String starAsset = 'assets/branding/signature_star.webp';

  /// 跟系統開場畫面同一個顏色(android res/values/colors.xml 的 parchment)。
  static const Color parchment = Color(0xFFEEE3CD);

  static const Duration duration = Duration(milliseconds: 4300);

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LaunchIntro.duration);

  late bool _visible = widget.enabled;
  bool _started = false;
  bool _starLanded = false;
  Timer? _fallback;

  // 時間軸(毫秒)
  static const double _writeFrom = 350, _writeTo = 2050;
  static const double _starFrom = 1950, _starTo = 2650;
  static const double _shineFrom = 2450, _shineTo = 3350;
  static const double _fadeFrom = 3650;
  static double get _total => LaunchIntro.duration.inMilliseconds.toDouble();

  /// 星星在簽名圖(1997 × 788)裡的位置。
  static const Size _sigSize = Size(1997, 788);
  static const Rect _star = Rect.fromLTWH(1025, 466, 279, 249);

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_visible || _started) return;
    // 系統要求減少動態效果的話,不播動畫,只很快地淡出
    if (MediaQuery.of(context).disableAnimations) {
      _start(from: _fadeFrom / _total);
      return;
    }
    // 簽名還沒解碼好就開始寫的話,前面會空白一下。先解碼,
    // 但最多等 400 毫秒,不要因為這個卡住。
    _fallback = Timer(const Duration(milliseconds: 400), _start);
    Future.wait([
      precacheImage(const AssetImage(LaunchIntro.signatureAsset), context),
      precacheImage(const AssetImage(LaunchIntro.starAsset), context),
    ]).whenComplete(_start);
  }

  void _start({double from = 0}) {
    if (_started || !mounted) return;
    _started = true;
    _fallback?.cancel();
    _c.forward(from: from);
  }

  void _tick() {
    // 星星落定的那一下:閃亮聲加輕微震動
    if (!_starLanded && _c.value * _total >= _starFrom + 260) {
      _starLanded = true;
      if (_c.value * _total < _fadeFrom) {
        AppSounds.shared.play(AppSound.sparkle);
        HapticFeedback.lightImpact();
      }
    }
  }

  void _skip() {
    final fade = _fadeFrom / _total;
    if (_c.value < fade) {
      _starLanded = true; // 跳過時不要再響
      _c.forward(from: fade);
    }
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _c.dispose();
    super.dispose();
  }

  double _seg(double from, double to) =>
      ((_c.value * _total - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          // MaterialApp.builder 這一層在 Navigator 外面,沒有 Material 祖先
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: _c,
              // 紙只畫一次,之後每一幀只是搬圖層
              child: const RepaintBoundary(
                child: CustomPaint(painter: _PaperPainter()),
              ),
              builder: (context, paper) => Opacity(
                opacity:
                    1 - Curves.easeIn.transform(_seg(_fadeFrom, _total)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    paper!,
                    LayoutBuilder(builder: (context, c) {
                      final width = min(c.maxWidth * 0.78, c.maxHeight * 1.55);
                      return Center(
                        child: SizedBox(
                          width: width,
                          height: width * _sigSize.height / _sigSize.width,
                          child: _signature(width),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _signature(double width) {
    final k = width / _sigSize.width;
    final write = Curves.easeInOutSine.transform(_seg(_writeFrom, _writeTo));
    final starT = _seg(_starFrom, _starTo);
    final shine = _seg(_shineFrom, _shineTo);
    // 整張像一張紙放下來,稍微縮回原尺寸
    final settle = Curves.easeOutCubic.transform(_seg(0, 900));
    const edge = 0.08; // 筆尖的柔邊
    final image = Image.asset(
      LaunchIntro.signatureAsset,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    return Transform.scale(
      scale: 1.04 - 0.04 * settle,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 墨跡從左寫到右(微微斜著,像筆順)
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: const Alignment(-1, -0.15),
                end: const Alignment(1, 0.15),
                colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
                stops: [0, write * (1 + edge), write * (1 + edge) + edge]
                    .map((v) => (v - edge).clamp(0.0, 1.0))
                    .toList(),
              ).createShader(r),
              child: image,
            ),
          ),
          // 一道金光沿著墨跡掃過,只亮在有墨的地方
          if (shine > 0 && shine < 1)
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) {
                  final x =
                      lerpDouble(-0.3, 1.3, Curves.easeInOut.transform(shine))!;
                  return LinearGradient(
                    begin: const Alignment(-1, -0.4),
                    end: const Alignment(1, 0.4),
                    colors: const [
                      Color(0x00F2C14E),
                      Color(0x8CFFD978),
                      Color(0x00F2C14E),
                    ],
                    stops: [
                      (x - 0.12).clamp(0.0, 1.0),
                      x.clamp(0.0, 1.0),
                      (x + 0.12).clamp(0.0, 1.0),
                    ],
                  ).createShader(r);
                },
                child: image,
              ),
            ),
          // 寫完之後星星轉著彈出來,後面炸開一圈金光
          if (starT > 0)
            Positioned(
              left: _star.left * k,
              top: _star.top * k,
              width: _star.width * k,
              height: _star.height * k,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: OverflowBox(
                        minWidth: _star.width * k * 3.2,
                        maxWidth: _star.width * k * 3.2,
                        minHeight: _star.width * k * 3.2,
                        maxHeight: _star.width * k * 3.2,
                        child: CustomPaint(
                          painter: _BurstPainter(
                            const Color(0xFFE8B84A),
                            // 星星出來 180 毫秒後炸開,炸 900 毫秒
                            _seg(_starFrom + 180, _starFrom + 1080),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: (starT * 4).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: -0.9 * (1 - Curves.easeOutBack.transform(starT)),
                        child: Transform.scale(
                          scale: Curves.elasticOut.transform(starT),
                          child: Image.asset(
                            LaunchIntro.starAsset,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 星星後面炸開的金光:一團光暈、14 道光芒、一圈往外擴的光環。
class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.color, this.t);

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final e = Curves.easeOutCubic.transform(t);
    final fade = (1 - t) * (1 - t);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.75 * fade),
            color.withValues(alpha: 0.25 * fade),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final rays = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * fade)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.02;
    for (var i = 0; i < 14; i++) {
      final a = i * 2 * pi / 14 + 0.2;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(c + d * r * (0.28 + 0.3 * e),
          c + d * r * (0.4 + 0.55 * e) * (i.isEven ? 1 : 0.8), rays);
    }
    canvas.drawCircle(
      c,
      r * (0.3 + 0.65 * e),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05 * (1 - t)
        ..color = Color.lerp(color, Colors.white, 0.5)!
            .withValues(alpha: 0.9 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// 羊皮紙:中間亮、四周暗一點,加上一點紙纖維。
class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.1,
          colors: [Color(0xFFF5ECDA), Color(0xFFEEE3CD), Color(0xFFD9C7A3)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    final rng = Random(3);
    final fibre = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 260; i++) {
      final p =
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height);
      final a = rng.nextDouble() * pi;
      final l = 4 + rng.nextDouble() * 14;
      fibre
        ..strokeWidth = 0.6 + rng.nextDouble() * 0.8
        ..color = const Color(0xFF8A6A3A)
            .withValues(alpha: 0.03 + rng.nextDouble() * 0.05);
      canvas.drawLine(p, p + Offset(cos(a), sin(a)) * l, fibre);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
