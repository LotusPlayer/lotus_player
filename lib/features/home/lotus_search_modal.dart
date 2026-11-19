import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/providers/lotus_playback_provider.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_widgets.dart';
import '../options/lotus_track_options_sheet.dart';
import '../playlists/lotus_add_to_playlist_dialog.dart';

class LotusSearchModalSafe extends StatefulWidget {
  final List<SongModel> allSongs;
  final ValueChanged<SongModel>? onSongSelected;

  const LotusSearchModalSafe({
    super.key,
    required this.allSongs,
    this.onSongSelected,
  });

  /// Opens the search modal as an AMOLED black or porcelain white full-height bottom sheet
  static Future<void> show(
      BuildContext context, {
        required List<SongModel> allSongs,
        ValueChanged<SongModel>? onSongSelected,
      }) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (BuildContext ctx) => LotusSearchModalSafe(
        allSongs: allSongs,
        onSongSelected: onSongSelected,
      ),
    );
  }

  @override
  State<LotusSearchModalSafe> createState() => _LotusSearchModalSafeState();
}

class _LotusSearchModalSafeState extends State<LotusSearchModalSafe>
    with SingleTickerProviderStateMixin {
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final LotusThemeController _theme = LotusThemeController.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _searchController.addListener(_onSearchChanged);
    _playback.addListener(_onPlaybackChanged);
    _theme.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _playback.removeListener(_onPlaybackChanged);
    _theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    final String q = _searchController.text.trim();
    if (_searchQuery != q) {
      setState(() {
        _searchQuery = q;
      });
    }
  }

  List<SongModel> get _filteredSongs {
    if (_searchQuery.isEmpty) return widget.allSongs;
    final String query = _searchQuery.toLowerCase();
    return widget.allSongs.where((SongModel s) {
      final String title = s.title.toLowerCase();
      final String artist = (s.artist ?? '').toLowerCase();
      final String album = (s.album ?? '').toLowerCase();
      final String ext = s.fileExtension.toLowerCase();
      return title.contains(query) ||
          artist.contains(query) ||
          album.contains(query) ||
          ext.contains(query);
    }).toList();
  }

  void _handleTrackSelected(SongModel song) {
    HapticFeedback.lightImpact();
    final bool isCurrent = _playback.isActiveSong(song);

    if (isCurrent) {
      _playback.togglePlayPause();
    } else {
      final List<SongModel> queueToPlay =
      _filteredSongs.isNotEmpty ? _filteredSongs : widget.allSongs;
      _playback.playSong(song, queue: queueToPlay, isSkipAction: false);
      widget.onSongSelected?.call(song);
    }
  }

  void _openTrackOptions(SongModel song) {
    HapticFeedback.lightImpact();
    LotusTrackOptionsSheet.show(
      context,
      song: song,
      onOpenPlaylistDialog: () =>
          LotusAddToPlaylistDialog.show(context, song: song),
    );
  }

  String _formatDuration(int ms) {
    final Duration d = Duration(milliseconds: ms);
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_theme, _playback]),
      builder: (BuildContext context, Widget? child) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final bool isWhitaniana = _theme.isWhitanianaActive;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;

        final List<SongModel> results = _filteredSongs;

        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          margin: EdgeInsets.only(bottom: bottomInset),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: modalShieldSurface,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isWhitaniana
                  ? _theme.cardBorderColor
                  : accent.withValues(alpha: 0.85),
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
              ...LotusDecorations.glowShadow(accent,
                  intensity: 0.28, blur: 28),
            ],
          ),
          child: Column(
            children: <Widget>[
              _buildDragHandle(),
              _buildTopHeader(accent, secondaryAccent, modalContainerLow),
              _buildSearchBar(accent, modalContainerLow),
              _buildResultsSubheader(results.length, accent),
              Expanded(
                child: results.isEmpty
                    ? _buildEmptyState(accent)
                    : _buildSearchResultsList(
                    results, accent, secondaryAccent, modalContainerLow),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 6.0),
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: isWhitaniana
              ? LotusColors.whitanianaCardBorder
              : Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTopHeader(
      Color accent, Color secondaryAccent, Color containerLow) {
    final SongModel? active = _playback.activeSong;
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 14, 8),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: const LotusSearchIcon(size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Search Device Audio Vault',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: <Widget>[
                    CircleAvatar(radius: 2.5, backgroundColor: accent),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        active != null
                            ? 'PLAYING: ${active.title.toUpperCase()}'
                            : 'BIT-PERFECT LOCAL AUDIO SCAN',
                        style: TextStyle(
                          color: accent,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: isWhitaniana
                    ? _theme.textSecondaryColor
                    : Colors.white70,
                size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isWhitaniana ? _theme.containerColor : containerLow,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: _searchQuery.isNotEmpty
                ? accent
                : _theme.cardBorderColor,
            width: _searchQuery.isNotEmpty ? 1.4 : 0.8,
          ),
          boxShadow: _searchQuery.isNotEmpty
              ? LotusDecorations.glowShadow(accent, intensity: 0.16, blur: 12)
              : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
        ),
        child: Row(
          children: <Widget>[
            const LotusSearchIcon(size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: accent,
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums, or FLAC/DSD...',
                  hintStyle: TextStyle(
                      color: _theme.textTertiaryColor, fontSize: 12.5),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _searchController.clear();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isWhitaniana
                          ? _theme.containerHighColor
                          : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded,
                        color: textPrimary, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSubheader(int count, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              _searchQuery.isNotEmpty
                  ? 'MATCHING STEMS ($count)'
                  : 'ALL VAULT STEMS ($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _theme.textTertiaryColor,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '384 KHZ ALSA PASS',
            style: TextStyle(
              color: accent,
              fontSize: 9.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList(
      List<SongModel> songs,
      Color accent,
      Color secondaryAccent,
      Color containerLow,
      ) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: songs.length,
      itemExtent: 74.0,
      itemBuilder: (BuildContext context, int index) {
        final SongModel song = songs[index];
        final bool isCurrent = _playback.isActiveSong(song);
        final Color itemAccent =
        isCurrent ? accent : (index % 2 == 0 ? accent : secondaryAccent);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3.0),
          decoration: BoxDecoration(
            color: isCurrent
                ? (isWhitaniana
                ? _theme.containerColor
                : _theme.modalContainerColor)
                : containerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? accent.withValues(alpha: 0.95)
                  : _theme.cardBorderColor,
              width: isCurrent ? 1.5 : 0.8,
            ),
            boxShadow: isCurrent
                ? LotusDecorations.glowShadow(accent,
                intensity: 0.22, blur: 14)
                : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _handleTrackSelected(song),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Row(
                  children: <Widget>[
                    Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: QueryArtworkWidget(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              keepOldArtwork: true,
                              artworkQuality: FilterQuality.low,
                              nullArtworkWidget: Container(
                                color: isWhitaniana
                                    ? _theme.containerColor
                                    : _theme.modalContainerLowColor,
                                child: Image.asset(
                                  'assets/images/now_playing_icon.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (BuildContext ctx, Object err,
                                      StackTrace? stack) {
                                    return Icon(
                                      Icons.music_note_rounded,
                                      color: isCurrent
                                          ? accent
                                          : _theme.textTertiaryColor,
                                      size: 22,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (isCurrent && _playback.isPlaying)
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Icon(Icons.equalizer_rounded,
                                  color: accent, size: 22),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? accent
                                        : _theme.textPrimaryColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isCurrent) ...<Widget>[
                                const SizedBox(width: 4),
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: accent.withValues(alpha: 0.6),
                                          width: 0.6),
                                    ),
                                    child: Text(
                                      'PLAYING',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: <Widget>[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: itemAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  song.fileExtension.isNotEmpty
                                      ? song.fileExtension.toUpperCase()
                                      : 'FLAC 24/96',
                                  style: TextStyle(
                                    color: itemAccent,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  song.artist ?? '<Unknown Artist>',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _theme.textSecondaryColor,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatDuration(song.duration ?? 0),
                      style: TextStyle(
                        color: _theme.textTertiaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: Icon(
                        isCurrent && _playback.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: isCurrent
                            ? accent
                            : (isWhitaniana
                            ? _theme.textPrimaryColor
                            : Colors.white70),
                        size: 28,
                      ),
                      onPressed: () => _handleTrackSelected(song),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: _theme.textSecondaryColor,
                        size: 18,
                      ),
                      onPressed: () => _openTrackOptions(song),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(Color accent) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.music_off_rounded,
              size: 48, color: _theme.textTertiaryColor),
          const SizedBox(height: 12),
          Text(
            'No stems matching "$_searchQuery"',
            style: TextStyle(
              color: _theme.textPrimaryColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check spelling or search by artist name or album title.',
            style: TextStyle(
                color: _theme.textSecondaryColor, fontSize: 11),
          ),
        ],
      ),
    );
  }
}