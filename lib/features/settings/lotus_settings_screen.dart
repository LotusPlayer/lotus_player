// ==============================================================================
// LOTUS PLAYER - SETTINGS SCREEN (CLEANED & STREAMLINED MASTER)
// Features: Dynamic Whitaniana Contrast, AMOLED Pure Black Mode,
// Petal Spectral Theme Engine, Telemetry & Factory Reset
// File: lib/features/settings/lotus_settings_screen.dart
// ==============================================================================

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/lotus_equalizer_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_widgets.dart';

class LotusSettingsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const LotusSettingsScreen({
    super.key,
    this.onBack,
  });

  @override
  State<LotusSettingsScreen> createState() => _LotusSettingsScreenState();
}

class _LotusSettingsScreenState extends State<LotusSettingsScreen> {
  final LotusThemeController _theme = LotusThemeController.instance;
  final LotusEqualizerService _eqService = LotusEqualizerService.instance;

  SharedPreferences? _cachedPrefs;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onStateDependencyChanged);
    _eqService.addListener(_onStateDependencyChanged);
  }

  @override
  void dispose() {
    _theme.removeListener(_onStateDependencyChanged);
    _eqService.removeListener(_onStateDependencyChanged);
    super.dispose();
  }

  void _onStateDependencyChanged() {
    if (mounted) setState(() {});
  }

  Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  void _handleThemeSelected(String themeId) {
    HapticFeedback.mediumImpact();
    _theme.setThemePreset(themeId);
  }

  Future<void> _resetToDefaults() async {
    HapticFeedback.heavyImpact();
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: _theme.modalSurfaceColor,
        clipBehavior: Clip.antiAlias,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
              color: _theme.secondaryAccent.withValues(alpha: 0.85),
              width: 1.4),
        ),
        title: Row(
          children: <Widget>[
            Icon(Icons.restore_rounded,
                color: _theme.secondaryAccent, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reset All Settings?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Revert themes and equalizer preferences back to factory defaults?',
          style: TextStyle(color: textSecondary, fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCEL',
              style: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _theme.secondaryAccent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'RESET',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.clear();

      await _eqService.resetToFlat();
      _theme.setAmoledMode(true);
      _theme.setThemePreset('cyber_bloom');

      if (mounted) {
        LotusSnackBar.show(
          context,
          message: 'All settings restored to factory defaults.',
          icon: Icons.check_circle_rounded,
          iconColor: _theme.secondaryAccent,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
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
                    padding:
                    const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 140.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildAmoledBlackCard(accent, containerLow),
                        const SizedBox(height: 12),
                        _buildPetalThemesCard(
                            accent, secondaryAccent, containerLow),
                        const SizedBox(height: 12),
                        _buildAboutAndBuildTelemetryCard(accent, containerLow),
                        const SizedBox(height: 14),
                        _buildResetButton(secondaryAccent, containerLow),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          bottom: BorderSide(
              color: isWhitaniana
                  ? _theme.cardBorderColor
                  : accent.withValues(alpha: 0.2),
              width: 0.8),
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
                'assets/icons/settings_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) {
                  return Center(
                    child: Icon(Icons.settings_rounded,
                        color: accent, size: 26),
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
                  'Settings',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: <Widget>[
                    CircleAvatar(radius: 2.5, backgroundColor: accent),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'THEMES & VISUAL CUSTOMIZATION',
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
        ],
      ),
    );
  }

  Widget _buildAmoledBlackCard(Color accent, Color containerLow) {
    final bool isAmoled = _theme.isAmoled;
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAmoled
              ? accent.withValues(alpha: 0.6)
              : _theme.cardBorderColor,
          width: isAmoled ? 1.2 : 0.8,
        ),
        boxShadow: isAmoled
            ? LotusDecorations.glowShadow(accent, intensity: 0.16, blur: 14)
            : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.brightness_2_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'AMOLED Pure Black Mode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '0.000 Nits • Active Diode Offload',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: isAmoled,
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
                _theme.setAmoledMode(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetalThemesCard(
      Color accent, Color secondaryAccent, Color containerLow) {
    final List<LotusThemeOption> presets = LotusDecorations.themePresets;
    final String activeId = _theme.selectedThemeId;
    final String activeThemeName = _theme.currentThemeOption.name;
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isWhitaniana
                ? _theme.cardBorderColor
                : accent.withValues(alpha: 0.4),
            width: 1.0),
        boxShadow: isWhitaniana
            ? LotusDecorations.whitanianaCardShadow()
            : LotusDecorations.glowShadow(accent, intensity: 0.12, blur: 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.palette_rounded, color: accent, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PETAL SPECTRAL THEMES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(
                  activeThemeName.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 8.0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(Icons.swipe_rounded,
                  color: _theme.textTertiaryColor, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Swipe left or right to explore all signature petals',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 10.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            child: SizedBox(
              height: 116,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: presets.length,
                itemBuilder: (BuildContext context, int index) {
                  final LotusThemeOption option = presets[index];
                  final bool isSelected = option.id == activeId;
                  return _buildThemePickerCard(option, isSelected, accent);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isWhitaniana
                  ? _theme.containerColor
                  : _theme.containerLowestColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_theme.currentThemeOption.name} • ${_theme.currentThemeOption.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 10.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'INSTANT PERSIST',
                  style: TextStyle(
                    color: LotusColors.voltLime,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemePickerCard(
      LotusThemeOption option, bool isSelected, Color accent) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return GestureDetector(
      onTap: () => _handleThemeSelected(option.id),
      child: Container(
        width: 96,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isWhitaniana ? _theme.containerColor : _theme.containerHighColor)
              : (isWhitaniana ? _theme.surfaceColor : _theme.containerLowestColor),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? option.primaryColor : _theme.cardBorderColor,
            width: isSelected ? 1.8 : 0.8,
          ),
          boxShadow: isSelected
              ? LotusDecorations.glowShadow(
            option.primaryColor,
            intensity: 0.28,
            blur: 12,
          )
              : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: option.gradient,
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? _theme.textPrimaryColor
                      : _theme.textSecondaryColor,
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutAndBuildTelemetryCard(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _theme.cardBorderColor),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded,
                  color: _theme.textSecondaryColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LOTUS PLAYER AUDIOPHILE ARCHITECTURE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _theme.textPrimaryColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildTelemetryLine(
            'DSP Hardware', 'Android Media3 Service',),
          _buildTelemetryLine(
            'Equalization Core', '10-Band Graphic EQ',),
          _buildTelemetryLine(
            'Audio Engine', 'Bit-Perfect 384 kHz',),
          _buildTelemetryLine(
            'Build Architecture', 'Rise & Bloom v3.2.0',),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Developed By Souljalazian',
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: <Widget>[
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              '$label: ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _theme.textSecondaryColor,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _theme.textPrimaryColor,
                fontSize: 10.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton(Color secondaryAccent, Color containerLow) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: secondaryAccent,
        side: BorderSide(color: secondaryAccent.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: _resetToDefaults,
      icon: const Icon(Icons.restore_rounded, size: 18),
      label: const Text(
        'RESET ALL SETTINGS TO DEFAULTS',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
      ),
    );
  }
}