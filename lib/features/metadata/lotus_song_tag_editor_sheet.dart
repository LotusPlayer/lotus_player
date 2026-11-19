import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_artwork_cache.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_widgets.dart';

class LotusSongTagEditorSheet extends StatefulWidget {
  final SongModel song;
  final ValueChanged<SongModel>? onTagsUpdated;

  const LotusSongTagEditorSheet({
    super.key,
    required this.song,
    this.onTagsUpdated,
  });

  static Future<void> show(
      BuildContext context, {
        required SongModel song,
        ValueChanged<SongModel>? onTagsUpdated,
      }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      useSafeArea: true,
      builder: (BuildContext ctx) => LotusSongTagEditorSheet(
        song: song,
        onTagsUpdated: onTagsUpdated,
      ),
    );
  }

  @override
  State<LotusSongTagEditorSheet> createState() =>
      _LotusSongTagEditorSheetState();
}

class _LotusSongTagEditorSheetState extends State<LotusSongTagEditorSheet> {
  final ImagePicker _imagePicker = ImagePicker();
  late final LotusPlaybackProvider _playback;
  late final LotusThemeController _theme;

  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _trackNumController;

  File? _pickedGalleryImage;
  bool _removeCover = false;
  bool _isSaving = false;

  static const String _kTagOverridesRegistryKey =
      'lotus_tag_overrides_registry_v2';
  static const MethodChannel _mediaScannerChannel =
  MethodChannel('com.souljalazian.lotus_player/media_scanner');

  @override
  void initState() {
    super.initState();
    _playback = LotusPlaybackProvider.instance;
    _theme = LotusThemeController.instance;
    _theme.addListener(_onThemeChanged);

    final String initialTitle = widget.song.title;
    final String initialArtist = (widget.song.artist != null &&
        !widget.song.artist!.toLowerCase().contains('<unknown>'))
        ? widget.song.artist!
        : '';
    final String initialAlbum = (widget.song.album != null &&
        !widget.song.album!.toLowerCase().contains('<unknown>'))
        ? widget.song.album!
        : '';
    final String initialGenre =
    (widget.song.genre != null && widget.song.genre!.isNotEmpty)
        ? widget.song.genre!
        : '';

    final String rawYear = (widget.song.getMap['year']?.toString() ??
        widget.song.getMap['YEAR']?.toString() ??
        '');
    final String initialYear =
    (rawYear == '0' || rawYear == 'null') ? '' : rawYear;

    final String initialTrack =
    (widget.song.track != null && widget.song.track! > 0)
        ? widget.song.track.toString().padLeft(2, '0')
        : '';

    _titleController = TextEditingController(text: initialTitle);
    _artistController = TextEditingController(text: initialArtist);
    _albumController = TextEditingController(text: initialAlbum);
    _genreController = TextEditingController(text: initialGenre);
    _yearController = TextEditingController(text: initialYear);
    _trackNumController = TextEditingController(text: initialTrack);

    _loadExistingSavedMetadata();
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadExistingSavedMetadata() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String prefix = 'tag_override_${widget.song.id}_';
      final String? savedTitle = prefs.getString('${prefix}title');
      final String? savedArtist = prefs.getString('${prefix}artist');
      final String? savedAlbum = prefs.getString('${prefix}album');
      final String? savedGenre = prefs.getString('${prefix}genre');
      final String? savedYear = prefs.getString('${prefix}year');
      final String? savedTrack = prefs.getString('${prefix}track_number');
      final String? savedImagePath = prefs.getString('${prefix}cover_path');
      final bool savedRemoved = prefs.getBool('${prefix}cover_removed') ?? false;

      if (mounted) {
        setState(() {
          if (savedTitle != null && savedTitle.trim().isNotEmpty) {
            _titleController.text = savedTitle;
          }
          if (savedArtist != null && savedArtist.trim().isNotEmpty) {
            _artistController.text = savedArtist;
          }
          if (savedAlbum != null && savedAlbum.trim().isNotEmpty) {
            _albumController.text = savedAlbum;
          }
          if (savedGenre != null && savedGenre.trim().isNotEmpty) {
            _genreController.text = savedGenre;
          }
          if (savedYear != null && savedYear.trim().isNotEmpty) {
            _yearController.text = savedYear;
          }
          if (savedTrack != null && savedTrack.trim().isNotEmpty) {
            _trackNumController.text = savedTrack;
          }
          _removeCover = savedRemoved;
          if (!savedRemoved &&
              savedImagePath != null &&
              File(savedImagePath).existsSync()) {
            _pickedGalleryImage = File(savedImagePath);
          } else {
            _pickedGalleryImage = null;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _pickCoverFromGallery() async {
    HapticFeedback.mediumImpact();
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 95,
      );
      if (picked != null) {
        try {
          final Directory dir = await getApplicationSupportDirectory();
          final Directory coversDir = Directory('${dir.path}/lotus_covers');
          if (!coversDir.existsSync()) coversDir.createSync(recursive: true);
          final String persistentPath =
              '${coversDir.path}/${widget.song.id}_cover.jpg';
          final File savedFile = await File(picked.path).copy(persistentPath);
          HapticFeedback.lightImpact();
          if (mounted) {
            setState(() {
              _pickedGalleryImage = savedFile;
              _removeCover = false;
            });
          }
        } catch (_) {
          HapticFeedback.lightImpact();
          if (mounted) {
            setState(() {
              _pickedGalleryImage = File(picked.path);
              _removeCover = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Gallery picker error: $e');
    }
  }

  void _deleteCurrentArtwork() {
    HapticFeedback.mediumImpact();
    setState(() {
      _pickedGalleryImage = null;
      _removeCover = true;
    });
  }

  Future<void> _commitTagsToStorage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String title = _titleController.text.trim();
    final String artist = _artistController.text.trim();
    final String album = _albumController.text.trim();
    final String genre = _genreController.text.trim();
    final String year = _yearController.text.trim();
    final String trackNo = _trackNumController.text.trim();
    final String filePath = widget.song.data;
    final int songId = widget.song.id;
    final Color accent = _theme.primaryAccent;
    final Color secondaryAccent = _theme.secondaryAccent;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String prefix = 'tag_override_${songId}_';
      final String pathPrefix = 'tag_override_path_${filePath}_';

      // Save override preferences first so native ArtworkCachePlugin / LotusBitmapLoader
      // immediately see cover_path / cover_removed flags on refresh.
      await prefs.setString('${prefix}title', title);
      await prefs.setString('${prefix}artist', artist);
      await prefs.setString('${prefix}album', album);
      await prefs.setString('${prefix}genre', genre);
      await prefs.setString('${prefix}year', year);
      await prefs.setString('${prefix}track_number', trackNo);
      await prefs.setString('${pathPrefix}title', title);
      await prefs.setString('${pathPrefix}artist', artist);
      await prefs.setString('${pathPrefix}album', album);

      if (_removeCover) {
        await prefs.setBool('${prefix}cover_removed', true);
        await prefs.remove('${prefix}cover_path');
        await prefs.remove('${pathPrefix}cover_path');
        try {
          final Directory dir = await getApplicationSupportDirectory();
          final File savedCover =
          File('${dir.path}/lotus_covers/${songId}_cover.jpg');
          if (savedCover.existsSync()) {
            await savedCover.delete();
          }
        } catch (_) {}
      } else if (_pickedGalleryImage != null) {
        await prefs.setBool('${prefix}cover_removed', false);
        await prefs.setString('${prefix}cover_path', _pickedGalleryImage!.path);
        await prefs.setString(
            '${pathPrefix}cover_path', _pickedGalleryImage!.path);
      } else {
        await prefs.setBool('${prefix}cover_removed', false);
        await prefs.remove('${prefix}cover_path');
        await prefs.remove('${pathPrefix}cover_path');
      }

      try {
        await _mediaScannerChannel.invokeMethod<dynamic>(
          'updateMediaStoreTags',
          <String, dynamic>{
            'songId': songId,
            'albumId': widget.song.albumId ?? 0,
            'filePath': filePath,
            'uri': widget.song.uri,
            'title': title.isNotEmpty ? title : widget.song.title,
            'artist': artist,
            'album': album,
            'genre': genre,
            'year': year,
            'track': trackNo,
            'coverPath': _removeCover ? null : _pickedGalleryImage?.path,
            'removeCover': _removeCover,
          },
        );
      } on PlatformException catch (e) {
        debugPrint('Native tag error: ${e.code} ${e.message}');
        if (e.code == 'PERMISSION_DENIED') {
          if (mounted) {
            setState(() => _isSaving = false);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              LotusSnackBar.create(
                borderColor: secondaryAccent,
                content: Text(
                  'Write permission denied - tags not saved.',
                  style: TextStyle(
                      color: _theme.isWhitanianaActive
                          ? LotusColors.whitanianaTextPrimary
                          : secondaryAccent,
                      fontWeight: FontWeight.bold),
                ),
              ),
            );
          }
          return;
        }
      } catch (e) {
        debugPrint('Native updateMediaStoreTags notice: $e');
      }

      Map<String, dynamic> registry = <String, dynamic>{};
      final String? rawRegistry = prefs.getString(_kTagOverridesRegistryKey);
      if (rawRegistry != null && rawRegistry.isNotEmpty) {
        try {
          registry = jsonDecode(rawRegistry) as Map<String, dynamic>;
        } catch (_) {}
      }

      registry[songId.toString()] = <String, dynamic>{
        'title': title.isNotEmpty ? title : widget.song.title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'year': year,
        'track': trackNo,
        'coverPath': _removeCover ? null : _pickedGalleryImage?.path,
        'coverRemoved': _removeCover,
        'filePath': filePath,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_kTagOverridesRegistryKey, jsonEncode(registry));

      final Map<dynamic, dynamic> rawMap =
      Map<dynamic, dynamic>.from(widget.song.getMap);
      if (title.isNotEmpty) rawMap['title'] = title;
      rawMap['artist'] = artist;
      rawMap['album'] = album;
      rawMap['genre'] = genre;
      rawMap['year'] = int.tryParse(year);
      rawMap['track'] = int.tryParse(trackNo) ?? widget.song.track;
      final SongModel updatedSong = SongModel(rawMap);

      // Clear Dart RAM cache & notify every mounted LotusArtworkImage immediately
      LotusArtworkCache.instance.evict(songId);
      // Push updated metadata & artwork to Flutter state and Media3 notification immediately
      _playback.notifySongUpdated(
        updatedSong,
        coverPath: _removeCover ? null : _pickedGalleryImage?.path,
        removeCover: _removeCover,
      );
      widget.onTagsUpdated?.call(updatedSong);

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop();
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          LotusSnackBar.create(
            duration: const Duration(seconds: 2),
            borderColor: accent,
            content: Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Updated tags for "${title.isNotEmpty ? title : widget.song.title}".',
                    style: TextStyle(
                      color: _theme.isWhitanianaActive
                          ? LotusColors.whitanianaTextPrimary
                          : accent,
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
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          LotusSnackBar.create(
            borderColor: secondaryAccent,
            content: Text(
              'Error saving tags: $e',
              style: TextStyle(
                color: _theme.isWhitanianaActive
                    ? LotusColors.whitanianaTextPrimary
                    : secondaryAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final double screenHeight = MediaQuery.sizeOf(context).height;

    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final bool isWhitaniana = _theme.isWhitanianaActive;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;

        return AnimatedPadding(
          padding: EdgeInsets.only(bottom: bottomInset),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: (screenHeight * 0.90) - (bottomInset > 0 ? 30 : 0),
            ),
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
                  color: Colors.black
                      .withValues(alpha: isWhitaniana ? 0.15 : 0.85),
                  blurRadius: 36,
                  spreadRadius: 8,
                  offset: const Offset(0, -6),
                ),
                ...LotusDecorations.glowShadow(accent,
                    intensity: 0.28, blur: 28),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildDragHandle(),
                _buildTopBar(accent, modalContainerLow),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 6.0),
                    children: <Widget>[
                      _buildArtworkGalleryPickerCard(
                          accent, secondaryAccent, modalContainerLow),
                      const SizedBox(height: 14),
                      _buildMetadataInputs(accent, modalContainerLow),
                      const SizedBox(height: 14),
                      _buildFileTelemetryCard(accent, modalContainerLow),
                      const SizedBox(height: 14),
                      _buildEmbeddedActionButtons(accent),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
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
        width: 42,
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

  Widget _buildTopBar(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isWhitaniana ? _theme.containerColor : containerLow,
                shape: BoxShape.circle,
                border: Border.all(color: _theme.cardBorderColor),
              ),
              child: Icon(Icons.close_rounded, color: textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Song Tag & Metadata Editor',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'PHYSICAL STORAGE & MEDIASTORE ALIGNED',
                  style: TextStyle(
                    color: accent,
                    fontSize: 9.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtworkGalleryPickerCard(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    final String statusBadge = _removeCover
        ? 'COVER REMOVED'
        : (_pickedGalleryImage != null
        ? 'GALLERY ATTACHED'
        : 'ORIGINAL EMBEDDED');
    final String statusTitle = _removeCover
        ? 'No Cover Artwork'
        : (_pickedGalleryImage != null
        ? 'Custom Gallery Photo'
        : 'Default Audio File Artwork');

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isWhitaniana
              ? _theme.cardBorderColor
              : accent.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: isWhitaniana
            ? LotusDecorations.whitanianaCardShadow()
            : LotusDecorations.glowShadow(accent, intensity: 0.12, blur: 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.photo_library_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Album Cover Artwork',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                fit: FlexFit.loose,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (_pickedGalleryImage != null || _removeCover)
                        ? secondaryAccent.withValues(alpha: 0.2)
                        : (isWhitaniana
                        ? _theme.containerHighColor
                        : Colors.white10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (_pickedGalleryImage != null || _removeCover)
                          ? secondaryAccent
                          : textSecondary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (_pickedGalleryImage != null || _removeCover)
                        ? secondaryAccent
                        : accent,
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _removeCover
                      ? Container(
                    color: _theme.containerHighColor,
                    child: Icon(
                      Icons.music_note_rounded,
                      color: accent,
                      size: 36,
                    ),
                  )
                      : (_pickedGalleryImage != null
                      ? Image.file(
                    _pickedGalleryImage!,
                    fit: BoxFit.cover,
                  )
                      : LotusArtworkImage(
                    songId: widget.song.id,
                    size: 84,
                    borderRadius: 12,
                    nullArtworkWidget: Container(
                      color: _theme.containerHighColor,
                      child: Icon(
                        Icons.music_note_rounded,
                        color: accent,
                        size: 36,
                      ),
                    ),
                  )),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      statusTitle,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'LOSSLESS BIT-PERFECT STREAM\nMediaStore & Disk Registry Aligned',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 9.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            elevation: 0,
                          ),
                          onPressed: _pickCoverFromGallery,
                          icon: const Icon(Icons.photo_library_rounded,
                              size: 13),
                          label: const Text(
                            'Pick from Gallery',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Delete Song Cover',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: secondaryAccent,
                              size: 20,
                            ),
                            onPressed: _deleteCurrentArtwork,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataInputs(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;

    return Container(
      padding: const EdgeInsets.all(14.0),
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
              Icon(Icons.edit_note_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Track Metadata Descriptor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  'PHYSICAL STORAGE SYNC',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildField('TITLE', _titleController, accent),
          const SizedBox(height: 10),
          _buildField('ARTIST', _artistController, accent),
          const SizedBox(height: 10),
          _buildField('ALBUM', _albumController, accent),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: _buildField('GENRE', _genreController, accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: _buildField(
                  'YEAR',
                  _yearController,
                  accent,
                  isNumeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildField(
            'TRACK NO.',
            _trackNumController,
            accent,
            isNumeric: true,
          ),
        ],
      ),
    );
  }

  Widget _buildField(
      String label,
      TextEditingController controller,
      Color accent, {
        bool isNumeric = false,
      }) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: _theme.textTertiaryColor,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isWhitaniana
                ? _theme.containerColor
                : _theme.containerLowestColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _theme.cardBorderColor),
          ),
          child: TextField(
            controller: controller,
            cursorColor: accent,
            keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
            inputFormatters: isNumeric
                ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
                : null,
            style: TextStyle(
              color: _theme.textPrimaryColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileTelemetryCard(Color accent, Color containerLow) {
    final String extension = widget.song.fileExtension.isNotEmpty
        ? widget.song.fileExtension.toUpperCase()
        : 'AUDIO';
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.terminal_rounded,
                  color: _theme.secondaryAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                'Physical Storage Telemetry',
                style: TextStyle(
                  color: _theme.textPrimaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.song.data.isNotEmpty
                ? widget.song.data
                : '/storage/emulated/0/Music',
            style: TextStyle(color: _theme.textSecondaryColor, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Protocol: $extension • Direct Storage & MediaScanner Broadcast',
            style: TextStyle(color: accent, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedActionButtons(Color accent) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: _theme.activeGradient,
            boxShadow:
            LotusDecorations.glowShadow(accent, intensity: 0.35, blur: 16),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _isSaving ? null : _commitTagsToStorage,
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.check_circle_outline_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'COMMIT CHANGES TO FILE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _theme.textSecondaryColor,
              side: BorderSide(color: _theme.cardBorderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
      ],
    );
  }
}