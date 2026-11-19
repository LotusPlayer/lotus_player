import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/lotus_equalizer_service.dart';
import '../../core/theme/lotus_theme.dart';

class LotusMoodSanctuaryModal extends StatefulWidget {
  final bool isEngineActive;
  final ValueChanged<bool> onToggleEngine;

  const LotusMoodSanctuaryModal({
    super.key,
    required this.isEngineActive,
    required this.onToggleEngine,
  });

  static void show(
      BuildContext context, {
        required bool isEngineActive,
        required ValueChanged<bool> onToggleEngine,
      }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (BuildContext ctx) => LotusMoodSanctuaryModal(
        isEngineActive: isEngineActive,
        onToggleEngine: onToggleEngine,
      ),
    );
  }

  @override
  State<LotusMoodSanctuaryModal> createState() =>
      _LotusMoodSanctuaryModalState();
}

class _LotusMoodSanctuaryModalState extends State<LotusMoodSanctuaryModal> {
  final LotusThemeController _theme = LotusThemeController.instance;
  final LotusEqualizerService _eqService = LotusEqualizerService.instance;

  static const String _kMoodPresetIndexKey = 'lotus_mood_preset_index';

  late bool _engineEnabled;
  int _selectedPresetIndex = 1; // Creative Flow (Theta 6.0 Hz)
  double _toneBlend = 0.35;
  double _isochronicDepth = 0.35;
  double _noiseMask = 0.20;

  Timer? _sliderThrottler;
  Timer? _diskSaveDebounce;
  bool _isDisposing = false;

  final List<Map<String, String>> _presets = const <Map<String, String>>[
    <String, String>{'title': 'Deep Sleep', 'freq': 'Delta 1.5Hz', 'icon': '🌙'},
    <String, String>{'title': 'Creative Flow', 'freq': 'Theta 6.0Hz', 'icon': '✨'},
    <String, String>{'title': 'Hyper Focus', 'freq': 'Alpha 10.0Hz', 'icon': '⚡'},
  ];

  @override
  void initState() {
    super.initState();
    _engineEnabled = widget.isEngineActive || _eqService.isMoodBioEngineActive;
    _toneBlend = _eqService.moodToneBlend;
    _isochronicDepth = _eqService.moodIsochronicDepth;
    _noiseMask = _eqService.moodNoiseMask;
    _eqService.addListener(_onEqServiceChanged);
    _loadPresetIndex();
  }

  @override
  void didUpdateWidget(covariant LotusMoodSanctuaryModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isEngineActive != widget.isEngineActive &&
        widget.isEngineActive != _engineEnabled) {
      setState(() {
        _engineEnabled = widget.isEngineActive;
      });
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _sliderThrottler?.cancel();
    _diskSaveDebounce?.cancel();
    _eqService.removeListener(_onEqServiceChanged);
    super.dispose();
  }

  void _onEqServiceChanged() {
    if (!mounted || _isDisposing) return;
    setState(() {
      _engineEnabled = _eqService.isMoodBioEngineActive;
      _toneBlend = _eqService.moodToneBlend;
      _isochronicDepth = _eqService.moodIsochronicDepth;
      _noiseMask = _eqService.moodNoiseMask;
    });
  }

  Future<void> _loadPresetIndex() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted || _isDisposing) return;
      setState(() {
        _selectedPresetIndex = prefs.getInt(_kMoodPresetIndexKey) ?? 1;
      });
    } catch (_) {}
  }

  double _pulseForIndex(int i) =>
      i == 0 ? 1.5 : (i == 1 ? 6.0 : (i == 2 ? 10.0 : 6.0));

  Future<void> _handleToggleEngine(bool val) async {
    HapticFeedback.heavyImpact();
    setState(() => _engineEnabled = val);
    widget.onToggleEngine(val);

    if (val) {
      await _theme.activateMoodMatrixTheme();
    } else {
      await _theme.deactivateMoodMatrixTheme();
    }

    await _eqService.setMoodBioEngine(
      enabled: val,
      toneBlend: _toneBlend,
      isochronicDepth: _isochronicDepth,
      noiseMask: _noiseMask,
      pulseFrequency: _pulseForIndex(_selectedPresetIndex),
    );
  }

  Future<void> _setPreset(int index) async {
    HapticFeedback.selectionClick();
    double freq = 6.0;
    setState(() {
      _selectedPresetIndex = index;
      if (index == 0) {
        // Deep Sleep: lower carrier, deeper breathing tremolo, warm ocean noise
        _toneBlend = 0.25;
        _isochronicDepth = 0.45;
        _noiseMask = 0.25;
        freq = 1.5;
      } else if (index == 1) {
        // Creative Flow: balanced harmonic pad & surf
        _toneBlend = 0.35;
        _isochronicDepth = 0.35;
        _noiseMask = 0.20;
        freq = 6.0;
      } else {
        // Hyper Focus: clear 10Hz cognitive pulse & gentle masking
        _toneBlend = 0.40;
        _isochronicDepth = 0.30;
        _noiseMask = 0.15;
        freq = 10.0;
      }
    });

    if (_engineEnabled) {
      await _eqService.setMoodBioEngine(
        enabled: true,
        toneBlend: _toneBlend,
        isochronicDepth: _isochronicDepth,
        noiseMask: _noiseMask,
        pulseFrequency: freq,
      );
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kMoodPresetIndexKey, index);
    } catch (_) {}
  }

  void _onSliderChanged({
    double? toneBlend,
    double? isochronicDepth,
    double? noiseMask,
  }) {
    setState(() {
      _selectedPresetIndex = -1;
      if (toneBlend != null) _toneBlend = toneBlend;
      if (isochronicDepth != null) _isochronicDepth = isochronicDepth;
      if (noiseMask != null) _noiseMask = noiseMask;
    });

    if (!_engineEnabled) return;

    _sliderThrottler?.cancel();
    _sliderThrottler = Timer(const Duration(milliseconds: 30), () async {
      if (_isDisposing) return;
      await _eqService.setMoodBioEngine(
        enabled: true,
        toneBlend: _toneBlend,
        isochronicDepth: _isochronicDepth,
        noiseMask: _noiseMask,
        pulseFrequency: _pulseForIndex(_selectedPresetIndex),
      );
    });

    _diskSaveDebounce?.cancel();
    _diskSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kMoodPresetIndexKey, -1);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext ctx, _) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final bool isWhitaniana = _theme.isWhitanianaActive;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;
        final Color textPrimary = _theme.textPrimaryColor;
        final Color textSecondary = _theme.textSecondaryColor;

        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: modalShieldSurface,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                color: isWhitaniana
                    ? _theme.cardBorderColor
                    : (_engineEnabled
                    ? secondaryAccent.withValues(alpha: 0.85)
                    : accent.withValues(alpha: 0.85)),
                width: 1.6,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: isWhitaniana ? 0.15 : 0.85),
                  blurRadius: 36,
                  spreadRadius: 8,
                  offset: const Offset(0, -6),
                ),
                if (_engineEnabled) ...<BoxShadow>[
                  BoxShadow(
                    color: secondaryAccent.withValues(
                        alpha: isWhitaniana ? 0.22 : 0.32),
                    blurRadius: 36,
                    spreadRadius: 2,
                    offset: const Offset(0, -6),
                  ),
                ] else ...<BoxShadow>[
                  ...LotusDecorations.glowShadow(accent,
                      intensity: 0.25, blur: 24),
                ],
              ],
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isWhitaniana
                            ? LotusColors.whitanianaCardBorder
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      // Custom Lotus Mood Brand Icon Asset
                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_engineEnabled
                              ? secondaryAccent
                              : (isWhitaniana
                              ? _theme.containerHighColor
                              : Colors.white24))
                              .withValues(alpha: 0.18),
                          border: Border.all(
                            color: _engineEnabled
                                ? secondaryAccent.withValues(alpha: 0.6)
                                : (isWhitaniana
                                ? _theme.cardBorderColor
                                : Colors.white24),
                          ),
                        ),
                        child: Image.asset(
                          'assets/icons/lotus_mood_icon.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.spa_rounded,
                            color: _engineEnabled
                                ? secondaryAccent
                                : textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    'Solfeggio Bio-Mixer',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _engineEnabled
                                        ? LotusColors.voltLime
                                        .withValues(alpha: 0.2)
                                        : (isWhitaniana
                                        ? _theme.containerHighColor
                                        : Colors.white10),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    _engineEnabled ? 'ACTIVE 528HZ' : 'BYPASS',
                                    style: TextStyle(
                                      color: _engineEnabled
                                          ? LotusColors.voltLime
                                          : _theme.textTertiaryColor,
                                      fontSize: 8.0,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'CIRCADIAN SYNCHRONIZER • NON-DESTRUCTIVE DSP',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Transform.scale(
                        scale: 0.88,
                        child: Switch(
                          value: _engineEnabled,
                          activeThumbColor: secondaryAccent,
                          activeTrackColor:
                          secondaryAccent.withValues(alpha: 0.4),
                          inactiveThumbColor: isWhitaniana
                              ? const Color(0xFF94A3B8)
                              : LotusColors.textSecondary,
                          inactiveTrackColor: isWhitaniana
                              ? const Color(0xFFCBD5E1)
                              : Colors.white12,
                          onChanged: (bool val) => _handleToggleEngine(val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BRAINWAVE TARGET FREQUENCY',
                    style: TextStyle(
                      color: _theme.textTertiaryColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List<Widget>.generate(_presets.length, (int i) {
                      final bool isSel = _selectedPresetIndex == i;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _setPreset(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                            padding: const EdgeInsets.symmetric(
                                vertical: 11, horizontal: 6),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? secondaryAccent.withValues(alpha: 0.22)
                                  : modalContainerLow,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isSel
                                    ? secondaryAccent
                                    : _theme.cardBorderColor,
                                width: isSel ? 1.5 : 0.8,
                              ),
                              boxShadow: isSel
                                  ? LotusDecorations.glowShadow(
                                  secondaryAccent,
                                  intensity: 0.24,
                                  blur: 12)
                                  : (isWhitaniana
                                  ? LotusDecorations.whitanianaCardShadow()
                                  : null),
                            ),
                            child: Column(
                              children: <Widget>[
                                Text(_presets[i]['icon']!,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(height: 4),
                                Text(
                                  _presets[i]['title']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isSel
                                        ? (isWhitaniana
                                        ? secondaryAccent
                                        : Colors.white)
                                        : textSecondary,
                                    fontSize: 11,
                                    fontWeight: isSel
                                        ? FontWeight.w900
                                        : FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  _presets[i]['freq']!,
                                  style: TextStyle(
                                    color: isSel
                                        ? secondaryAccent
                                        : _theme.textTertiaryColor,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  _buildSliderRow(
                    'Solfeggio Tone Blend (528Hz Miracle)',
                    _toneBlend,
                    accent,
                    textPrimary,
                    isWhitaniana,
                        (double v) => _onSliderChanged(toneBlend: v),
                  ),
                  const SizedBox(height: 12),
                  _buildSliderRow(
                    'Binaural Isochronic Depth',
                    _isochronicDepth,
                    secondaryAccent,
                    textPrimary,
                    isWhitaniana,
                        (double v) => _onSliderChanged(isochronicDepth: v),
                  ),
                  const SizedBox(height: 12),
                  _buildSliderRow(
                    'Pink & Brown Noise Mask',
                    _noiseMask,
                    LotusColors.solarGold,
                    textPrimary,
                    isWhitaniana,
                        (double v) => _onSliderChanged(noiseMask: v),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _engineEnabled
                          ? secondaryAccent
                          : (isWhitaniana
                          ? _theme.containerColor
                          : _theme.modalContainerHighColor),
                      foregroundColor: _engineEnabled
                          ? Colors.white
                          : (isWhitaniana
                              ? _theme.textPrimaryColor
                              : Colors.white70),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: _engineEnabled ? 4 : 0,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      _engineEnabled
                          ? 'KEEP ENGINE ACTIVE • BLOOM'
                          : 'CLOSE SANCTUARY',
                      style: TextStyle(
                        color: _engineEnabled
                            ? Colors.white
                            : (isWhitaniana
                            ? _theme.textPrimaryColor
                            : Colors.white70),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSliderRow(
      String label,
      double value,
      Color color,
      Color textPrimary,
      bool isWhitaniana,
      ValueChanged<double> onChanged,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
            activeTrackColor: color,
            inactiveTrackColor:
            isWhitaniana ? const Color(0xFFCBD5E1) : Colors.white12,
            thumbColor: isWhitaniana ? color : Colors.white,
          ),
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            onChanged: _engineEnabled ? onChanged : null,
          ),
        ),
      ],
    );
  }
}