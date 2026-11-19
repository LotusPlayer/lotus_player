import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_lyrics_scraper_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_widgets.dart';
import 'lotus_lyrics_sync_dialog.dart';

class LotusLyricsStageScreen extends StatefulWidget {
  final SongModel song;
  final Duration currentPosition;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onBack;

  const LotusLyricsStageScreen({
    super.key,
    required this.song,
    this.currentPosition = Duration.zero,
    this.onSeek,
    this.onBack,
  });

  @override
  State<LotusLyricsStageScreen> createState() => _LotusLyricsStageScreenState();
}

class _LotusLyricsStageScreenState extends State<LotusLyricsStageScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final LotusLyricsScraperService _scraperService = LotusLyricsScraperService();
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final LotusThemeController _theme = LotusThemeController.instance;
  final ScrollController _lyricsScrollController = ScrollController();

  static const String _kAutoScrollKey = 'lotus_lyrics_auto_scroll_enabled';

  LotusLyricsDocument? _lyricsDocument;
  bool _isLoadingLyrics = true;
  bool _autoScrollEnabled = true;
  bool _prefsLoaded = false;
  double _fontSize = 16.0;
  int _activeLineIndex = -1;
  int _timeOffsetMs = 0;

  Timer? _userScrollResumeTimer;
  bool _isUserDragging = false;
  int _lastAutoScrollTimestampMs = 0;

  late final AnimationController _glowController;

  @override
  bool get wantKeepAlive => true;

  double get _effectiveItemHeight {
    final bool hasSubtitles = _lyricsDocument?.lines.any((LotusLyricLine l) =>
    l.phoneticRomanized != null || l.translationEnglish != null) ??
        false;
    double height = 94.0;
    if (_fontSize > 16.0) height += 20.0;
    if (_fontSize < 15.0) height -= 10.0;
    if (hasSubtitles) height += 22.0;
    return height;
  }

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _playback.positionNotifier.addListener(_onPositionNotifierTick);
    _theme.addListener(_onThemeTick);
    _initStage();
  }

  Future<void> _initStage() async {
    await _loadAutoScrollPreference();
    _prefsLoaded = true;
    await _loadLyricsWithPersistence();
  }

  Future<void> _loadAutoScrollPreference() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool? savedVal = prefs.getBool(_kAutoScrollKey);
      if (savedVal != null && mounted) {
        setState(() => _autoScrollEnabled = savedVal);
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant LotusLyricsStageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _loadLyricsWithPersistence();
    } else if (widget.currentPosition != oldWidget.currentPosition &&
        widget.currentPosition != Duration.zero) {
      _calculateActiveLine(widget.currentPosition);
    }
  }

  @override
  void dispose() {
    _userScrollResumeTimer?.cancel();
    _playback.positionNotifier.removeListener(_onPositionNotifierTick);
    _theme.removeListener(_onThemeTick);
    _glowController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _onThemeTick() {
    if (mounted) setState(() {});
  }

  void _onPositionNotifierTick() {
    if (!mounted) return;
    final int currentMs = _playback.positionNotifier.value;
    _calculateActiveLine(Duration(milliseconds: currentMs));
  }

  Future<void> _loadLyricsWithPersistence(
      {bool ignoreCustomDiskCache = false}) async {
    if (!mounted) return;
    setState(() => _isLoadingLyrics = true);

    int savedOffsetMs = 0;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      savedOffsetMs = prefs.getInt('lyrics_offset_${widget.song.id}') ?? 0;

      if (!ignoreCustomDiskCache) {
        final String? savedRaw = prefs
            .getString('custom_lyrics_${widget.song.id}') ??
            prefs.getString(
                'custom_lyrics_title_${widget.song.title.trim().toLowerCase()}');

        if (savedRaw != null && savedRaw.trim().isNotEmpty) {
          final LotusLyricsDocument doc = _parseUniversalLyricsContent(
            savedRaw,
            song: widget.song,
            source: 'Saved Custom Lyrics',
          );

          if (mounted) {
            setState(() {
              _lyricsDocument = doc;
              _timeOffsetMs = savedOffsetMs;
              _isLoadingLyrics = false;
              _activeLineIndex = -1;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _calculateActiveLine(
                Duration(milliseconds: _playback.currentPositionMs),
                forceScroll: _autoScrollEnabled,
              );
            });
            return;
          }
        }
      }
    } catch (_) {}

    final LotusLyricsDocument doc =
    await _scraperService.fetchLyricsForSong(widget.song);

    if (mounted) {
      setState(() {
        _lyricsDocument = doc;
        _timeOffsetMs = savedOffsetMs;
        _isLoadingLyrics = false;
        _activeLineIndex = -1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateActiveLine(
          Duration(milliseconds: _playback.currentPositionMs),
          forceScroll: _autoScrollEnabled,
        );
      });
    }
  }

  Future<void> _handleForceReFetch() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoadingLyrics = true);

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('custom_lyrics_${widget.song.id}');
      await prefs.remove(
          'custom_lyrics_title_${widget.song.title.trim().toLowerCase()}');
    } catch (_) {}

    await _loadLyricsWithPersistence(ignoreCustomDiskCache: true);

    if (mounted) {
      final int count = _lyricsDocument?.lines.length ?? 0;
      final String src = _lyricsDocument?.source ?? 'Search Database';
      final Color accent = _theme.primaryAccent;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2000),
          backgroundColor: _theme.containerHighColor,
          content: Row(
            children: <Widget>[
              Icon(Icons.refresh_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 0
                      ? 'Re-fetch complete: $count lines synced from $src.'
                      : 'Re-fetch complete: No online lyrics matched. Tap "Search Google" below.',
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  static LotusLyricsDocument _parseUniversalLyricsContent(
      String rawText, {
        required SongModel song,
        String source = 'Custom Saved Lyrics',
      }) {
    final String trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return LotusLyricsDocument(
        title: song.title,
        artist: song.artist ?? '',
        album: song.album ?? '',
        source: source,
        lines: <LotusLyricLine>[],
      );
    }

    final bool hasTimestamps = RegExp(r'\[\d{1,2}:\d{2}').hasMatch(trimmed);

    if (hasTimestamps) {
      return LotusLyricsScraperService.parseLrcContent(
        trimmed,
        song: song,
        source: source,
      );
    }

    final List<String> rawLines = trimmed
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();

    final int totalDurationMs =
    (song.duration != null && song.duration! > 0) ? song.duration! : 240000;

    final List<LotusLyricLine> timedLines = <LotusLyricLine>[];

    if (rawLines.isNotEmpty) {
      final double intervalMs = totalDurationMs / (rawLines.length + 1);
      for (int i = 0; i < rawLines.length; i++) {
        final int lineMs = ((i + 1) * intervalMs).toInt();
        timedLines.add(
          LotusLyricLine(
            timestamp: Duration(milliseconds: lineMs),
            text: rawLines[i],
          ),
        );
      }
    }

    return LotusLyricsDocument(
      title: song.title,
      artist: song.artist ?? '',
      album: song.album ?? '',
      source: '$source (Auto-Timed)',
      lines: timedLines,
    );
  }

  void _calculateActiveLine(Duration position, {bool forceScroll = false}) {
    if (_lyricsDocument == null || _lyricsDocument!.isEmpty) return;

    final int effectiveMs = position.inMilliseconds +
        _timeOffsetMs +
        (_lyricsDocument?.offsetMilliseconds ?? 0);
    int targetIndex = -1;

    for (int i = 0; i < _lyricsDocument!.lines.length; i++) {
      if (_lyricsDocument!.lines[i].milliseconds <= effectiveMs) {
        targetIndex = i;
      } else {
        break;
      }
    }

    if (targetIndex != _activeLineIndex || (forceScroll && _autoScrollEnabled)) {
      if (_activeLineIndex != targetIndex) {
        setState(() => _activeLineIndex = targetIndex);
      }

      if (_prefsLoaded &&
          _autoScrollEnabled &&
          !_isUserDragging &&
          targetIndex >= 0) {
        _scrollToActiveLine(targetIndex);
      }
    }
  }

  void _scrollToActiveLine(int index) {
    if (!_prefsLoaded || !_autoScrollEnabled || index < 0) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAutoScrollTimestampMs < 60) return;
    _lastAutoScrollTimestampMs = now;

    void performScroll() {
      if (!_prefsLoaded ||
          !_autoScrollEnabled ||
          !_lyricsScrollController.hasClients) {
        return;
      }

      final double itemH = _effectiveItemHeight;
      final double viewportHeight =
          _lyricsScrollController.position.viewportDimension;
      if (viewportHeight <= 0) return;

      final double targetOffset =
          (index * itemH) + 16.0 - (viewportHeight / 2) + (itemH / 2);
      final double maxScroll =
          _lyricsScrollController.position.maxScrollExtent;
      final double minScroll =
          _lyricsScrollController.position.minScrollExtent;
      final double clamped = targetOffset.clamp(minScroll, maxScroll);

      if ((_lyricsScrollController.offset - clamped).abs() < 1.5) return;

      _lyricsScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }

    if (!_lyricsScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => performScroll());
    } else {
      performScroll();
    }
  }

  void _onLineTapped(LotusLyricLine line) {
    HapticFeedback.selectionClick();
    widget.onSeek?.call(line.timestamp);
    _playback.seek(line.timestamp);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        backgroundColor: _theme.containerHighColor,
        content: Text(
          'Synced to ${line.formattedTimestamp}',
          style: TextStyle(
              color: _theme.primaryAccent,
              fontWeight: FontWeight.bold,
              fontSize: 11),
        ),
      ),
    );
  }

  void _openSyncOffsetDialog() {
    HapticFeedback.selectionClick();
    LotusLyricsSyncDialog.show(
      context,
      song: widget.song,
      initialOffsetMs: _timeOffsetMs,
      onOffsetChanged: (int newOffsetMs) async {
        if (!mounted) return;
        setState(() => _timeOffsetMs = newOffsetMs);
        _calculateActiveLine(
          Duration(milliseconds: _playback.currentPositionMs),
          forceScroll: _autoScrollEnabled,
        );
        try {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setInt('lyrics_offset_${widget.song.id}', newOffsetMs);
        } catch (_) {}
      },
      onCustomLrcPasted: (String content) async {
        final LotusLyricsDocument parsed = _parseUniversalLyricsContent(
          content,
          song: widget.song,
          source: 'Custom Saved Lyrics',
        );
        try {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('custom_lyrics_${widget.song.id}', content);
          await prefs.setString(
            'custom_lyrics_title_${widget.song.title.trim().toLowerCase()}',
            content,
          );
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _lyricsDocument = parsed;
          _isLoadingLyrics = false;
          _activeLineIndex = -1;
        });

        if (_autoScrollEnabled && _lyricsScrollController.hasClients) {
          _lyricsScrollController.jumpTo(0.0);
        }
        _calculateActiveLine(
          Duration(milliseconds: _playback.currentPositionMs),
          forceScroll: _autoScrollEnabled,
        );
      },
    );
  }

  Future<void> _openFullScreenAddLyricsDialog() async {
    HapticFeedback.mediumImpact();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TextEditingController pasteController = TextEditingController();
    final Color accent = _theme.primaryAccent;
    final Color secondaryAccent = _theme.secondaryAccent;
    final bool isWhitaniana = _theme.isWhitanianaActive;

    final Color modalShieldSurface = _theme.modalSurfaceColor;
    final Color modalContainerLow = _theme.modalContainerLowColor;
    final Color modalContainerLowest = isWhitaniana
        ? _theme.containerColor
        : _theme.containerLowestColor;
    final Color modalContainerHigh = _theme.modalContainerHighColor;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    if (_lyricsDocument != null && _lyricsDocument!.isNotEmpty) {
      pasteController.text = _lyricsDocument!.lines.map((LotusLyricLine l) {
        return '${l.formattedTimestamp} ${l.text}';
      }).join('\n');
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Add Lyrics Dialog',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (BuildContext ctx, Animation<double> anim1,
          Animation<double> anim2, Widget child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
      pageBuilder:
          (BuildContext ctx, Animation<double> anim1, Animation<double> anim2) {
        return Scaffold(
          backgroundColor: modalShieldSurface,
          appBar: AppBar(
            backgroundColor: modalShieldSurface,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: textPrimary),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            title: Text(
              'Add & Paste Lyrics',
              style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  pasteController.clear();
                  HapticFeedback.selectionClick();
                },
                child: Text('CLEAR',
                    style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: modalContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: isWhitaniana
                              ? _theme.cardBorderColor
                              : secondaryAccent.withValues(alpha: 0.4)),
                      boxShadow: isWhitaniana
                          ? LotusDecorations.whitanianaCardShadow()
                          : null,
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: secondaryAccent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.lyrics_rounded,
                              color: secondaryAccent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                widget.song.title,
                                style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Universal Hybrid LRC Parser',
                                style: TextStyle(
                                    color: textSecondary, fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final ClipboardData? data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                            if (data != null &&
                                data.text != null &&
                                data.text!.isNotEmpty) {
                              HapticFeedback.lightImpact();
                              pasteController.text = data.text!;
                            }
                          },
                          icon:
                          const Icon(Icons.content_paste_rounded, size: 14),
                          label: const Text('PASTE',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 10.5)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: modalContainerLowest,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _theme.cardBorderColor),
                      ),
                      child: TextField(
                        controller: pasteController,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            height: 1.5,
                            fontFamily: 'monospace'),
                        cursorColor: accent,
                        decoration: InputDecoration(
                          hintText:
                          'Paste synchronized .LRC timestamps OR plain song verses here...\n\nLeave blank and tap "SAVE LYRICS" to remove/clear all saved lyrics for this song.\n\nExample with Timestamps:\n[00:08.00] First verse of the song\n[00:18.00] Second verse of the song\n\nExample without Timestamps:\nPaste plain lyrics directly — Lotus Player will automatically synchronize them to the track duration!',
                          hintStyle: TextStyle(
                              color: _theme.textTertiaryColor, fontSize: 11.5),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textSecondary,
                            side: BorderSide(color: _theme.cardBorderColor),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('CANCEL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: _theme.activeGradient,
                            boxShadow: LotusDecorations.glowShadow(accent,
                                intensity: 0.35, blur: 14),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () async {
                                final String text = pasteController.text.trim();
                                HapticFeedback.heavyImpact();

                                final SharedPreferences prefs =
                                await SharedPreferences.getInstance();

                                if (text.isEmpty) {
                                  await prefs.remove(
                                      'custom_lyrics_${widget.song.id}');
                                  await prefs.remove(
                                      'custom_lyrics_title_${widget.song.title.trim().toLowerCase()}');

                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();

                                  if (!mounted) return;

                                  setState(() {
                                    _lyricsDocument = LotusLyricsDocument(
                                      title: widget.song.title,
                                      artist: widget.song.artist ?? '',
                                      album: widget.song.album ?? '',
                                      source: 'Google Search Ready',
                                      lines: <LotusLyricLine>[],
                                    );
                                    _activeLineIndex = -1;
                                  });

                                  messenger.showSnackBar(
                                    SnackBar(
                                      backgroundColor: modalContainerHigh,
                                      content: Text(
                                        'Lyrics removed for "${widget.song.title}".',
                                        style: TextStyle(
                                          color: secondaryAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                } else {
                                  final LotusLyricsDocument parsed =
                                  _parseUniversalLyricsContent(
                                    text,
                                    song: widget.song,
                                    source: 'Custom Saved Lyrics',
                                  );

                                  await prefs.setString(
                                      'custom_lyrics_${widget.song.id}', text);
                                  await prefs.setString(
                                    'custom_lyrics_title_${widget.song.title.trim().toLowerCase()}',
                                    text,
                                  );

                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();

                                  if (!mounted) return;

                                  setState(() {
                                    _lyricsDocument = parsed;
                                    _isLoadingLyrics = false;
                                    _activeLineIndex = -1;
                                  });

                                  if (_autoScrollEnabled &&
                                      _lyricsScrollController.hasClients) {
                                    _lyricsScrollController.jumpTo(0.0);
                                  }
                                  _calculateActiveLine(
                                    Duration(
                                        milliseconds:
                                        _playback.currentPositionMs),
                                    forceScroll: _autoScrollEnabled,
                                  );

                                  messenger.showSnackBar(
                                    SnackBar(
                                      backgroundColor: modalContainerHigh,
                                      content: Text(
                                        'Loaded ${parsed.lines.length} lyric lines into active stage.',
                                        style: TextStyle(
                                          color: accent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Center(
                                child: Text(
                                  'SAVE LYRICS',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                      letterSpacing: 0.8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;

        return Container(
          color: modalShieldSurface,
          child: Column(
            children: <Widget>[
              _buildScraperTelemetryCard(accent, modalContainerLow),
              _buildQuickControlsBar(
                  accent, secondaryAccent, modalContainerLow),
              Expanded(
                child: _isLoadingLyrics
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CircularProgressIndicator(color: accent),
                      const SizedBox(height: 12),
                      Text(
                        'Fetching synchronized lyrics...',
                        style: TextStyle(
                            color: _theme.textSecondaryColor,
                            fontSize: 11.5),
                      ),
                    ],
                  ),
                )
                    : _buildLyricsViewport(
                    accent, secondaryAccent, modalContainerLow),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScraperTelemetryCard(Color accent, Color containerLow) {
    final String cleanQuery =
    LotusLyricsScraperService.buildCleanSearchQuery(widget.song);
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: containerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isWhitaniana
                  ? _theme.cardBorderColor
                  : accent.withValues(alpha: 0.35),
              width: 0.9),
          boxShadow:
          isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.verified_rounded, color: accent, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _lyricsDocument?.source ?? 'Google Search Ready',
                    style: TextStyle(
                        color: _theme.textPrimaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Query: "$cleanQuery"',
                    style: TextStyle(
                        color: _theme.textSecondaryColor, fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isLoadingLyrics ? null : _handleForceReFetch,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _theme.containerColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.5), width: 1.0),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.refresh_rounded,
                      color:
                      _isLoadingLyrics ? _theme.textTertiaryColor : accent,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isLoadingLyrics ? 'Fetching...' : 'Re-fetch',
                      style: TextStyle(
                        color: _isLoadingLyrics
                            ? _theme.textTertiaryColor
                            : accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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

  Widget _buildQuickControlsBar(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final double offsetSec = _timeOffsetMs / 1000.0;
    final String offsetLabel = _timeOffsetMs == 0
        ? 'Sync'
        : 'Sync: ${offsetSec >= 0 ? "+" : ""}${offsetSec.toStringAsFixed(1)}s';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: () async {
                HapticFeedback.selectionClick();
                final bool nextState = !_autoScrollEnabled;

                _userScrollResumeTimer?.cancel();
                setState(() {
                  _autoScrollEnabled = nextState;
                  _isUserDragging = false;
                });

                if (!nextState) {
                  // Definitively stop all scrolling. jumpTo(currentOffset) is a
                  // no-op and does NOT halt a running DrivenScrollActivity, so
                  // the last auto-scroll glide would otherwise continue for up
                  // to ~400 ms after toggling off. hold() immediately replaces
                  // the in-flight activity and pins the viewport.
                  _lastAutoScrollTimestampMs = 0;
                  if (_lyricsScrollController.hasClients) {
                    _lyricsScrollController.position.hold(() {});
                  }
                } else if (_activeLineIndex >= 0) {
                  _lastAutoScrollTimestampMs = 0;
                  _scrollToActiveLine(_activeLineIndex);
                }

                try {
                  final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
                  await prefs.setBool(_kAutoScrollKey, nextState);
                } catch (_) {}

                if (!mounted) return;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(milliseconds: 900),
                    backgroundColor: _theme.containerHighColor,
                    content: Text(
                      nextState ? 'Auto-Scroll Enabled' : 'Auto-Scroll Paused',
                      style: TextStyle(
                        color: nextState ? accent : _theme.textSecondaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              },
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _autoScrollEnabled
                      ? accent.withValues(alpha: 0.18)
                      : containerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _autoScrollEnabled
                          ? accent
                          : _theme.cardBorderColor),
                  boxShadow: isWhitaniana && !_autoScrollEnabled
                      ? LotusDecorations.whitanianaCardShadow()
                      : null,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _autoScrollEnabled
                          ? Icons.lock_outline_rounded
                          : Icons.lock_open_rounded,
                      color: _autoScrollEnabled
                          ? accent
                          : _theme.textSecondaryColor,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _autoScrollEnabled
                          ? 'Auto-Scroll: ON'
                          : 'Auto-Scroll: OFF',
                      style: TextStyle(
                        color: _autoScrollEnabled
                            ? accent
                            : _theme.textSecondaryColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _fontSize = _fontSize == 16.0
                      ? 19.0
                      : (_fontSize == 19.0 ? 14.0 : 16.0);
                });
              },
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: containerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _theme.cardBorderColor),
                  boxShadow: isWhitaniana
                      ? LotusDecorations.whitanianaCardShadow()
                      : null,
                ),
                child: Text(
                  'Font: ${_fontSize.toInt()}px',
                  style: TextStyle(
                      color: _theme.textPrimaryColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _openSyncOffsetDialog,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _timeOffsetMs != 0
                      ? accent.withValues(alpha: 0.16)
                      : containerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                      _timeOffsetMs != 0 ? accent : _theme.cardBorderColor),
                  boxShadow: isWhitaniana && _timeOffsetMs == 0
                      ? LotusDecorations.whitanianaCardShadow()
                      : null,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.sync_rounded,
                      size: 13,
                      color: _timeOffsetMs != 0
                          ? accent
                          : _theme.textSecondaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      offsetLabel,
                      style: TextStyle(
                        color: _timeOffsetMs != 0
                            ? accent
                            : _theme.textPrimaryColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _openFullScreenAddLyricsDialog,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: secondaryAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: secondaryAccent, width: 1.1),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.add_rounded, color: secondaryAccent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Add Lyrics',
                      style: TextStyle(
                          color: secondaryAccent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold),
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

  Widget _buildLyricsViewport(
      Color accent, Color secondaryAccent, Color containerLow) {
    if (_lyricsDocument == null || _lyricsDocument!.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.music_off_rounded,
                    size: 52, color: _theme.textTertiaryColor),
                const SizedBox(height: 14),
                Text(
                  'No Lyrics Found for Track',
                  style: TextStyle(
                      color: _theme.textPrimaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Search Google" to copy lyrics, then tap "+ Add Lyrics" above to paste them directly into the player.',
                  style: TextStyle(
                      color: _theme.textSecondaryColor,
                      fontSize: 12,
                      height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: LotusDecorations.glowShadow(accent,
                          intensity: 0.28, blur: 16),
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: () =>
                          LotusLyricsScraperService.launchGoogleLyricsSearch(
                              widget.song),
                      icon: const LotusSearchIcon(size: 20),
                      label: const Text(
                        'Search Google',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final double itemHeight = _effectiveItemHeight;

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (!_autoScrollEnabled) return false;

        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _isUserDragging = true;
          _userScrollResumeTimer?.cancel();
        } else if (notification is UserScrollNotification) {
          if (notification.direction != ScrollDirection.idle) {
            _isUserDragging = true;
            _userScrollResumeTimer?.cancel();
          } else {
            _userScrollResumeTimer?.cancel();
            if (_autoScrollEnabled) {
              _userScrollResumeTimer =
                  Timer(const Duration(milliseconds: 2500), () {
                    if (mounted && _autoScrollEnabled) {
                      setState(() => _isUserDragging = false);
                      if (_activeLineIndex >= 0) {
                        _scrollToActiveLine(_activeLineIndex);
                      }
                    }
                  });
            }
          }
        } else if (notification is ScrollEndNotification) {
          _userScrollResumeTimer?.cancel();
          if (_autoScrollEnabled && _isUserDragging) {
            _userScrollResumeTimer =
                Timer(const Duration(milliseconds: 2500), () {
                  if (mounted && _autoScrollEnabled) {
                    setState(() => _isUserDragging = false);
                    if (_activeLineIndex >= 0) {
                      _scrollToActiveLine(_activeLineIndex);
                    }
                  }
                });
          }
        }
        return false;
      },
      child: RepaintBoundary(
        child: ListView.builder(
          controller: _lyricsScrollController,
          itemCount: _lyricsDocument!.lines.length,
          itemExtent: itemHeight,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 120.0),
          itemBuilder: (BuildContext context, int index) {
            final LotusLyricLine line = _lyricsDocument!.lines[index];
            final bool isActive = index == _activeLineIndex;
            return _buildLyricLineCard(
                line, isActive, index, accent, secondaryAccent, containerLow);
          },
        ),
      ),
    );
  }

  Widget _buildLyricLineCard(
      LotusLyricLine line,
      bool isActive,
      int index,
      Color accent,
      Color secondaryAccent,
      Color containerLow,
      ) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    final Color activeTextColor =
    isWhitaniana ? LotusColors.whitanianaCyanAccent : Colors.white;

    final Color inactiveTextColor = isWhitaniana
        ? _theme.textSecondaryColor
        : LotusColors.textSecondary;

    return GestureDetector(
      onTap: () => _onLineTapped(line),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isActive
              ? (isWhitaniana
              ? _theme.containerColor
              : _theme.modalContainerColor)
              : containerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? accent.withValues(alpha: 0.85)
                : (isWhitaniana ? _theme.cardBorderColor : Colors.transparent),
            width: isActive ? 1.4 : (isWhitaniana ? 0.8 : 0.0),
          ),
          boxShadow: isActive
              ? LotusDecorations.glowShadow(accent, intensity: 0.22, blur: 16)
              : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (isActive) ...<Widget>[
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (BuildContext context, Widget? child) {
                      return Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: secondaryAccent,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: secondaryAccent.withValues(
                                  alpha: 0.4 + 0.6 * _glowController.value),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'NOW SINGING',
                    style: TextStyle(
                      color: accent,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                ] else ...<Widget>[
                  const Spacer(),
                ],
                Text(
                  line.formattedTimestamp.replaceAll(RegExp(r'\[|\]'), ''),
                  style: TextStyle(
                    color: isActive ? accent : _theme.textTertiaryColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              line.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? activeTextColor : inactiveTextColor,
                fontSize: _fontSize,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                letterSpacing: 0.3,
                shadows: isActive && !isWhitaniana
                    ? <Shadow>[
                  Shadow(color: accent, blurRadius: 10),
                ]
                    : null,
              ),
            ),
            if (line.phoneticRomanized != null ||
                line.translationEnglish != null) ...<Widget>[
              const SizedBox(height: 1),
              Text(
                line.phoneticRomanized ?? line.translationEnglish!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? secondaryAccent : _theme.textTertiaryColor,
                  fontSize: _fontSize * 0.72,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}