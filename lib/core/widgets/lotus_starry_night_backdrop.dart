import 'dart:math' as math;
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import '../theme/lotus_theme.dart';

class LotusStarryNightBackdrop extends StatefulWidget {
  final Widget child;

  const LotusStarryNightBackdrop({
    super.key,
    required this.child,
  });

  @override
  State<LotusStarryNightBackdrop> createState() =>
      _LotusStarryNightBackdropState();
}

class _LotusStarryNightBackdropState extends State<LotusStarryNightBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LotusThemeController _theme = LotusThemeController.instance;
  late final AnimationController _animController;

  // Frame-throttle: repaint at ~30fps (every 2nd frame) instead of every frame.
  // Halves GPU load; visually identical for a slow-moving starfield/gradient.
  int _frameCounter = 0;
  final ValueNotifier<double> _paintProgress = ValueNotifier<double>(0.0);

  static const int _kStarCount = 85;
  static final List<_StarParticle> _stars = _generateStars(_kStarCount);

  static List<_StarParticle> _generateStars(int count) {
    final math.Random rng = math.Random(42);
    return List<_StarParticle>.generate(count, (int index) {
      return _StarParticle(
        relX: rng.nextDouble(),
        relY: rng.nextDouble(),
        speed: 0.045 + (rng.nextDouble() * 0.085),
        phase: rng.nextDouble() * math.pi * 2,
        colorIndex: index & 3, // 0: Cyan, 1: Purple, 2: Magenta, 3: Amber
        baseAlpha: 0.30 + (rng.nextDouble() * 0.55),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    _animController.addListener(_onControllerFrame);

    _theme.addListener(_onThemeChanged);
    _syncController();
  }

  void _onControllerFrame() {
    _frameCounter++;
    if (_frameCounter % 2 == 0) {
      _paintProgress.value = _animController.value;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncController();
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  void _onThemeChanged() {
    _syncController();
    if (mounted) setState(() {});
  }

  void _syncController() {
    if (_theme.isStarryNightActive) {
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.removeListener(_onThemeChanged);
    _animController.removeListener(_onControllerFrame);
    _animController.dispose();
    _paintProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, _) {
        final bool isStarry = _theme.isStarryNightActive;

        if (!isStarry) {
          return widget.child;
        }

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Deep Celestial Cosmic Space Void Backdrop
            const RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LotusColors.starryVoidBg,
                ),
              ),
            ),

            // 2. Throttled 30fps Stardust & Luminous Edge Wave Painter
            RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _paintProgress,
                builder: (BuildContext context, double value, _) {
                  return CustomPaint(
                    size: Size.infinite,
                    painter: _CalmStarryNightPainter(
                      progress: value,
                      stars: _stars,
                    ),
                  );
                },
              ),
            ),

            // 3. Transparent App Layer Pass-Through
            widget.child,
          ],
        );
      },
    );
  }
}

class _StarParticle {
  final double relX;
  final double relY;
  final double speed;
  final double phase;
  final int colorIndex;
  final double baseAlpha;

  const _StarParticle({
    required this.relX,
    required this.relY,
    required this.speed,
    required this.phase,
    required this.colorIndex,
    required this.baseAlpha,
  });
}

class _CalmStarryNightPainter extends CustomPainter {
  final double progress;
  final List<_StarParticle> stars;

  _CalmStarryNightPainter({
    required this.progress,
    required this.stars,
  });

  // Reusable Zero-GC Point Buffers (Avoids 85+ heap allocations every frame)
  static final List<Offset> _pointsCyan = <Offset>[];
  static final List<Offset> _pointsPurple = <Offset>[];
  static final List<Offset> _pointsMagenta = <Offset>[];
  static final List<Offset> _pointsAmber = <Offset>[];

  // Pre-allocated batch paints for the 4 spectral star colors
  static final Paint _starPaintCyan = Paint()
    ..color = LotusColors.starryCyanStardust.withValues(alpha: 0.70)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.4;

  static final Paint _starPaintPurple = Paint()
    ..color = LotusColors.starryNeonPurple.withValues(alpha: 0.75)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.4;

  static final Paint _starPaintMagenta = Paint()
    ..color = LotusColors.starryCosmicMagenta.withValues(alpha: 0.65)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.4;

  static final Paint _starPaintAmber = Paint()
    ..color = LotusColors.starryAmberGold.withValues(alpha: 0.70)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.4;

  static final Paint _edgeGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;

  static final Paint _outerCoronaPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double t = progress * math.pi * 2;

    // ── 1. ZERO-GC BATCHED STARDUST RENDERING ─────────────────────────────────
    _pointsCyan.clear();
    _pointsPurple.clear();
    _pointsMagenta.clear();
    _pointsAmber.clear();

    for (int i = 0; i < stars.length; i++) {
      final _StarParticle star = stars[i];

      final double currentY = (star.relY + (progress * star.speed * 2.5)) % 1.0;
      final double px = star.relX * size.width;
      final double py = currentY * size.height;
      final Offset pt = Offset(px, py);

      if (star.colorIndex == 0) {
        _pointsCyan.add(pt);
      } else if (star.colorIndex == 1) {
        _pointsPurple.add(pt);
      } else if (star.colorIndex == 2) {
        _pointsMagenta.add(pt);
      } else {
        _pointsAmber.add(pt);
      }
    }

    // Dynamic Twinkle Alpha Modulation
    final double twinkleBreath = 0.80 + 0.20 * math.sin(t * 3.0);
    _starPaintCyan.color =
        LotusColors.starryCyanStardust.withValues(alpha: (0.70 * twinkleBreath).clamp(0.2, 1.0));
    _starPaintPurple.color =
        LotusColors.starryNeonPurple.withValues(alpha: (0.75 * twinkleBreath).clamp(0.2, 1.0));
    _starPaintMagenta.color =
        LotusColors.starryCosmicMagenta.withValues(alpha: (0.65 * twinkleBreath).clamp(0.2, 1.0));
    _starPaintAmber.color =
        LotusColors.starryAmberGold.withValues(alpha: (0.70 * twinkleBreath).clamp(0.2, 1.0));

    // 4 hardware draw calls for all stars
    if (_pointsCyan.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsCyan, _starPaintCyan);
    }
    if (_pointsPurple.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsPurple, _starPaintPurple);
    }
    if (_pointsMagenta.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsMagenta, _starPaintMagenta);
    }
    if (_pointsAmber.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsAmber, _starPaintAmber);
    }

    // ── 2. MOVING HORIZON EDGE LIGHT (ZERO-OFFSCREEN BLUR PASS) ──────────────
    final Rect bounds =
    Rect.fromLTWH(1.5, 1.5, size.width - 3.0, size.height - 3.0);
    final RRect rrect =
    RRect.fromRectAndRadius(bounds, const Radius.circular(24.0));

    final double breathCycle = 0.75 + 0.25 * ((math.sin(t * 2.0) + 1.0) * 0.5);

    final SweepGradient edgeSweep = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi * 2,
      transform: GradientRotation(t),
      colors: <Color>[
        LotusColors.starryNeonPurple.withValues(alpha: 0.0),
        LotusColors.starryNeonPurple.withValues(alpha: 0.55 * breathCycle),
        LotusColors.starryUltraviolet.withValues(alpha: 0.75 * breathCycle),
        LotusColors.starryCyanStardust.withValues(alpha: 0.65 * breathCycle),
        LotusColors.starryCosmicMagenta.withValues(alpha: 0.50 * breathCycle),
        LotusColors.starryNeonPurple.withValues(alpha: 0.0),
      ],
      stops: const <double>[0.0, 0.20, 0.45, 0.70, 0.88, 1.0],
    );

    final Shader sweepShader = edgeSweep.createShader(bounds);

    _outerCoronaPaint.shader = sweepShader;
    canvas.drawRRect(rrect, _outerCoronaPaint);

    _edgeGlowPaint.shader = sweepShader;
    canvas.drawRRect(rrect, _edgeGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _CalmStarryNightPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
