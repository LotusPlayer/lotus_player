import 'dart:math' as math;
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import '../theme/lotus_theme.dart';

class _MoodMatrixScope extends InheritedWidget {
  const _MoodMatrixScope({required super.child});

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

class LotusMoodMatrixBackdrop extends StatefulWidget {
  final Widget child;

  const LotusMoodMatrixBackdrop({
    super.key,
    required this.child,
  });

  @override
  State<LotusMoodMatrixBackdrop> createState() => _LotusMoodMatrixBackdropState();
}

class _LotusMoodMatrixBackdropState extends State<LotusMoodMatrixBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LotusThemeController _theme = LotusThemeController.instance;
  late final AnimationController _matrixController;
  bool _hasAncestorBackdrop = false;

  // Frame-throttle: repaint at ~30fps (every 2nd frame). The dot-grid painter
  // is CPU-heavy (~2k iterations/frame); halving the rate halves UI-thread load.
  int _frameCounter = 0;
  final ValueNotifier<double> _paintProgress = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _matrixController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _matrixController.addListener(_onControllerFrame);

    _theme.addListener(_onThemeChanged);
  }

  void _onControllerFrame() {
    _frameCounter++;
    if (_frameCounter % 2 == 0) {
      _paintProgress.value = _matrixController.value;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateAnimationTicker();
    } else {
      if (_matrixController.isAnimating) {
        _matrixController.stop();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _MoodMatrixScope? scope =
    context.dependOnInheritedWidgetOfExactType<_MoodMatrixScope>();
    _hasAncestorBackdrop = (scope != null);
    _updateAnimationTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.removeListener(_onThemeChanged);
    _matrixController.removeListener(_onControllerFrame);
    _matrixController.dispose();
    _paintProgress.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    _updateAnimationTicker();
    if (mounted) setState(() {});
  }

  void _updateAnimationTicker() {
    if (_hasAncestorBackdrop) {
      if (_matrixController.isAnimating) {
        _matrixController.stop();
      }
      return;
    }

    if (_theme.isMoodMatrixActive) {
      if (!_matrixController.isAnimating) {
        _matrixController.repeat();
      }
    } else {
      if (_matrixController.isAnimating) {
        _matrixController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAncestorBackdrop) {
      return widget.child;
    }

    return _MoodMatrixScope(
      child: ListenableBuilder(
        listenable: _theme,
        builder: (BuildContext context, Widget? child) {
          final bool isMatrixThemeActive = _theme.isMoodMatrixActive;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (isMatrixThemeActive)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _paintProgress,
                      builder: (BuildContext context, double value, _) {
                        return CustomPaint(
                          willChange: true,
                          painter: _DotMatrixMeshPainter(
                            progress: value,
                            isAmoled: _theme.isAmoled,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              widget.child,
            ],
          );
        },
      ),
    );
  }
}

class _DotMatrixMeshPainter extends CustomPainter {
  final double progress;
  final bool isAmoled;

  // Reusable Zero-GC Point Buffers (Avoids allocating hundreds of heap objects per frame)
  static final List<Offset> _pointsCyan = <Offset>[];
  static final List<Offset> _pointsViolet = <Offset>[];
  static final List<Offset> _pointsMagenta = <Offset>[];
  static final List<Offset> _pointsGold = <Offset>[];

  static final Shader _cachedBlob1Shader = const RadialGradient(
    colors: <Color>[
      Color(0x2900F2FE),
      Color(0x147928CA),
      Colors.transparent,
    ],
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: 180));

  static final Shader _cachedBlob2Shader = const RadialGradient(
    colors: <Color>[
      Color(0x24FF2A8D),
      Color(0x0FFFB300),
      Colors.transparent,
    ],
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: 200));

  static final Paint _blob1Paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..shader = _cachedBlob1Shader;

  static final Paint _blob2Paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..shader = _cachedBlob2Shader;

  static final Paint _bgAmoledPaint = Paint()..color = const Color(0xFF000000);
  static final Paint _bgObsidianPaint = Paint()..color = const Color(0xFF070A12);

  // 4 Pre-allocated batch paints with StrokeCap.round for instant hardware circle drawing
  static final Paint _paintCyan = Paint()
    ..color = const Color(0x3D00F2FE)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  static final Paint _paintViolet = Paint()
    ..color = const Color(0x357928CA)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  static final Paint _paintMagenta = Paint()
    ..color = const Color(0x3DFF2A8D)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  static final Paint _paintGold = Paint()
    ..color = const Color(0x35FFB300)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  _DotMatrixMeshPainter({
    required this.progress,
    required this.isAmoled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Ambient Background Base
    final Rect bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(bgRect, isAmoled ? _bgAmoledPaint : _bgObsidianPaint);

    // 2. Multi-color Radiant Gradient Blobs
    final double radAngle = progress * (2.0 * math.pi);

    final double blob1X = size.width * 0.25 + (math.sin(radAngle) * 50.0);
    final double blob1Y = size.height * 0.20 + (math.cos(radAngle) * 60.0);

    final double blob2X = size.width * 0.75 + (math.cos(radAngle) * 60.0);
    final double blob2Y = size.height * 0.70 + (math.sin(radAngle) * 70.0);

    canvas.save();
    canvas.translate(blob1X, blob1Y);
    canvas.drawCircle(Offset.zero, 180, _blob1Paint);
    canvas.restore();

    canvas.save();
    canvas.translate(blob2X, blob2Y);
    canvas.drawCircle(Offset.zero, 200, _blob2Paint);
    canvas.restore();

    // 3. Batched Floating Semi-Dots Grid (Zero-GC Buffer Execution)
    // Spacing widened from 34 to 44 (~45% fewer dots per frame → less UI-thread CPU).
    const double spacing = 44.0;
    final int cols = (size.width / spacing).ceil() + 1;
    final int rows = (size.height / spacing).ceil() + 1;

    final double globalPhase = progress * (2.0 * math.pi);

    _pointsCyan.clear();
    _pointsViolet.clear();
    _pointsMagenta.clear();
    _pointsGold.clear();

    for (int r = 0; r < rows; r++) {
      final double baseY = r * spacing;
      final double rowPhase = (r * 0.35) + globalPhase;

      for (int c = 0; c < cols; c++) {
        final double baseX = c * spacing;
        final double dotPhase = rowPhase + (c * 0.28);
        final double wave = math.sin(dotPhase);

        if (wave < -0.25) continue;

        final double driftX = baseX + (math.cos(dotPhase) * 4.0);
        final double driftY = baseY + (wave * 4.0);

        final int colorIndex = (r + c) & 3;
        final Offset pt = Offset(driftX, driftY);

        if (colorIndex == 0) {
          _pointsCyan.add(pt);
        } else if (colorIndex == 1) {
          _pointsViolet.add(pt);
        } else if (colorIndex == 2) {
          _pointsMagenta.add(pt);
        } else {
          _pointsGold.add(pt);
        }
      }
    }

    // 4. Execute 4 Batched Hardware Point Draws
    if (_pointsCyan.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsCyan, _paintCyan);
    }
    if (_pointsViolet.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsViolet, _paintViolet);
    }
    if (_pointsMagenta.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsMagenta, _paintMagenta);
    }
    if (_pointsGold.isNotEmpty) {
      canvas.drawPoints(PointMode.points, _pointsGold, _paintGold);
    }
  }

  @override
  bool shouldRepaint(covariant _DotMatrixMeshPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isAmoled != isAmoled;
  }
}
