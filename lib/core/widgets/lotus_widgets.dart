import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../providers/lotus_playback_provider.dart';
import '../theme/lotus_theme.dart';
import 'lotus_artwork_image.dart';

/// 1. PURE WHITE HIGH-CONTRAST BOTTOM NAVIGATION BAR (WHITANIANA CALIBRATED)
class LotusBottomNavigationBar extends StatelessWidget {
    final int currentIndex;
    final ValueChanged<int> onTabSelected;

    const LotusBottomNavigationBar({
        super.key,
        required this.currentIndex,
        required this.onTabSelected,
    });

    @override
    Widget build(BuildContext context) {
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;
        final Color accent = theme.primaryAccent;

        final Color barBackground = isWhitaniana
            ? LotusColors.whitanianaBottomBarBg
            : (theme.isAmoled
            ? const Color(0xFF040609)
            : theme.containerLowestColor);

        final Color borderColor = isWhitaniana
            ? LotusColors.whitanianaBottomBarBorder
            : LotusColors.glassBorder;

        final List<Map<String, dynamic>> tabs = <Map<String, dynamic>>[
            <String, dynamic>{
                'label': 'HOME',
                'icon': Icons.home_rounded,
                'asset': 'assets/icons/nav_home.png'
            },
            <String, dynamic>{
                'label': 'VAULT',
                'icon': Icons.folder_special_rounded,
                'asset': 'assets/icons/nav_vault.png'
            },
            <String, dynamic>{
                'label': 'DSP EQ',
                'icon': Icons.equalizer_rounded,
                'asset': 'assets/icons/nav_eq.png'
            },
            <String, dynamic>{
                'label': 'MIXES',
                'icon': Icons.library_music_rounded,
                'asset': 'assets/icons/nav_mixes.png'
            },
            <String, dynamic>{
                'label': 'SETTINGS',
                'icon': Icons.settings_rounded,
                'asset': 'assets/icons/nav_settings.png'
            },
        ];

        return Container(
            decoration: BoxDecoration(
                color: barBackground,
                border: Border(
                    top: BorderSide(color: borderColor, width: 1.0),
                ),
                boxShadow: isWhitaniana
                    ? <BoxShadow>[
                    BoxShadow(
                        color: const Color(0xFF0E141B).withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -3),
                    ),
                ]
                    : <BoxShadow>[
                    const BoxShadow(
                        color: Colors.black,
                        blurRadius: 18,
                        offset: Offset(0, -2),
                    ),
                ],
            ),
            child: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List<Widget>.generate(tabs.length, (int index) {
                            final bool isSelected = currentIndex == index;
                            final Map<String, dynamic> tab = tabs[index];
                            final String label = tab['label'] as String;
                            final IconData iconData = tab['icon'] as IconData;

                            final Color activeColor =
                            isWhitaniana ? const Color(0xFF0B0F19) : Colors.white;
                            final Color inactiveColor = isWhitaniana
                                ? const Color(0xFF64748B)
                                : LotusColors.textTertiary;

                            final Color iconColor = isSelected
                                ? (isWhitaniana ? accent : activeColor)
                                : inactiveColor;

                            final Color labelColor = isSelected ? activeColor : inactiveColor;

                            return Expanded(
                                child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                        HapticFeedback.lightImpact();
                                        onTabSelected(index);
                                    },
                                    child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4.0, vertical: 6.0),
                                        decoration: BoxDecoration(
                                            color: isSelected
                                                ? (isWhitaniana
                                                ? accent.withValues(alpha: 0.16)
                                                : accent.withValues(alpha: 0.22))
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                                color: isSelected
                                                    ? (isWhitaniana
                                                    ? accent.withValues(alpha: 0.85)
                                                    : accent)
                                                    : Colors.transparent,
                                                width: 1.2,
                                            ),
                                            boxShadow: isSelected && !isWhitaniana
                                                ? LotusDecorations.glowShadow(accent,
                                                intensity: 0.35, blur: 12)
                                                : null,
                                        ),
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                                Icon(
                                                    iconData,
                                                    color: iconColor,
                                                    size: 22,
                                                ),
                                                const SizedBox(height: 3),
                                                FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                        label,
                                                        style: TextStyle(
                                                            color: labelColor,
                                                            fontSize: 9.0,
                                                            fontWeight: isSelected
                                                                ? FontWeight.w900
                                                                : FontWeight.w700,
                                                            letterSpacing: 0.4,
                                                        ),
                                                    ),
                                                ),
                                            ],
                                        ),
                                    ),
                                ),
                            );
                        }),
                    ),
                ),
            ),
        );
    }
}

/// 2. Standardized Album Artwork Widget with Precision Bevel & Contact Shadow
class LotusArtworkThumb extends StatelessWidget {
    final int songId;
    final double size;
    final double borderRadius;
    final Color? fallbackAccent;

    const LotusArtworkThumb({
        super.key,
        required this.songId,
        this.size = 44.0,
        this.borderRadius = 12.0,
        this.fallbackAccent,
    });

    @override
    Widget build(BuildContext context) {
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;
        final Color accent = fallbackAccent ?? theme.primaryAccent;

        return Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                    color: isWhitaniana
                        ? LotusColors.whitanianaCardBorder
                        : LotusColors.glassBorder,
                    width: 1.0,
                ),
                boxShadow: isWhitaniana
                    ? <BoxShadow>[
                    BoxShadow(
                        color: const Color(0xFF0E141B).withValues(alpha: 0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                    ),
                ]
                    : null,
            ),
            child: LotusArtworkImage(
                songId: songId,
                size: size,
                borderRadius: borderRadius,
                nullArtworkWidget: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        color: isWhitaniana
                            ? const Color(0xFFF1F5F9)
                            : theme.containerHighColor,
                    ),
                    child: Center(
                        child: Icon(
                            Icons.local_florist_rounded,
                            color: accent,
                            size: size * 0.52,
                        ),
                    ),
                ),
            ),
        );
    }
}

/// 3. High-Contrast Audio Quality & Codec Badge (FLAC, DSD 96K, BIT-PERFECT, MASTER)
class LotusQualityBadge extends StatelessWidget {
    final String label;
    final Color? color;
    final bool isSolid;

    const LotusQualityBadge({
        super.key,
        required this.label,
        this.color,
        this.isSolid = false,
    });

    @override
    Widget build(BuildContext context) {
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;
        final Color badgeColor = color ??
            (isWhitaniana ? LotusColors.whitanianaCyanAccent : theme.primaryAccent);

        final Color effectiveBackground =
        isSolid ? badgeColor : badgeColor.withValues(alpha: 0.16);

        final Color effectiveBorder = isWhitaniana
            ? badgeColor.withValues(alpha: 0.85)
            : badgeColor.withValues(alpha: 0.50);

        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.0),
            decoration: BoxDecoration(
                color: effectiveBackground,
                borderRadius: BorderRadius.circular(4.5),
                border: Border.all(color: effectiveBorder, width: 0.9),
            ),
            child: Text(
                label,
                style: TextStyle(
                    color: isSolid ? Colors.white : badgeColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                ),
            ),
        );
    }
}

/// 4. Luminous Gradient Track Scrubber (Theme Reactive)
class LotusScrubberBar extends StatelessWidget {
    final double progress; // 0.0 to 1.0
    final double height;
    final Gradient? gradient;

    const LotusScrubberBar({
        super.key,
        required this.progress,
        this.height = 3.5,
        this.gradient,
    });

    @override
    Widget build(BuildContext context) {
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;
        final double clamped = progress.clamp(0.0, 1.0);
        final Gradient activeGrad = gradient ?? theme.activeGradient;

        return ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: SizedBox(
                height: height,
                width: double.infinity,
                child: Stack(
                    children: <Widget>[
                        Container(
                            color: isWhitaniana ? const Color(0xFFCBD5E1) : Colors.white12,
                        ),
                        FractionallySizedBox(
                            widthFactor: clamped,
                            child: Container(
                                decoration: BoxDecoration(
                                    gradient: activeGrad,
                                    boxShadow: LotusDecorations.glowShadow(
                                        theme.primaryAccent,
                                        intensity: 0.65,
                                        blur: 10,
                                    ),
                                ),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}

/// 5. Tactile Circle Icon Action Button (Always Visible in Whitaniana)
class LotusIconButton extends StatelessWidget {
    final IconData icon;
    final VoidCallback onTap;
    final Color? color;
    final Color? iconColor;
    final double size;

    const LotusIconButton({
        super.key,
        required this.icon,
        required this.onTap,
        this.color,
        this.iconColor,
        this.size = 36.0,
    });

    @override
    Widget build(BuildContext context) {
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;

        final Color effectiveBg = color ??
            (isWhitaniana ? const Color(0xFFFFFFFF) : theme.containerLowColor);

        final Color effectiveBorder = isWhitaniana
            ? LotusColors.whitanianaCardBorder
            : LotusColors.glassBorder;

        final Color effectiveIconColor =
            iconColor ?? (isWhitaniana ? const Color(0xFF0B0F19) : Colors.white);

        return GestureDetector(
            onTap: () {
                HapticFeedback.lightImpact();
                onTap();
            },
            child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                    color: effectiveBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: effectiveBorder, width: 1.0),
                    boxShadow: isWhitaniana
                        ? <BoxShadow>[
                        BoxShadow(
                            color: const Color(0xFF0E141B).withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                        ),
                    ]
                        : null,
                ),
                child: Center(
                    child: Icon(
                        icon,
                        color: effectiveIconColor,
                        size: size * 0.52,
                    ),
                ),
            ),
        );
    }
}

/// 6. Concentric Turntable / Vinyl Artwork Stage
class LotusTurntableConcentricArtwork extends StatefulWidget {
    final int songId;
    final bool isPlaying;
    final double diameter;

    const LotusTurntableConcentricArtwork({
        super.key,
        required this.songId,
        required this.isPlaying,
        this.diameter = 46.0,
    });

    @override
    State<LotusTurntableConcentricArtwork> createState() =>
        _LotusTurntableConcentricArtworkState();
}

class _LotusTurntableConcentricArtworkState
    extends State<LotusTurntableConcentricArtwork>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
    final LotusThemeController _theme = LotusThemeController.instance;
    late final AnimationController _pulseController;

    @override
    void initState() {
        super.initState();
        WidgetsBinding.instance.addObserver(this);
        _pulseController = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 2400),
        );
        if (widget.isPlaying) {
            _pulseController.repeat(reverse: true);
        }
    }

    @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
        if (state == AppLifecycleState.resumed && widget.isPlaying) {
            if (!_pulseController.isAnimating) {
                _pulseController.repeat(reverse: true);
            }
        } else {
            if (_pulseController.isAnimating) {
                _pulseController.stop();
            }
        }
    }

    @override
    void didUpdateWidget(covariant LotusTurntableConcentricArtwork oldWidget) {
        super.didUpdateWidget(oldWidget);
        if (widget.isPlaying != oldWidget.isPlaying) {
            if (widget.isPlaying) {
                if (!_pulseController.isAnimating) {
                    _pulseController.repeat(reverse: true);
                }
            } else {
                if (_pulseController.isAnimating) {
                    _pulseController.stop();
                }
            }
        }
    }

    @override
    void dispose() {
        WidgetsBinding.instance.removeObserver(this);
        _pulseController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return ListenableBuilder(
            listenable: _theme,
            builder: (BuildContext context, _) {
                final Color accent = _theme.primaryAccent;
                final Color secondaryAccent = _theme.secondaryAccent;
                final double diameter = widget.diameter;

                return RepaintBoundary(
                    child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                            AnimatedBuilder(
                                animation: _pulseController,
                                builder: (BuildContext context, Widget? child) {
                                    final double p =
                                    widget.isPlaying ? _pulseController.value : 0.0;
                                    return Transform.scale(
                                        scale: 1.0 + (0.04 * p),
                                        child: Opacity(
                                            opacity: widget.isPlaying ? (0.65 + (0.35 * p)) : 0.55,
                                            child: child,
                                        ),
                                    );
                                },
                                child: Container(
                                    width: diameter + 4,
                                    height: diameter + 4,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: <BoxShadow>[
                                            BoxShadow(
                                                color: secondaryAccent.withValues(alpha: 0.55),
                                                blurRadius: 16,
                                                spreadRadius: 2.5,
                                            ),
                                            BoxShadow(
                                                color: accent.withValues(alpha: 0.30),
                                                blurRadius: 10,
                                            ),
                                        ],
                                    ),
                                ),
                            ),
                            Container(
                                width: diameter + 2,
                                height: diameter + 2,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24, width: 1.0),
                                ),
                            ),
                            Container(
                                width: diameter,
                                height: diameter,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: accent, width: 1.6),
                                ),
                                child: ClipOval(
                                    child: LotusArtworkImage(
                                        songId: widget.songId,
                                        size: diameter,
                                        borderRadius: diameter / 2,
                                        keepOldArtwork: true,
                                        nullArtworkWidget: Container(
                                            width: diameter,
                                            height: diameter,
                                            decoration: BoxDecoration(
                                                gradient: RadialGradient(
                                                    colors: <Color>[
                                                        accent.withValues(alpha: 0.35),
                                                        _theme.containerLowestColor,
                                                    ],
                                                ),
                                            ),
                                            child: Center(
                                                child: Icon(
                                                    Icons.music_note_rounded,
                                                    color: accent,
                                                    size: 22,
                                                ),
                                            ),
                                        ),
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

/// 7. LotusMiniPlayerPill / LotusMagnificentDeck
class LotusMiniPlayerPill extends StatelessWidget {
    final SongModel song;
    final bool isPlaying;
    final VoidCallback onTogglePlay;
    final VoidCallback onSkipNext;
    final VoidCallback? onSkipPrevious;
    final VoidCallback onTap;
    final VoidCallback? onToggleFavorite;
    final bool? isFavoriteOverride;
    final int currentPositionMs;
    final int totalDurationMs;
    final bool isCollapsed;
    final VoidCallback? onToggleCollapse;

    const LotusMiniPlayerPill({
        super.key,
        required this.song,
        required this.isPlaying,
        required this.onTogglePlay,
        required this.onSkipNext,
        this.onSkipPrevious,
        required this.onTap,
        this.onToggleFavorite,
        this.isFavoriteOverride,
        this.currentPositionMs = 0,
        this.totalDurationMs = 0,
        this.isCollapsed = false,
        this.onToggleCollapse,
    });

    static String formatDuration(int ms) {
        final int safeMs = ms.clamp(0, 359999999);
        final Duration d = Duration(milliseconds: safeMs);
        final int minutes = d.inMinutes;
        final int seconds = d.inSeconds.remainder(60);
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    @override
    Widget build(BuildContext context) {
        final LotusPlaybackProvider playback = LotusPlaybackProvider.instance;
        final LotusThemeController theme = LotusThemeController.instance;

        final bool isWhitaniana = theme.isWhitanianaActive;
        final Color accent = theme.primaryAccent;
        final Color secondaryAccent = theme.secondaryAccent;
        final LinearGradient activeGradient = theme.activeGradient;

        final int duration = totalDurationMs > 0
            ? totalDurationMs
            : (song.duration != null && song.duration! > 0
            ? song.duration!
            : 240000);

        final double progress =
        duration > 0 ? (currentPositionMs / duration).clamp(0.0, 1.0) : 0.0;
        final bool isFav = isFavoriteOverride ??
            (playback.activeSong?.id == song.id && playback.isFavorite);

        final Color deckSurfaceColor;
        final Color deckBorderColor;
        final List<BoxShadow> deckShadows;

        if (isWhitaniana) {
            deckSurfaceColor = const Color(0xF00E1217);
            deckBorderColor = isPlaying
                ? const Color(0xFF0284C7).withValues(alpha: 0.90)
                : const Color(0x400284C7);
            deckShadows = <BoxShadow>[
                BoxShadow(
                    color: const Color(0xFF0E141B).withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                ),
                BoxShadow(
                    color: const Color(0xFF0284C7)
                        .withValues(alpha: isPlaying ? 0.35 : 0.14),
                    blurRadius: 18,
                ),
            ];
        } else {
            final bool isSpecialTheme = theme.isMoodMatrixActive ||
                theme.isStarryNightActive ||
                theme.isTransparentPassThrough;
            deckSurfaceColor = isSpecialTheme
                ? const Color(0xFF070B14)
                : (theme.isAmoled
                ? const Color(0xFF070B14)
                : theme.containerLowColor);
            deckBorderColor = isPlaying
                ? accent.withValues(alpha: 0.85)
                : accent.withValues(alpha: 0.45);
            deckShadows = <BoxShadow>[
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.85),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                ),
                BoxShadow(
                    color: accent.withValues(alpha: isPlaying ? 0.22 : 0.08),
                    blurRadius: 20,
                ),
            ];
        }

        return RepaintBoundary(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                    if (onToggleCollapse != null)
                        GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                                HapticFeedback.lightImpact();
                                onToggleCollapse!();
                            },
                            child: Container(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 28, vertical: 4.0),
                                decoration: BoxDecoration(
                                    color: deckSurfaceColor,
                                    borderRadius:
                                    const BorderRadius.vertical(top: Radius.circular(16)),
                                    border: Border(
                                        top: BorderSide(
                                            color: isWhitaniana
                                                ? const Color(0xFF0284C7).withValues(alpha: 0.85)
                                                : accent.withValues(alpha: 0.85),
                                            width: 1.4,
                                        ),
                                        left: BorderSide(
                                            color: isWhitaniana
                                                ? const Color(0x400284C7)
                                                : accent.withValues(alpha: 0.5),
                                            width: 1.0,
                                        ),
                                        right: BorderSide(
                                            color: isWhitaniana
                                                ? const Color(0x400284C7)
                                                : accent.withValues(alpha: 0.5),
                                            width: 1.0,
                                        ),
                                    ),
                                    boxShadow: LotusDecorations.glowShadow(accent,
                                        intensity: 0.28, blur: 14),
                                ),
                                child: Container(
                                    width: 24,
                                    height: 3.5,
                                    decoration: BoxDecoration(
                                        gradient: activeGradient,
                                        borderRadius: BorderRadius.circular(2),
                                    ),
                                ),
                            ),
                        ),
                    AnimatedCrossFade(
                        crossFadeState: isCollapsed
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 320),
                        firstCurve: Curves.easeOutCubic,
                        secondCurve: Curves.easeInCubic,
                        secondChild: const SizedBox(height: 0, width: double.infinity),
                        firstChild: GestureDetector(
                            onTap: onTap,
                            child: Container(
                                margin:
                                const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                                decoration: BoxDecoration(
                                    color: deckSurfaceColor,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                        color: deckBorderColor,
                                        width: 1.4,
                                    ),
                                    boxShadow: deckShadows,
                                ),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                        Row(
                                            children: <Widget>[
                                                LotusTurntableConcentricArtwork(
                                                    songId: song.id,
                                                    isPlaying: isPlaying,
                                                    diameter: 46.0,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                    child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: <Widget>[
                                                            Text(
                                                                song.title,
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 14.0,
                                                                    fontWeight: FontWeight.bold,
                                                                    letterSpacing: -0.2,
                                                                ),
                                                            ),
                                                            const SizedBox(height: 3),
                                                            Row(
                                                                children: <Widget>[
                                                                    Flexible(
                                                                        fit: FlexFit.loose,
                                                                        child: LotusQualityBadge(
                                                                            label: song.fileExtension.isNotEmpty
                                                                                ? song.fileExtension.toUpperCase()
                                                                                : (isWhitaniana
                                                                                ? 'DSD 96K'
                                                                                : 'DSD512'),
                                                                            color: isWhitaniana
                                                                                ? const Color(0xFF0284C7)
                                                                                : accent,
                                                                        ),
                                                                    ),
                                                                    const SizedBox(width: 6),
                                                                    Flexible(
                                                                        fit: FlexFit.loose,
                                                                        child: Text(
                                                                            '${formatDuration(currentPositionMs)} / ${formatDuration(duration)}',
                                                                            maxLines: 1,
                                                                            overflow: TextOverflow.ellipsis,
                                                                            style: TextStyle(
                                                                                color: isWhitaniana
                                                                                    ? const Color(0xFF38BDF8)
                                                                                    : secondaryAccent,
                                                                                fontSize: 9.5,
                                                                                fontWeight: FontWeight.bold,
                                                                                fontFamily: 'monospace',
                                                                            ),
                                                                        ),
                                                                    ),
                                                                ],
                                                            ),
                                                        ],
                                                    ),
                                                ),
                                                const SizedBox(width: 6),
                                                Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: <Widget>[
                                                        GestureDetector(
                                                            behavior: HitTestBehavior.opaque,
                                                            onTap: onToggleFavorite ??
                                                                    () => playback.toggleFavorite(),
                                                            child: Container(
                                                                padding: const EdgeInsets.all(7.5),
                                                                decoration: BoxDecoration(
                                                                    color: isFav
                                                                        ? secondaryAccent.withValues(alpha: 0.25)
                                                                        : Colors.white.withValues(alpha: 0.12),
                                                                    shape: BoxShape.circle,
                                                                    border: Border.all(
                                                                        color: isFav
                                                                            ? secondaryAccent
                                                                            : Colors.white24,
                                                                    ),
                                                                ),
                                                                child: Icon(
                                                                    isFav
                                                                        ? Icons.favorite_rounded
                                                                        : Icons.favorite_border_rounded,
                                                                    color: isFav ? secondaryAccent : Colors.white,
                                                                    size: 18,
                                                                ),
                                                            ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        GestureDetector(
                                                            behavior: HitTestBehavior.opaque,
                                                            onTap: onSkipPrevious ??
                                                                    () => playback.skipPrevious(),
                                                            child: Container(
                                                                padding: const EdgeInsets.all(7.5),
                                                                decoration: BoxDecoration(
                                                                    color: Colors.white.withValues(alpha: 0.12),
                                                                    shape: BoxShape.circle,
                                                                    border: Border.all(color: Colors.white24),
                                                                ),
                                                                child: const Icon(
                                                                    Icons.skip_previous_rounded,
                                                                    color: Colors.white,
                                                                    size: 18,
                                                                ),
                                                            ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        GestureDetector(
                                                            behavior: HitTestBehavior.opaque,
                                                            onTap: () {
                                                                HapticFeedback.heavyImpact();
                                                                onTogglePlay();
                                                            },
                                                            child: Container(
                                                                width: 40,
                                                                height: 40,
                                                                decoration: BoxDecoration(
                                                                    shape: BoxShape.circle,
                                                                    gradient: activeGradient,
                                                                    boxShadow: LotusDecorations.glowShadow(
                                                                        accent,
                                                                        intensity: 0.50,
                                                                        blur: 16,
                                                                    ),
                                                                ),
                                                                child: Icon(
                                                                    isPlaying
                                                                        ? Icons.pause_rounded
                                                                        : Icons.play_arrow_rounded,
                                                                    color:
                                                                    isWhitaniana ? Colors.white : Colors.black,
                                                                    size: 22,
                                                                ),
                                                            ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        GestureDetector(
                                                            behavior: HitTestBehavior.opaque,
                                                            onTap: () {
                                                                HapticFeedback.lightImpact();
                                                                onSkipNext();
                                                            },
                                                            child: Container(
                                                                padding: const EdgeInsets.all(7.5),
                                                                decoration: BoxDecoration(
                                                                    color: Colors.white.withValues(alpha: 0.12),
                                                                    shape: BoxShape.circle,
                                                                    border: Border.all(color: Colors.white24),
                                                                ),
                                                                child: const Icon(
                                                                    Icons.skip_next_rounded,
                                                                    color: Colors.white,
                                                                    size: 18,
                                                                ),
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                            ],
                                        ),
                                        const SizedBox(height: 8),
                                        LotusScrubberBar(
                                            progress: progress,
                                            height: 3.5,
                                            gradient: activeGradient,
                                        ),
                                    ],
                                ),
                            ),
                        ),
                    ),
                ],
            ),
        );
    }
}

/// CRYSTAL RAINBOW LOTUS MAGNIFYING GLASS SEARCH ICON
class LotusSearchIcon extends StatelessWidget {
    final double size;
    final Color? color;

    const LotusSearchIcon({
        super.key,
        this.size = 20,
        this.color,
    });

    @override
    Widget build(BuildContext context) {
        return Image.asset(
            'assets/icons/search_icon.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                Icon(Icons.search_rounded, size: size, color: color),
        );
    }
}

/// 8. Standardized Lotus Floating Pop-Up SnackBar (Flutter 3.50+ & Whitaniana Calibrated)
class LotusSnackBar {
    static SnackBar create({
        required Widget content,
        Duration duration = const Duration(seconds: 2),
        SnackBarAction? action,
        Color? borderColor,
        Color? backgroundColor,
    }) {
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;
        final Color accent = borderColor ?? theme.primaryAccent;

        final Color bgColor = backgroundColor ??
            (isWhitaniana
                ? LotusColors.whitanianaPureWhiteCard
                : (theme.isAmoled ? const Color(0xFF131826) : theme.containerHighColor));

        final Color resolvedBorder = isWhitaniana
            ? accent.withValues(alpha: 0.55)
            : accent.withValues(alpha: 0.35);

        return SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: bgColor,
            elevation: isWhitaniana ? 6 : 8,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: resolvedBorder, width: 1.2),
            ),
            duration: duration,
            action: action,
            content: content,
        );
    }

    static void show(
        BuildContext context, {
        required String message,
        IconData? icon,
        Color? iconColor,
        Duration duration = const Duration(seconds: 2),
        SnackBarAction? action,
        Color? borderColor,
    }) {
        if (!context.mounted) return;
        final LotusThemeController theme = LotusThemeController.instance;
        final bool isWhitaniana = theme.isWhitanianaActive;
        final Color accent = iconColor ?? theme.primaryAccent;
        final Color textColor = isWhitaniana
            ? LotusColors.whitanianaTextPrimary
            : Colors.white;

        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
            create(
                duration: duration,
                action: action,
                borderColor: borderColor ?? accent,
                content: Row(
                    children: <Widget>[
                        if (icon != null) ...<Widget>[
                            Icon(icon, color: accent, size: 20),
                            const SizedBox(width: 10),
                        ],
                        Expanded(
                            child: Text(
                                message,
                                style: TextStyle(
                                    color: textColor,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}
