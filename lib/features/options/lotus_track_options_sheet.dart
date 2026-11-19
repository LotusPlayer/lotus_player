import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_artwork_cache.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_widgets.dart';
import '../metadata/lotus_song_tag_editor_sheet.dart';
import '../playlists/lotus_add_to_playlist_dialog.dart';

class LotusTrackOptionsSheet extends StatefulWidget {
  final SongModel song;
  final VoidCallback? onOpenTagEditor;
  final VoidCallback? onOpenPlaylistDialog;
  final ValueChanged<SongModel>? onTrackDeleted;
  final ValueChanged<SongModel>? onTagsUpdated;

  const LotusTrackOptionsSheet({
    super.key,
    required this.song,
    this.onOpenTagEditor,
    this.onOpenPlaylistDialog,
    this.onTrackDeleted,
    this.onTagsUpdated,
  });

  /// Opens the right-to-left sliding popup dialog
  static Future<void> show(
      BuildContext context, {
        required SongModel song,
        VoidCallback? onOpenTagEditor,
        VoidCallback? onOpenPlaylistDialog,
        ValueChanged<SongModel>? onTrackDeleted,
        ValueChanged<SongModel>? onTagsUpdated,
      }) {
    HapticFeedback.mediumImpact();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Track Options Right-to-Left Menu',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (BuildContext ctx, Animation<double> anim1,
          Animation<double> anim2, Widget child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (BuildContext ctx, Animation<double> anim1,
          Animation<double> anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: LotusTrackOptionsSheet(
              song: song,
              onOpenTagEditor: onOpenTagEditor,
              onOpenPlaylistDialog: onOpenPlaylistDialog,
              onTrackDeleted: onTrackDeleted,
              onTagsUpdated: onTagsUpdated,
            ),
          ),
        );
      },
    );
  }

  @override
  State<LotusTrackOptionsSheet> createState() => _LotusTrackOptionsSheetState();
}

class _LotusTrackOptionsSheetState extends State<LotusTrackOptionsSheet> {
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
  final LotusThemeController _theme = LotusThemeController.instance;

  late SongModel _currentSong;
  late bool _isFavorite;
  File? _customCoverFile;

  static const MethodChannel _deleterChannel =
  MethodChannel('com.souljalazian.lotus_player/media_storage_deleter');

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
    _playback.addListener(_onPlaybackChanged);
    _currentSong = widget.song;

    _isFavorite = _playback.isSongFavorite(_currentSong.id);

    _checkInitialArtwork();
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    _playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  Future<void> _checkInitialArtwork() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? customArt =
      prefs.getString('tag_override_${_currentSong.id}_cover_path');

      if (mounted && customArt != null && File(customArt).existsSync()) {
        setState(() {
          _customCoverFile = File(customArt);
        });
      }
    } catch (_) {}
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onPlaybackChanged() {
    if (!mounted) return;
    final bool currentFav = _playback.isSongFavorite(_currentSong.id);
    if (currentFav != _isFavorite) {
      setState(() {
        _isFavorite = currentFav;
      });
    }
  }

  // ============================================================================
  // OPTION 1: FAVORITE TOGGLE
  // ============================================================================
  Future<void> _toggleFavorite() async {
    HapticFeedback.mediumImpact();
    final String songTitle = _currentSong.title;
    final Color secondaryAccent = _theme.secondaryAccent;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isFavorite = !_isFavorite;
    });

    await _playback.toggleFavoriteSong(_currentSong);

    if (mounted) {
      final bool providerState = _playback.isSongFavorite(_currentSong.id);
      if (providerState != _isFavorite) {
        setState(() {
          _isFavorite = providerState;
        });
      }
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      LotusSnackBar.create(
        duration: const Duration(milliseconds: 1400),
        borderColor: secondaryAccent,
        content: Row(
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
              child: Text(
                _isFavorite
                    ? 'Added "$songTitle" to Favorites Vault'
                    : 'Removed "$songTitle" from Favorites Vault',
                style: TextStyle(
                  color: _isFavorite
                      ? secondaryAccent
                      : _theme.textSecondaryColor,
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

  // ============================================================================
  // OPTION 2: PLAYLIST / CRATE
  // ============================================================================
  void _openPlaylistDialog() {
    HapticFeedback.mediumImpact();
    final BuildContext rootCtx =
        Navigator.of(context, rootNavigator: true).context;
    final VoidCallback? customCallback = widget.onOpenPlaylistDialog;
    final SongModel song = _currentSong;

    Navigator.of(context).pop();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (customCallback != null) {
        customCallback();
      } else {
        final bool? changed =
        await LotusAddToPlaylistDialog.show(rootCtx, song: song);
        if (changed == true) {
          LotusAddToPlaylistDialog.notifyPlaylistsChanged();
        }
      }
    });
  }

  // ============================================================================
  // OPTION 3: EDIT TAGS & METADATA
  // ============================================================================
  void _openTagEditor() {
    HapticFeedback.mediumImpact();
    final BuildContext rootContext =
        Navigator.of(context, rootNavigator: true).context;
    final ValueChanged<SongModel>? onUpdated = widget.onTagsUpdated;
    final SongModel song = _currentSong;

    Navigator.of(context).pop();

    LotusSongTagEditorSheet.show(
      rootContext,
      song: song,
      onTagsUpdated: (SongModel updated) {
        onUpdated?.call(updated);
      },
    );
  }

  // ============================================================================
  // OPTION 4: SHARE TRACK
  // ============================================================================
  void _handleShare() {
    HapticFeedback.lightImpact();
    final BuildContext rootCtx =
        Navigator.of(context, rootNavigator: true).context;
    final SongModel song = _currentSong;

    Navigator.of(context).pop();
    _playback.shareSong(song, context: rootCtx);
  }

  // ============================================================================
  // OPTION 5: PERMANENT PHYSICAL DELETION
  // ============================================================================
  Future<void> _confirmAndDeleteFromStorage() async {
    HapticFeedback.heavyImpact();

    final Color secondaryAccent = _theme.secondaryAccent;
    final Color modalShieldSurface = _theme.modalSurfaceColor;
    final Color modalContainerLow = _theme.modalContainerLowColor;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: modalShieldSurface,
          clipBehavior: Clip.antiAlias,
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: secondaryAccent.withValues(alpha: 0.85), width: 1.6),
          ),
          shadowColor: Colors.black,
          elevation: 28,
          title: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: secondaryAccent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border:
                  Border.all(color: secondaryAccent.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.delete_forever_rounded,
                    color: secondaryAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Delete from Device?',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Permanently delete "${_currentSong.title}" from your physical phone storage?',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: modalContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: secondaryAccent.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.insert_drive_file_rounded,
                            color: secondaryAccent, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _currentSong.data.isNotEmpty
                                ? _currentSong.data
                                : '/storage/emulated/0/Music',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      children: <Widget>[
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFFF5252), size: 15),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This unlinks the audio file from disk via Android Scoped Storage.',
                            style: TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
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
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop(false);
              },
              child: Text(
                'CANCEL',
                style: TextStyle(
                  color: textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: secondaryAccent,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: secondaryAccent.withValues(alpha: 0.5),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.of(ctx).pop(true);
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.delete_rounded, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'DELETE FROM DISK',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    final String songTitle = _currentSong.title;
    final int songId = _currentSong.id;
    final String filePath = _currentSong.data;

    bool nativeSuccess = false;
    try {
      final dynamic result = await _deleterChannel.invokeMethod<dynamic>(
        'deletePhysicalAudioFile',
        <String, dynamic>{
          'filePath': filePath,
          'songId': songId,
        },
      );
      nativeSuccess = (result == true);
    } catch (e) {
      debugPrint('Lotus Native Storage Deleter invocation error: $e');
      nativeSuccess = false;
    }

    if (!nativeSuccess) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        LotusSnackBar.create(
          duration: const Duration(seconds: 2),
          borderColor: textSecondary,
          content: Row(
            children: <Widget>[
              Icon(Icons.cancel_outlined, color: textSecondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Deletion cancelled for "$songTitle".',
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    LotusArtworkCache.instance.evict(songId);

    if (_playback.isSongFavorite(songId)) {
      await _playback.toggleFavoriteSong(_currentSong);
    }

    if (_playback.activeSong?.id == songId) {
      try {
        await _playback.skipNext();
      } catch (_) {}
    }

    widget.onTrackDeleted?.call(_currentSong);

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      LotusSnackBar.create(
        duration: const Duration(seconds: 2),
        borderColor: secondaryAccent,
        content: Row(
          children: <Widget>[
            Icon(Icons.delete_outline_rounded,
                color: secondaryAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Deleted "$songTitle" from physical storage.',
                style: TextStyle(
                  color: secondaryAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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

  // ============================================================================
  // OPTION 6: SAFE APP-ONLY HIDE
  // ============================================================================
  Future<void> _confirmAndRemoveTrackFromApp() async {
    HapticFeedback.heavyImpact();

    final Color accent = _theme.primaryAccent;
    final Color modalShieldSurface = _theme.modalSurfaceColor;
    final Color modalContainerLow = _theme.modalContainerLowColor;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? shouldRemove = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: modalShieldSurface,
          clipBehavior: Clip.antiAlias,
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: accent.withValues(alpha: 0.85), width: 1.6),
          ),
          shadowColor: Colors.black,
          elevation: 28,
          title: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child:
                Icon(Icons.visibility_off_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hide from App?',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Hide "${_currentSong.title}" from your Lotus Player library and playlists?',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: modalContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Row(
                      children: <Widget>[
                        Icon(Icons.shield_outlined,
                            color: LotusColors.voltLime, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Your physical audio file will NOT be deleted.',
                            style: TextStyle(
                              color: LotusColors.voltLime,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The file remains intact on your phone storage. It is only hidden from app views and moved to "Hidden Songs" vault in Mixes.',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop(false);
              },
              child: Text(
                'CANCEL',
                style: TextStyle(
                  color: textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: accent.withValues(alpha: 0.5),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.of(ctx).pop(true);
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.visibility_off_rounded, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'HIDE FROM APP',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) return;

    final String songTitle = _currentSong.title;
    final SongModel targetSong = _currentSong;

    await _playback.hideSong(targetSong);
    widget.onTrackDeleted?.call(targetSong);

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      LotusSnackBar.create(
        duration: const Duration(seconds: 3),
        borderColor: accent,
        content: Row(
          children: <Widget>[
            Icon(Icons.visibility_off_rounded, color: accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hidden "$songTitle" from app. You can retrieve it anytime from "Hidden Songs" in Mixes.',
                style: TextStyle(
                  color: _theme.textPrimaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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

  void _dismissMenu() {
    HapticFeedback.selectionClick();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);

    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final bool isWhitaniana = _theme.isWhitanianaActive;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;

        return Container(
          width: screenSize.width * 0.85,
          constraints: BoxConstraints(maxHeight: screenSize.height * 0.88),
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: modalShieldSurface,
            borderRadius: BorderRadius.circular(28),
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
                offset: const Offset(-4, 0),
              ),
              ...LotusDecorations.glowShadow(accent,
                  intensity: 0.30, blur: 28),
            ],
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildTopPopupHeader(accent, modalContainerLow),
                _buildTrackMiniPreview(
                    accent, secondaryAccent, modalContainerLow),
                Divider(color: _theme.cardBorderColor, height: 16),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 4.0),
                    children: <Widget>[
                      _buildSlideActionItem(
                        icon: _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        title: 'Favorite',
                        subtitle: _isFavorite
                            ? 'Saved in Favorites Vault'
                            : 'Add to Favorites Vault',
                        iconColor: _isFavorite ? secondaryAccent : accent,
                        badge: _isFavorite ? 'SAVED' : null,
                        badgeColor: secondaryAccent,
                        containerLow: modalContainerLow,
                        accent: accent,
                        onTap: _toggleFavorite,
                      ),
                      _buildSlideActionItem(
                        icon: Icons.playlist_add_rounded,
                        title: 'Playlist / Crate',
                        subtitle: 'Store In App Private Vault & Playlists',
                        iconColor: accent,
                        badge: 'CRATE',
                        badgeColor: accent,
                        containerLow: modalContainerLow,
                        accent: accent,
                        onTap: _openPlaylistDialog,
                      ),
                      _buildSlideActionItem(
                        icon: Icons.edit_note_rounded,
                        title: 'Edit Song Tags',
                        subtitle: 'Update Title, Artist, Album & Cover Art',
                        iconColor: secondaryAccent,
                        badge: 'ID3',
                        badgeColor: secondaryAccent,
                        containerLow: modalContainerLow,
                        accent: accent,
                        onTap: _openTagEditor,
                      ),
                      _buildSlideActionItem(
                        icon: Icons.share_rounded,
                        title: 'Share Track',
                        subtitle: 'Share File Through Social Media',
                        iconColor: accent,
                        badge: 'SHARE',
                        badgeColor: accent.withValues(alpha: 0.8),
                        containerLow: modalContainerLow,
                        accent: accent,
                        onTap: _handleShare,
                      ),
                      _buildSlideActionItem(
                        icon: Icons.delete_forever_rounded,
                        title: 'Delete From Storage',
                        subtitle: 'Permanently Delete File From Device',
                        iconColor: secondaryAccent,
                        badge: 'PURGE',
                        badgeColor: secondaryAccent,
                        containerLow: modalContainerLow,
                        accent: secondaryAccent,
                        onTap: _confirmAndDeleteFromStorage,
                      ),
                      _buildSlideActionItem(
                        icon: Icons.visibility_off_rounded,
                        title: 'Hide From App',
                        subtitle: 'Retrieve From Mixes Operations',
                        iconColor: accent,
                        badge: 'HIDE',
                        badgeColor: LotusColors.voltLime,
                        containerLow: modalContainerLow,
                        accent: accent,
                        onTap: _confirmAndRemoveTrackFromApp,
                      ),
                    ],
                  ),
                ),
                Divider(color: _theme.cardBorderColor, height: 12),
                _buildDismissButton(accent, modalContainerLow),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopPopupHeader(Color accent, Color containerLow) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.more_horiz_rounded, color: accent, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'Track Options',
                style: TextStyle(
                    color: _theme.textPrimaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          GestureDetector(
            onTap: _dismissMenu,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: containerLow,
                shape: BoxShape.circle,
                border: Border.all(color: _theme.cardBorderColor),
              ),
              child: Icon(Icons.close_rounded, color: accent, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackMiniPreview(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: containerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _theme.cardBorderColor, width: 1.0),
          boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isWhitaniana
                      ? _theme.containerColor
                      : _theme.containerHighColor,
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _customCoverFile != null
                    ? Image.file(_customCoverFile!, fit: BoxFit.cover)
                    : LotusArtworkImage(
                  songId: _currentSong.id,
                  size: 44,
                  borderRadius: 8,
                  keepOldArtwork: true,
                  nullArtworkWidget: Image.asset(
                    'assets/icons/now_playing_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext ctx, Object err,
                        StackTrace? stack) {
                      return Center(
                        child: Icon(Icons.music_note_rounded,
                            color: accent, size: 22),
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
                children: <Widget>[
                  Text(
                    _currentSong.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currentSong.artist ?? '<unknown artist>',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _theme.textSecondaryColor, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Color containerLow,
    required Color accent,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isWhitaniana
                ? _theme.cardBorderColor
                : iconColor.withValues(alpha: 0.35),
            width: 1.0),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 11.0),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: iconColor.withValues(alpha: 0.5)),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: _theme.textPrimaryColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (badge != null) ...<Widget>[
                            const SizedBox(width: 6),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: (badgeColor ?? iconColor)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: (badgeColor ?? iconColor)
                                          .withValues(alpha: 0.5),
                                      width: 0.8),
                                ),
                                child: Text(
                                  badge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: badgeColor ?? iconColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _theme.textSecondaryColor, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: accent.withValues(alpha: 0.75), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDismissButton(Color accent, Color containerLow) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: containerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.2),
          boxShadow:
          LotusDecorations.glowShadow(accent, intensity: 0.15, blur: 10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _dismissMenu,
            child: Center(
              child: Text(
                'DISMISS MENU',
                style: TextStyle(
                  color: accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}