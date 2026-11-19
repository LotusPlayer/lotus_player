import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_equalizer_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../home/lotus_mood_sanctuary_modal.dart';

class LotusDspEqualizerScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const LotusDspEqualizerScreen({
    super.key,
    this.onBack,
  });

  @override
  State<LotusDspEqualizerScreen> createState() =>
      _LotusDspEqualizerScreenState();
}

class _LotusDspEqualizerScreenState extends State<LotusDspEqualizerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final LotusEqualizerService _eqService = LotusEqualizerService.instance;
  final LotusThemeController _theme = LotusThemeController.instance;

  static const List<String> _bandFrequencies = <String>[
    '31Hz',
    '63Hz',
    '125Hz',
    '250Hz',
    '500Hz',
    '1kHz',
    '2kHz',
    '4kHz',
    '8kHz',
    '16kHz',
  ];

  late final AnimationController _fftController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _syncAnimationWithPlayback();

    _playback.addListener(_onPlaybackStateChanged);
    _eqService.addListener(_onEqServiceChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAnimationWithPlayback();
    } else {
      if (_fftController.isAnimating) {
        _fftController.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback.removeListener(_onPlaybackStateChanged);
    _eqService.removeListener(_onEqServiceChanged);
    _fftController.dispose();
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    _syncAnimationWithPlayback();
  }

  void _onEqServiceChanged() {
    if (!mounted) return;
    setState(() {});
    _syncAnimationWithPlayback();
  }

  void _syncAnimationWithPlayback() {
    if (!mounted) return;
    final bool shouldAnimate = _playback.isPlaying &&
        _playback.activeSong != null &&
        _eqService.isEnabled;

    if (shouldAnimate) {
      if (!_fftController.isAnimating) {
        _fftController.repeat(reverse: true);
      }
    } else {
      if (_fftController.isAnimating) {
        _fftController.stop();
        _fftController.value = 0.0;
      }
    }
  }

  void _applyPreset(String preset) {
    HapticFeedback.selectionClick();
    _eqService.applyPreset(preset);
  }

  Color _getBandColor(int index, Color accent, Color secondaryAccent) {
    if (index < 3) return secondaryAccent;
    if (index < 7) return accent;
    return LotusColors.solarGold;
  }

  String _formatGain(double gain) {
    final String sign = gain > 0 ? '+' : '';
    if (gain == gain.roundToDouble()) {
      return '$sign${gain.toInt()}dB';
    }
    return '$sign${gain.toStringAsFixed(1)}dB';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, _) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final Color bgColor = _theme.backgroundColor;
        final Color surfaceColor = _theme.surfaceColor;
        final Color containerLow = _theme.containerLowColor;

        return Scaffold(
          backgroundColor: bgColor,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildTopAppBar(accent, surfaceColor, containerLow),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 120.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildFftSpectrumCard(accent, containerLow),
                        const SizedBox(height: 14),
                        _buildMoodSanctuaryQuickBanner(
                            accent, secondaryAccent, containerLow),
                        const SizedBox(height: 14),
                        _buildPresetsRow(accent, containerLow),
                        const SizedBox(height: 14),
                        _buildTenBandSlidersCard(
                            accent, secondaryAccent, containerLow),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopAppBar(
      Color accent, Color surfaceColor, Color containerLow) {
    final Color textPrimary = _theme.textPrimaryColor;
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return ListenableBuilder(
      listenable: _eqService,
      builder: (BuildContext context, _) {
        final bool eqOn = _eqService.isEnabled;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(
              bottom: BorderSide(
                color: isWhitaniana
                    ? _theme.cardBorderColor
                    : accent.withValues(alpha: 0.2),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: containerLow,
                  border: Border.all(color: accent, width: 1.8),
                  boxShadow: LotusDecorations.glowShadow(accent,
                      intensity: 0.35, blur: 16),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icons/dsp_icon.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (BuildContext context, Object error,
                        StackTrace? stackTrace) {
                      return Center(
                        child: Icon(Icons.equalizer_rounded,
                            color: accent, size: 28),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Graphic Equalizer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        CircleAvatar(radius: 2.5, backgroundColor: accent),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '10-BAND INDEPENDENT HARMONIC ENGINE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 8.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                eqOn ? 'ON' : 'OFF',
                style: TextStyle(
                  color: eqOn ? accent : _theme.textSecondaryColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: eqOn,
                  activeThumbColor: accent,
                  activeTrackColor: accent.withValues(alpha: 0.35),
                  inactiveThumbColor: isWhitaniana
                      ? const Color(0xFF94A3B8)
                      : LotusColors.textSecondary,
                  inactiveTrackColor: isWhitaniana
                      ? const Color(0xFFCBD5E1)
                      : Colors.white12,
                  onChanged: (bool val) {
                    HapticFeedback.lightImpact();
                    _eqService.toggleEnabled(val);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFftSpectrumCard(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_playback, _eqService]),
      builder: (BuildContext context, _) {
        final bool isDspLive = _playback.isPlaying &&
            _playback.activeSong != null &&
            _eqService.isEnabled;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: containerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDspLive
                  ? accent.withValues(alpha: 0.45)
                  : _theme.cardBorderColor,
              width: 1.0,
            ),
            boxShadow: isDspLive
                ? LotusDecorations.glowShadow(accent,
                intensity: 0.16, blur: 16)
                : (isWhitaniana
                ? LotusDecorations.whitanianaCardShadow()
                : null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.graphic_eq_rounded,
                    color: isDspLive ? accent : _theme.textTertiaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'REALTIME HARMONIC SPECTRUM (FFT)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDspLive
                            ? _theme.textPrimaryColor
                            : _theme.textSecondaryColor,
                        fontSize: 10.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isDspLive
                          ? accent.withValues(alpha: 0.18)
                          : (isWhitaniana
                          ? _theme.containerHighColor
                          : Colors.white10),
                      borderRadius: BorderRadius.circular(6),
                      border: isDspLive
                          ? Border.all(
                          color: accent.withValues(alpha: 0.5), width: 0.8)
                          : null,
                    ),
                    child: Text(
                      isDspLive
                          ? 'HIGH PRECISION DSP'
                          : (!_eqService.isEnabled ? 'BYPASS' : 'STANDBY'),
                      style: TextStyle(
                        color: isDspLive ? accent : _theme.textSecondaryColor,
                        fontSize: 8.0,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _fftController,
                  builder: (BuildContext context, Widget? child) {
                    return CustomPaint(
                      size: const Size(double.infinity, 42),
                      painter: _FftSpectrumPainter(
                        progress: isDspLive ? _fftController.value : 0.0,
                        enabled: isDspLive,
                        accent: accent,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoodSanctuaryQuickBanner(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return ListenableBuilder(
      listenable: _eqService,
      builder: (BuildContext context, _) {
        final bool isMoodActive = _eqService.isMoodBioEngineActive;

        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            LotusMoodSanctuaryModal.show(
              context,
              isEngineActive: isMoodActive,
              onToggleEngine: (bool val) {
                _eqService.setMoodBioEngine(enabled: val);
              },
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isMoodActive
                  ? secondaryAccent.withValues(alpha: 0.18)
                  : containerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isMoodActive ? secondaryAccent : _theme.cardBorderColor,
                width: isMoodActive ? 1.4 : 0.8,
              ),
              boxShadow: isMoodActive
                  ? LotusDecorations.glowShadow(secondaryAccent,
                  intensity: 0.20, blur: 14)
                  : (isWhitaniana
                  ? LotusDecorations.whitanianaCardShadow()
                  : null),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: (isMoodActive
                        ? secondaryAccent
                        : _theme.textSecondaryColor.withValues(alpha: 0.2))
                        .withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isMoodActive
                          ? secondaryAccent.withValues(alpha: 0.6)
                          : Colors.transparent,
                      width: 1.0,
                    ),
                  ),
                  child: Image.asset(
                    'assets/icons/lotus_mood_icon.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.spa_rounded,
                      color: isMoodActive
                          ? secondaryAccent
                          : _theme.textSecondaryColor,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              'Solfeggio Mood Sanctuary',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _theme.textPrimaryColor,
                                fontSize: 12.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isMoodActive
                                  ? LotusColors.voltLime.withValues(alpha: 0.2)
                                  : (isWhitaniana
                                  ? _theme.containerHighColor
                                  : Colors.white10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isMoodActive ? '528Hz ACTIVE' : 'OPEN MODAL',
                              style: TextStyle(
                                color: isMoodActive
                                    ? LotusColors.voltLime
                                    : _theme.textTertiaryColor,
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Warm Harmonic Bell & Solfeggio Resonance',
                        style: TextStyle(
                          color: _theme.textSecondaryColor,
                          fontSize: 9.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: isMoodActive
                      ? secondaryAccent
                      : _theme.textTertiaryColor,
                  size: 13,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetsRow(Color accent, Color containerLow) {
    final List<String> presetNames =
    LotusEqualizerService.presets.keys.toList();
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return ListenableBuilder(
      listenable: _eqService,
      builder: (BuildContext context, _) {
        final String activePreset = _eqService.activePresetName;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  'GRAPHIC SOUND PRESETS',
                  style: TextStyle(
                    color: _theme.textSecondaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _applyPreset('Flat / Bit-Perfect'),
                  child: Text(
                    'Reset Flat',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: presetNames.map((String p) {
                  final bool isSelected = activePreset == p;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: GestureDetector(
                      onTap: () => _applyPreset(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isWhitaniana
                              ? accent
                              : _theme.containerHighColor)
                              : containerLow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? accent : _theme.cardBorderColor,
                            width: isSelected ? 1.4 : 0.8,
                          ),
                          boxShadow: isSelected
                              ? LotusDecorations.glowShadow(accent,
                              intensity: 0.22, blur: 10)
                              : (isWhitaniana
                              ? LotusDecorations.whitanianaCardShadow()
                              : null),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : _theme.textSecondaryColor,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTenBandSlidersCard(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return ListenableBuilder(
      listenable: _eqService,
      builder: (BuildContext context, _) {
        final List<double> gains = _eqService.bandGainsDb;
        final bool eqOn = _eqService.isEnabled;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 14.0),
          decoration: BoxDecoration(
            color: containerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: accent.withValues(alpha: 0.35), width: 1.0),
            boxShadow: isWhitaniana
                ? LotusDecorations.whitanianaCardShadow()
                : LotusDecorations.glowShadow(accent,
                intensity: 0.10, blur: 16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '10-BAND INDEPENDENT EQUALIZER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _theme.textPrimaryColor,
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      '±12 dB Precision',
                      style: TextStyle(
                        color: accent,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                child: SizedBox(
                  height: 190,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List<Widget>.generate(10, (int index) {
                      final double gain =
                      index < gains.length ? gains[index] : 0.0;
                      final String label = _bandFrequencies[index];
                      final Color bandColor =
                      _getBandColor(index, accent, secondaryAccent);

                      return Expanded(
                        child: Column(
                          children: <Widget>[
                            Text(
                              _formatGain(gain),
                              style: TextStyle(
                                color: bandColor,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.0,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5.0),
                                    overlayShape:
                                    const RoundSliderOverlayShape(
                                        overlayRadius: 8.0),
                                    activeTrackColor: bandColor,
                                    inactiveTrackColor: isWhitaniana
                                        ? const Color(0xFFCBD5E1)
                                        : Colors.white12,
                                    thumbColor: isWhitaniana
                                        ? bandColor
                                        : Colors.white,
                                  ),
                                  child: Slider(
                                    value: gain,
                                    min: -12.0,
                                    max: 12.0,
                                    onChanged: eqOn
                                        ? (double val) {
                                      _eqService.setBandGain(index, val);
                                    }
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: TextStyle(
                                color: _theme.textSecondaryColor,
                                fontSize: 8.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FftSpectrumPainter extends CustomPainter {
  final double progress;
  final bool enabled;
  final Color accent;

  static Size? _lastSize;
  static Color? _lastAccent;
  static bool? _lastEnabled;
  static Paint? _cachedEvenPaint;
  static Paint? _cachedOddPaint;

  const _FftSpectrumPainter({
    required this.progress,
    required this.enabled,
    required this.accent,
  });

  void _ensureShaders(Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (_cachedEvenPaint != null &&
        _lastSize == size &&
        _lastAccent == accent &&
        _lastEnabled == enabled) {
      return;
    }

    _lastSize = size;
    _lastAccent = accent;
    _lastEnabled = enabled;

    final Rect fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    final Shader evenShader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: enabled
          ? <Color>[accent, LotusColors.magentaNeon]
          : <Color>[
        LotusColors.textTertiary.withValues(alpha: 0.4),
        LotusColors.textTertiary.withValues(alpha: 0.6),
      ],
    ).createShader(fullRect);

    final Shader oddShader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: enabled
          ? <Color>[accent, LotusColors.purpleNeon]
          : <Color>[
        LotusColors.textTertiary.withValues(alpha: 0.4),
        LotusColors.textTertiary.withValues(alpha: 0.6),
      ],
    ).createShader(fullRect);

    _cachedEvenPaint = Paint()..shader = evenShader;
    _cachedOddPaint = Paint()..shader = oddShader;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _ensureShaders(size);

    final Paint evenPaint = _cachedEvenPaint ?? (Paint()..color = accent);
    final Paint oddPaint =
        _cachedOddPaint ?? (Paint()..color = LotusColors.purpleNeon);

    const int barCount = 28;
    final double barWidth = size.width / (barCount * 1.5);

    for (int i = 0; i < barCount; i++) {
      double heightRatio;
      if (!enabled || progress == 0.0) {
        heightRatio = 0.08;
      } else {
        final double wave = math.sin((progress * math.pi) + (i * 0.35)).abs();
        heightRatio = 0.2 + (0.8 * wave);
      }

      final double h = (size.height * heightRatio).clamp(3.0, size.height);
      final double left = i * (barWidth * 1.5);
      final double top = size.height - h;

      final RRect rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, h),
        const Radius.circular(2),
      );

      canvas.drawRRect(rect, i % 2 == 0 ? evenPaint : oddPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FftSpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.enabled != enabled ||
        oldDelegate.accent != accent;
  }
}