import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_equalizer_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_mood_matrix_backdrop.dart';
import '../../core/widgets/lotus_starry_night_backdrop.dart';
import '../equalizer/lotus_dsp_equalizer_screen.dart';
import '../lyrics/lotus_lyrics_stage_screen.dart';
import '../metadata/lotus_song_tag_editor_sheet.dart';
import '../options/lotus_track_options_sheet.dart';
import '../playlists/lotus_add_to_playlist_dialog.dart';

class LotusNowPlayingScreen extends StatefulWidget {
  final SongModel song;
  final VoidCallback? onBack;

  const LotusNowPlayingScreen({
    super.key,
    required this.song,
    this.onBack,
  });

  @override
  State<LotusNowPlayingScreen> createState() => _LotusNowPlayingScreenState();
}

class _LotusNowPlayingScreenState extends State<LotusNowPlayingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final LotusEqualizerService _eqService = LotusEqualizerService.instance;
  final LotusThemeController _theme = LotusThemeController.instance;

  late final AnimationController _pulseController;
  late final AnimationController _haloController;

  final ValueNotifier<double> _dragNotifier = ValueNotifier<double>(-1.0);

  bool _isLyricsMode = false;
  bool _hasMountedLyricsStage = false;
  int _lastSongId = -1;
  int _lastMetadataRevision = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastSongId = _playback.activeSong?.id ?? widget.song.id;
    _lastMetadataRevision = _playback.songMetadataRevisionNotifier.value;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );

    _syncAnimationState();

    _playback.addListener(_onPlaybackStateChanged);
    _playback.songMetadataRevisionNotifier.addListener(_onSongMetadataChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAnimationState();
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
      if (_haloController.isAnimating) _haloController.stop();
    }
  }

  void _syncAnimationState() {
    if (_playback.isPlaying) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      if (!_haloController.isAnimating) {
        _haloController.repeat();
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
      if (_haloController.isAnimating) {
        _haloController.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback.removeListener(_onPlaybackStateChanged);
    _playback.songMetadataRevisionNotifier
        .removeListener(_onSongMetadataChanged);
    _pulseController.dispose();
    _haloController.dispose();
    _dragNotifier.dispose();
    super.dispose();
  }

  void _onSongMetadataChanged() {
    if (!mounted) return;
    _lastMetadataRevision = _playback.songMetadataRevisionNotifier.value;
    setState(() {});
  }

  void _onPlaybackStateChanged() {
    _syncAnimationState();

    final int currentId = _playback.activeSong?.id ?? -1;
    final int currentRev = _playback.songMetadataRevisionNotifier.value;
    if (currentId != _lastSongId || currentRev != _lastMetadataRevision) {
      _lastSongId = currentId;
      _lastMetadataRevision = currentRev;
      _dragNotifier.value = -1.0;
      if (mounted) setState(() {});
    }
  }

  void _handleBackAction() {
    HapticFeedback.lightImpact();
    if (_isLyricsMode) {
      setState(() => _isLyricsMode = false);
      return;
    }

    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _togglePlayPause() {
    HapticFeedback.heavyImpact();
    _playback.togglePlayPause();
  }

  void _handleFavoriteSingleTap() {
    HapticFeedback.selectionClick();
    _playback.toggleFavorite();
  }

  void _handleFavoriteLongPress() {
    HapticFeedback.heavyImpact();
    final SongModel active = _playback.activeSong ?? widget.song;
    LotusAddToPlaylistDialog.show(
      context,
      song: active,
    );
  }

  void _toggleShuffle() {
    HapticFeedback.lightImpact();
    _playback.toggleShuffle();
  }

  void _cycleRepeatMode() {
    HapticFeedback.lightImpact();
    _playback.toggleRepeatMode();
  }

  void _handleTrackDeleted(SongModel deletedSong) {
    HapticFeedback.mediumImpact();
    if (_playback.currentQueue.isEmpty ||
        (_playback.currentQueue.length == 1 &&
            _playback.currentQueue.first.id == deletedSong.id)) {
      if (mounted) {
        if (widget.onBack != null) {
          widget.onBack!();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } else {
      if (mounted) setState(() {});
    }
  }

  void _openTrackOptionsMenu() {
    HapticFeedback.mediumImpact();
    final SongModel active = _playback.activeSong ?? widget.song;
    LotusTrackOptionsSheet.show(
      context,
      song: active,
      onOpenTagEditor: _openSongTagEditor,
      onOpenPlaylistDialog: _handleFavoriteLongPress,
      onTrackDeleted: _handleTrackDeleted,
    );
  }

  void _openSongTagEditor() {
    HapticFeedback.mediumImpact();
    final SongModel active = _playback.activeSong ?? widget.song;
    LotusSongTagEditorSheet.show(
      context,
      song: active,
      onTagsUpdated: (_) {
        if (mounted) setState(() {});
      },
    );
  }

  void _openEqualizerScreen() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LotusDspEqualizerScreen(),
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final Duration d = Duration(milliseconds: milliseconds);
    final int min = d.inMinutes;
    final int sec = d.inSeconds.remainder(60);
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final bool isWhitaniana = _theme.isWhitanianaActive;
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final LinearGradient gradient = _theme.activeGradient;

        final Color effectiveBgColor = isWhitaniana
            ? LotusColors.whitanianaPureWhite
            : _theme.backgroundColor;

        final Color textPrimary =
        isWhitaniana ? LotusColors.whitanianaTextPrimary : Colors.white;

        final Color textSecondary = isWhitaniana
            ? LotusColors.whitanianaTextSecondary
            : LotusColors.textSecondary;

        final Color textTertiary = isWhitaniana
            ? LotusColors.whitanianaTextTertiary
            : LotusColors.textTertiary;

        final Color cardBackground = isWhitaniana
            ? LotusColors.whitanianaPureWhiteCard
            : _theme.modalContainerLowColor;

        final Color cardBorder = isWhitaniana
            ? LotusColors.whitanianaCardBorder
            : LotusColors.glassBorder;

        final Color fallbackBgColor = isWhitaniana
            ? const Color(0xFF0E1217)
            : _theme.containerLowestColor;

        final SongModel currentSong = _playback.activeSong ?? widget.song;
        final int totalMs = _playback.totalDurationMs > 0
            ? _playback.totalDurationMs
            : (currentSong.duration ?? 240000);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
            isWhitaniana ? Brightness.dark : Brightness.light,
            statusBarBrightness:
            isWhitaniana ? Brightness.dark : Brightness.light,
            systemNavigationBarColor:
            isWhitaniana ? Colors.white : Colors.black,
            systemNavigationBarIconBrightness:
            isWhitaniana ? Brightness.dark : Brightness.light,
            systemNavigationBarDividerColor: isWhitaniana
                ? LotusColors.whitanianaCardBorder
                : Colors.transparent,
          ),
          child: PopScope(
            canPop: !_isLyricsMode,
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              if (didPop) return;

              if (_isLyricsMode) {
                HapticFeedback.lightImpact();
                setState(() => _isLyricsMode = false);
              }
            },
            child: LotusStarryNightBackdrop(
              child: LotusMoodMatrixBackdrop(
                child: Scaffold(
                  backgroundColor: effectiveBgColor,
                  body: SafeArea(
                    child: Column(
                      children: <Widget>[
                        _buildTopAppBar(
                          currentSong,
                          accent,
                          textPrimary,
                          textSecondary,
                          cardBackground,
                          cardBorder,
                          isWhitaniana,
                        ),
                        _buildStageModeSwitch(
                          accent,
                          secondaryAccent,
                          cardBackground,
                          cardBorder,
                          isWhitaniana,
                        ),
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              Offstage(
                                offstage: _isLyricsMode,
                                child: TickerMode(
                                  enabled: !_isLyricsMode,
                                  child: Column(
                                    children: <Widget>[
                                      Expanded(
                                        child: _buildAlbumArtworkStage(
                                          currentSong,
                                          accent,
                                          secondaryAccent,
                                          fallbackBgColor,
                                          isWhitaniana,
                                        ),
                                      ),
                                      _buildTrackInfoAndActions(
                                        currentSong,
                                        accent,
                                        secondaryAccent,
                                        textPrimary,
                                        textSecondary,
                                        cardBackground,
                                        cardBorder,
                                        isWhitaniana,
                                      ),
                                      _buildScrubberDeck(
                                        totalMs,
                                        accent,
                                        textTertiary,
                                        cardBackground,
                                        cardBorder,
                                        isWhitaniana,
                                      ),
                                      _buildPlaybackControls(
                                        accent,
                                        secondaryAccent,
                                        gradient,
                                        textPrimary,
                                        textTertiary,
                                        isWhitaniana,
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                  ),
                                ),
                              ),
                              if (_hasMountedLyricsStage)
                                Offstage(
                                  offstage: !_isLyricsMode,
                                  child: TickerMode(
                                    enabled: _isLyricsMode,
                                    child: LotusLyricsStageScreen(
                                      song: currentSong,
                                      onSeek: (Duration p) => _playback.seek(p),
                                      onBack: () =>
                                          setState(() => _isLyricsMode = false),
                                    ),
                                  ),
                                ),
                            ],
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

  Widget _buildTopAppBar(
      SongModel currentSong,
      Color accent,
      Color textPrimary,
      Color textSecondary,
      Color cardBackground,
      Color cardBorder,
      bool isWhitaniana,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: 'Back to Library',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleBackAction,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isWhitaniana
                          ? const Color(0xFFF1F5F9)
                          : cardBackground,
                      border: Border.all(
                        color: isWhitaniana
                            ? LotusColors.whitanianaCyanAccent
                            : accent,
                        width: 1.8,
                      ),
                      boxShadow: isWhitaniana
                          ? <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFF0E141B)
                              .withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                        ...LotusDecorations.glowShadow(
                          accent,
                          intensity: 0.22,
                          blur: 12,
                        ),
                      ]
                          : LotusDecorations.glowShadow(
                        accent,
                        intensity: 0.35,
                        blur: 16,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icons/now_playing_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                            ) {
                          return Center(
                            child: Icon(
                              Icons.local_florist_rounded,
                              color: accent,
                              size: 28,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: isWhitaniana
                            ? const Color(0xFF0B0F19)
                            : Colors.black.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isWhitaniana
                              ? LotusColors.whitanianaCyanAccent
                              : accent,
                          width: 1.0,
                        ),
                        boxShadow: LotusDecorations.glowShadow(
                          accent,
                          intensity: 0.25,
                          blur: 6,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _isLyricsMode ? 'Synchronized Lyrics' : 'Now Playing Stage',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Container(
                      width: 5.5,
                      height: 5.5,
                      decoration: BoxDecoration(
                        color: isWhitaniana
                            ? LotusColors.whitanianaCyanAccent
                            : accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        'LOTUS BIT-PERFECT DAC ENGINE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isWhitaniana
                              ? const Color(0xFF0369A1)
                              : accent,
                          fontSize: 9.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _eqService,
            builder: (BuildContext context, _) {
              final bool eqOn = _eqService.isEnabled;
              return GestureDetector(
                onTap: _openEqualizerScreen,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: eqOn
                        ? accent.withValues(alpha: isWhitaniana ? 0.16 : 0.18)
                        : (isWhitaniana
                        ? const Color(0xFFF1F5F9)
                        : cardBackground),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: eqOn ? accent : cardBorder,
                      width: 1.0,
                    ),
                    boxShadow: isWhitaniana
                        ? LotusDecorations.whitanianaCardShadow()
                        : null,
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: eqOn
                        ? (isWhitaniana ? const Color(0xFF0284C7) : accent)
                        : textSecondary,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStageModeSwitch(
      Color accent,
      Color secondaryAccent,
      Color cardBackground,
      Color cardBorder,
      bool isWhitaniana,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 6.0),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          color: isWhitaniana ? _theme.containerColor : cardBackground,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isWhitaniana ? _theme.cardBorderColor : cardBorder,
            width: 1.0,
          ),
          boxShadow:
          isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_isLyricsMode) {
                    HapticFeedback.selectionClick();
                    setState(() => _isLyricsMode = false);
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: !_isLyricsMode
                        ? (isWhitaniana
                        ? LotusColors.whitanianaCyanAccent
                        : accent)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      'ALBUM ART',
                      style: TextStyle(
                        color: !_isLyricsMode
                            ? Colors.white
                            : (isWhitaniana
                            ? _theme.textSecondaryColor
                            : Colors.white70),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (!_isLyricsMode) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _hasMountedLyricsStage = true;
                      _isLyricsMode = true;
                    });
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _isLyricsMode
                        ? (isWhitaniana
                        ? LotusColors.whitanianaCyanAccent
                        : secondaryAccent.withValues(alpha: 0.25))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: _isLyricsMode && !isWhitaniana
                        ? Border.all(color: secondaryAccent, width: 1.0)
                        : null,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          'LYRICS',
                          style: TextStyle(
                            color: _isLyricsMode
                                ? Colors.white
                                : (isWhitaniana
                                ? _theme.textSecondaryColor
                                : Colors.white70),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 4.5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isWhitaniana
                                ? const Color(0xFF0CD494)
                                : secondaryAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumArtworkStage(
      SongModel currentSong,
      Color accent,
      Color secondaryAccent,
      Color fallbackBgColor,
      bool isWhitaniana,
      ) {
    final String extension = currentSong.fileExtension.isNotEmpty
        ? currentSong.fileExtension.toUpperCase()
        : 'MP3';

    const double stageDiameter = 260.0;

    return Center(
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _haloController,
                builder: (BuildContext context, Widget? child) {
                  return Transform.rotate(
                    angle: _haloController.value * 2 * math.pi,
                    child: child,
                  );
                },
                child: Container(
                  width: 294,
                  height: 294,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isWhitaniana
                          ? LotusColors.whitanianaChromeBorder
                          : Colors.white.withValues(alpha: 0.08),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (BuildContext context, Widget? child) {
                  final double p = _pulseController.value;
                  return Transform.scale(
                    scale: 1.0 + (0.05 * p),
                    child: Opacity(
                      opacity: 0.72 + (0.28 * p),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: stageDiameter,
                  height: stageDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: secondaryAccent.withValues(
                          alpha: isWhitaniana ? 0.30 : 0.48,
                        ),
                        blurRadius: 24,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: accent.withValues(
                          alpha: isWhitaniana ? 0.22 : 0.30,
                        ),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: stageDiameter,
              height: stageDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0E1217),
                border: Border.all(
                  color: isWhitaniana
                      ? LotusColors.whitanianaCyanAccent
                      : accent.withValues(alpha: 0.8),
                  width: 2.2,
                ),
                boxShadow: isWhitaniana
                    ? <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF0E141B)
                        .withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: LotusColors.whitanianaCyanAccent
                        .withValues(alpha: 0.25),
                    blurRadius: 18,
                  ),
                ]
                    : const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x77000000),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    LotusArtworkImage(
                      songId: currentSong.id,
                      size: stageDiameter,
                      borderRadius: stageDiameter / 2,
                      keepOldArtwork: true,
                      nullArtworkWidget: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: <Color>[
                              accent.withValues(alpha: 0.35),
                              fallbackBgColor,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/icons/now_playing_icon.png',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: GestureDetector(
                        onTap: _openEqualizerScreen,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isWhitaniana
                                  ? LotusColors.whitanianaCyanAccent
                                  : accent.withValues(alpha: 0.5),
                              width: 1.0,
                            ),
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: isWhitaniana
                                ? LotusColors.whitanianaCyanAccent
                                : accent,
                            size: 15,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ListenableBuilder(
                          listenable: _eqService,
                          builder: (BuildContext context, _) {
                            final bool eqOn = _eqService.isEnabled;
                            final String tuningBadge =
                            eqOn ? 'HIGH PRECISION DSP' : 'BIT-PERFECT';
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isWhitaniana
                                      ? LotusColors.whitanianaCyanAccent
                                      : accent.withValues(alpha: 0.6),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  CircleAvatar(
                                    radius: 3,
                                    backgroundColor: eqOn
                                        ? (isWhitaniana
                                        ? LotusColors.whitanianaCyanAccent
                                        : accent)
                                        : LotusColors.textTertiary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$extension • $tuningBadge',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackInfoAndActions(
      SongModel currentSong,
      Color accent,
      Color secondaryAccent,
      Color textPrimary,
      Color textSecondary,
      Color cardBackground,
      Color cardBorder,
      bool isWhitaniana,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            currentSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isWhitaniana
                                ? const Color(0xFF00E5FF)
                                .withValues(alpha: 0.16)
                                : accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isWhitaniana
                                  ? const Color(0xFF00E5FF)
                                  : accent,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'MASTER',
                            style: TextStyle(
                              color: isWhitaniana
                                  ? const Color(0xFF0284C7)
                                  : accent,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${currentSong.artist ?? "Lotus Sanctuary"} • ${currentSong.album ?? "Lotus Vault"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: _playback,
                builder: (BuildContext context, _) {
                  final bool isFav = _playback.isFavorite;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleFavoriteSingleTap,
                    onLongPress: _handleFavoriteLongPress,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isFav
                            ? secondaryAccent.withValues(
                          alpha: isWhitaniana ? 0.18 : 0.22,
                        )
                            : (isWhitaniana
                            ? const Color(0xFFF1F5F9)
                            : cardBackground),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isFav
                              ? secondaryAccent
                              : (isWhitaniana ? cardBorder : Colors.white24),
                          width: isFav ? 1.5 : 1.0,
                        ),
                        boxShadow: isFav
                            ? LotusDecorations.glowShadow(
                          secondaryAccent,
                          intensity: 0.35,
                          blur: 14,
                        )
                            : (isWhitaniana
                            ? LotusDecorations.whitanianaCardShadow()
                            : null),
                      ),
                      child: Icon(
                        isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFav
                            ? secondaryAccent
                            : (isWhitaniana
                            ? const Color(0xFF0B0F19)
                            : Colors.white.withValues(alpha: 0.85)),
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color:
                  isWhitaniana ? textSecondary : LotusColors.textSecondary,
                  size: 22,
                ),
                onPressed: _openTrackOptionsMenu,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isWhitaniana ? _theme.containerColor : cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isWhitaniana ? _theme.cardBorderColor : cardBorder,
              ),
              boxShadow: isWhitaniana
                  ? LotusDecorations.whitanianaCardShadow()
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.touch_app_rounded,
                  color: isWhitaniana
                      ? LotusColors.whitanianaCyanAccent
                      : accent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap: Toggle Favorite  |  Long-Press: Route to Playlists',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isWhitaniana
                          ? _theme.textPrimaryColor
                          : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _handleFavoriteLongPress,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isWhitaniana
                          ? LotusColors.whitanianaCyanAccent
                          : secondaryAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'TRY',
                      style: TextStyle(
                        color: isWhitaniana ? Colors.white : Colors.black,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrubberDeck(
      int totalMs,
      Color accent,
      Color textTertiary,
      Color cardBackground,
      Color cardBorder,
      bool isWhitaniana,
      ) {
    final double safeTotal = totalMs > 0 ? totalMs.toDouble() : 1.0;

    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: _playback.positionNotifier,
        builder: (BuildContext context, int playbackPosMs, Widget? child) {
          return ValueListenableBuilder<double>(
            valueListenable: _dragNotifier,
            builder: (BuildContext context, double dragPos, Widget? child) {
              final int displayPosMs =
              dragPos >= 0 ? dragPos.toInt() : playbackPosMs;
              final double safePos =
              displayPosMs.toDouble().clamp(0.0, safeTotal);

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 4.0,
                ),
                child: Column(
                  children: <Widget>[
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: isWhitaniana
                            ? LotusColors.whitanianaCyanAccent
                            : accent,
                        inactiveTrackColor: isWhitaniana
                            ? const Color(0xFFCBD5E1)
                            : Colors.white12,
                        thumbColor: isWhitaniana
                            ? LotusColors.whitanianaCyanAccent
                            : Colors.white,
                        overlayColor: accent.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: safePos,
                        min: 0.0,
                        max: safeTotal,
                        onChanged: (double val) {
                          _dragNotifier.value = val;
                        },
                        onChangeEnd: (double val) {
                          _dragNotifier.value = -1.0;
                          _playback.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            _formatDuration(displayPosMs),
                            style: TextStyle(
                              color: isWhitaniana
                                  ? const Color(0xFF0369A1)
                                  : accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Flexible(
                            fit: FlexFit.loose,
                            child: ListenableBuilder(
                              listenable: _eqService,
                              builder: (BuildContext context, _) {
                                final bool eqOn = _eqService.isEnabled;
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isWhitaniana
                                        ? const Color(0xFFF1F5F9)
                                        : cardBackground,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.settings_input_component_rounded,
                                        size: 11,
                                        color: eqOn
                                            ? (isWhitaniana
                                            ? const Color(0xFF059669)
                                            : LotusColors.voltLime)
                                            : textTertiary,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          eqOn
                                              ? 'DSP DIRECT BIT-STREAM'
                                              : 'DIRECT PASSTHROUGH',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isWhitaniana
                                                ? const Color(0xFF0B0F19)
                                                : (eqOn
                                                ? LotusColors.voltLime
                                                : LotusColors.textTertiary),
                                            fontSize: 9.0,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          Text(
                            '-${_formatDuration((totalMs - displayPosMs).clamp(0, totalMs))}',
                            style: TextStyle(
                              color: textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPlaybackControls(
      Color accent,
      Color secondaryAccent,
      LinearGradient gradient,
      Color textPrimary,
      Color textTertiary,
      bool isWhitaniana,
      ) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            ValueListenableBuilder<bool>(
              valueListenable: _playback.shuffleNotifier,
              builder: (BuildContext context, bool isShuffle, _) {
                return IconButton(
                  icon: Icon(
                    Icons.shuffle_rounded,
                    color: isShuffle
                        ? (isWhitaniana
                        ? LotusColors.whitanianaCyanAccent
                        : accent)
                        : textTertiary,
                    size: 22,
                  ),
                  onPressed: _toggleShuffle,
                );
              },
            ),
            IconButton(
              icon: Icon(
                Icons.skip_previous_rounded,
                color: textPrimary,
                size: 34,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                _playback.skipPrevious();
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _playback.isPlayingNotifier,
              builder: (BuildContext context, bool isPlaying, _) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradient,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: (isWhitaniana
                              ? LotusColors.whitanianaCyanAccent
                              : accent)
                              .withValues(alpha: isWhitaniana ? 0.45 : 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: isWhitaniana ? Colors.white : Colors.black,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(
                Icons.skip_next_rounded,
                color: textPrimary,
                size: 34,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                _playback.skipNext();
              },
            ),
            ValueListenableBuilder<LotusRepeatMode>(
              valueListenable: _playback.repeatModeNotifier,
              builder: (BuildContext context, LotusRepeatMode loopMode, _) {
                return IconButton(
                  icon: Icon(
                    loopMode == LotusRepeatMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: loopMode != LotusRepeatMode.off
                        ? secondaryAccent
                        : textTertiary,
                    size: 22,
                  ),
                  onPressed: _cycleRepeatMode,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}