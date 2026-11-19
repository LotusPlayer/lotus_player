// ==============================================================================
// LOTUS THEME - STARRY NIGHT EXTENSION & THEME CONFIGURATION (ENHANCED MASTER)
// Name: Starry Night ("starry_night")
// Visual Identity:
// 1. Moving thinking-process iridescent purple/violet edge light border glow.
// 2. Translucent glassmorphism containers & full transparent backdrops.
// 3. Thousands of colored stardust points (cyan, amber, magenta, violet, soft gold).
// 4. Pure deep celestial dark space palette (#040209, #0B0616).
// ==============================================================================

import 'package:material_ui/material_ui.dart';
import 'lotus_theme.dart';

class StarryNightThemeDefinition {
  static const String themeId = 'starry_night';
  static const String themeName = 'Starry Night';
  static const String themeSubtitle = 'Celestial Thinking Horizon & Stardust';

  // Core Spectral Accents
  static const Color primaryNeonPurple = Color(0xFFC084FC); // Radiant Purple
  static const Color deepUltraviolet = Color(0xFF9333EA);   // Thinking Violet
  static const Color cyanStardust = Color(0xFF38BDF8);      // Nebula Cyan
  static const Color cosmicMagenta = Color(0xFFE879F9);      // Luminous Fuchsia
  static const Color amberSpark = Color(0xFFFBBF24);        // Twinkling Amber
  static const Color celestialGold = Color(0xFFFFD166);     // Solar Pulse

  // Celestial Space & Translucent Glass Surface Hierarchy
  static const Color cosmicVoidBg = Color(0xFF040209);
  static const Color surfaceGlass = Color(0x33120A24);          // 20% transparent glass
  static const Color containerLowestGlass = Color(0x1A0B0616);  // 10% translucent
  static const Color containerLowGlass = Color(0x24180E30);     // 14% translucent
  static const Color containerGlass = Color(0x381E113C);        // 22% translucent
  static const Color containerHighGlass = Color(0x4D241246);    // 30% translucent
  static const Color containerHighestGlass = Color(0x662E1758); // 40% translucent

  // Edge Glowing Border Linear Gradient (Fixed Angle)
  static const LinearGradient thinkingEdgeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFFC084FC), // Radiant Purple
      Color(0xFF9333EA), // Violet
      Color(0xFF38BDF8), // Nebula Cyan
      Color(0xFFE879F9), // Luminous Fuchsia
      Color(0xFFC084FC), // Seamless loop
    ],
    stops: <double>[0.0, 0.25, 0.55, 0.85, 1.0],
  );

  // Rotating Thinking Sweep Gradient (For kinetic revolving border shaders)
  static const SweepGradient thinkingSweepGradient = SweepGradient(
    colors: <Color>[
      Color(0xFFC084FC),
      Color(0xFF9333EA),
      Color(0xFF38BDF8),
      Color(0xFFE879F9),
      Color(0xFFFBBF24),
      Color(0xFFC084FC),
    ],
    stops: <double>[0.0, 0.20, 0.45, 0.70, 0.88, 1.0],
  );

  // Pre-allocated BoxShadows for 120 FPS performance
  static List<BoxShadow> cosmicGlow({
    Color color = primaryNeonPurple,
    double intensity = 0.32,
    double blur = 24.0,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: intensity),
        blurRadius: blur,
        spreadRadius: 1.5,
      ),
      BoxShadow(
        color: deepUltraviolet.withValues(alpha: intensity * 0.6),
        blurRadius: blur * 1.5,
        spreadRadius: 2.5,
      ),
    ];
  }

  /// Preset Master Registry Option
  static const LotusThemeOption starryNightOption = LotusThemeOption(
    id: themeId,
    name: themeName,
    subtitle: themeSubtitle,
    primaryColor: primaryNeonPurple,
    secondaryColor: deepUltraviolet,
    gradient: thinkingEdgeGradient,
    previewColors: <Color>[
      primaryNeonPurple,
      deepUltraviolet,
      cyanStardust,
      cosmicMagenta,
    ],
  );
}