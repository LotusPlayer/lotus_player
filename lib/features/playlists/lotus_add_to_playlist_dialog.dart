import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_widgets.dart';

class AppPrivatePlaylistRecord {
  final int id;
  String title;
  List<int> songIds;
  int dateCreated;
  bool isSelected;

  AppPrivatePlaylistRecord({
    required this.id,
    required this.title,
    required this.songIds,
    required this.dateCreated,
    this.isSelected = false,
  });

  int get trackCount => songIds.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': title,
    'songIds': songIds,
    'dateCreated': dateCreated,
    'isFavorites': false,
  };

  factory AppPrivatePlaylistRecord.fromJson(Map<String, dynamic> json) {
    return AppPrivatePlaylistRecord(
      id: json['id'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      title: (json['name'] ?? json['title'] ?? 'Custom Playlist') as String,
      songIds: (json['songIds'] as List<dynamic>?)
          ?.map((dynamic e) => int.tryParse(e.toString()) ?? 0)
          .where((int id) => id > 0)
          .toList() ??
          <int>[],
      dateCreated:
      json['dateCreated'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class LotusAddToPlaylistDialog extends StatefulWidget {
  final SongModel song;

  const LotusAddToPlaylistDialog({
    super.key,
    required this.song,
  });

  static final ValueNotifier<int> playlistsChangeNotifier =
  ValueNotifier<int>(0);

  static void notifyPlaylistsChanged() {
    playlistsChangeNotifier.value++;
  }

  static Future<bool?> show(BuildContext context, {required SongModel song}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      useSafeArea: false,
      builder: (BuildContext ctx) => LotusAddToPlaylistDialog(song: song),
    );
  }

  @override
  State<LotusAddToPlaylistDialog> createState() =>
      _LotusAddToPlaylistDialogState();
}

class _LotusAddToPlaylistDialogState extends State<LotusAddToPlaylistDialog> {
  final LotusThemeController _theme = LotusThemeController.instance;
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final TextEditingController _newPlaylistController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  SharedPreferences? _cachedPrefs;

  static const String _kPrivatePlaylistsStorageKey =
      'lotus_private_app_playlists_v2';
  static const String _kVerifiedPlaylistCountKey =
      'lotus_verified_playlist_count';

  bool _isLoading = true;
  bool _isFavorite = false;
  List<AppPrivatePlaylistRecord> _playlists = <AppPrivatePlaylistRecord>[];

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
    _isFavorite = _playback.isSongFavorite(widget.song.id);
    _loadPrivatePlaylists();
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    _newPlaylistController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<SharedPreferences> _getPrefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  Future<void> _loadPrivatePlaylists() async {
    setState(() => _isLoading = true);

    try {
      final SharedPreferences prefs = await _getPrefs();
      final String? rawJson = prefs.getString(_kPrivatePlaylistsStorageKey);

      final List<AppPrivatePlaylistRecord> entries =
      <AppPrivatePlaylistRecord>[];

      if (rawJson != null && rawJson.trim().isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(rawJson) as List<dynamic>;
        for (final dynamic item in decodedList) {
          if (item is Map<String, dynamic>) {
            final bool isFav = item['isFavorites'] as bool? ?? false;
            final String name =
            (item['name'] ?? item['title'] ?? '') as String;
            if (isFav || name.toLowerCase() == 'favorites vault') continue;

            final AppPrivatePlaylistRecord record =
            AppPrivatePlaylistRecord.fromJson(item);
            record.isSelected = record.songIds.contains(widget.song.id);
            entries.add(record);
          }
        }
      }

      if (mounted) {
        setState(() {
          _playlists = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lotus AddToPlaylist loading error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNewPlaylist() async {
    final String name = _newPlaylistController.text.trim();
    if (name.isEmpty) return;

    final Color accent = _theme.primaryAccent;
    final Color secondaryAccent = _theme.secondaryAccent;

    if (_playlists.any((AppPrivatePlaylistRecord p) =>
    p.title.toLowerCase() == name.toLowerCase())) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        LotusSnackBar.create(
          borderColor: secondaryAccent,
          content: Text(
            'Playlist "$name" already exists.',
            style: TextStyle(
              color: _theme.isWhitanianaActive
                  ? LotusColors.whitanianaTextPrimary
                  : secondaryAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    _inputFocusNode.unfocus();

    try {
      final int newId = DateTime.now().millisecondsSinceEpoch;
      final AppPrivatePlaylistRecord newEntry = AppPrivatePlaylistRecord(
        id: newId,
        title: name,
        songIds: <int>[widget.song.id],
        dateCreated: newId,
        isSelected: true,
      );

      setState(() {
        _playlists.insert(0, newEntry);
        _newPlaylistController.clear();
      });

      await _persistAllToStorage();
      LotusAddToPlaylistDialog.notifyPlaylistsChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          LotusSnackBar.create(
            duration: const Duration(milliseconds: 1600),
            borderColor: accent,
            content: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.check_circle_rounded, color: accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Playlist "$name" created & track added.',
                      style: TextStyle(
                          color: _theme.isWhitanianaActive
                              ? LotusColors.whitanianaTextPrimary
                              : accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating playlist: $e');
    }
  }

  Future<void> _persistAllToStorage() async {
    try {
      final SharedPreferences prefs = await _getPrefs();
      final List<Map<String, dynamic>> rawList =
      _playlists.map((AppPrivatePlaylistRecord p) => p.toJson()).toList();
      await prefs.setString(_kPrivatePlaylistsStorageKey, jsonEncode(rawList));
      await prefs.setInt(_kVerifiedPlaylistCountKey, _playlists.length + 1);
    } catch (e) {
      debugPrint('Lotus AddToPlaylist persist error: $e');
    }
  }

  Future<void> _commitSelection() async {
    HapticFeedback.mediumImpact();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Color accent = _theme.primaryAccent;

    int modifiedCount = 0;

    final bool currentFav = _playback.isSongFavorite(widget.song.id);
    if (_isFavorite != currentFav) {
      await _playback.toggleFavoriteSong(widget.song);
      modifiedCount++;
    }

    for (final AppPrivatePlaylistRecord entry in _playlists) {
      if (entry.isSelected) {
        if (!entry.songIds.contains(widget.song.id)) {
          entry.songIds.add(widget.song.id);
          modifiedCount++;
        }
      } else {
        if (entry.songIds.contains(widget.song.id)) {
          entry.songIds.remove(widget.song.id);
          modifiedCount++;
        }
      }
    }

    await _persistAllToStorage();
    LotusAddToPlaylistDialog.notifyPlaylistsChanged();

    if (mounted) {
      Navigator.of(context).pop(true);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        LotusSnackBar.create(
          duration: const Duration(seconds: 2),
          borderColor: accent,
          content: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.check_circle_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Updated $modifiedCount playlist container(s) for "${widget.song.title}".',
                  style: TextStyle(
                      color: _theme.isWhitanianaActive
                          ? LotusColors.whitanianaTextPrimary
                          : accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final int selectedCustomCount =
        _playlists.where((AppPrivatePlaylistRecord p) => p.isSelected).length;
    final int totalSelected = selectedCustomCount + (_isFavorite ? 1 : 0);

    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final bool isWhitaniana = _theme.isWhitanianaActive;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;
        final Color modalContainerLowest = _theme.isWhitanianaActive
            ? _theme.containerColor
            : _theme.containerLowestColor;

        final Color dialogBorderColor = _theme.cardBorderColor;

        final MediaQueryData media = MediaQuery.of(context);
        final double screenHeight = media.size.height;
        final double keyboardInset = media.viewInsets.bottom;
        final bool isKeyboardOpen = keyboardInset > 0.0;

        final double safeTopPadding =
        media.padding.top > 0 ? media.padding.top : 24.0;
        final double safeBottomPadding =
        isKeyboardOpen ? keyboardInset + 8.0 : media.padding.bottom + 24.0;
        final double dialogMaxHeight =
        (screenHeight - safeTopPadding - safeBottomPadding)
            .clamp(280.0, 680.0);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: isKeyboardOpen ? 12.0 : safeTopPadding,
            bottom: safeBottomPadding,
          ),
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: dialogMaxHeight,
                ),
                decoration: BoxDecoration(
                  color: modalShieldSurface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: dialogBorderColor,
                    width: 1.6,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(
                          alpha: isWhitaniana ? 0.15 : 0.85),
                      blurRadius: 36,
                      spreadRadius: 8,
                      offset: const Offset(0, 6),
                    ),
                    ...LotusDecorations.glowShadow(accent,
                        intensity: 0.28, blur: 28),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    color: modalShieldSurface,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildDialogHeader(accent, modalShieldSurface),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 140),
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                  16.0, 8.0, 16.0, 12.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  _buildTrackTargetCard(accent, secondaryAccent,
                                      modalContainerLow),
                                  const SizedBox(height: 10),
                                  _buildInlinePlaylistCreator(accent,
                                      modalContainerLow, modalContainerLowest),
                                  const SizedBox(height: 10),
                                  _buildFavoritesVaultTile(
                                      secondaryAccent, modalContainerLow),
                                  const SizedBox(height: 8),
                                  _isLoading
                                      ? Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                          color: accent),
                                    ),
                                  )
                                      : _buildPlaylistsList(
                                      accent, modalContainerLow),
                                  const SizedBox(height: 10),
                                  _buildAppPrivateVaultNotice(
                                      modalContainerLow, accent),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _buildBottomButtons(
                            totalSelected, accent, modalShieldSurface),
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

  Widget _buildDialogHeader(Color accent, Color modalShieldSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
      decoration: BoxDecoration(
        color: modalShieldSurface,
        border: Border(
          bottom: BorderSide(
            color: _theme.cardBorderColor,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Icon(Icons.playlist_add_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add to Playlist',
              style: TextStyle(
                color: _theme.textPrimaryColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded,
                color: _theme.textSecondaryColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTargetCard(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _theme.cardBorderColor),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isWhitaniana ? _theme.containerColor : containerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: LotusArtworkImage(
                songId: widget.song.id,
                size: 42,
                borderRadius: 8,
                keepOldArtwork: true,
                nullArtworkWidget: Image.asset(
                  'assets/icons/now_playing_icon.png',
                  fit: BoxFit.cover,
                  errorBuilder:
                      (BuildContext ctx, Object err, StackTrace? stack) {
                    return Center(
                      child: Icon(Icons.music_note_rounded,
                          color: secondaryAccent, size: 20),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _theme.textPrimaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.song.artist ?? 'Local Audio Stem',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _theme.textSecondaryColor,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: secondaryAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: secondaryAccent.withValues(alpha: 0.5)),
              ),
              child: Text(
                'STEM',
                style: TextStyle(
                  color: secondaryAccent,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlinePlaylistCreator(
      Color accent, Color containerLow, Color containerLowest) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _theme.cardBorderColor),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Create New Playlist',
            style: TextStyle(
              color: _theme.textPrimaryColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: containerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _theme.cardBorderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.add_circle_outline_rounded,
                          color: accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _newPlaylistController,
                          focusNode: _inputFocusNode,
                          style: TextStyle(
                              color: _theme.textPrimaryColor, fontSize: 12),
                          cursorColor: accent,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _createNewPlaylist(),
                          decoration: InputDecoration(
                            hintText: 'Enter playlist title...',
                            hintStyle: TextStyle(
                                color: _theme.textTertiaryColor, fontSize: 11),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  elevation: 0,
                ),
                onPressed: _createNewPlaylist,
                child: const Text(
                  'CREATE',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesVaultTile(Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      decoration: BoxDecoration(
        color: _isFavorite
            ? secondaryAccent.withValues(alpha: 0.16)
            : containerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isFavorite
              ? secondaryAccent.withValues(alpha: 0.75)
              : _theme.cardBorderColor,
          width: _isFavorite ? 1.4 : 0.8,
        ),
        boxShadow: _isFavorite
            ? LotusDecorations.glowShadow(secondaryAccent,
            intensity: 0.18, blur: 10)
            : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _isFavorite = !_isFavorite);
          },
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  _isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: secondaryAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Favorites Vault',
                        style: TextStyle(
                          color: _theme.textPrimaryColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isFavorite ? 'Track is favorited' : 'Tap to favorite',
                        style: TextStyle(
                          color: _theme.textSecondaryColor,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isFavorite
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color:
                  _isFavorite ? secondaryAccent : _theme.textTertiaryColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistsList(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    if (_playlists.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: containerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _theme.cardBorderColor),
          boxShadow:
          isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
        ),
        child: Center(
          child: Text(
            'No custom playlists yet.\nEnter a name above to create your first playlist.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _theme.textSecondaryColor, fontSize: 11),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _playlists.map((AppPrivatePlaylistRecord entry) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          decoration: BoxDecoration(
            color: entry.isSelected
                ? accent.withValues(alpha: 0.16)
                : containerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: entry.isSelected
                  ? accent.withValues(alpha: 0.85)
                  : _theme.cardBorderColor,
              width: entry.isSelected ? 1.4 : 0.8,
            ),
            boxShadow: entry.isSelected
                ? LotusDecorations.glowShadow(accent, intensity: 0.18, blur: 10)
                : (isWhitaniana
                ? LotusDecorations.whitanianaCardShadow()
                : null),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => entry.isSelected = !entry.isSelected);
              },
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.queue_music_rounded,
                      color:
                      entry.isSelected ? accent : _theme.textSecondaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            entry.title,
                            style: TextStyle(
                              color: _theme.textPrimaryColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${entry.trackCount} Tracks in Vault',
                            style: TextStyle(
                              color: _theme.textSecondaryColor,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      entry.isSelected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color:
                      entry.isSelected ? accent : _theme.textTertiaryColor,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAppPrivateVaultNotice(Color containerLow, Color accent) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _theme.cardBorderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.shield_outlined,
              color: LotusColors.voltLime, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'App-Private Vault: Isolated to Lotus Player (no system MediaStore leaks).',
              style: TextStyle(
                color: _theme.textSecondaryColor,
                fontSize: 9.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(
      int selectedCount, Color accent, Color modalShieldSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: modalShieldSurface,
        border: Border(top: BorderSide(color: _theme.cardBorderColor)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: _theme.textSecondaryColor),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: _theme.activeGradient,
                boxShadow: LotusDecorations.glowShadow(accent,
                    intensity: 0.3, blur: 14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(21),
                  onTap: _commitSelection,
                  child: Center(
                    child: Text(
                      'SAVE TO PLAYLIST ($selectedCount)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
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
}