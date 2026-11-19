import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data model representing a selectable theme accent (Solid or Gradient)
class LotusThemeOption {
  final String id;
  final String name;
  final String subtitle;
  final Color primaryColor;
  final Color secondaryColor;
  final LinearGradient gradient;
  final List<Color> previewColors;

  const LotusThemeOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gradient,
    required this.previewColors,
  });
}

/// Static color tokens, surface hierarchy, and brand anchors (Pure Const)
class LotusColors {
  // Pure AMOLED Black Tier (0.000 Nits True Diode Offload)
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF07090E);
  static const Color amoledSurfaceContainerLowest = Color(0xFF040609);
  static const Color amoledSurfaceContainerLow = Color(0xFF0D111A);
  static const Color amoledSurfaceContainer = Color(0xFF131824);
  static const Color amoledSurfaceContainerHigh = Color(0xFF1C2232);
  static const Color amoledSurfaceContainerHighest = Color(0xFF262D42);

  // Surface Hierarchy (Standard Obsidian & Carbon Tiers)
  static const Color background = Color(0xFF080B11);
  static const Color backgroundDim = Color(0xFF05070B);
  static const Color surface = Color(0xFF10141D);
  static const Color surfaceContainerLowest = Color(0xFF0C0F17);
  static const Color surfaceContainerLow = Color(0xFF151A26);
  static const Color surfaceContainer = Color(0xFF1B2232);
  static const Color surfaceContainerHigh = Color(0xFF242C3F);
  static const Color surfaceContainerHighest = Color(0xFF2E384F);

  // ============================================================================
  // ★ WHITANIANA SIGNATURE TOKENS: PURE CONTRAST & VISIBLE CARD SURFACES ★
  // Substrate is subtle pale porcelain gray-white (#F5F7FB) so pure white (#FFFFFF)
  // cards pop out with crystal clarity!
  // ============================================================================
  static const Color whitanianaPureWhite = Color(0xFFF5F7FB);     // Soft porcelain background
  static const Color whitanianaPureWhiteDim = Color(0xFFE9EEF5);  // Dimmed base
  static const Color whitanianaPureWhiteCard = Color(0xFFFFFFFF); // Pure white cards

  // Visible Card Containers in Whitaniana
  static const Color whitanianaCardLow = Color(0xFFFFFFFF);       // Cards pop off background
  static const Color whitanianaCardContainer = Color(0xFFEEF2F7); // Search bars, input tiles
  static const Color whitanianaCardHigh = Color(0xFFE1E7F0);      // Elevated containers
  static const Color whitanianaCardBorder = Color(0xFFCBD5E1);    // Crisp visible border outline

  // High-Contrast Light Theme Typography (Strictly deep obsidian & slate)
  static const Color whitanianaTextPrimary = Color(0xFF0B101D);   // High-contrast obsidian
  static const Color whitanianaTextSecondary = Color(0xFF334155); // Rich slate charcoal
  static const Color whitanianaTextTertiary = Color(0xFF64748B);  // Polished slate
  static const Color whitanianaTextMuted = Color(0xFF94A3B8);     // Muted caption slate

  // Whitaniana Pure White Bottom Nav Bar
  static const Color whitanianaBottomBarBg = Color(0xFFFFFFFF);
  static const Color whitanianaBottomBarBorder = Color(0xFFCBD5E1);

  // Smoked Obsidian Glass (For floating player deck & modals)
  static const Color whitanianaSmokedGlassBase = Color(0xFF0E1217);
  static const Color whitanianaSmokedGlassSurface = Color(0xE00E1217);
  static const Color whitanianaSmokedGlassLowest = Color(0xFFFFFFFF);
  static const Color whitanianaSmokedGlassLow = Color(0xFFFFFFFF);
  static const Color whitanianaSmokedGlassContainer = Color(0xFFF1F5F9);
  static const Color whitanianaSmokedGlassHigh = Color(0xFFE2E8F0);
  static const Color whitanianaSmokedGlassHighest = Color(0xFFCBD5E1);

  // Whitaniana Spectral & Acoustic Accents
  static const Color whitanianaCyanAccent = Color(0xFF0284C7);   // High-contrast vibrant Cyan-Blue (WCAG AAA)
  static const Color whitanianaEmeraldAccent = Color(0xFF059669);// High-contrast Acoustic Verdi Emerald
  static const Color whitanianaChromeBorder = Color(0x400284C7);  // Luster precision bevel rim

  // Neon Electric Brand Accents
  static const Color cyanNeon = Color(0xFF00F2FE);
  static const Color magentaNeon = Color(0xFFFF2A8D);
  static const Color purpleNeon = Color(0xFF8A2BE2);
  static const Color solarGold = Color(0xFFFFB300);
  static const Color voltLime = Color(0xFF00E676);
  static const Color electricViolet = Color(0xFF7928CA);
  static const Color hyperAmber = Color(0xFFFF7A00);
  static const Color radiantCoral = Color(0xFFFF416C);
  static const Color galacticTeal = Color(0xFF00C9FF);
  static const Color auroraPink = Color(0xFFF72585);
  static const Color deepUltraviolet = Color(0xFF5B00FF);
  static const Color springEmerald = Color(0xFF10B981);

  // Starry Night Signature Spectral Palette
  static const Color starryNeonPurple = Color(0xFFC084FC);
  static const Color starryUltraviolet = Color(0xFF9333EA);
  static const Color starryCyanStardust = Color(0xFF38BDF8);
  static const Color starryCosmicMagenta = Color(0xFFE879F9);
  static const Color starryAmberGold = Color(0xFFFBBF24);

  // Audiophile Quality Signal Accents
  static const Color flacCyan = Color(0xFF00F2FE);
  static const Color dsdMagenta = Color(0xFFFF2A8D);
  static const Color pcmGold = Color(0xFFFFB300);

  // Default Dark Mode Typography & Text Contrasts
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF475569);

  // Translucent Glass & Neon Glow Borders
  static const Color glassBorder = Color(0x1AFFFFFF);
  static const Color glassBorderGlow = Color(0x33FF2A8D);
  static const Color glassBorderCyan = Color(0x3300F2FE);
  static const Color glassBorderGold = Color(0x33FFB300);
  static const Color glassBorderViolet = Color(0x337928CA);
  static const Color glassBorderLime = Color(0x3300E676);

  // Translucent Glassmorphic Surface Tiers
  static const Color matrixGlassSurface = Color(0x3307090E);
  static const Color matrixGlassLowest = Color(0x1A040609);
  static const Color matrixGlassLow = Color(0x2B0D111A);
  static const Color matrixGlassContainer = Color(0x3D131824);
  static const Color matrixGlassHigh = Color(0x521C2232);
  static const Color matrixGlassHighest = Color(0x66262D42);

  // Starry Night Celestial Void Tiers
  static const Color starryVoidBg = Color(0xFF040209);
  static const Color starryGlassSurface = Color(0x33120A24);
  static const Color starryGlassLowest = Color(0x1A0B0616);
  static const Color starryGlassLow = Color(0x24180E30);
  static const Color starryGlassContainer = Color(0x381E113C);
  static const Color starryGlassHigh = Color(0x4D241246);
  static const Color starryGlassHighest = Color(0x662E1758);

  // Solid AMOLED Shield Tiers
  static const Color modalShieldBackground = Color(0xFF05070B);
  static const Color modalShieldSurface = Color(0xFF0A0E17);
  static const Color modalShieldContainerLow = Color(0xFF111724);
  static const Color modalShieldContainer = Color(0xFF172030);
  static const Color modalShieldContainerHigh = Color(0xFF1E283D);
  static const Color modalShieldBorder = Color(0x3D00F2FE);
}

/// Constant Gradients, Shadows, and Dynamic Styles
class LotusDecorations {
  static const LinearGradient primaryPillGradient = LinearGradient(
    colors: <Color>[LotusColors.cyanNeon, LotusColors.magentaNeon],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient starryNightGradient = LinearGradient(
    colors: <Color>[
      LotusColors.starryNeonPurple,
      LotusColors.starryUltraviolet,
      LotusColors.starryCyanStardust,
      LotusColors.starryCosmicMagenta,
      LotusColors.starryNeonPurple,
    ],
    stops: <double>[0.0, 0.25, 0.55, 0.85, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Whitaniana Cyan & Emerald High-Definition Gradient
  static const LinearGradient whitanianaGradient = LinearGradient(
    colors: <Color>[
      Color(0xFF0284C7),
      Color(0xFF0EA5E9),
      LotusColors.whitanianaEmeraldAccent,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient solarFlareGradient = LinearGradient(
    colors: <Color>[LotusColors.solarGold, LotusColors.hyperAmber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient petalDreamGradient = LinearGradient(
    colors: <Color>[LotusColors.electricViolet, LotusColors.auroraPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient galacticOceanGradient = LinearGradient(
    colors: <Color>[LotusColors.galacticTeal, LotusColors.cyanNeon],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient lotusSunsetGradient = LinearGradient(
    colors: <Color>[LotusColors.radiantCoral, LotusColors.solarGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bioLuminescenceGradient = LinearGradient(
    colors: <Color>[LotusColors.voltLime, LotusColors.cyanNeon],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient cosmicVoidGradient = LinearGradient(
    colors: <Color>[LotusColors.deepUltraviolet, LotusColors.magentaNeon],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient lotusMoodMatrixGradient = LinearGradient(
    colors: <Color>[
      LotusColors.cyanNeon,
      LotusColors.electricViolet,
      LotusColors.magentaNeon,
      LotusColors.solarGold,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroCardGradient = LinearGradient(
    colors: <Color>[Color(0xFF1E142B), Color(0xFF0D1625)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scrubberGradient = LinearGradient(
    colors: <Color>[
      LotusColors.cyanNeon,
      LotusColors.magentaNeon,
      LotusColors.solarGold,
      Colors.white12,
    ],
    stops: <double>[0.0, 0.45, 0.65, 0.65],
  );

  static LinearGradient scrubberGradientWithAccent(Color accent) {
    return LinearGradient(
      colors: <Color>[
        accent,
        LotusColors.magentaNeon,
        LotusColors.solarGold,
        Colors.white12,
      ],
      stops: const <double>[0.0, 0.45, 0.65, 0.65],
    );
  }

  static List<BoxShadow> glowShadow(
      Color color, {
        double intensity = 0.3,
        double blur = 20.0,
      }) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: intensity),
        blurRadius: blur,
        spreadRadius: 1.5,
      ),
    ];
  }

  /// Contact shadow for visible porcelain Whitaniana cards
  static List<BoxShadow> whitanianaCardShadow() {
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFF0E141B).withValues(alpha: 0.06),
        blurRadius: 10,
        offset: const Offset(0, 3),
        spreadRadius: 1,
      ),
      BoxShadow(
        color: const Color(0xFF0E141B).withValues(alpha: 0.03),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// Preset Master Registry
  static const List<LotusThemeOption> themePresets = <LotusThemeOption>[
    LotusThemeOption(
      id: 'cyber_bloom',
      name: 'Cyber Bloom',
      subtitle: 'Cyan to Magenta Signature',
      primaryColor: LotusColors.cyanNeon,
      secondaryColor: LotusColors.magentaNeon,
      gradient: primaryPillGradient,
      previewColors: <Color>[LotusColors.cyanNeon, LotusColors.magentaNeon],
    ),
    LotusThemeOption(
      id: 'whitaniana',
      name: 'Whitaniana',
      subtitle: 'Pure White Ground & Crisp Obsidian',
      primaryColor: LotusColors.whitanianaCyanAccent,
      secondaryColor: LotusColors.whitanianaEmeraldAccent,
      gradient: whitanianaGradient,
      previewColors: <Color>[
        LotusColors.whitanianaPureWhite,
        LotusColors.whitanianaTextPrimary,
        LotusColors.whitanianaCyanAccent,
        LotusColors.whitanianaEmeraldAccent,
      ],
    ),
    LotusThemeOption(
      id: 'starry_night',
      name: 'Starry Night',
      subtitle: 'Celestial Thinking Horizon & Stardust',
      primaryColor: LotusColors.starryNeonPurple,
      secondaryColor: LotusColors.starryUltraviolet,
      gradient: starryNightGradient,
      previewColors: <Color>[
        LotusColors.starryNeonPurple,
        LotusColors.starryUltraviolet,
        LotusColors.starryCyanStardust,
        LotusColors.starryCosmicMagenta,
      ],
    ),
    LotusThemeOption(
      id: 'lotus_mood_matrix',
      name: 'Lotus Mood',
      subtitle: 'Harmonic Gradient Semi-Dots',
      primaryColor: LotusColors.cyanNeon,
      secondaryColor: LotusColors.electricViolet,
      gradient: lotusMoodMatrixGradient,
      previewColors: <Color>[
        LotusColors.cyanNeon,
        LotusColors.electricViolet,
        LotusColors.magentaNeon,
        LotusColors.solarGold,
      ],
    ),
    LotusThemeOption(
      id: 'cyan_neon',
      name: 'Cyan Neon',
      subtitle: 'Electric ALSA Direct Bus',
      primaryColor: LotusColors.cyanNeon,
      secondaryColor: Color(0xFF00B4D8),
      gradient: LinearGradient(
        colors: <Color>[LotusColors.cyanNeon, Color(0xFF0096C7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      previewColors: <Color>[LotusColors.cyanNeon, Color(0xFF0096C7)],
    ),
    LotusThemeOption(
      id: 'magenta_neon',
      name: 'Neon Magenta',
      subtitle: 'Lotus Petal Sanctuary',
      primaryColor: LotusColors.magentaNeon,
      secondaryColor: Color(0xFFC2185B),
      gradient: LinearGradient(
        colors: <Color>[LotusColors.magentaNeon, Color(0xFF9C27B0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      previewColors: <Color>[LotusColors.magentaNeon, Color(0xFF9C27B0)],
    ),
    LotusThemeOption(
      id: 'petal_dream',
      name: 'Petal Dream',
      subtitle: 'Electric Violet to Pink',
      primaryColor: LotusColors.electricViolet,
      secondaryColor: LotusColors.auroraPink,
      gradient: petalDreamGradient,
      previewColors: <Color>[LotusColors.electricViolet, LotusColors.auroraPink],
    ),
    LotusThemeOption(
      id: 'solar_flare',
      name: 'Solar Flare',
      subtitle: 'Solar Gold to Amber DSD',
      primaryColor: LotusColors.solarGold,
      secondaryColor: LotusColors.hyperAmber,
      gradient: solarFlareGradient,
      previewColors: <Color>[LotusColors.solarGold, LotusColors.hyperAmber],
    ),
    LotusThemeOption(
      id: 'galactic_ocean',
      name: 'Galactic Ocean',
      subtitle: 'Deep Teal to Oceanic Cyan',
      primaryColor: LotusColors.galacticTeal,
      secondaryColor: LotusColors.cyanNeon,
      gradient: galacticOceanGradient,
      previewColors: <Color>[LotusColors.galacticTeal, LotusColors.cyanNeon],
    ),
    LotusThemeOption(
      id: 'lotus_sunset',
      name: 'Lotus Sunset',
      subtitle: 'Radiant Coral to Gold',
      primaryColor: LotusColors.radiantCoral,
      secondaryColor: LotusColors.solarGold,
      gradient: lotusSunsetGradient,
      previewColors: <Color>[LotusColors.radiantCoral, LotusColors.solarGold],
    ),
    LotusThemeOption(
      id: 'bio_luminescence',
      name: 'Bio Luminescence',
      subtitle: 'Volt Lime to Aqua Cyan',
      primaryColor: LotusColors.voltLime,
      secondaryColor: LotusColors.cyanNeon,
      gradient: bioLuminescenceGradient,
      previewColors: <Color>[LotusColors.voltLime, LotusColors.cyanNeon],
    ),
    LotusThemeOption(
      id: 'cosmic_void',
      name: 'Cosmic Void',
      subtitle: 'Deep Ultraviolet to Magenta',
      primaryColor: LotusColors.deepUltraviolet,
      secondaryColor: LotusColors.magentaNeon,
      gradient: cosmicVoidGradient,
      previewColors: <Color>[
        LotusColors.deepUltraviolet,
        LotusColors.magentaNeon,
      ],
    ),
  ];
}

// ==============================================================================
// GLOBAL REACTIVE THEME CONTROLLER & CACHED ENGINE
// ==============================================================================
class LotusThemeController extends ChangeNotifier {
  static final LotusThemeController instance = LotusThemeController._();

  LotusThemeController._() {
    _hydratePreferences();
  }

  static const String _kSelectedThemeKey = 'lotus_theme_selected_id';
  static const String _kIsAmoledKey = 'lotus_theme_is_amoled';
  static const String _kPreviousThemeBeforeMoodKey =
      'lotus_theme_previous_before_mood';

  bool _isAmoled = true;
  String _selectedThemeId = 'cyber_bloom';
  String? _previousThemeBeforeMood;
  ThemeData? _cachedThemeData;

  bool get isAmoled => _isAmoled;
  String get selectedThemeId => _selectedThemeId;

  bool get isMoodMatrixActive => _selectedThemeId == 'lotus_mood_matrix';
  bool get isStarryNightActive => _selectedThemeId == 'starry_night';
  bool get isWhitanianaActive => _selectedThemeId == 'whitaniana';
  bool get isTransparentPassThrough => isMoodMatrixActive || isStarryNightActive;

  LotusThemeOption get currentThemeOption {
    return LotusDecorations.themePresets.firstWhere(
          (LotusThemeOption t) => t.id == _selectedThemeId,
      orElse: () => LotusDecorations.themePresets.first,
    );
  }

  Color get primaryAccent => currentThemeOption.primaryColor;
  Color get secondaryAccent => currentThemeOption.secondaryColor;
  LinearGradient get activeGradient => currentThemeOption.gradient;

  // Background Ground
  Color get backgroundColor {
    if (isWhitanianaActive) return LotusColors.whitanianaPureWhite;
    if (isTransparentPassThrough) return Colors.transparent;
    return _isAmoled ? LotusColors.amoledBackground : LotusColors.background;
  }

  // Primary Text Color
  Color get textPrimaryColor {
    return isWhitanianaActive
        ? LotusColors.whitanianaTextPrimary
        : LotusColors.textPrimary;
  }

  // Secondary Text Color
  Color get textSecondaryColor {
    return isWhitanianaActive
        ? LotusColors.whitanianaTextSecondary
        : LotusColors.textSecondary;
  }

  // Tertiary Text Color
  Color get textTertiaryColor {
    return isWhitanianaActive
        ? LotusColors.whitanianaTextTertiary
        : LotusColors.textTertiary;
  }

  // Muted/Caption Text Color
  Color get textMutedColor {
    return isWhitanianaActive
        ? LotusColors.whitanianaTextMuted
        : LotusColors.textMuted;
  }

  // Bottom Navigation Bar Color
  Color get bottomBarBackgroundColor {
    if (isWhitanianaActive) return LotusColors.whitanianaBottomBarBg;
    return _isAmoled
        ? const Color(0xFF040609)
        : LotusColors.surfaceContainerLowest;
  }

  Color get bottomBarBorderColor {
    if (isWhitanianaActive) return LotusColors.whitanianaBottomBarBorder;
    return LotusColors.glassBorder;
  }

  Color get surfaceColor {
    if (isWhitanianaActive) return LotusColors.whitanianaPureWhiteCard;
    if (isStarryNightActive) return LotusColors.starryGlassSurface;
    if (isMoodMatrixActive) return LotusColors.matrixGlassSurface;
    return _isAmoled ? LotusColors.amoledSurface : LotusColors.surface;
  }

  Color get containerLowestColor {
    if (isWhitanianaActive) return LotusColors.whitanianaCardLow;
    if (isStarryNightActive) return LotusColors.starryGlassLowest;
    if (isMoodMatrixActive) return LotusColors.matrixGlassLowest;
    return _isAmoled
        ? LotusColors.amoledSurfaceContainerLowest
        : LotusColors.surfaceContainerLowest;
  }

  Color get containerLowColor {
    if (isWhitanianaActive) return LotusColors.whitanianaCardLow;
    if (isStarryNightActive) return LotusColors.starryGlassLow;
    if (isMoodMatrixActive) return LotusColors.matrixGlassLow;
    return _isAmoled
        ? LotusColors.amoledSurfaceContainerLow
        : LotusColors.surfaceContainerLow;
  }

  Color get containerColor {
    if (isWhitanianaActive) return LotusColors.whitanianaCardContainer;
    if (isStarryNightActive) return LotusColors.starryGlassContainer;
    if (isMoodMatrixActive) return LotusColors.matrixGlassContainer;
    return _isAmoled
        ? LotusColors.amoledSurfaceContainer
        : LotusColors.surfaceContainer;
  }

  Color get containerHighColor {
    if (isWhitanianaActive) return LotusColors.whitanianaCardHigh;
    if (isStarryNightActive) return LotusColors.starryGlassHigh;
    if (isMoodMatrixActive) return LotusColors.matrixGlassHigh;
    return _isAmoled
        ? LotusColors.amoledSurfaceContainerHigh
        : LotusColors.surfaceContainerHigh;
  }

  Color get containerHighestColor {
    if (isWhitanianaActive) return LotusColors.whitanianaCardBorder;
    if (isStarryNightActive) return LotusColors.starryGlassHighest;
    if (isMoodMatrixActive) return LotusColors.matrixGlassHighest;
    return _isAmoled
        ? LotusColors.amoledSurfaceContainerHighest
        : LotusColors.surfaceContainerHighest;
  }

  Color get cardBorderColor {
    if (isWhitanianaActive) return LotusColors.whitanianaCardBorder;
    return LotusColors.glassBorder;
  }

  // Modal & Dialog Shield Tokens
  Color get modalBackgroundColor => isWhitanianaActive
      ? LotusColors.whitanianaPureWhite
      : LotusColors.modalShieldBackground;

  Color get modalSurfaceColor => isWhitanianaActive
      ? LotusColors.whitanianaPureWhiteCard
      : LotusColors.modalShieldSurface;

  Color get modalContainerLowColor => isWhitanianaActive
      ? LotusColors.whitanianaCardLow
      : LotusColors.modalShieldContainerLow;

  Color get modalContainerColor => isWhitanianaActive
      ? LotusColors.whitanianaCardContainer
      : LotusColors.modalShieldContainer;

  Color get modalContainerHighColor => isWhitanianaActive
      ? LotusColors.whitanianaCardHigh
      : LotusColors.modalShieldContainerHigh;

  BoxDecoration modalSheetDecoration({
    required Color accent,
    double topRadius = 30.0,
    double borderWidth = 1.6,
  }) {
    return BoxDecoration(
      color: modalSurfaceColor,
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      border: Border(
        top: BorderSide(
          color: accent.withValues(alpha: 0.85),
          width: borderWidth,
        ),
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: isWhitanianaActive
              ? Colors.black.withValues(alpha: 0.12)
              : Colors.black,
          blurRadius: 32,
          spreadRadius: 8,
          offset: const Offset(0, -4),
        ),
        ...LotusDecorations.glowShadow(accent, intensity: 0.28, blur: 24),
      ],
    );
  }

  BoxDecoration dialogDecoration({
    required Color accent,
    double radius = 24.0,
    double borderWidth = 1.4,
  }) {
    return BoxDecoration(
      color: modalSurfaceColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent.withValues(alpha: 0.75),
        width: borderWidth,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: isWhitanianaActive
              ? Colors.black.withValues(alpha: 0.15)
              : Colors.black,
          blurRadius: 36,
          spreadRadius: 10,
        ),
        ...LotusDecorations.glowShadow(accent, intensity: 0.25, blur: 20),
      ],
    );
  }

  ThemeData get currentThemeData {
    _cachedThemeData ??= LotusAppTheme.buildThemeWithAccent(
      primaryAccent,
      secondaryAccent: secondaryAccent,
      isAmoled: _isAmoled,
      isMatrixTheme: isTransparentPassThrough,
      isStarryNight: isStarryNightActive,
      isWhitaniana: isWhitanianaActive,
    );
    return _cachedThemeData!;
  }

  Future<void> ensureInitialized() => _hydratePreferences();

  Future<void> _hydratePreferences() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? savedId = prefs.getString(_kSelectedThemeKey);
      final bool? savedAmoled = prefs.getBool(_kIsAmoledKey);
      final String? prevId = prefs.getString(_kPreviousThemeBeforeMoodKey);

      bool changed = false;
      if (savedId != null && savedId != _selectedThemeId) {
        _selectedThemeId = savedId;
        changed = true;
      }
      if (savedAmoled != null && savedAmoled != _isAmoled) {
        _isAmoled = savedAmoled;
        changed = true;
      }
      if (prevId != null) {
        _previousThemeBeforeMood = prevId;
      }

      if (changed) {
        _cachedThemeData = null;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setThemePreset(String themeId, {bool force = false}) async {
    if (!force && _selectedThemeId == themeId) return;

    if (themeId == 'lotus_mood_matrix' && _selectedThemeId != 'lotus_mood_matrix') {
      _previousThemeBeforeMood = _selectedThemeId;
    }

    _selectedThemeId = themeId;
    _cachedThemeData = null;
    notifyListeners();

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await Future.wait(<Future<bool>>[
        prefs.setString(_kSelectedThemeKey, themeId),
        if (_previousThemeBeforeMood != null)
          prefs.setString(_kPreviousThemeBeforeMoodKey, _previousThemeBeforeMood!),
      ]);
    } catch (_) {}
  }

  Future<void> activateWhitanianaTheme() async {
    await setThemePreset('whitaniana', force: true);
  }

  Future<void> deactivateWhitanianaTheme() async {
    if (_selectedThemeId == 'whitaniana') {
      await setThemePreset('cyber_bloom', force: true);
    }
  }

  Future<void> activateMoodMatrixTheme() async {
    await setThemePreset('lotus_mood_matrix', force: true);
  }

  Future<void> deactivateMoodMatrixTheme() async {
    if (_selectedThemeId == 'lotus_mood_matrix') {
      final String fallback = _previousThemeBeforeMood ?? 'cyber_bloom';
      await setThemePreset(fallback, force: true);
    }
  }

  Future<void> setAmoledMode(bool enabled) async {
    if (_isAmoled == enabled) return;
    _isAmoled = enabled;
    _cachedThemeData = null;
    notifyListeners();

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsAmoledKey, enabled);
    } catch (_) {}
  }
}

/// Unified Theme Provider & System UI Overlay Controller
class LotusAppTheme {
  static const String fontFamily = 'Space Grotesk';

  static const List<String> fontFallbacks = <String>[
    'Roboto',
    'Noto Sans',
    'Noto Sans Arabic',
    'sans-serif',
  ];

  static ThemeData buildThemeWithAccent(
      Color accentColor, {
        Color? secondaryAccent,
        bool isAmoled = false,
        bool isMatrixTheme = false,
        bool isStarryNight = false,
        bool isWhitaniana = false,
      }) {
    final Color secondaryColor = secondaryAccent ??
        (isWhitaniana
            ? LotusColors.whitanianaEmeraldAccent
            : LotusColors.magentaNeon);

    final Color bgColor = isWhitaniana
        ? LotusColors.whitanianaPureWhite
        : ((isMatrixTheme || isStarryNight)
        ? Colors.transparent
        : (isAmoled
        ? LotusColors.amoledBackground
        : LotusColors.background));

    final Color surfaceColor = isWhitaniana
        ? LotusColors.whitanianaPureWhiteCard
        : (isStarryNight
        ? LotusColors.starryGlassSurface
        : (isMatrixTheme
        ? LotusColors.matrixGlassSurface
        : (isAmoled
        ? LotusColors.amoledSurface
        : LotusColors.surface)));

    final Color containerLowest = isWhitaniana
        ? LotusColors.whitanianaCardLow
        : (isStarryNight
        ? LotusColors.starryGlassLowest
        : (isMatrixTheme
        ? LotusColors.matrixGlassLowest
        : (isAmoled
        ? LotusColors.amoledSurfaceContainerLowest
        : LotusColors.surfaceContainerLowest)));

    final Color containerLow = isWhitaniana
        ? LotusColors.whitanianaCardLow
        : (isStarryNight
        ? LotusColors.starryGlassLow
        : (isMatrixTheme
        ? LotusColors.matrixGlassLow
        : (isAmoled
        ? LotusColors.amoledSurfaceContainerLow
        : LotusColors.surfaceContainerLow)));

    final Color container = isWhitaniana
        ? LotusColors.whitanianaCardContainer
        : (isStarryNight
        ? LotusColors.starryGlassContainer
        : (isMatrixTheme
        ? LotusColors.matrixGlassContainer
        : (isAmoled
        ? LotusColors.amoledSurfaceContainer
        : LotusColors.surfaceContainer)));

    final Color containerHigh = isWhitaniana
        ? LotusColors.whitanianaCardHigh
        : (isStarryNight
        ? LotusColors.starryGlassHigh
        : (isMatrixTheme
        ? LotusColors.matrixGlassHigh
        : (isAmoled
        ? LotusColors.amoledSurfaceContainerHigh
        : LotusColors.surfaceContainerHigh)));

    final Color containerHighest = isWhitaniana
        ? LotusColors.whitanianaCardBorder
        : (isStarryNight
        ? LotusColors.starryGlassHighest
        : (isMatrixTheme
        ? LotusColors.matrixGlassHighest
        : (isAmoled
        ? LotusColors.amoledSurfaceContainerHighest
        : LotusColors.surfaceContainerHighest)));

    final Color effectiveTextPrimary = isWhitaniana
        ? LotusColors.whitanianaTextPrimary
        : LotusColors.textPrimary;
    final Color effectiveTextSecondary = isWhitaniana
        ? LotusColors.whitanianaTextSecondary
        : LotusColors.textSecondary;
    final Color effectiveTextTertiary = isWhitaniana
        ? LotusColors.whitanianaTextTertiary
        : LotusColors.textTertiary;
    final Color effectiveTextMuted = isWhitaniana
        ? LotusColors.whitanianaTextMuted
        : LotusColors.textMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: isWhitaniana ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: bgColor,
      canvasColor: bgColor,
      cardColor: surfaceColor,
      dividerColor: isWhitaniana
          ? LotusColors.whitanianaCardBorder
          : LotusColors.glassBorder,
      primaryColor: accentColor,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      colorScheme: ColorScheme(
        brightness: isWhitaniana ? Brightness.light : Brightness.dark,
        primary: accentColor,
        onPrimary: isWhitaniana ? Colors.white : Colors.black,
        secondary: secondaryColor,
        onSecondary: Colors.white,
        tertiary: LotusColors.solarGold,
        onTertiary: Colors.black,
        error: const Color(0xFFFF5252),
        onError: Colors.white,
        surface: surfaceColor,
        onSurface: effectiveTextPrimary,
        onSurfaceVariant: effectiveTextSecondary,
        outline: isWhitaniana
            ? LotusColors.whitanianaCardBorder
            : LotusColors.glassBorder,
        outlineVariant: isWhitaniana
            ? const Color(0xFFE2E8F0)
            : const Color(0x33FFFFFF),
        surfaceContainerLowest: containerLowest,
        surfaceContainerLow: containerLow,
        surfaceContainer: container,
        surfaceContainerHigh: containerHigh,
        surfaceContainerHighest: containerHighest,
      ),
      iconTheme: IconThemeData(
        color: effectiveTextPrimary,
        size: 22,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isWhitaniana
            ? LotusColors.whitanianaPureWhite
            : Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
          isWhitaniana ? Brightness.dark : Brightness.light,
          statusBarBrightness:
          isWhitaniana ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isWhitaniana
              ? LotusColors.whitanianaBottomBarBg
              : Colors.transparent,
          systemNavigationBarIconBrightness:
          isWhitaniana ? Brightness.dark : Brightness.light,
          systemNavigationBarDividerColor: isWhitaniana
              ? LotusColors.whitanianaBottomBarBorder
              : Colors.transparent,
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: effectiveTextPrimary,
        ),
        iconTheme: IconThemeData(
          color: effectiveTextPrimary,
          size: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: containerLow,
        elevation: isWhitaniana ? 2 : 0,
        shadowColor: isWhitaniana
            ? Colors.black.withValues(alpha: 0.08)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isWhitaniana
                ? LotusColors.whitanianaCardBorder
                : LotusColors.glassBorder,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isWhitaniana
            ? LotusColors.whitanianaPureWhiteCard
            : LotusColors.modalShieldSurface,
        elevation: 12,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isWhitaniana
                ? LotusColors.whitanianaCardBorder
                : LotusColors.glassBorder,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3.5,
        trackShape: const RoundedRectSliderTrackShape(),
        activeTrackColor: accentColor,
        inactiveTrackColor:
        isWhitaniana ? const Color(0xFFCBD5E1) : Colors.white12,
        thumbColor: isWhitaniana ? accentColor : Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        overlayColor: accentColor.withValues(alpha: 0.2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return isWhitaniana
              ? const Color(0xFF64748B)
              : LotusColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor.withValues(alpha: 0.35);
          }
          return isWhitaniana ? const Color(0xFFE2E8F0) : Colors.white12;
        }),
        trackOutlineColor:
        const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          color: effectiveTextPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: effectiveTextPrimary,
        ),
        displaySmall: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: effectiveTextPrimary,
        ),
        headlineLarge: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: effectiveTextPrimary,
          letterSpacing: 0.3,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: effectiveTextPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: effectiveTextPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: effectiveTextPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: effectiveTextPrimary,
        ),
        titleSmall: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: effectiveTextSecondary,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: effectiveTextPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: effectiveTextSecondary,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: effectiveTextMuted,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: effectiveTextPrimary,
        ),
        labelMedium: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: effectiveTextSecondary,
        ),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: effectiveTextTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Dynamic Context Helpers for high-speed & overflow-safe UI coding
extension LotusContextTheme on BuildContext {
  LotusThemeController get lotusTheme => LotusThemeController.instance;
  bool get isWhitaniana => LotusThemeController.instance.isWhitanianaActive;
  Color get lotusAccent => LotusThemeController.instance.primaryAccent;
  Color get lotusTextPrimary => LotusThemeController.instance.textPrimaryColor;
  Color get lotusTextSecondary => LotusThemeController.instance.textSecondaryColor;
  Color get lotusTextTertiary => LotusThemeController.instance.textTertiaryColor;
  Color get lotusTextMuted => LotusThemeController.instance.textMutedColor;
  Color get lotusSurface => LotusThemeController.instance.surfaceColor;
  Color get lotusCardLow => LotusThemeController.instance.containerLowColor;
  Color get lotusCardContainer => LotusThemeController.instance.containerColor;
  Color get lotusBorder => LotusThemeController.instance.cardBorderColor;
}