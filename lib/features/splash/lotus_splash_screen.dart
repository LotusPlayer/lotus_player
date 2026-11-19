import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/theme/lotus_theme.dart';
import '../navigation/lotus_main_scaffold.dart';

class LotusSplashScreen extends StatefulWidget {
  const LotusSplashScreen({super.key});

  @override
  State<LotusSplashScreen> createState() => _LotusSplashScreenState();
}

class _LotusSplashScreenState extends State<LotusSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bloomController;
  late final AnimationController _haloRotateController;
  late final AnimationController _midiSpectrumController;
  late final AnimationController _pulseGlowController;
  late final AnimationController _bufferLoadingController;
  late final AnimationController _radialExpansionController;

  late final Animation<double> _bloomScale;
  late final Animation<double> _bloomFade;
  late final Animation<double> _textFade;
  late final Animation<double> _progressAnimation;
  late final Animation<double> _radialExpansionAnimation;

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final LotusThemeController _theme = LotusThemeController.instance;

  bool _isNavigating = false;
  bool _isBufferReady = false;

  @override
  void initState() {
    super.initState();

    // 1. Organic Flower Bloom Animation (Entrance)
    _bloomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _bloomScale = CurvedAnimation(
      parent: _bloomController,
      curve: Curves.easeOutBack,
    );

    _bloomFade = CurvedAnimation(
      parent: _bloomController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );

    _textFade = CurvedAnimation(
      parent: _bloomController,
      curve: const Interval(0.2, 0.85, curve: Curves.easeOut),
    );

    // 2. Halo & Harmonic MIDI Orbit Rings Rotation
    _haloRotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // 3. Realtime MIDI Frequency Bar Dancing
    _midiSpectrumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // 4. Ambient Breathing Pulse
    _pulseGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    // 5. Optimized Buffer Progress (Streamlined to 1000ms for instant feel)
    _bufferLoadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _progressAnimation = CurvedAnimation(
      parent: _bufferLoadingController,
      curve: Curves.easeInOutCubic,
    );

    // 6. Snappy Radial Bloom Expansion
    _radialExpansionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _radialExpansionAnimation = CurvedAnimation(
      parent: _radialExpansionController,
      curve: Curves.easeInOutQuart,
    );

    _bufferLoadingController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed &&
          mounted &&
          _isBufferReady &&
          !_isNavigating) {
        _onEnterSoundSanctuaryPressed();
      }
    });

    _bloomController.forward();
    _bufferLoadingController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionsAndStartApp();
    });
  }

  Future<void> _requestPermissionsAndStartApp() async {
    try {
      if (Platform.isAndroid) {
        bool granted = false;

        // Android 13+ (API 33+) Media Permissions Guard
        if (await Permission.audio.isGranted) {
          granted = true;
        } else {
          final PermissionStatus audioStatus = await Permission.audio.request();
          granted = audioStatus.isGranted;

          // Fallback check for Android 12 and below
          if (!granted && await Permission.storage.request().isGranted) {
            granted = true;
          }
        }

        // Request notification permission smoothly without blocking audio boot
        try {
          if (!await Permission.notification.isGranted) {
            await Permission.notification.request();
          }
        } catch (_) {}

        if (granted) {
          try {
            final List<SongModel> songs = await _audioQuery.querySongs(
              sortType: SongSortType.DATE_ADDED,
              orderType: OrderType.DESC_OR_GREATER,
              uriType: UriType.EXTERNAL,
              ignoreCase: true,
            ).timeout(const Duration(seconds: 2));

            if (songs.isNotEmpty) {
              unawaited(LotusPlaybackProvider.instance.hydrateLastPlayed(songs));
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Lotus Permission handling notice: $e');
    } finally {
      if (mounted) {
        setState(() => _isBufferReady = true);

        if (!_bufferLoadingController.isAnimating && !_isNavigating) {
          _onEnterSoundSanctuaryPressed();
        }
      }
    }
  }

  void _onEnterSoundSanctuaryPressed() {
    if (_isNavigating || !mounted) return;
    setState(() {
      _isNavigating = true;
    });

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    _radialExpansionController.forward().then((_) {
      if (!mounted) return;

      _haloRotateController.stop();
      _midiSpectrumController.stop();
      _pulseGlowController.stop();
      _bufferLoadingController.stop();

      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (BuildContext context, Animation<double> a,
              Animation<double> sa) {
            return const LotusMainScaffold();
          },
          transitionsBuilder: (BuildContext context, Animation<double> a,
              Animation<double> sa, Widget child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: a,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 250),
        ),
      );
    });
  }

  @override
  void dispose() {
    _bloomController.dispose();
    _haloRotateController.dispose();
    _midiSpectrumController.dispose();
    _pulseGlowController.dispose();
    _bufferLoadingController.dispose();
    _radialExpansionController.dispose();
    super.dispose();
  }

  String _getStatusText(double progress) {
    if (progress < 0.35) {
      return 'CALIBRATING DIRECT AUDIO ENGINE...';
    } else if (progress < 0.75) {
      return 'SYNCHRONIZING DSP EQUALIZER...';
    } else {
      return 'BLOOM HARMONIC ENGINE READY';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _theme.primaryAccent;
    final Color secondaryAccent = _theme.secondaryAccent;

    return Scaffold(
      backgroundColor: LotusColors.background,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: RepaintBoundary(
              child: LotusSplashDotMatrixBackdrop(),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulseGlowController,
                builder: (BuildContext context, Widget? child) {
                  final double pulse = _pulseGlowController.value;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.22),
                        radius: 1.25 + (0.2 * pulse),
                        colors: <Color>[
                          LotusColors.electricViolet
                              .withValues(alpha: 0.16 + (0.06 * pulse)),
                          LotusColors.magentaNeon.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                const SizedBox(height: 14),
                _buildTopChip(accent),
                const Spacer(),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _haloRotateController,
                          builder: (BuildContext context, Widget? child) {
                            return Transform.rotate(
                              angle: _haloRotateController.value * 2 * math.pi,
                              child: const CustomPaint(
                                size: Size(280, 280),
                                painter: LotusCymaticOrbitPainter(),
                              ),
                            );
                          },
                        ),
                      ),
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _haloRotateController,
                          builder: (BuildContext context, Widget? child) {
                            return Transform.rotate(
                              angle: -_haloRotateController.value *
                                  2 *
                                  math.pi *
                                  0.7,
                              child: const CustomPaint(
                                size: Size(220, 220),
                                painter: LotusInnerHarmonicOrbitPainter(),
                              ),
                            );
                          },
                        ),
                      ),
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _pulseGlowController,
                          builder: (BuildContext context, Widget? child) {
                            final double p = _pulseGlowController.value;
                            return Container(
                              width: 180 + (26 * p),
                              height: 180 + (26 * p),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: LotusColors.magentaNeon
                                        .withValues(alpha: 0.35 + (0.2 * p)),
                                    blurRadius: 42 + (20 * p),
                                    spreadRadius: 8,
                                  ),
                                  BoxShadow(
                                    color: LotusColors.cyanNeon
                                        .withValues(alpha: 0.32),
                                    blurRadius: 32,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      ScaleTransition(
                        scale: _bloomScale,
                        child: FadeTransition(
                          opacity: _bloomFade,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                LotusColors.cyanNeon.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                              boxShadow: LotusDecorations.glowShadow(
                                LotusColors.cyanNeon,
                                intensity: 0.28,
                                blur: 18,
                              ),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/lotus_flower_icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (BuildContext context,
                                    Object error, StackTrace? stackTrace) {
                                  return const CustomPaint(
                                    painter: FallbackLotusFlowerPainter(),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _midiSpectrumController,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        size: const Size(190, 34),
                        painter: LotusHarmonicSpectrumPainter(
                          progress: _midiSpectrumController.value,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _textFade,
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: LotusColors.cyanNeon,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ShaderMask(
                            shaderCallback: (Rect bounds) =>
                                const LinearGradient(
                                  colors: <Color>[
                                    LotusColors.cyanNeon,
                                    Colors.white,
                                    LotusColors.magentaNeon,
                                  ],
                                ).createShader(bounds),
                            child: const Text(
                              'Lotus Player',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: LotusColors.magentaNeon,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Makes Your Emotions Bloom',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: LotusColors.auroraPink.withValues(alpha: 0.95),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: LotusColors.glassBorder),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.spa_rounded,
                                size: 12, color: LotusColors.cyanNeon),
                            SizedBox(width: 6),
                            Text(
                              '120 FPS BIT-PERFECT BOOTSTRAP • 528HZ SOLFEGGIO',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                color: Colors.white70,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (BuildContext context, Widget? child) {
                      final double val =
                      _progressAnimation.value.clamp(0.0, 1.0);
                      final int percent = (val * 100).toInt();
                      final String status = _getStatusText(val);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: LotusColors.textMuted,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$percent% READY',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                  color: LotusColors.cyanNeon,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: LayoutBuilder(
                              builder: (BuildContext context,
                                  BoxConstraints constraints) {
                                final double barWidth =
                                    constraints.maxWidth * val;
                                return Stack(
                                  children: <Widget>[
                                    Container(
                                      width: barWidth,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        gradient: const LinearGradient(
                                          colors: <Color>[
                                            LotusColors.magentaNeon,
                                            LotusColors.electricViolet,
                                            LotusColors.cyanNeon,
                                          ],
                                        ),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: LotusColors.cyanNeon
                                                .withValues(alpha: 0.55),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: <Color>[
                          LotusColors.magentaNeon,
                          LotusColors.cyanNeon,
                        ],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: LotusColors.cyanNeon.withValues(alpha: 0.38),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _onEnterSoundSanctuaryPressed,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(Icons.local_florist_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                _isNavigating
                                    ? 'Entering Sound Sanctuary...'
                                    : (_isBufferReady
                                    ? 'Enter Sound Sanctuary'
                                    : 'Calibrating Audio Engines...'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: LotusColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.verified_rounded,
                              size: 13, color: LotusColors.cyanNeon),
                          SizedBox(width: 6),
                          Text(
                            'Developed By Souljalazian',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: Color(0xFFD6DBE7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _radialExpansionAnimation,
            builder: (BuildContext context, Widget? child) {
              final double progress = _radialExpansionAnimation.value;
              if (progress <= 0.001) return const SizedBox.shrink();

              return Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RadialBloomExpansionPainter(
                      progress: progress,
                      accent: accent,
                      secondaryAccent: secondaryAccent,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopChip(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: LotusColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(radius: 3.5, backgroundColor: LotusColors.cyanNeon),
            SizedBox(width: 8),
            Text(
              'DSP 32-BIT • 768KHZ BIT-PERFECT DIRECT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: LotusColors.cyanNeon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// OPTIMIZED SEMI-DOT MATRIX BACKDROP (ZERO-GC BATCHED HARDWARE DRAWS)
// ==============================================================================
class LotusSplashDotMatrixBackdrop extends StatefulWidget {
  const LotusSplashDotMatrixBackdrop({super.key});

  @override
  State<LotusSplashDotMatrixBackdrop> createState() =>
      _LotusSplashDotMatrixBackdropState();
}

class _LotusSplashDotMatrixBackdropState
    extends State<LotusSplashDotMatrixBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _matrixController;

  @override
  void initState() {
    super.initState();
    _matrixController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _matrixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _matrixController,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _SplashDotMatrixPainter(progress: _matrixController.value),
        );
      },
    );
  }
}

class _SplashDotMatrixPainter extends CustomPainter {
  final double progress;

  _SplashDotMatrixPainter({required this.progress});

  // Pre-allocated Zero-GC point buffers
  static final List<Offset> _pointsCyan = <Offset>[];
  static final List<Offset> _pointsViolet = <Offset>[];
  static final List<Offset> _pointsMagenta = <Offset>[];
  static final List<Offset> _pointsGold = <Offset>[];

  static final Paint _paintCyan = Paint()
    ..color = const Color(0xFF00F2FE).withValues(alpha: 0.35)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  static final Paint _paintViolet = Paint()
    ..color = const Color(0xFF7928CA).withValues(alpha: 0.32)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  static final Paint _paintMagenta = Paint()
    ..color = const Color(0xFFFF2A8D).withValues(alpha: 0.35)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  static final Paint _paintGold = Paint()
    ..color = const Color(0xFFFFB300).withValues(alpha: 0.32)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF080B11),
    );

    const double spacing = 40.0;
    final int cols = (size.width / spacing).ceil() + 1;
    final int rows = (size.height / spacing).ceil() + 1;

    _pointsCyan.clear();
    _pointsViolet.clear();
    _pointsMagenta.clear();
    _pointsGold.clear();

    final double globalPhase = progress * 2 * math.pi;

    for (int r = 0; r < rows; r++) {
      final double baseY = r * spacing;
      final double rowPhase = (r * 0.35) + globalPhase;

      for (int c = 0; c < cols; c++) {
        final double baseX = c * spacing;
        final double dotPhase = rowPhase + (c * 0.28);
        final double wave = math.sin(dotPhase);

        if (wave < 0.0) continue;

        final double driftX = baseX + (math.cos(dotPhase) * 3.5);
        final double driftY = baseY + (wave * 3.5);
        final Offset pt = Offset(driftX, driftY);

        final int colorIndex = (r + c) & 3;
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

    // 4 Hardware draw calls replace hundreds of unbatched drawCircle commands
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
  bool shouldRepaint(covariant _SplashDotMatrixPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ==============================================================================
// 2. OUTER CYMATIC SOUNDWAVE ORBIT RING PAINTER
// ==============================================================================
class LotusCymaticOrbitPainter extends CustomPainter {
  const LotusCymaticOrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    final Paint dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas.drawCircle(center, radius - 4, dashPaint);

    const int stepCount = 20;
    for (int i = 0; i < stepCount; i++) {
      final double angle = (i * 2 * math.pi) / stepCount;
      final double x = center.dx + (radius - 4) * math.cos(angle);
      final double y = center.dy + (radius - 4) * math.sin(angle);

      final Paint nodePaint = Paint();
      double nodeSize = 2.2;

      if (i % 5 == 0) {
        nodePaint.color = LotusColors.cyanNeon;
        nodeSize = 4.0;
      } else if (i % 2 == 0) {
        nodePaint.color = LotusColors.magentaNeon;
        nodeSize = 3.0;
      } else {
        nodePaint.color = Colors.white24;
      }

      canvas.drawCircle(Offset(x, y), nodeSize, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==============================================================================
// 3. INNER HARMONIC ORBIT PAINTER
// ==============================================================================
class LotusInnerHarmonicOrbitPainter extends CustomPainter {
  const LotusInnerHarmonicOrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    final Paint ringPaint = Paint()
      ..color = LotusColors.cyanNeon.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius - 2, ringPaint);

    const int nodeCount = 12;
    for (int i = 0; i < nodeCount; i++) {
      final double angle = (i * 2 * math.pi) / nodeCount;
      final double x = center.dx + (radius - 2) * math.cos(angle);
      final double y = center.dy + (radius - 2) * math.sin(angle);

      final Paint nodePaint = Paint()
        ..color = (i % 3 == 0) ? LotusColors.solarGold : LotusColors.electricViolet;

      canvas.drawCircle(Offset(x, y), 2.4, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==============================================================================
// 4. HARMONIC SPECTRUM VISUALIZER BARS PAINTER
// ==============================================================================
class LotusHarmonicSpectrumPainter extends CustomPainter {
  final double progress;

  static const int barCount = 15;
  static const List<double> baseHeights = <double>[
    0.2, 0.4, 0.7, 0.95, 0.65, 0.85, 1.0, 0.75, 0.55, 0.85, 0.6, 0.45, 0.3, 0.5, 0.2
  ];

  static Shader? _cyanShader;
  static Shader? _magentaShader;
  static double _cachedHeight = 0.0;

  const LotusHarmonicSpectrumPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double barWidth = size.width / (barCount * 1.8);

    if (_cyanShader == null || _cachedHeight != size.height) {
      _cachedHeight = size.height;
      _cyanShader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[
          LotusColors.cyanNeon,
          LotusColors.magentaNeon,
        ],
      ).createShader(Rect.fromLTWH(0, 0, barWidth, size.height));

      _magentaShader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[
          LotusColors.magentaNeon,
          LotusColors.solarGold,
        ],
      ).createShader(Rect.fromLTWH(0, 0, barWidth, size.height));
    }

    final Paint cyanPaint = Paint()..shader = _cyanShader;
    final Paint magentaPaint = Paint()..shader = _magentaShader;

    for (int i = 0; i < barCount; i++) {
      final double dynamicFactor =
      math.sin((progress * math.pi) + (i * 0.38)).abs();
      final double barHeight = (size.height *
          baseHeights[i] *
          (0.4 + 0.6 * dynamicFactor))
          .clamp(6.0, size.height);

      final double left = i * (barWidth * 1.8);
      final double top = size.height - barHeight;

      final RRect rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(4),
      );

      canvas.drawRRect(rect, (i % 2 == 0) ? cyanPaint : magentaPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LotusHarmonicSpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ==============================================================================
// 5. RADIAL-BLOOM EXPANSION TRANSITION PAINTER
// ==============================================================================
class _RadialBloomExpansionPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color secondaryAccent;

  _RadialBloomExpansionPainter({
    required this.progress,
    required this.accent,
    required this.secondaryAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height * 0.42);
    final double maxRadius =
        math.sqrt(size.width * size.width + size.height * size.height) * 1.05;
    final double currentRadius = maxRadius * progress;

    final Paint wavePaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          accent.withValues(alpha: (1.0 - progress) * 0.7),
          secondaryAccent.withValues(alpha: (1.0 - progress) * 0.5),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: currentRadius));

    canvas.drawCircle(center, currentRadius, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _RadialBloomExpansionPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.secondaryAccent != secondaryAccent;
  }
}

// ==============================================================================
// 6. FALLBACK LOTUS FLOWER PAINTER
// ==============================================================================
class FallbackLotusFlowerPainter extends CustomPainter {
  const FallbackLotusFlowerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        colors: <Color>[
          LotusColors.solarGold,
          LotusColors.magentaNeon,
          LotusColors.cyanNeon,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((i * 45) * math.pi / 180);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -45), width: 36, height: 75),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}