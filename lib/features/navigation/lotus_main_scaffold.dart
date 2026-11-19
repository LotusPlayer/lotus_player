// ==============================================================================
// LOTUS PLAYER - MAIN SCAFFOLD & AUDIOPHILE BOTTOM INTERFACE (FLUTTER 3.50+ / DART 3.7)
// File: lib/features/navigation/lotus_main_scaffold.dart
// Features: Dynamic Edge-to-Edge Navigation, Hardware 120 FPS Mini-Player Deck,
//           Flip-3D Compression, Scoped State Notifiers, Pure Flutter Framework Imports
// ==============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_notification_channel_manager.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_mood_matrix_backdrop.dart';
import '../../core/widgets/lotus_starry_night_backdrop.dart';
import '../equalizer/lotus_dsp_equalizer_screen.dart';
import '../home/lotus_home_screen.dart';
import '../now_playing/lotus_now_playing_screen.dart';
import '../playlists/lotus_playlists_unified_screen.dart';
import '../settings/lotus_settings_screen.dart';
import '../vault/lotus_vault_folders_screen.dart';

class LotusMainScaffold extends StatefulWidget {
  const LotusMainScaffold({super.key});

  @override
  State<LotusMainScaffold> createState() => _LotusMainScaffoldState();
}

class _LotusMainScaffoldState extends State<LotusMainScaffold> {
  int _currentTabIndex = 0;
  final Set<int> _loadedTabs = <int>{0};
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final LotusThemeController _theme = LotusThemeController.instance;

  bool _isMiniPlayerCollapsed = false;
  bool _isNowPlayingRouteOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safelyInitSystemServices();
    });
  }

  Future<void> _safelyInitSystemServices() async {
    if (!mounted || !Platform.isAndroid) return;

    try {
      try {
        final bool isAudioGranted = await Permission.audio.status.isGranted;
        final bool isStorageGranted = await Permission.storage.status.isGranted;

        if (!isAudioGranted && !isStorageGranted) {
          final PermissionStatus audioStatus = await Permission.audio.request();
          if (!audioStatus.isGranted) {
            await Permission.storage.request();
          }
        }
      } catch (e) {
        debugPrint('Lotus Permission check notice: $e');
      }

      if (mounted) {
        try {
          final PermissionStatus notifStatus =
          await Permission.notification.status;
          if (!notifStatus.isGranted) {
            await Permission.notification.request();
          }
        } catch (e) {
          debugPrint('Lotus Notification permission notice: $e');
        }
      }

      try {
        await LotusNotificationChannelManager.instance
            .initializeNotificationChannels(
          requestPermissionOnBoot: false,
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Lotus system init exception: $e');
    }
  }

  void _onTabSelected(int index) {
    if (_currentTabIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentTabIndex = index;
      _loadedTabs.add(index);
    });
  }

  void _handleCategoryShortcutTapped(int categoryIndex) {
    if (categoryIndex == 3 || categoryIndex == 1) {
      _onTabSelected(3);
    } else if (categoryIndex == 2) {
      _onTabSelected(2);
    } else if (categoryIndex == 0) {
      _onTabSelected(1);
    }
  }

  void _handleOpenEqualizerFromTopBar() {
    _onTabSelected(2);
  }

  Future<void> _handleTrackSelected(SongModel song) async {
    HapticFeedback.lightImpact();
  }

  void _openNowPlayingStage() {
    if (_isNowPlayingRouteOpen) return;
    final SongModel? song = _playback.activeSong;
    if (song == null) return;

    _isNowPlayingRouteOpen = true;
    HapticFeedback.mediumImpact();

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder:
            (BuildContext ctx, Animation<double> a, Animation<double> sa) {
          return LotusNowPlayingScreen(
            song: song,
            onBack: () {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
          );
        },
        transitionsBuilder: (BuildContext ctx, Animation<double> a,
            Animation<double> sa, Widget child) {
          return SlideTransition(
            position: a.drive(
              Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    ).then((_) {
      _isNowPlayingRouteOpen = false;
    });
  }

  void _toggleMiniPlayerCollapse() {
    HapticFeedback.lightImpact();
    setState(() {
      _isMiniPlayerCollapsed = !_isMiniPlayerCollapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double bottomSystemInset = MediaQuery.paddingOf(context).bottom;
    final double safeBottomPadding =
    bottomSystemInset > 0 ? bottomSystemInset + 6.0 : 16.0;

    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool isKeyboardOpen = keyboardInset > 0.0;

    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final bool isWhitaniana = _theme.isWhitanianaActive;
        final Color activeAccent = _theme.primaryAccent;
        final Color effectiveScaffoldBg = _theme.backgroundColor;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
            isWhitaniana ? Brightness.dark : Brightness.light,
            statusBarBrightness:
            isWhitaniana ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: isWhitaniana
                ? LotusColors.whitanianaBottomBarBg
                : Colors.black,
            systemNavigationBarIconBrightness:
            isWhitaniana ? Brightness.dark : Brightness.light,
            systemNavigationBarDividerColor: isWhitaniana
                ? LotusColors.whitanianaBottomBarBorder
                : Colors.transparent,
          ),
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              if (didPop) return;
              if (_currentTabIndex != 0) {
                _onTabSelected(0);
              } else {
                const MethodChannel('com.souljalazian.lotus_player/intents')
                    .invokeMethod<void>('moveToBackground');
              }
            },
            child: RepaintBoundary(
              child: LotusStarryNightBackdrop(
                child: LotusMoodMatrixBackdrop(
                  child: Scaffold(
                    resizeToAvoidBottomInset: true,
                    backgroundColor: effectiveScaffoldBg,
                    body: Stack(
                      children: <Widget>[
                        RepaintBoundary(
                          child: IndexedStack(
                            index: _currentTabIndex,
                            children: <Widget>[
                              LotusHomeScreen(
                                onSongSelected: _handleTrackSelected,
                                onOpenNowPlaying: _openNowPlayingStage,
                                onCategoryTapped: _handleCategoryShortcutTapped,
                                onOpenEqualizer: _handleOpenEqualizerFromTopBar,
                              ),
                              _loadedTabs.contains(1)
                                  ? LotusVaultFoldersScreen(
                                onSongSelected: _handleTrackSelected,
                                onOpenNowPlaying: _openNowPlayingStage,
                              )
                                  : const SizedBox.shrink(),
                              _loadedTabs.contains(2)
                                  ? LotusDspEqualizerScreen(
                                onBack: () => _onTabSelected(0),
                              )
                                  : const SizedBox.shrink(),
                              _loadedTabs.contains(3)
                                  ? LotusPlaylistsUnifiedScreen(
                                onSongSelected: _handleTrackSelected,
                                onOpenNowPlaying: _openNowPlayingStage,
                                onOpenEqualizer:
                                _handleOpenEqualizerFromTopBar,
                              )
                                  : const SizedBox.shrink(),
                              _loadedTabs.contains(4)
                                  ? LotusSettingsScreen(
                                onBack: () => _onTabSelected(0),
                              )
                                  : const SizedBox.shrink(),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            offset: isKeyboardOpen
                                ? const Offset(0, 1.2)
                                : Offset.zero,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              opacity: isKeyboardOpen ? 0.0 : 1.0,
                              child: IgnorePointer(
                                ignoring: isKeyboardOpen,
                                child: RepaintBoundary(
                                  child: _buildBottomInterface(
                                    safeBottomPadding,
                                    activeAccent,
                                    isWhitaniana,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomInterface(
      double safeBottomPadding, Color activeAccent, bool isWhitaniana) {
    final Color containerLow = _theme.containerLowColor;

    final Color solidBarBg = isWhitaniana
        ? LotusColors.whitanianaBottomBarBg
        : (_theme.isAmoled
        ? const Color(0xFF04060A)
        : const Color(0xFF0A0F1D));

    final Color barBorderColor = isWhitaniana
        ? LotusColors.whitanianaBottomBarBorder
        : activeAccent.withValues(alpha: 0.35);

    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListenableBuilder(
            listenable: _playback,
            builder: (BuildContext context, _) {
              final SongModel? activeSong = _playback.activeSong;
              if (activeSong == null) return const SizedBox.shrink();
              return Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _playback.isPlayingNotifier,
                  builder:
                      (BuildContext context, bool isPlaying, Widget? child) {
                    return LotusMagnificentBottomDeck(
                      song: activeSong,
                      isPlaying: isPlaying,
                      currentPositionMs: 0,
                      totalDurationMs: _playback.totalDurationMs,
                      isCollapsed: _isMiniPlayerCollapsed,
                      onToggleCollapse: _toggleMiniPlayerCollapse,
                      onTogglePlay: () => _playback.togglePlayPause(),
                      onSkipNext: () => _playback.skipNext(),
                      onSkipPrevious: () => _playback.skipPrevious(),
                      onTap: _openNowPlayingStage,
                    );
                  },
                ),
              );
            },
          ),
          Container(
            padding: EdgeInsets.only(top: 8, bottom: safeBottomPadding),
            decoration: BoxDecoration(
              color: solidBarBg,
              border: Border(
                top: BorderSide(
                  color: barBorderColor,
                  width: 1.0,
                ),
              ),
              boxShadow: isWhitaniana
                  ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF0E141B).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, -3),
                ),
              ]
                  : <BoxShadow>[
                const BoxShadow(
                  color: Colors.black87,
                  blurRadius: 18,
                  offset: Offset(0, -3),
                ),
                ...LotusDecorations.glowShadow(activeAccent,
                    intensity: 0.16, blur: 16),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                Expanded(
                  child: _buildPngTabItem(
                      0,
                      'assets/icons/home_icon.png',
                      Icons.local_florist_rounded,
                      'HOME',
                      activeAccent,
                      containerLow,
                      isWhitaniana),
                ),
                Expanded(
                  child: _buildPngTabItem(
                      1,
                      'assets/icons/vault_icon.png',
                      Icons.folder_copy_rounded,
                      'VAULT',
                      activeAccent,
                      containerLow,
                      isWhitaniana),
                ),
                Expanded(
                  child: _buildPngTabItem(
                      2,
                      'assets/icons/dsp_icon.png',
                      Icons.tune_rounded,
                      'DSP EQ',
                      activeAccent,
                      containerLow,
                      isWhitaniana),
                ),
                Expanded(
                  child: _buildPngTabItem(
                      3,
                      'assets/icons/mixes_icon.png',
                      Icons.queue_music_rounded,
                      'MIXES',
                      activeAccent,
                      containerLow,
                      isWhitaniana),
                ),
                Expanded(
                  child: _buildPngTabItem(
                      4,
                      'assets/icons/settings_icon.png',
                      Icons.settings_rounded,
                      'SETTINGS',
                      activeAccent,
                      containerLow,
                      isWhitaniana),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPngTabItem(
      int index,
      String assetPath,
      IconData fallbackIcon,
      String label,
      Color activeAccent,
      Color containerLow,
      bool isWhitaniana) {
    final bool isActive = _currentTabIndex == index;

    final Color activeTextColor =
    isWhitaniana ? const Color(0xFF0B0F19) : activeAccent;
    final Color inactiveTextColor =
    isWhitaniana ? const Color(0xFF64748B) : LotusColors.textSecondary;
    final Color textColor = isActive ? activeTextColor : inactiveTextColor;

    return GestureDetector(
      onTap: () => _onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? activeAccent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(
            color: isWhitaniana
                ? activeAccent.withValues(alpha: 0.85)
                : activeAccent.withValues(alpha: 0.45),
            width: 1.1,
          )
              : null,
          boxShadow: isActive && !isWhitaniana
              ? LotusDecorations.glowShadow(activeAccent,
              intensity: 0.22, blur: 12)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 30,
              height: 30,
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) {
                  return Icon(
                    fallbackIcon,
                    color: isActive
                        ? activeAccent
                        : (isWhitaniana
                        ? const Color(0xFF64748B)
                        : LotusColors.textSecondary),
                    size: 26,
                  );
                },
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 9.5,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// MAGNIFICENT AUDIOPHILE BOTTOM PLAYER DECK
// ==============================================================================
class LotusMagnificentBottomDeck extends StatefulWidget {
  final SongModel song;
  final bool isPlaying;
  final int currentPositionMs;
  final int totalDurationMs;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onTogglePlay;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final VoidCallback onTap;

  const LotusMagnificentBottomDeck({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.currentPositionMs,
    required this.totalDurationMs,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.onTogglePlay,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.onTap,
  });

  @override
  State<LotusMagnificentBottomDeck> createState() =>
      _LotusMagnificentBottomDeckState();
}

class _LotusMagnificentBottomDeckState extends State<LotusMagnificentBottomDeck>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final LotusThemeController _theme = LotusThemeController.instance;
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  late final AnimationController _deckPulseController;
  late final AnimationController _waveformController;
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _deckPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOutCubicEmphasized,
      reverseCurve: Curves.easeInOutCubic,
    );

    if (widget.isCollapsed) {
      _flipController.value = 1.0;
    }

    if (widget.isPlaying) {
      _deckPulseController.repeat(reverse: true);
      _waveformController.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isPlaying) {
      if (!_deckPulseController.isAnimating) {
        _deckPulseController.repeat(reverse: true);
      }
      if (!_waveformController.isAnimating) {
        _waveformController.repeat(reverse: true);
      }
    } else {
      if (_deckPulseController.isAnimating) _deckPulseController.stop();
      if (_waveformController.isAnimating) _waveformController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant LotusMagnificentBottomDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCollapsed != oldWidget.isCollapsed) {
      if (widget.isCollapsed) {
        _flipController.forward();
      } else {
        _flipController.reverse();
      }
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_deckPulseController.isAnimating) {
          _deckPulseController.repeat(reverse: true);
        }
        if (!_waveformController.isAnimating) {
          _waveformController.repeat(reverse: true);
        }
      } else {
        if (_deckPulseController.isAnimating) {
          _deckPulseController.stop();
        }
        if (_waveformController.isAnimating) {
          _waveformController.stop();
          _waveformController.value = 0.0;
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flipController.dispose();
    _deckPulseController.dispose();
    _waveformController.dispose();
    super.dispose();
  }

  static String formatDuration(int ms) {
    final int safeMs = ms.clamp(0, 359999999);
    final Duration d = Duration(milliseconds: safeMs);
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleFavoriteTap(BuildContext context, Color secondaryAccent) {
    HapticFeedback.mediumImpact();
    final LotusPlaybackProvider playback = LotusPlaybackProvider.instance;
    final bool nextState = !playback.isFavorite;
    playback.toggleFavorite();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        backgroundColor: _theme.containerHighColor,
        content: Row(
          children: <Widget>[
            Icon(
              nextState
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: secondaryAccent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                nextState
                    ? 'Added "${widget.song.title}" to Favorites Vault'
                    : 'Removed "${widget.song.title}" from Favorites Vault',
                style: TextStyle(
                  color: nextState ? secondaryAccent : LotusColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color accent = _theme.primaryAccent;
    final Color secondaryAccent = _theme.secondaryAccent;
    final LinearGradient activeGradient = _theme.activeGradient;

    final int duration = widget.totalDurationMs > 0
        ? widget.totalDurationMs
        : (widget.song.duration != null && widget.song.duration! > 0
        ? widget.song.duration!
        : 240000);

    final bool isCollapsed = widget.isCollapsed;
    final bool isFav =
    LotusPlaybackProvider.instance.isSongFavorite(widget.song.id);

    final Color solidDeckBg;
    final Color deckBorderColor;
    final List<BoxShadow> deckShadows;

    if (isWhitaniana) {
      solidDeckBg = const Color(0xE00E1217);
      deckBorderColor = widget.isPlaying
          ? LotusColors.whitanianaCyanAccent.withValues(alpha: 0.90)
          : const Color(0x3300C7E6);
      deckShadows = <BoxShadow>[
        BoxShadow(
          color: const Color(0xFF0E141B).withValues(alpha: 0.35),
          blurRadius: 24,
          spreadRadius: 2,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: LotusColors.whitanianaCyanAccent
              .withValues(alpha: widget.isPlaying ? 0.35 : 0.14),
          blurRadius: 18,
        ),
      ];
    } else {
      final bool isSpecialTheme = _theme.isMoodMatrixActive ||
          _theme.isStarryNightActive ||
          _theme.isTransparentPassThrough;
      solidDeckBg = isSpecialTheme
          ? const Color(0xFF070B14)
          : (_theme.isAmoled
          ? const Color(0xFF070B14)
          : _theme.containerLowColor);
      deckBorderColor = widget.isPlaying
          ? accent.withValues(alpha: 0.85)
          : accent.withValues(alpha: 0.45);
      deckShadows = <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.85),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: accent.withValues(alpha: widget.isPlaying ? 0.22 : 0.08),
          blurRadius: 20,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: secondaryAccent
              .withValues(alpha: widget.isPlaying ? 0.18 : 0.05),
          blurRadius: 24,
          spreadRadius: 2,
        ),
      ];
    }

    return Align(
      alignment: isCollapsed ? Alignment.centerRight : Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onToggleCollapse();
            },
            child: CustomPaint(
              painter: _CurvedTabPainter(
                fillColor: solidDeckBg,
                borderColor: isWhitaniana
                    ? LotusColors.whitanianaCyanAccent.withValues(alpha: 0.85)
                    : accent.withValues(alpha: 0.85),
                strokeWidth: 1.4,
                radius: 16.0,
                shadows: LotusDecorations.glowShadow(accent,
                    intensity: 0.28, blur: 14),
              ),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 6.0),
                child: AnimatedBuilder(
                  animation: _flipAnimation,
                  builder: (BuildContext context, Widget? child) {
                    final double flipVal = _flipAnimation.value;
                    final double pillWidth = 24.0 + (flipVal * 10.0);

                    return Container(
                      width: pillWidth,
                      height: 3.5,
                      decoration: BoxDecoration(
                        gradient: activeGradient,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: LotusDecorations.glowShadow(
                          accent,
                          intensity: flipVal > 0.5 ? 0.75 : 0.50,
                          blur: flipVal > 0.5 ? 10 : 6,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _flipAnimation,
            builder: (BuildContext context, Widget? child) {
              final double flipVal = _flipAnimation.value;
              if (flipVal >= 1.0) {
                return const SizedBox(height: 0, width: double.infinity);
              }

              final double angle = flipVal * (math.pi / 2.2);
              final double scale = 1.0 - (flipVal * 0.12);
              final double opacity = (1.0 - (flipVal * 1.4)).clamp(0.0, 1.0);

              return Opacity(
                opacity: opacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: deckShadows,
                  ),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0016)
                      ..rotateX(-angle)
                      ..scaleByDouble(scale, scale, 1.0, 1.0),
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: (1.0 - flipVal).clamp(0.0, 1.0),
                        child: child,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                margin:
                const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                decoration: BoxDecoration(
                  color: solidDeckBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: deckBorderColor,
                    width: 1.4,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _buildTurntableCircularArtwork(
                            accent, secondaryAccent, isWhitaniana),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      widget.song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.0,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildLiveWaveform(
                                      accent, secondaryAccent, isWhitaniana),
                                ],
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isWhitaniana
                                            ? LotusColors.whitanianaCyanAccent
                                            .withValues(alpha: 0.22)
                                            : accent.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isWhitaniana
                                              ? LotusColors
                                              .whitanianaCyanAccent
                                              : accent.withValues(alpha: 0.6),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        widget.song.fileExtension.isNotEmpty
                                            ? widget.song.fileExtension
                                            .toUpperCase()
                                            : (isWhitaniana
                                            ? 'DSD 96K'
                                            : 'DSD512'),
                                        style: TextStyle(
                                          color: isWhitaniana
                                              ? LotusColors
                                              .whitanianaCyanAccent
                                              : accent,
                                          fontSize: 8.0,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'monospace',
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    ValueListenableBuilder<int>(
                                      valueListenable:
                                      _playback.positionNotifier,
                                      builder: (BuildContext context, int posMs,
                                          Widget? child) {
                                        return Text(
                                          '${formatDuration(posMs)} / ${formatDuration(duration)}',
                                          style: TextStyle(
                                            color: isWhitaniana
                                                ? LotusColors
                                                .whitanianaCyanAccent
                                                : secondaryAccent,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
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
                              onTap: () =>
                                  _handleFavoriteTap(context, secondaryAccent),
                              child: Container(
                                padding: const EdgeInsets.all(6.0),
                                decoration: BoxDecoration(
                                  color: isFav
                                      ? secondaryAccent.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isFav
                                        ? secondaryAccent
                                        : Colors.white24,
                                    width: 1.0,
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
                            const SizedBox(width: 4),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onSkipPrevious();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white24, width: 1.0),
                                ),
                                child: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.heavyImpact();
                                widget.onTogglePlay();
                              },
                              child: AnimatedBuilder(
                                animation: _deckPulseController,
                                builder: (BuildContext context, Widget? child) {
                                  final double p = widget.isPlaying
                                      ? _deckPulseController.value
                                      : 0.0;
                                  return Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: activeGradient,
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: secondaryAccent.withValues(
                                              alpha: 0.40 + (0.35 * p)),
                                          blurRadius: 14 + (6 * p),
                                          spreadRadius: 1.5 + (1.5 * p),
                                        ),
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.35),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      widget.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 22,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 5),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onSkipNext();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white24, width: 1.0),
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
                    ValueListenableBuilder<int>(
                      valueListenable: _playback.positionNotifier,
                      builder:
                          (BuildContext context, int posMs, Widget? child) {
                        final double ratio = duration > 0
                            ? (posMs / duration).clamp(0.0, 1.0)
                            : 0.0;
                        return _buildLaserScrubber(
                            ratio, accent, secondaryAccent, activeGradient);
                      },
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

  Widget _buildTurntableCircularArtwork(
      Color accent, Color secondaryAccent, bool isWhitaniana) {
    const double diameter = 46.0;

    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _deckPulseController,
            builder: (BuildContext context, Widget? child) {
              final double p =
              widget.isPlaying ? _deckPulseController.value : 0.0;
              return Container(
                width: diameter + 4,
                height: diameter + 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color:
                      secondaryAccent.withValues(alpha: 0.35 + (0.35 * p)),
                      blurRadius: 12 + (8 * p),
                      spreadRadius: 1.5 + (2 * p),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 10,
                    ),
                  ],
                ),
              );
            },
          ),
          Container(
            width: diameter + 2,
            height: diameter + 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isWhitaniana
                    ? LotusColors.whitanianaChromeBorder
                    : Colors.white24,
                width: 1.0,
              ),
            ),
          ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: isWhitaniana
                      ? LotusColors.whitanianaCyanAccent
                      : accent,
                  width: 1.6),
            ),
            child: ClipOval(
              child: LotusArtworkImage(
                songId: widget.song.id,
                size: diameter,
                borderRadius: diameter / 2,
                keepOldArtwork: true,
                nullArtworkWidget: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: <Color>[
                        accent.withValues(alpha: 0.35),
                        _theme.containerLowestColor,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/icons/now_playing_icon.png',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (BuildContext context, Object error,
                          StackTrace? stackTrace) {
                        return Icon(Icons.music_note_rounded,
                            color: accent, size: 22);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveWaveform(
      Color accent, Color secondaryAccent, bool isWhitaniana) {
    return AnimatedBuilder(
      animation: _waveformController,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List<Widget>.generate(4, (int index) {
            final double factor = widget.isPlaying
                ? ((_waveformController.value + (index * 0.28)) % 1.0)
                : 0.2;
            final double barHeight = 4.0 + (9.0 * factor);
            final Color barColor = index % 2 == 0
                ? (isWhitaniana ? LotusColors.whitanianaCyanAccent : accent)
                : secondaryAccent;

            return Container(
              width: 2.5,
              height: barHeight,
              margin: const EdgeInsets.only(left: 2.0),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(1.5),
                boxShadow: widget.isPlaying
                    ? <BoxShadow>[
                  BoxShadow(
                    color: barColor.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ]
                    : null,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildLaserScrubber(double progress, Color accent,
      Color secondaryAccent, LinearGradient activeGradient) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double trackWidth = constraints.maxWidth;
          final double thumbLeft =
          ((trackWidth - 10.0) * progress.clamp(0.0, 1.0))
              .clamp(0.0, trackWidth - 10.0);

          return Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              Container(
                height: 3.5,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 3.5,
                  decoration: BoxDecoration(
                    gradient: activeGradient,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: LotusDecorations.glowShadow(accent,
                        intensity: 0.5, blur: 6),
                  ),
                ),
              ),
              Positioned(
                left: thumbLeft,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 1.5),
                    boxShadow: <BoxShadow>[
                      const BoxShadow(
                        color: Colors.white,
                        blurRadius: 6,
                      ),
                      BoxShadow(
                        color: accent.withValues(alpha: 0.8),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==============================================================================
// PERFECT ARCH TAB PAINTER
// ==============================================================================
class _CurvedTabPainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final double strokeWidth;
  final double radius;
  final List<BoxShadow>? shadows;

  const _CurvedTabPainter({
    required this.fillColor,
    required this.borderColor,
    this.strokeWidth = 1.4,
    this.radius = 16.0,
    this.shadows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double r = radius;
    final double halfStroke = strokeWidth / 2.0;

    final Path fillPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r))
      ..lineTo(size.width, size.height)
      ..close();

    if (shadows != null) {
      for (final BoxShadow s in shadows!) {
        final Paint shadowPaint = s.toPaint();
        final Path shadowPath = fillPath.shift(s.offset);
        canvas.drawPath(shadowPath, shadowPaint);
      }
    }

    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final Path strokePath = Path()
      ..moveTo(halfStroke, size.height)
      ..lineTo(halfStroke, r)
      ..arcToPoint(
        Offset(r, halfStroke),
        radius: Radius.circular(r - halfStroke),
      )
      ..lineTo(size.width - r, halfStroke)
      ..arcToPoint(
        Offset(size.width - halfStroke, r),
        radius: Radius.circular(r - halfStroke),
      )
      ..lineTo(size.width - halfStroke, size.height);

    final Paint strokePaint = Paint()
      ..color = borderColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    canvas.drawPath(strokePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedTabPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}