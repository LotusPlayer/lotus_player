import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_equalizer_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_widgets.dart';
import '../options/lotus_track_options_sheet.dart';
import '../playlists/lotus_add_to_playlist_dialog.dart';
import 'lotus_mood_sanctuary_modal.dart';
import 'lotus_search_modal.dart';
import 'lotus_smart_flow_sheet.dart';

enum VaultSortField {
  title,
  artist,
  duration,
  dateAdded,
}

class LotusHomeScreen extends StatefulWidget {
  final ValueChanged<SongModel>? onSongSelected;
  final VoidCallback? onOpenNowPlaying;
  final ValueChanged<int>? onCategoryTapped;
  final VoidCallback? onOpenEqualizer;

  const LotusHomeScreen({
    super.key,
    this.onSongSelected,
    this.onOpenNowPlaying,
    this.onCategoryTapped,
    this.onOpenEqualizer,
  });

  @override
  State<LotusHomeScreen> createState() => _LotusHomeScreenState();
}

class _LotusHomeScreenState extends State<LotusHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
final OnAudioQuery _audioQuery = OnAudioQuery();
final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
final LotusEqualizerService _eqService = LotusEqualizerService.instance;
final LotusThemeController _theme = LotusThemeController.instance;

SharedPreferences? _cachedPrefs;

Future<SharedPreferences> _getPrefs() async =>
_cachedPrefs ??= await SharedPreferences.getInstance();

bool _hasPermission = false;
bool _isLoading = false;
bool _isScanning = false;
bool _showBackToTop = false;

Timer? _idleHideTimer;
Timer? _recentTimeTicker;
StreamSubscription<HiddenSongsChangeEvent>? _hiddenSongsSub;
late final AnimationController _backToTopAnimController;
late final Animation<double> _backToTopFadeAnimation;
late final Animation<Offset> _backToTopSlideAnimation;

List<SongModel> _allSongs = <SongModel>[];
List<AlbumModel> _allAlbums = <AlbumModel>[];
List<ArtistModel> _allArtists = <ArtistModel>[];

Map<int, List<SongModel>> _songsByAlbumId = <int, List<SongModel>>{};
Map<String, List<SongModel>> _songsByAlbumName = <String, List<SongModel>>{};
Map<String, List<SongModel>> _songsByArtistName = <String, List<SongModel>>{};
List<SongModel> _cachedDisplaySongs = <SongModel>[];

bool _isMoodCardTappedDown = false;
late final AnimationController _moodVisualizerController;
late final AnimationController _moodCardPulseController;

bool get _isBioEngineActive => _eqService.isMoodBioEngineActive;
String get _activeFrequencyLabel =>
_isBioEngineActive ? '528HZ ACTIVE' : 'BYPASS';

List<SongModel> get _recentSongs => _playback.recentSongs;

int _activeCategoryIndex = -1;
String? _selectedArtistFilter;
String? _selectedAlbumFilter;
int _selectedFilterIndex = 0;

final TextEditingController _searchController = TextEditingController();
final FocusNode _searchFocusNode = FocusNode();
String _activeSearchQuery = '';
Timer? _searchDebounceTimer;

late final AnimationController _pulseController;
late final AnimationController _spectrumController;
final ScrollController _scrollController = ScrollController();
final GlobalKey _vaultSectionKey = GlobalKey();
final GlobalKey _albumsSectionKey = GlobalKey();

VaultSortField _sortField = VaultSortField.title;
bool _isAscending = true;

@override
void initState() {
super.initState();
WidgetsBinding.instance.addObserver(this);

_pulseController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 2400),
);

_spectrumController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 950),
);

_moodVisualizerController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 900),
);

_moodCardPulseController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 1400),
);

_backToTopAnimController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 280),
reverseDuration: const Duration(milliseconds: 220),
);

_backToTopFadeAnimation = CurvedAnimation(
parent: _backToTopAnimController,
curve: Curves.easeOutCubic,
reverseCurve: Curves.easeInCubic,
);

_backToTopSlideAnimation = Tween<Offset>(
begin: const Offset(0.35, 0.0),
end: Offset.zero,
).animate(CurvedAnimation(
parent: _backToTopAnimController,
curve: Curves.easeOutBack,
reverseCurve: Curves.easeInCubic,
));

_scrollController.addListener(_onScrollListener);
_searchController.addListener(_onSearchInputChanged);
_playback.addListener(_onPlaybackStateChanged);
_playback.songMetadataRevisionNotifier.addListener(_onSongMetadataUpdated);
_theme.addListener(_onThemeChanged);
_eqService.addListener(_onEqChanged);
_hiddenSongsSub = _playback.hiddenSongsChangeStream.listen((_) {
if (!mounted) return;
setState(() {
_recomputeDisplaySongs();
});
});

_recentTimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
if (mounted && _recentSongs.isNotEmpty) {
setState(() {});
}
});

_syncAnimations();
_fastBootAudioInit();
}

void _syncAnimations() {
if (_playback.isPlaying && _playback.activeSong != null) {
if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
if (!_spectrumController.isAnimating) {
_spectrumController.repeat(reverse: true);
}
} else {
if (_pulseController.isAnimating) _pulseController.stop();
if (_spectrumController.isAnimating) _spectrumController.stop();
}

if (_isBioEngineActive) {
if (!_moodCardPulseController.isAnimating) {
_moodCardPulseController.repeat(reverse: true);
}
if (!_moodVisualizerController.isAnimating) {
_moodVisualizerController.repeat(reverse: true);
}
} else {
if (_moodCardPulseController.isAnimating) {
_moodCardPulseController.stop();
_moodCardPulseController.value = 0.0;
}
if (_moodVisualizerController.isAnimating) {
_moodVisualizerController.stop();
_moodVisualizerController.value = 0.0;
}
}
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
if (state == AppLifecycleState.resumed) {
if (!_hasPermission) {
_checkPermissionAndScan();
}
_syncAnimations();
_searchFocusNode.unfocus();
if (mounted) setState(() {});
} else {
if (_pulseController.isAnimating) _pulseController.stop();
if (_spectrumController.isAnimating) _spectrumController.stop();
if (_moodCardPulseController.isAnimating) {
_moodCardPulseController.stop();
}
if (_moodVisualizerController.isAnimating) {
_moodVisualizerController.stop();
}
}
}

void _onScrollListener() {
if (!_scrollController.hasClients) return;
final bool pastThreshold = _scrollController.offset > 420.0;

if (pastThreshold) {
if (!_showBackToTop) {
setState(() => _showBackToTop = true);
}
_revealBackToTopWithIdleTimer();
} else {
if (_showBackToTop) {
_idleHideTimer?.cancel();
_backToTopAnimController.reverse().then((_) {
if (mounted &&
_scrollController.hasClients &&
_scrollController.offset <= 420.0) {
setState(() => _showBackToTop = false);
}
});
}
}
}

void _revealBackToTopWithIdleTimer() {
_idleHideTimer?.cancel();

if (_backToTopAnimController.status != AnimationStatus.forward &&
_backToTopAnimController.status != AnimationStatus.completed) {
_backToTopAnimController.forward();
}

_idleHideTimer = Timer(const Duration(milliseconds: 2500), () {
if (mounted && _showBackToTop) {
_backToTopAnimController.reverse();
}
});
}

void _scrollToTop() {
HapticFeedback.mediumImpact();
_idleHideTimer?.cancel();
_backToTopAnimController.reverse();

if (_scrollController.hasClients) {
_scrollController
.animateTo(
0.0,
duration: const Duration(milliseconds: 550),
curve: Curves.easeOutCubic,
)
.then((_) {
if (mounted) {
setState(() => _showBackToTop = false);
}
});
} else {
if (mounted) setState(() => _showBackToTop = false);
}
}

@override
void dispose() {
WidgetsBinding.instance.removeObserver(this);
_idleHideTimer?.cancel();
_recentTimeTicker?.cancel();
_searchDebounceTimer?.cancel();
_hiddenSongsSub?.cancel();
_backToTopAnimController.dispose();
_pulseController.dispose();
_spectrumController.dispose();
_moodVisualizerController.dispose();
_moodCardPulseController.dispose();
_scrollController.removeListener(_onScrollListener);
_scrollController.dispose();
_searchController.removeListener(_onSearchInputChanged);
_searchController.dispose();
_searchFocusNode.dispose();
_playback.removeListener(_onPlaybackStateChanged);
_playback.songMetadataRevisionNotifier
.removeListener(_onSongMetadataUpdated);
_theme.removeListener(_onThemeChanged);
_eqService.removeListener(_onEqChanged);
super.dispose();
}

void _onThemeChanged() {
if (mounted) setState(() {});
}

void _onSongMetadataUpdated() {
bool updated = false;
for (int i = 0; i < _allSongs.length; i++) {
final SongModel? latest = _playback.getSongById(_allSongs[i].id);
if (latest != null && !identical(latest, _allSongs[i])) {
_allSongs[i] = latest;
updated = true;
}
}
if (updated) {
_rebuildAlbumIndex(_allSongs);
_recomputeDisplaySongs();
}
if (mounted) setState(() {});
}

void _onPlaybackStateChanged() {
final SongModel? active = _playback.activeSong;
if (active != null) {
final int index =
_allSongs.indexWhere((SongModel s) => s.id == active.id);
if (index != -1 &&
(_allSongs[index].title != active.title ||
_allSongs[index].artist != active.artist ||
_allSongs[index].album != active.album)) {
_allSongs[index] = active;
_rebuildAlbumIndex(_allSongs);
_recomputeDisplaySongs();
if (mounted) setState(() {});
}
}

_syncAnimations();
}

void _onEqChanged() {
_syncAnimations();
if (mounted) setState(() {});
}

void _onSearchInputChanged() {
_searchDebounceTimer?.cancel();
_searchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
final String query = _searchController.text.trim();
if (_activeSearchQuery != query) {
setState(() {
_activeSearchQuery = query;
_recomputeDisplaySongs();
});
}
});
}

Future<void> _fastBootAudioInit() async {
await _checkPermissionAndScan();
}

Future<void> _checkPermissionAndScan() async {
try {
bool granted = false;

if (!kIsWeb && Platform.isAndroid) {
if (await Permission.audio.isGranted ||
await Permission.storage.isGranted) {
granted = true;
} else {
final Map<Permission, PermissionStatus> statuses = await <Permission>[
Permission.audio,
Permission.storage,
].request();

granted = (statuses[Permission.audio]?.isGranted == true) ||
(statuses[Permission.storage]?.isGranted == true);
}
} else {
granted = true;
}

if (!mounted) return;

setState(() {
_hasPermission = granted;
});

if (granted) {
await _scanDeviceLibrary();
}
} catch (e) {
debugPrint('Lotus permission notice: $e');
}
}

void _rebuildAlbumIndex(List<SongModel> songs) {
final Map<int, List<SongModel>> byId = <int, List<SongModel>>{};
final Map<String, List<SongModel>> byName = <String, List<SongModel>>{};
final Map<String, List<SongModel>> byArtist = <String, List<SongModel>>{};
for (final SongModel s in songs) {
if (s.albumId != null) {
(byId[s.albumId!] ??= <SongModel>[]).add(s);
}
final String albumKey = (s.album ?? '').trim().toLowerCase();
if (albumKey.isNotEmpty) {
(byName[albumKey] ??= <SongModel>[]).add(s);
}
final String artistKey = (s.artist ?? '').trim().toLowerCase();
if (artistKey.isNotEmpty) {
(byArtist[artistKey] ??= <SongModel>[]).add(s);
}
}
_songsByAlbumId = byId;
_songsByAlbumName = byName;
_songsByArtistName = byArtist;
}

Future<void> _scanDeviceLibrary() async {
if (_isScanning) return;
_isScanning = true;

if (mounted) {
setState(() => _isLoading = true);
}

try {
final SharedPreferences prefs = await _getPrefs();

final List<SongModel> songs = await _audioQuery.querySongs(
sortType: SongSortType.TITLE,
orderType: OrderType.ASC_OR_SMALLER,
uriType: UriType.EXTERNAL,
ignoreCase: true,
);

final List<SongModel> valid =
songs.where((SongModel s) => (s.duration ?? 0) > 10000).toList();

try {
final String? rawRegistry =
prefs.getString('lotus_tag_overrides_registry_v2');
if (rawRegistry != null && rawRegistry.isNotEmpty) {
final dynamic decoded = jsonDecode(rawRegistry);
if (decoded is Map<String, dynamic>) {
for (int i = 0; i < valid.length; i++) {
final String songIdStr = valid[i].id.toString();
if (decoded.containsKey(songIdStr)) {
final dynamic override = decoded[songIdStr];
if (override is Map<String, dynamic>) {
final Map<dynamic, dynamic> rawMap =
Map<dynamic, dynamic>.from(valid[i].getMap);
if (override['title']?.toString().isNotEmpty == true) {
rawMap['title'] = override['title'];
}
if (override['artist']?.toString().isNotEmpty == true) {
rawMap['artist'] = override['artist'];
}
if (override['album']?.toString().isNotEmpty == true) {
rawMap['album'] = override['album'];
}
valid[i] = SongModel(rawMap);
}
}
}
}
}
} catch (_) {}

if (mounted) {
setState(() {
_allSongs = valid;
_rebuildAlbumIndex(valid);
_recomputeDisplaySongs();
});

if (valid.isNotEmpty) {
_playback.hydrateLastPlayed(valid);
}
}

final List<AlbumModel> albums = await _audioQuery.queryAlbums(
sortType: AlbumSortType.ALBUM,
orderType: OrderType.ASC_OR_SMALLER,
uriType: UriType.EXTERNAL,
ignoreCase: true,
);

final List<ArtistModel> artists = await _audioQuery.queryArtists(
sortType: ArtistSortType.ARTIST,
orderType: OrderType.ASC_OR_SMALLER,
uriType: UriType.EXTERNAL,
ignoreCase: true,
);

if (mounted) {
setState(() {
_allAlbums = albums;
_allArtists = artists;
});
}
} catch (e) {
debugPrint('Lotus scan library notice: $e');
} finally {
_isScanning = false;
if (mounted) setState(() => _isLoading = false);
}
}

Future<void> _handlePullToRefresh() async {
HapticFeedback.mediumImpact();
await _checkPermissionAndScan();
}

void _handleTrackDeleted(SongModel deletedSong) {
HapticFeedback.mediumImpact();
setState(() {
_allSongs.removeWhere((SongModel s) => s.id == deletedSong.id);
_rebuildAlbumIndex(_allSongs);
_recomputeDisplaySongs();
});
}

void _openTrackOptions(SongModel song) {
HapticFeedback.lightImpact();
LotusTrackOptionsSheet.show(
context,
song: song,
onOpenPlaylistDialog: () {
LotusAddToPlaylistDialog.show(context, song: song);
},
onTrackDeleted: _handleTrackDeleted,
onTagsUpdated: (SongModel updatedSong) {
setState(() {
final int index =
_allSongs.indexWhere((SongModel s) => s.id == updatedSong.id);
if (index != -1) {
_allSongs[index] = updatedSong;
_rebuildAlbumIndex(_allSongs);
_recomputeDisplaySongs();
}
});
},
);
}

Future<void> _toggleFavoriteSong(SongModel song) async {
HapticFeedback.mediumImpact();
final bool isNowFav = !_playback.isSongFavorite(song.id);

await _playback.toggleFavoriteSong(song);

if (mounted) {
final Color secondaryAccent = _theme.secondaryAccent;
LotusSnackBar.show(
context,
message: isNowFav
? 'Added "${song.title}" to Favorites Vault'
: 'Removed "${song.title}" from Favorites Vault',
icon: isNowFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
iconColor: secondaryAccent,
);
}
}

void _toggleSortOrder() {
HapticFeedback.selectionClick();
setState(() {
_isAscending = !_isAscending;
_recomputeDisplaySongs();
});
}

void _showSortMenu() {
HapticFeedback.selectionClick();
final Color accent = _theme.primaryAccent;
final Color modalShieldSurface = _theme.modalSurfaceColor;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

showModalBottomSheet<void>(
context: context,
backgroundColor: Colors.transparent,
barrierColor: Colors.black.withValues(alpha: 0.85),
builder: (BuildContext ctx) => Container(
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
decoration: BoxDecoration(
color: modalShieldSurface,
borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
border: Border(
top: BorderSide(
color: accent.withValues(alpha: 0.85),
width: 1.8,
),
left: BorderSide(
color: accent.withValues(alpha: 0.35),
width: 1.0,
),
right: BorderSide(
color: accent.withValues(alpha: 0.35),
width: 1.0,
),
),
boxShadow: <BoxShadow>[
BoxShadow(
color: Colors.black.withValues(alpha: 0.6),
blurRadius: 36,
spreadRadius: 8,
offset: const Offset(0, -6),
),
...LotusDecorations.glowShadow(accent, intensity: 0.28, blur: 28),
],
),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: <Widget>[
Center(
child: Container(
width: 40,
height: 4,
margin: const EdgeInsets.only(bottom: 12),
decoration: BoxDecoration(
color: _theme.isWhitanianaActive
? LotusColors.whitanianaCardBorder
: Colors.white24,
borderRadius: BorderRadius.circular(2),
),
),
),
Row(
children: <Widget>[
Icon(Icons.sort_rounded, color: accent, size: 20),
const SizedBox(width: 8),
Expanded(
child: Text(
'Sort Device Audio Vault',
style: TextStyle(
color: textPrimary,
fontSize: 15,
fontWeight: FontWeight.bold,
),
),
),
GestureDetector(
onTap: () {
Navigator.of(ctx).pop();
_toggleSortOrder();
},
child: Container(
padding:
const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.18),
borderRadius: BorderRadius.circular(12),
border: Border.all(color: accent.withValues(alpha: 0.4)),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(
_isAscending
? Icons.arrow_upward_rounded
: Icons.arrow_downward_rounded,
size: 14,
color: accent,
),
const SizedBox(width: 4),
Text(
_isAscending ? 'ASC' : 'DESC',
style: TextStyle(
color: accent,
fontSize: 10,
fontWeight: FontWeight.w900,
),
),
],
),
),
),
],
),
Divider(color: _theme.cardBorderColor, height: 16),
_buildSortOptionTile(
ctx,
'Track Title (Alphabetical)',
VaultSortField.title,
Icons.title_rounded,
accent,
textPrimary,
textSecondary,
),
_buildSortOptionTile(
ctx,
'Artist Name',
VaultSortField.artist,
Icons.person_rounded,
accent,
textPrimary,
textSecondary,
),
_buildSortOptionTile(
ctx,
'Duration (Length)',
VaultSortField.duration,
Icons.timer_rounded,
accent,
textPrimary,
textSecondary,
),
_buildSortOptionTile(
ctx,
'Date Added (Recent)',
VaultSortField.dateAdded,
Icons.calendar_today_rounded,
accent,
textPrimary,
textSecondary,
),
],
),
),
);
}

Widget _buildSortOptionTile(
BuildContext ctx,
String label,
VaultSortField field,
IconData icon,
Color accent,
Color textPrimary,
Color textSecondary,
) {
final bool isSelected = _sortField == field;
return ListTile(
dense: true,
contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
leading: Icon(icon, color: isSelected ? accent : textSecondary, size: 18),
title: Text(
label,
style: TextStyle(
color: isSelected ? textPrimary : textSecondary,
fontSize: 13,
fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
),
),
trailing: isSelected
? Icon(
_isAscending
? Icons.arrow_upward_rounded
: Icons.arrow_downward_rounded,
color: accent,
size: 18,
)
: null,
onTap: () {
HapticFeedback.selectionClick();
setState(() {
if (_sortField == field) {
_isAscending = !_isAscending;
} else {
_sortField = field;
}
_recomputeDisplaySongs();
});
Navigator.of(ctx).pop();
},
);
}

void _openSearchModal() {
HapticFeedback.selectionClick();
_searchFocusNode.unfocus();
LotusSearchModalSafe.show(
context,
allSongs: _allSongs,
onSongSelected: (SongModel song) {
widget.onSongSelected?.call(song);
},
);
}

void _openSmartFlowCustomizerSheet() {
HapticFeedback.heavyImpact();
_searchFocusNode.unfocus();
LotusSmartFlowSheet.show(
context,
allSongs: _allSongs,
referenceSong: _playback.activeSong,
onFlowCompiled: (List<SongModel> compiledQueue) {
if (mounted) setState(() {});
},
);
}

Future<void> _triggerSmartFlow() async {
HapticFeedback.heavyImpact();
_searchFocusNode.unfocus();
final Color accent = _theme.primaryAccent;

final List<SongModel> visiblePool = _allSongs
.where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
.toList();

if (visiblePool.isEmpty) {
LotusSnackBar.show(
context,
message: 'No tracks available in storage vault to compile Smart Flow.',
icon: Icons.info_outline_rounded,
iconColor: accent,
);
return;
}

final SongModel? referenceSong =
_playback.activeSong ?? visiblePool.firstOrNull;
if (referenceSong == null) return;

final List<SongModel> compiledQueue = List<SongModel>.from(visiblePool)
..shuffle();
compiledQueue.removeWhere((SongModel s) => s.id == referenceSong.id);
compiledQueue.insert(0, referenceSong);

_playback.playSong(referenceSong, queue: compiledQueue);

if (!mounted) return;
LotusSnackBar.show(
context,
message: 'Smart Flow Active: Harmonic stems queued • Bit-Perfect DSP Aligned',
icon: Icons.all_inclusive_rounded,
iconColor: accent,
);
}

void _triggerShuffleVault() {
HapticFeedback.mediumImpact();
_searchFocusNode.unfocus();
final List<SongModel> visiblePool = _allSongs
.where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
.toList();
if (visiblePool.isEmpty) return;

final Color secondaryAccent = _theme.secondaryAccent;
final List<SongModel> shuffledQueue = List<SongModel>.from(visiblePool)
..shuffle();
final SongModel randomPick = shuffledQueue.first;

_playback.playSong(randomPick, queue: shuffledQueue);

LotusSnackBar.show(
context,
message: 'Shuffled ${visiblePool.length} tracks • Playing "${randomPick.title}"',
icon: Icons.shuffle_rounded,
iconColor: secondaryAccent,
);
}

void _openMoodSanctuaryModal() {
HapticFeedback.heavyImpact();
_searchFocusNode.unfocus();
LotusMoodSanctuaryModal.show(
context,
isEngineActive: _isBioEngineActive,
onToggleEngine: (bool active) async {
await _eqService.setMoodBioEngine(enabled: active);
if (active) {
await _theme.activateMoodMatrixTheme();
} else {
await _theme.deactivateMoodMatrixTheme();
}
_syncAnimations();
if (mounted) setState(() {});
},
);
}

void _handleCategoryCardTap(int categoryIndex) {
HapticFeedback.selectionClick();
_searchFocusNode.unfocus();

setState(() {
if (_activeCategoryIndex == categoryIndex && categoryIndex != 3) {
_activeCategoryIndex = -1;
_selectedArtistFilter = null;
_selectedAlbumFilter = null;
} else {
_activeCategoryIndex = categoryIndex;
}
_recomputeDisplaySongs();
});

switch (categoryIndex) {
case 0:
setState(() {
_selectedArtistFilter = null;
_selectedAlbumFilter = null;
_searchController.clear();
_recomputeDisplaySongs();
});
_scrollToSection(offsetAdjustment: 480.0);
break;
case 1:
_openArtistsFilterModal();
break;
case 2:
_scrollToSection(offsetAdjustment: 320.0);
break;
case 3:
_openMoodSanctuaryModal();
break;
}
}

void _scrollToSection({double offsetAdjustment = 400.0}) {
if (_scrollController.hasClients) {
final double targetOffset = math.min(
offsetAdjustment,
_scrollController.position.maxScrollExtent,
);
_scrollController.animateTo(
targetOffset,
duration: const Duration(milliseconds: 450),
curve: Curves.easeOutCubic,
);
}
}

void _scrollToActiveSong() {
HapticFeedback.heavyImpact();
_searchFocusNode.unfocus();
if (!_scrollController.hasClients) return;

final SongModel? playing = _playback.activeSong;
if (playing == null) return;

final int targetIndex =
_cachedDisplaySongs.indexWhere((SongModel s) => _playback.isActiveSong(s));
if (targetIndex == -1) return;

const double headerHeight = 780.0;
const double itemHeight = 74.0;
final double targetOffset =
(headerHeight + (targetIndex * itemHeight) - 80.0)
.clamp(0.0, _scrollController.position.maxScrollExtent);

_scrollController.animateTo(
targetOffset,
duration: const Duration(milliseconds: 550),
curve: Curves.easeOutCubic,
);

if ((targetIndex >= 6 || targetOffset > 420.0) && mounted) {
setState(() => _showBackToTop = true);
_revealBackToTopWithIdleTimer();
}

LotusSnackBar.show(
context,
message: 'Jumped to active track: "${playing.title}" (#${targetIndex + 1})',
icon: Icons.my_location_rounded,
iconColor: _theme.primaryAccent,
);
}

void _openArtistsFilterModal() {
_searchFocusNode.unfocus();
showModalBottomSheet<void>(
context: context,
backgroundColor: Colors.transparent,
barrierColor: Colors.black.withValues(alpha: 0.85),
isScrollControlled: true,
builder: (BuildContext ctx) {
return _LotusArtistsFilterSheet(
allArtists: _allArtists,
allSongs: _allSongs,
songsByArtistName: _songsByArtistName,
selectedArtistFilter: _selectedArtistFilter,
onArtistSelected: (String? selectedArtist, SongModel? songToPlay,
List<SongModel>? artistQueue) {
setState(() {
_selectedArtistFilter = selectedArtist;
_selectedAlbumFilter = null;
_activeCategoryIndex = selectedArtist != null ? 1 : -1;
_recomputeDisplaySongs();
});

if (songToPlay != null && artistQueue != null) {
_playback.playSong(songToPlay, queue: artistQueue);
widget.onSongSelected?.call(songToPlay);

LotusSnackBar.show(
context,
message: 'Playing: "${songToPlay.title}" by ${selectedArtist ?? ""}',
icon: Icons.play_circle_fill_rounded,
iconColor: _theme.secondaryAccent,
);
} else if (selectedArtist != null) {
_scrollToSection(offsetAdjustment: 480.0);
}
},
);
},
);
}

void _handleSongSelected(SongModel song) {
HapticFeedback.lightImpact();
_searchFocusNode.unfocus();
_playback.playSong(song, queue: _cachedDisplaySongs);
widget.onSongSelected?.call(song);
}

void _recomputeDisplaySongs() {
final String query = _activeSearchQuery.toLowerCase();
final String? artistFilter = _selectedArtistFilter?.toLowerCase();
final String? albumFilter = _selectedAlbumFilter?.toLowerCase();

List<SongModel> list = _allSongs.where((SongModel s) {
if (_playback.isSongHidden(s.id, s.data)) return false;

if (query.isNotEmpty) {
final String title = s.title.toLowerCase();
final String artist = (s.artist ?? '').toLowerCase();
final String album = (s.album ?? '').toLowerCase();
if (!title.contains(query) &&
!artist.contains(query) &&
!album.contains(query)) {
return false;
}
}

if (artistFilter != null &&
(s.artist ?? '').toLowerCase() != artistFilter) {
return false;
}

if (albumFilter != null &&
(s.album ?? '').toLowerCase() != albumFilter) {
return false;
}

if (_selectedFilterIndex == 1) {
final String ext = s.fileExtension.toLowerCase();
final bool isLossless = ext.contains('flac') ||
ext.contains('dsd') ||
ext.contains('alac') ||
ext.contains('wav');
if (!isLossless && (s.duration ?? 0) < 180000) return false;
}

return true;
}).toList();

switch (_sortField) {
case VaultSortField.title:
list.sort((SongModel a, SongModel b) =>
a.title.toLowerCase().compareTo(b.title.toLowerCase()));
break;
case VaultSortField.artist:
list.sort((SongModel a, SongModel b) => (a.artist ?? '')
.toLowerCase()
.compareTo((b.artist ?? '').toLowerCase()));
break;
case VaultSortField.duration:
list.sort((SongModel a, SongModel b) =>
(b.duration ?? 0).compareTo(a.duration ?? 0));
break;
case VaultSortField.dateAdded:
list.sort((SongModel a, SongModel b) =>
(b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
break;
}

if (!_isAscending) {
list = list.reversed.toList();
}

_cachedDisplaySongs = list;
}

String _formatRecentTimeAgo(int? playedAtMs, bool isActivelyPlaying) {
if (isActivelyPlaying) return 'Now';
if (playedAtMs == null || playedAtMs <= 0) return 'Earlier';

final int diffMs = DateTime.now().millisecondsSinceEpoch - playedAtMs;
if (diffMs < 0) return 'Just now';

final Duration diff = Duration(milliseconds: diffMs);
if (diff.inSeconds < 60) {
return 'Just now';
} else if (diff.inMinutes < 60) {
return '${diff.inMinutes}m ago';
} else if (diff.inHours < 24) {
return '${diff.inHours}h ago';
} else if (diff.inDays == 1) {
return 'Yesterday';
} else if (diff.inDays < 7) {
return '${diff.inDays}d ago';
} else {
final DateTime dt = DateTime.fromMillisecondsSinceEpoch(playedAtMs);
return '${dt.day}/${dt.month}';
}
}

@override
Widget build(BuildContext context) {
return ListenableBuilder(
listenable: _theme,
builder: (BuildContext context, Widget? child) {
final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;
final Color effectiveBgColor = _theme.backgroundColor;
final Color surfaceColor = _theme.surfaceColor;
final Color containerLow = _theme.containerLowColor;

return Scaffold(
backgroundColor: effectiveBgColor,
body: SafeArea(
top: true,
bottom: false,
child: Stack(
children: <Widget>[
RefreshIndicator(
color: accent,
backgroundColor: surfaceColor,
displacement: 28.0,
onRefresh: _handlePullToRefresh,
child: CustomScrollView(
controller: _scrollController,
physics: const BouncingScrollPhysics(
parent: AlwaysScrollableScrollPhysics()),
slivers: <Widget>[
SliverToBoxAdapter(
child: RepaintBoundary(
child: _buildSignatureBrandHeader(
accent, surfaceColor, containerLow),
),
),
SliverToBoxAdapter(
child: RepaintBoundary(
child: _buildCategoryShortcutCards(
accent, secondaryAccent, containerLow),
),
),
SliverToBoxAdapter(
child: RepaintBoundary(
child: ListenableBuilder(
listenable: _playback,
builder: (BuildContext context, _) {
return _buildHarmonicBloomHero(
accent, secondaryAccent);
},
),
),
),
SliverToBoxAdapter(
child: _buildFilterChips(
accent, secondaryAccent, containerLow),
),
if (_allAlbums.isNotEmpty)
SliverToBoxAdapter(
key: _albumsSectionKey,
child: RepaintBoundary(
child: _buildAcousticVelocityCarousel(
accent, secondaryAccent, containerLow),
),
),
SliverToBoxAdapter(
child: RepaintBoundary(
child: ListenableBuilder(
listenable: _playback,
builder: (BuildContext context, _) {
if (_recentSongs.isEmpty) {
return const SizedBox.shrink();
}
return _buildRecentlyPlayedCarousel(
accent, secondaryAccent, containerLow);
},
),
),
),
SliverToBoxAdapter(
key: _vaultSectionKey,
child: _buildSectionHeader(
accent, secondaryAccent, containerLow),
),
_buildRealSongListSliver(
accent, secondaryAccent, containerLow),
SliverToBoxAdapter(
child: ListenableBuilder(
listenable: _playback,
builder: (BuildContext context, _) {
return SizedBox(
height: _playback.activeSong != null ? 160 : 100,
);
},
),
),
],
),
),
if (_showBackToTop)
ListenableBuilder(
listenable: _playback,
builder: (BuildContext context, _) {
return Positioned(
right: 18,
bottom: _playback.activeSong != null ? 148 : 88,
child: SlideTransition(
position: _backToTopSlideAnimation,
child: FadeTransition(
opacity: _backToTopFadeAnimation,
child: _buildUniqueBackToTopOrb(
accent, secondaryAccent),
),
),
);
},
),
],
),
),
);
},
);
}

Widget _buildUniqueBackToTopOrb(Color accent, Color secondaryAccent) {
final bool isSpecialTheme = _theme.isMoodMatrixActive ||
_theme.isStarryNightActive ||
_theme.isTransparentPassThrough;

final Color solidOrbBg = isSpecialTheme
? const Color(0xFF070B14)
: (_theme.isAmoled
? const Color(0xFF080C16)
: (_theme.isWhitanianaActive
? LotusColors.whitanianaPureWhiteCard
: _theme.containerLowColor));

return Material(
color: Colors.transparent,
child: InkWell(
onTap: _scrollToTop,
borderRadius: BorderRadius.circular(24),
splashColor: accent.withValues(alpha: 0.25),
highlightColor: secondaryAccent.withValues(alpha: 0.15),
child: Container(
width: 48,
height: 48,
decoration: BoxDecoration(
color: solidOrbBg,
shape: BoxShape.circle,
border: Border.all(
color: accent.withValues(alpha: 0.92),
width: 1.6,
),
boxShadow: <BoxShadow>[
BoxShadow(
color: Colors.black.withValues(
alpha: _theme.isWhitanianaActive ? 0.15 : 0.90),
blurRadius: 20,
offset: const Offset(0, 6),
),
...LotusDecorations.glowShadow(accent, intensity: 0.38, blur: 18),
],
),
child: Stack(
alignment: Alignment.center,
children: <Widget>[
Container(
width: 36,
height: 36,
decoration: BoxDecoration(
shape: BoxShape.circle,
border: Border.all(
color: secondaryAccent.withValues(alpha: 0.40),
width: 1.0,
),
gradient: RadialGradient(
colors: <Color>[
secondaryAccent.withValues(alpha: 0.12),
Colors.transparent,
],
radius: 0.85,
),
),
),
Column(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(
Icons.keyboard_double_arrow_up_rounded,
color: accent,
size: 22,
),
const SizedBox(height: 1),
Container(
width: 3.5,
height: 3.5,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: secondaryAccent,
boxShadow: LotusDecorations.glowShadow(
secondaryAccent,
intensity: 0.65,
blur: 6,
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
}

Widget _buildSignatureBrandHeader(
Color accent, Color surfaceColor, Color containerLow) {
final Color textPrimary = _theme.textPrimaryColor;
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
decoration: BoxDecoration(
color: surfaceColor,
border: Border(
bottom: BorderSide(
color: isWhitaniana
? _theme.cardBorderColor
: accent.withValues(alpha: 0.2),
width: 0.8,
),
),
),
padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 8.0),
child: Column(
children: <Widget>[
Row(
children: <Widget>[
Container(
width: 44,
height: 44,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: containerLow,
border: Border.all(color: accent, width: 1.8),
boxShadow: LotusDecorations.glowShadow(accent,
intensity: 0.35, blur: 16),
),
child: ClipOval(
child: Image.asset(
'assets/icons/top_bar_icon.png',
fit: BoxFit.cover,
cacheWidth: 128,
cacheHeight: 128,
errorBuilder: (BuildContext context, Object error,
StackTrace? stackTrace) {
return Center(
child: Icon(Icons.local_florist_rounded,
color: accent, size: 30),
);
},
),
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
children: <Widget>[
Flexible(
fit: FlexFit.loose,
child: Text(
'Lotus Player',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: textPrimary,
fontSize: 17.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.3,
),
),
),
const SizedBox(width: 6),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 5, vertical: 1.5),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.18),
borderRadius: BorderRadius.circular(6),
border: Border.all(
color: accent.withValues(alpha: 0.5)),
),
child: Text(
'Rise & Bloom',
style: TextStyle(
color: accent,
fontSize: 7.5,
fontWeight: FontWeight.w900,
),
),
),
],
),
const SizedBox(height: 2),
Row(
children: <Widget>[
Container(
width: 5,
height: 5,
decoration: BoxDecoration(
color: accent,
shape: BoxShape.circle,
),
),
const SizedBox(width: 5),
Flexible(
fit: FlexFit.loose,
child: Text(
'Makes Your Emotions Bloom',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: accent,
fontSize: 9,
fontWeight: FontWeight.w700,
letterSpacing: 0.6,
),
),
),
],
),
],
),
),
_buildCircleIconButton(
Icons.search_rounded,
_openSearchModal,
isWhitaniana ? _theme.containerColor : containerLow,
tooltip: 'Search Device Music Vault',
customIcon: const LotusSearchIcon(size: 20),
),
],
),
const SizedBox(height: 10),
Container(
height: 46,
padding: const EdgeInsets.symmetric(horizontal: 14),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(23),
border: Border.all(
color: _activeSearchQuery.isNotEmpty
? accent
: _theme.cardBorderColor,
width: _activeSearchQuery.isNotEmpty ? 1.2 : 0.8,
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
: null,
),
child: Row(
children: <Widget>[
const LotusSearchIcon(size: 20),
const SizedBox(width: 10),
Expanded(
child: TextField(
controller: _searchController,
focusNode: _searchFocusNode,
autofocus: false,
style: TextStyle(color: textPrimary, fontSize: 13),
cursorColor: accent,
decoration: InputDecoration(
hintText: 'Search songs, artists, albums...',
hintStyle: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 13,
),
border: InputBorder.none,
contentPadding: const EdgeInsets.symmetric(vertical: 10),
isDense: true,
),
),
),
if (_activeSearchQuery.isNotEmpty)
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () {
HapticFeedback.lightImpact();
_searchController.clear();
_searchFocusNode.unfocus();
},
child: Padding(
padding: const EdgeInsets.all(6.0),
child: Icon(Icons.close_rounded,
color: _theme.textTertiaryColor, size: 18),
),
)
else
GestureDetector(
onTap: _openSearchModal,
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 8, vertical: 3.5),
decoration: BoxDecoration(
color: isWhitaniana
? _theme.containerHighColor
: _theme.containerColor,
borderRadius: BorderRadius.circular(8),
),
child: Text(
'ALL VAULT',
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.bold,
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

Widget _buildCategoryShortcutCards(
Color accent, Color secondaryAccent, Color containerLow) {
final int songsCount = _allSongs
.where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
.length;
final int artistsCount = _allArtists.length;
final int albumsCount = _allAlbums.length;

return Padding(
padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
child: Column(
children: <Widget>[
Row(
children: <Widget>[
Expanded(
child: _buildCategoryCard(
icon: Icons.music_note_rounded,
iconColor: accent,
title: 'Songs',
count: '$songsCount Tracks',
badge: 'FLAC',
badgeColor: accent,
containerLow: containerLow,
isActive: _activeCategoryIndex == 0,
onTap: () => _handleCategoryCardTap(0),
),
),
const SizedBox(width: 10),
Expanded(
child: _buildCategoryCard(
icon: Icons.person_rounded,
iconColor: secondaryAccent,
title: 'Artists',
count: '$artistsCount Curated',
badge: 'STUDIO',
badgeColor: secondaryAccent,
containerLow: containerLow,
isActive: _activeCategoryIndex == 1,
onTap: () => _handleCategoryCardTap(1),
),
),
],
),
const SizedBox(height: 10),
Row(
children: <Widget>[
Expanded(
child: _buildCategoryCard(
icon: Icons.album_rounded,
iconColor: LotusColors.solarGold,
title: 'Albums',
count: '$albumsCount Masters',
badge: 'DSD256',
badgeColor: LotusColors.solarGold,
containerLow: containerLow,
isActive: _activeCategoryIndex == 2,
onTap: () => _handleCategoryCardTap(2),
),
),
const SizedBox(width: 10),
Expanded(
child:
_buildLotusMoodCard(accent, secondaryAccent, containerLow),
),
],
),
],
),
);
}

Widget _buildCategoryCard({
required IconData icon,
required Color iconColor,
required String title,
required String count,
required String badge,
required Color badgeColor,
required Color containerLow,
required bool isActive,
required VoidCallback onTap,
}) {
final bool isWhitaniana = _theme.isWhitanianaActive;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

return GestureDetector(
onTap: () {
HapticFeedback.lightImpact();
onTap();
},
child: Container(
height: 126,
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: isActive ? iconColor.withValues(alpha: 0.18) : containerLow,
borderRadius: BorderRadius.circular(18),
border: Border.all(
color: isActive ? iconColor : _theme.cardBorderColor,
width: isActive ? 1.6 : 0.9,
),
boxShadow: isActive
? LotusDecorations.glowShadow(iconColor,
intensity: 0.28, blur: 14)
: (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Container(
padding: const EdgeInsets.all(7),
decoration: BoxDecoration(
color: iconColor.withValues(alpha: 0.16),
shape: BoxShape.circle,
),
child: Icon(icon, color: iconColor, size: 18),
),
Icon(Icons.arrow_outward_rounded,
color: _theme.textTertiaryColor, size: 16),
],
),
const Spacer(),
Text(
title,
style: TextStyle(
color: textPrimary,
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 2),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Expanded(
child: Text(
count,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: textSecondary,
fontSize: 10,
),
),
),
const SizedBox(width: 4),
Text(
badge,
style: TextStyle(
color: badgeColor,
fontSize: 8.5,
fontWeight: FontWeight.w900,
fontFamily: 'monospace',
),
),
],
),
],
),
),
);
}

Widget _buildLotusMoodCard(
Color accent, Color secondaryAccent, Color containerLow) {
final bool isActive = _isBioEngineActive;
final bool isPressed = _isMoodCardTappedDown;
final bool isWhitaniana = _theme.isWhitanianaActive;

return GestureDetector(
onTapDown: (_) => setState(() => _isMoodCardTappedDown = true),
onTapUp: (_) => setState(() => _isMoodCardTappedDown = false),
onTapCancel: () => setState(() => _isMoodCardTappedDown = false),
onTap: _openMoodSanctuaryModal,
child: AnimatedBuilder(
animation: _moodCardPulseController,
builder: (BuildContext context, Widget? child) {
final double pulse = isActive ? _moodCardPulseController.value : 0.0;

return AnimatedContainer(
duration: const Duration(milliseconds: 140),
curve: Curves.easeOutCubic,
height: 126,
transform: Matrix4.identity()
..translateByDouble(
0.0,
isPressed ? 3.0 : (isActive ? 1.5 : 0.0),
0.0,
1.0,
)
..scaleByDouble(
isPressed ? 0.95 : (isActive ? 0.98 : 1.0),
isPressed ? 0.95 : (isActive ? 0.98 : 1.0),
1.0,
1.0,
),
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
gradient: isActive
? LinearGradient(
colors: <Color>[
const Color(0xFF1E0E35).withValues(alpha: 0.65),
const Color(0xFF0F1829).withValues(alpha: 0.50),
_theme.containerLowestColor,
],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
)
: LinearGradient(
colors: <Color>[
const Color(0xFF7928CA).withValues(alpha: 0.12),
containerLow,
],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
borderRadius: BorderRadius.circular(18),
border: Border.all(
color: isActive
? secondaryAccent.withValues(alpha: 0.85 + (0.15 * pulse))
: _theme.cardBorderColor,
width: isActive ? 1.8 : 0.9,
),
boxShadow: isActive
? <BoxShadow>[
BoxShadow(
color: Colors.black.withValues(alpha: 0.6),
blurRadius: 10,
offset: const Offset(0, 3),
),
BoxShadow(
color: secondaryAccent
.withValues(alpha: 0.28 + (0.18 * pulse)),
  blurRadius: 20 + (10 * pulse),
  spreadRadius: 1.5,
),
  BoxShadow(
    color: accent.withValues(alpha: 0.20),
    blurRadius: 14,
  ),
]
    : (isWhitaniana
    ? LotusDecorations.whitanianaCardShadow()
    : null),
),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: isActive
                  ? LotusColors.voltLime.withValues(alpha: 0.22)
                  : (isWhitaniana
                  ? _theme.containerHighColor
                  : Colors.white10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? LotusColors.voltLime.withValues(alpha: 0.6)
                    : (isWhitaniana
                    ? _theme.cardBorderColor
                    : Colors.white12),
                width: 0.8,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? LotusColors.voltLime
                        : _theme.textTertiaryColor,
                    boxShadow: isActive
                        ? LotusDecorations.glowShadow(
                        LotusColors.voltLime,
                        intensity: 0.6,
                        blur: 6)
                        : null,
                  ),
                ),
                const SizedBox(width: 4.5),
                Text(
                  isActive ? 'ENGAGED' : 'STANDBY',
                  style: TextStyle(
                    color: isActive
                        ? LotusColors.voltLime
                        : _theme.textTertiaryColor,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: (isActive
                  ? secondaryAccent
                  : _theme.textTertiaryColor)
                  .withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: (isActive
                    ? secondaryAccent
                    : _theme.textTertiaryColor)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              Icons.spa_rounded,
              color: isActive
                  ? secondaryAccent
                  : _theme.textSecondaryColor,
              size: 16,
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Row(
        children: <Widget>[
          Text(
            _activeFrequencyLabel,
            style: TextStyle(
              color: isActive
                  ? secondaryAccent
                  : _theme.textTertiaryColor,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              fontFamily: 'monospace',
            ),
          ),
          if (isActive) ...<Widget>[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 0.5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'SOLFEGGIO',
                style: TextStyle(
                  color: accent,
                  fontSize: 7.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
      const Spacer(),
      Row(
        children: <Widget>[
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              'Lotus Mood',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _theme.textPrimaryColor,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (isActive) ...<Widget>[
            const SizedBox(width: 5),
            Icon(Icons.check_circle_rounded,
                color: secondaryAccent, size: 14),
          ],
        ],
      ),
      const SizedBox(height: 2),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Text(
              isActive ? 'Harmonic Matrix' : 'Circadian Bio-Mixer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive
                    ? (isWhitaniana
                    ? LotusColors.whitanianaCyanAccent
                    : Colors.white70)
                    : _theme.textSecondaryColor,
                fontSize: 9.5,
                fontWeight:
                isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _moodVisualizerController,
            builder: (BuildContext context, Widget? child) {
              return Row(
                children: List<Widget>.generate(4, (int i) {
                  final double h = isActive
                      ? (6 +
                      (11 *
                          ((_moodVisualizerController.value +
                              (i * 0.25)) %
                              1.0)))
                      : 4.0;
                  return Container(
                    width: 2.8,
                    height: h,
                    margin: const EdgeInsets.only(left: 2.2),
                    decoration: BoxDecoration(
                      color: i % 2 == 0 ? accent : secondaryAccent,
                      borderRadius: BorderRadius.circular(1.5),
                      boxShadow: isActive
                          ? <BoxShadow>[
                        BoxShadow(
                          color: (i % 2 == 0
                              ? accent
                              : secondaryAccent)
                              .withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ]
                          : null,
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    ],
  ),
);
},
),
);
}

Widget _buildHarmonicBloomHero(Color accent, Color secondaryAccent) {
  final SongModel? currentSong = _playback.activeSong ??
      (_cachedDisplaySongs.isNotEmpty
          ? _cachedDisplaySongs.first
          : (_allSongs.isNotEmpty ? _allSongs.first : null));

  final bool isTransparent = _theme.isTransparentPassThrough;
  final bool isWhitaniana = _theme.isWhitanianaActive;

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    padding: const EdgeInsets.all(14.0),
    decoration: BoxDecoration(
      color: isWhitaniana ? LotusColors.whitanianaPureWhiteCard : null,
      gradient: isWhitaniana
          ? const LinearGradient(
              colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : (isTransparent
              ? LinearGradient(
                  colors: <Color>[
                    const Color(0xFF1E142B).withValues(alpha: 0.40),
                    const Color(0xFF0D1625).withValues(alpha: 0.25),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LotusDecorations.heroCardGradient),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: isWhitaniana
            ? LotusColors.whitanianaCardBorder
            : accent.withValues(alpha: 0.35),
        width: 1.2,
      ),
      boxShadow: isWhitaniana
          ? LotusDecorations.whitanianaCardShadow()
          : LotusDecorations.glowShadow(accent, intensity: 0.15, blur: 20),
    ),
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration:
              BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'HARMONIC BLOOM SANCTUARY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
              decoration: BoxDecoration(
                color: isWhitaniana
                    ? secondaryAccent.withValues(alpha: 0.12)
                    : secondaryAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: secondaryAccent.withValues(alpha: isWhitaniana ? 0.6 : 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.tune_rounded,
                      color: secondaryAccent, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    _eqService.isEnabled ? '10-BAND EQ ON' : 'BYPASS',
                    style: TextStyle(
                      color: secondaryAccent,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (BuildContext context, Widget? child) {
                    return Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: secondaryAccent.withValues(
                                alpha: 0.35 + (0.2 * _pulseController.value)),
                            blurRadius: 16 + (8 * _pulseController.value),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 66,
                    height: 66,
                    color: isWhitaniana
                        ? const Color(0xFFF1F5F9)
                        : _theme.containerHighColor,
                    child: currentSong != null
                        ? LotusArtworkImage(
                      songId: currentSong.id,
                      size: 66,
                      borderRadius: 16,
                      keepOldArtwork: true,
                      nullArtworkWidget: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(colors: <Color>[
                            secondaryAccent,
                            _theme.containerLowestColor
                          ]),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/icons/now_playing_icon.png',
                            fit: BoxFit.cover,
                            cacheWidth: 192,
                            cacheHeight: 192,
                            errorBuilder: (BuildContext context,
                                Object error, StackTrace? stackTrace) {
                              return Center(
                                child: Icon(
                                  Icons.local_florist_rounded,
                                  color: accent,
                                  size: 30,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    )
                        : ClipOval(
                      child: Image.asset(
                        'assets/icons/now_playing_icon.png',
                        fit: BoxFit.cover,
                        cacheWidth: 192,
                        cacheHeight: 192,
                        errorBuilder: (BuildContext context,
                            Object error, StackTrace? stackTrace) {
                          return Center(
                            child: Icon(Icons.music_note_rounded,
                                color: isWhitaniana
                                    ? LotusColors.whitanianaTextTertiary
                                    : LotusColors.textSecondary,
                                size: 30),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    currentSong?.title ?? 'Resonance In Bloom',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isWhitaniana
                          ? LotusColors.whitanianaTextPrimary
                          : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    currentSong?.artist ?? 'High-Fidelity Studio Audio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isWhitaniana
                          ? LotusColors.whitanianaTextSecondary
                          : LotusColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _spectrumController,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        size: const Size(130, 14),
                        painter: _MicroSpectrumPainter(
                          progress: _playback.isPlaying
                              ? _spectrumController.value
                              : 0.0,
                          accent: accent,
                          secondaryAccent: secondaryAccent,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _buildGradientActionButton(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle Vault',
                gradient: LinearGradient(colors: <Color>[
                  secondaryAccent,
                  secondaryAccent.withValues(alpha: 0.8),
                ]),
                onTap: _triggerShuffleVault,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGradientActionButton(
                icon: Icons.all_inclusive_rounded,
                label: 'Smart Flow',
                gradient: _theme.activeGradient,
                onTap: _triggerSmartFlow,
                onLongPress: _openSmartFlowCustomizerSheet,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildFilterChips(
    Color accent, Color secondaryAccent, Color containerLow) {
  final int count = _cachedDisplaySongs.length;
  final bool isWhitaniana = _theme.isWhitanianaActive;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_selectedArtistFilter != null ||
            _selectedAlbumFilter != null ||
            _activeSearchQuery.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: secondaryAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: secondaryAccent.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.filter_list_rounded,
                    color: secondaryAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _activeSearchQuery.isNotEmpty
                        ? 'Search: "$_activeSearchQuery" ($count matches)'
                        : 'Filtered by: ${_selectedArtistFilter ?? _selectedAlbumFilter} ($count tracks)',
                    style: TextStyle(
                      color: _theme.textPrimaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedArtistFilter = null;
                      _selectedAlbumFilter = null;
                      _activeCategoryIndex = -1;
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                      _recomputeDisplaySongs();
                    });
                  },
                  child: Icon(Icons.close_rounded,
                      color: _theme.textPrimaryColor, size: 16),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            _buildChip(
              index: 0,
              label: 'All Songs',
              count: count.toString(),
              color: accent,
              containerLow:
              isWhitaniana ? _theme.containerColor : containerLow,
            ),
            const SizedBox(width: 10),
            _buildChip(
              index: 1,
              label: 'Hi-Res Lossless',
              count: (count > 5 ? (count * 0.7).toInt() : count).toString(),
              color: secondaryAccent,
              containerLow:
              isWhitaniana ? _theme.containerColor : containerLow,
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildChip({
  required int index,
  required String label,
  required String count,
  required Color color,
  required Color containerLow,
}) {
  final bool isSelected = _selectedFilterIndex == index;
  final bool isWhitaniana = _theme.isWhitanianaActive;

  return GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      _searchFocusNode.unfocus();
      setState(() {
        _selectedFilterIndex = index;
        _recomputeDisplaySongs();
      });
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.2) : containerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? color : _theme.cardBorderColor,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? (isWhitaniana ? color : Colors.white)
                  : _theme.textSecondaryColor,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? color
                  : (isWhitaniana
                  ? _theme.containerHighColor
                  : Colors.white10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count,
              style: TextStyle(
                color:
                isSelected ? Colors.white : _theme.textSecondaryColor,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildAcousticVelocityCarousel(
    Color accent, Color secondaryAccent, Color containerLow) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.blur_on_rounded, color: accent, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Acoustic Velocity',
                  style: TextStyle(
                    color: _theme.textPrimaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              'SEE ALL (${_allAlbums.length})',
              style: TextStyle(
                color: _theme.textTertiaryColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 184,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          itemCount: _allAlbums.length,
          itemBuilder: (BuildContext context, int index) {
            final AlbumModel album = _allAlbums[index];
            return _buildAlbumSnapCard(
                album, index, accent, secondaryAccent, containerLow);
          },
        ),
      ),
    ],
  );
}

Widget _buildAlbumSnapCard(AlbumModel album, int index, Color accent,
    Color secondaryAccent, Color containerLow) {
  final bool isSelected = _selectedAlbumFilter == album.album;
  final Color itemAccent = index % 2 == 0 ? accent : secondaryAccent;
  final bool isWhitaniana = _theme.isWhitanianaActive;

  final List<SongModel> albumSongs = (_songsByAlbumId[album.id] ??
      _songsByAlbumName[album.album.trim().toLowerCase()] ??
      const <SongModel>[])
      .where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
      .toList();

  return GestureDetector(
    onTap: () {
      HapticFeedback.heavyImpact();
      _searchFocusNode.unfocus();

      if (albumSongs.isNotEmpty) {
        final SongModel songToPlay = albumSongs.first;
        _playback.playSong(songToPlay, queue: albumSongs);
        widget.onSongSelected?.call(songToPlay);

        setState(() {
          _selectedAlbumFilter = album.album;
          _selectedArtistFilter = null;
          _activeCategoryIndex = 2;
          _recomputeDisplaySongs();
        });

        LotusSnackBar.show(
          context,
          message: 'Playing: "${songToPlay.title}" • ${album.album}',
          icon: Icons.play_circle_fill_rounded,
          iconColor: itemAccent,
        );
      } else {
        setState(() {
          _selectedAlbumFilter = album.album;
          _selectedArtistFilter = null;
          _activeCategoryIndex = 2;
          _recomputeDisplaySongs();
        });
      }
    },
    child: Container(
      width: 145,
      margin: const EdgeInsets.symmetric(horizontal: 6.0),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? accent : _theme.cardBorderColor,
          width: isSelected ? 1.6 : 0.8,
        ),
        boxShadow: isSelected
            ? LotusDecorations.glowShadow(accent, intensity: 0.2, blur: 12)
            : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(18)),
                child: SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: QueryArtworkWidget(
                    id: album.id,
                    type: ArtworkType.ALBUM,
                    keepOldArtwork: true,
                    nullArtworkWidget: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            itemAccent.withValues(alpha: 0.18),
                            _theme.containerLowestColor,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(Icons.album_rounded,
                            color: itemAccent, size: 38),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: itemAccent, width: 0.8),
                  ),
                  child: Text(
                    index % 2 == 0 ? 'FLAC 24/96' : 'DSD 11.2M',
                    style: TextStyle(
                      color: itemAccent,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: itemAccent,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: itemAccent.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.black, size: 20),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _theme.textPrimaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  album.artist ?? '${album.numOfSongs} Tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _theme.textSecondaryColor,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildRecentlyPlayedCarousel(
    Color accent, Color secondaryAccent, Color containerLow) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.history_rounded, color: accent, size: 18),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                'Recently Played',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _theme.textPrimaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'AUTO-RESUME READY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'VIEW HISTORY',
                  style: TextStyle(
                    color: _theme.textTertiaryColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 1),
                Icon(Icons.chevron_right_rounded,
                    color: _theme.textTertiaryColor, size: 13),
              ],
            ),
          ],
        ),
      ),
      SizedBox(
        height: 194,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          itemCount: _recentSongs.length,
          itemBuilder: (BuildContext context, int index) {
            final SongModel song = _recentSongs[index];
            return _buildRecentTrackCard(
                song, index, accent, secondaryAccent, containerLow);
          },
        ),
      ),
    ],
  );
}

Widget _buildRecentTrackCard(SongModel song, int index, Color accent,
    Color secondaryAccent, Color containerLow) {
  final bool isCurrent = _playback.isActiveSong(song);
  final int? playedAtMs = _playback.getRecentPlayedTimestampMs(song.id);
  final String timeAgo =
  _formatRecentTimeAgo(playedAtMs, isCurrent && _playback.isPlaying);
  final Color badgeColor = index % 2 == 0 ? accent : secondaryAccent;
  final bool isWhitaniana = _theme.isWhitanianaActive;

  return Container(
    width: 140,
    margin: const EdgeInsets.symmetric(horizontal: 6.0),
    decoration: BoxDecoration(
      color: containerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color:
        isCurrent ? accent.withValues(alpha: 0.8) : _theme.cardBorderColor,
        width: isCurrent ? 1.4 : 0.8,
      ),
      boxShadow: isCurrent
          ? LotusDecorations.glowShadow(accent, intensity: 0.16, blur: 14)
          : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _handleSongSelected(song),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
                  child: SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: LotusArtworkImage(
                        songId: song.id,
                        size: 140,
                        borderRadius: 0,
                        keepOldArtwork: true,
                        nullArtworkWidget: Container(
                          width: 140,
                          height: 110,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                badgeColor.withValues(alpha: 0.18),
                                _theme.containerLowestColor,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(Icons.music_note_rounded,
                                color: badgeColor, size: 36),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.6),
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      timeAgo,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => _handleSongSelected(song),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isCurrent && _playback.isPlaying
                            ? LotusColors.voltLime
                            : badgeColor,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: badgeColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        isCurrent && _playback.isPlaying
                            ? Icons.equalizer_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _theme.textPrimaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist ?? 'Lotus Vault',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _theme.textSecondaryColor,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          song.fileExtension.isNotEmpty
                              ? song.fileExtension.toUpperCase()
                              : 'FLAC',
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        isCurrent ? 'Playing' : 'Ready',
                        style: TextStyle(
                          color: isCurrent
                              ? accent
                              : _theme.textTertiaryColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildSectionHeader(
    Color accent, Color secondaryAccent, Color containerLow) {
  final int count = _cachedDisplaySongs.length;
  final bool isWhitaniana = _theme.isWhitanianaActive;

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_special_rounded,
                  color: secondaryAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedArtistFilter != null
                      ? 'Artist Vault: $_selectedArtistFilter ($count)'
                      : (_selectedAlbumFilter != null
                      ? 'Album Vault: $_selectedAlbumFilter ($count)'
                      : 'Device Audio Vault ($count)'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _theme.textPrimaryColor,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListenableBuilder(
              listenable: _playback,
              builder: (BuildContext context, _) {
                if (_playback.activeSong == null) {
                  return const SizedBox.shrink();
                }
                return GestureDetector(
                  onTap: _scrollToActiveSong,
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.65), width: 1.0),
                      boxShadow: LotusDecorations.glowShadow(accent,
                          intensity: 0.22, blur: 10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.my_location_rounded,
                            color: accent, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'LOCATE',
                          style: TextStyle(
                            color: accent,
                            fontSize: 9.0,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Tooltip(
              message:
              _isAscending ? 'Order: Ascending' : 'Order: Descending',
              child: GestureDetector(
                onTap: _toggleSortOrder,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isWhitaniana
                        ? _theme.containerColor
                        : containerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.6), width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _isAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: accent,
                        size: 15,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _isAscending ? 'ASC' : 'DESC',
                        style: TextStyle(
                          color: accent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _buildCircleIconButton(
              Icons.tune_rounded,
              _showSortMenu,
              isWhitaniana ? _theme.containerColor : containerLow,
              tooltip: 'Sort By: Title, Artist, Duration, Date',
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildRealSongListSliver(
    Color accent, Color secondaryAccent, Color containerLow) {
  if (_isLoading) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Center(child: CircularProgressIndicator(color: accent)),
      ),
    );
  }

  if (!_hasPermission && _allSongs.isEmpty) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.folder_off_rounded, color: accent, size: 48),
              const SizedBox(height: 12),
              Text(
                'Audio storage permission is required to read your music.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _theme.textSecondaryColor,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _checkPermissionAndScan,
                icon: const Icon(Icons.security_rounded, size: 18),
                label: const Text('Grant Access',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final List<SongModel> songs = _cachedDisplaySongs;

  if (songs.isEmpty) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            _activeSearchQuery.isNotEmpty
                ? 'No tracks matching "$_activeSearchQuery".'
                : (_selectedArtistFilter != null ||
                _selectedAlbumFilter != null
                ? 'No tracks matching the selected filter.'
                : 'Scanning device storage audio stems...'),
            style: TextStyle(color: _theme.textSecondaryColor),
          ),
        ),
      ),
    );
  }

  return SliverFixedExtentList(
    itemExtent: 74.0,
    delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
        final SongModel song = songs[index];
        return ValueListenableBuilder<int>(
          valueListenable: _playback.activeSongIdNotifier,
          builder: (BuildContext context, int activeId, _) {
            final bool isSelected = activeId == song.id;
            return _buildTrackRow(song, isSelected, index, accent,
                secondaryAccent, containerLow);
          },
        );
      },
      childCount: songs.length,
    ),
  );
}

Widget _buildTrackRow(
    SongModel song,
    bool isSelected,
    int index,
    Color accent,
    Color secondaryAccent,
    Color containerLow,
    ) {
  final bool isFav = _playback.isSongFavorite(song.id);
  final bool isWhitaniana = _theme.isWhitanianaActive;

  final String resolvedArtist = (song.artist != null &&
      song.artist!.trim().isNotEmpty &&
      !song.artist!.contains('<unknown>'))
      ? song.artist!
      : '<Unknown Artist>';

  final Color badgeColor = (index % 3 == 0) ? secondaryAccent : accent;

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
    decoration: BoxDecoration(
      color: isSelected
          ? (isWhitaniana
          ? _theme.containerColor
          : _theme.containerHighColor)
          : containerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isSelected
            ? accent.withValues(alpha: 0.95)
            : _theme.cardBorderColor,
        width: isSelected ? 1.6 : 0.8,
      ),
      boxShadow: isSelected
          ? LotusDecorations.glowShadow(accent, intensity: 0.22, blur: 14)
          : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _handleSongSelected(song),
        onLongPress: () => _openTrackOptions(song),
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
                      width: 46,
                      height: 46,
                      child: LotusArtworkImage(
                        songId: song.id,
                        size: 46,
                        borderRadius: 10,
                        keepOldArtwork: true,
                        nullArtworkWidget: Container(
                          color: _theme.containerColor,
                          child: Image.asset(
                            'assets/icons/now_playing_icon.png',
                            fit: BoxFit.cover,
                            cacheWidth: 128,
                            cacheHeight: 128,
                            errorBuilder: (BuildContext ctx, Object err,
                                StackTrace? stack) {
                              return Icon(
                                Icons.music_note_rounded,
                                color: isSelected
                                    ? accent
                                    : _theme.textTertiaryColor,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isSelected && _playback.isPlaying)
                    Container(
                      width: 46,
                      height: 46,
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
                              color: isSelected
                                  ? accent
                                  : _theme.textPrimaryColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected) ...<Widget>[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.6),
                                  width: 0.6),
                            ),
                            child: Text(
                              'PLAYING',
                              style: TextStyle(
                                color: accent,
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            song.fileExtension.isNotEmpty
                                ? song.fileExtension.toUpperCase()
                                : 'FLAC',
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            resolvedArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _theme.textSecondaryColor,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(song.duration ?? 0),
                style: TextStyle(
                  color: _theme.textTertiaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleFavoriteSong(song),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6.0, vertical: 8.0),
                  child: Icon(
                    isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 20,
                    color: isFav
                        ? secondaryAccent
                        : _theme.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildCircleIconButton(
    IconData icon,
    VoidCallback onTap,
    Color containerLow, {
      String? tooltip,
      Widget? customIcon,
    }) {
  return Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: containerLow,
          shape: BoxShape.circle,
          border: Border.all(color: _theme.cardBorderColor),
        ),
        child: Center(
          child: customIcon ??
              Icon(
                icon,
                color: _theme.textPrimaryColor,
                size: 18,
              ),
        ),
      ),
    ),
  );
}

Widget _buildGradientActionButton({
  required IconData icon,
  required String label,
  required Gradient gradient,
  required VoidCallback onTap,
  VoidCallback? onLongPress,
}) {
  return Container(
    height: 42,
    decoration: BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(22),
      boxShadow: LotusDecorations.glowShadow(gradient.colors.first,
          intensity: 0.35, blur: 10),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatDuration(int milliseconds) {
  final Duration duration = Duration(milliseconds: milliseconds);
  final int minutes = duration.inMinutes;
  final int seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
}

// ==============================================================================
// DEDICATED STATEFUL ARTISTS FILTER SHEET
// ==============================================================================
class _LotusArtistsFilterSheet extends StatefulWidget {
  final List<ArtistModel> allArtists;
  final List<SongModel> allSongs;
  final Map<String, List<SongModel>> songsByArtistName;
  final String? selectedArtistFilter;
  final void Function(String? selectedArtist, SongModel? songToPlay,
      List<SongModel>? artistQueue) onArtistSelected;

  const _LotusArtistsFilterSheet({
    required this.allArtists,
    required this.allSongs,
    required this.songsByArtistName,
    required this.selectedArtistFilter,
    required this.onArtistSelected,
  });

  @override
  State<_LotusArtistsFilterSheet> createState() =>
      _LotusArtistsFilterSheetState();
}

class _LotusArtistsFilterSheetState extends State<_LotusArtistsFilterSheet> {
  late final TextEditingController _artistSearchCtrl;
  late final ScrollController _scrollController;
  int _activeArtistTab = 0;
  bool _isAlphabeticalAscending = true;

  @override
  void initState() {
    super.initState();
    _artistSearchCtrl = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _artistSearchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildArtistFilterTab({
    required String label,
    required bool isSelected,
    required Color accent,
    required Color containerLow,
    required VoidCallback onTap,
  }) {
    final LotusThemeController theme = LotusThemeController.instance;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.18) : containerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : theme.cardBorderColor,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? accent : theme.textSecondaryColor,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LotusThemeController theme = LotusThemeController.instance;
    final LotusPlaybackProvider playback = LotusPlaybackProvider.instance;
    final Color accent = theme.primaryAccent;
    final Color secondaryAccent = theme.secondaryAccent;

    final Color modalShieldSurface = theme.modalSurfaceColor;
    final Color modalContainerLow = theme.modalContainerLowColor;
    final Color textPrimary = theme.textPrimaryColor;
    final Color textSecondary = theme.textSecondaryColor;

    final String searchQuery = _artistSearchCtrl.text.trim().toLowerCase();

    List<ArtistModel> filteredArtists =
    widget.allArtists.where((ArtistModel a) {
      if (searchQuery.isEmpty) return true;
      return a.artist.toLowerCase().contains(searchQuery);
    }).toList();

    if (_activeArtistTab == 1) {
      filteredArtists.sort((ArtistModel a, ArtistModel b) {
        final int comp =
        a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        return _isAlphabeticalAscending ? comp : -comp;
      });
    } else if (_activeArtistTab == 2) {
      filteredArtists.sort((ArtistModel a, ArtistModel b) =>
          (b.numberOfTracks ?? 0).compareTo(a.numberOfTracks ?? 0));
    } else if (_activeArtistTab == 3) {
      filteredArtists = filteredArtists.where((ArtistModel a) {
        final String key = a.artist.toLowerCase().trim();
        final List<SongModel>? songs = widget.songsByArtistName[key];
        if (songs == null) return false;
        return songs.any((SongModel s) {
          if (playback.isSongHidden(s.id, s.data)) return false;
          final String ext = s.fileExtension.toLowerCase();
          return ext.contains('flac') || ext.contains('dsd');
        });
      }).toList();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: modalShieldSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: secondaryAccent.withValues(alpha: 0.85),
          width: 1.6,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
                alpha: theme.isWhitanianaActive ? 0.15 : 0.85),
            blurRadius: 36,
            spreadRadius: 8,
            offset: const Offset(0, -6),
          ),
          ...LotusDecorations.glowShadow(secondaryAccent,
              intensity: 0.28, blur: 28),
        ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: theme.isWhitanianaActive
                    ? LotusColors.whitanianaCardBorder
                    : Colors.white24,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: modalContainerLow,
                    border: Border.all(color: accent, width: 1.8),
                    boxShadow: LotusDecorations.glowShadow(accent,
                        intensity: 0.35, blur: 16),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icons/artists_icon.png',
                      fit: BoxFit.cover,
                      cacheWidth: 128,
                      cacheHeight: 128,
                      errorBuilder: (BuildContext context, Object error,
                          StackTrace? stackTrace) {
                        return Center(
                          child: Icon(Icons.local_florist_rounded,
                              color: accent, size: 30),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              'Artists',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: secondaryAccent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'MASTER',
                              style: TextStyle(
                                color: secondaryAccent,
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${widget.allArtists.length} Curated Performers • FLAC & Studio Master',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.selectedArtistFilter != null)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onArtistSelected(null, null, null);
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'RESET',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon:
                  Icon(Icons.close_rounded, color: textSecondary, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: modalContainerLow,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(
                  color: searchQuery.isNotEmpty
                      ? secondaryAccent
                      : theme.cardBorderColor,
                  width: searchQuery.isNotEmpty ? 1.2 : 0.8,
                ),
              ),
              child: Row(
                children: <Widget>[
                  const LotusSearchIcon(size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _artistSearchCtrl,
                      autofocus: false,
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      cursorColor: secondaryAccent,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search artists, bands, vocalists...',
                        hintStyle:
                        TextStyle(color: textSecondary, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _artistSearchCtrl.clear();
                        setState(() {});
                      },
                      child: Icon(Icons.close_rounded,
                          color: theme.textTertiaryColor, size: 18),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                _buildArtistFilterTab(
                  label: 'All (${widget.allArtists.length})',
                  isSelected: _activeArtistTab == 0,
                  accent: secondaryAccent,
                  containerLow: modalContainerLow,
                  onTap: () => setState(() => _activeArtistTab = 0),
                ),
                const SizedBox(width: 8),
                _buildArtistFilterTab(
                  label: _activeArtistTab == 1
                      ? (_isAlphabeticalAscending
                      ? 'A–Z Alphabetical ↑'
                      : 'Z–A Alphabetical ↓')
                      : 'A–Z Alphabetical',
                  isSelected: _activeArtistTab == 1,
                  accent: secondaryAccent,
                  containerLow: modalContainerLow,
                  onTap: () {
                    setState(() {
                      if (_activeArtistTab == 1) {
                        _isAlphabeticalAscending = !_isAlphabeticalAscending;
                      } else {
                        _activeArtistTab = 1;
                        _isAlphabeticalAscending = true;
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildArtistFilterTab(
                  label: 'Top Played',
                  isSelected: _activeArtistTab == 2,
                  accent: secondaryAccent,
                  containerLow: modalContainerLow,
                  onTap: () => setState(() => _activeArtistTab = 2),
                ),
                const SizedBox(width: 8),
                _buildArtistFilterTab(
                  label: '• Studio FLAC',
                  isSelected: _activeArtistTab == 3,
                  accent: accent,
                  containerLow: modalContainerLow,
                  onTap: () => setState(() => _activeArtistTab = 3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: theme.cardBorderColor, height: 1),
          Expanded(
            child: filteredArtists.isEmpty
                ? Center(
              child: Text(
                'No artists matching "$searchQuery"',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                ),
              ),
            )
                : ListView.builder(
              key: const PageStorageKey<String>(
                  'lotus_artists_modal_list'),
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              itemCount: filteredArtists.length,
              itemBuilder: (BuildContext context, int index) {
                final ArtistModel artist = filteredArtists[index];
                final bool isSelected =
                    widget.selectedArtistFilter == artist.artist;

                final List<SongModel> artistSongs =
                (widget.songsByArtistName[
                artist.artist.toLowerCase().trim()] ??
                    const <SongModel>[])
                    .where((SongModel s) =>
                !playback.isSongHidden(s.id, s.data))
                    .toList();

                final bool hasSongs = artistSongs.isNotEmpty;

                final String initials = artist.artist.trim().isNotEmpty
                    ? (artist.artist
                    .trim()
                    .split(RegExp(r'\s+'))
                    .take(2)
                    .map((String e) => e[0].toUpperCase())
                    .join())
                    : 'A';

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.modalContainerColor
                        : modalContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? secondaryAccent
                          : theme.cardBorderColor,
                      width: isSelected ? 1.4 : 0.8,
                    ),
                    boxShadow: isSelected
                        ? LotusDecorations.glowShadow(secondaryAccent,
                        intensity: 0.22, blur: 10)
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        Navigator.of(context).pop();

                        if (hasSongs) {
                          final SongModel songToPlay = artistSongs.first;
                          widget.onArtistSelected(
                              artist.artist, songToPlay, artistSongs);
                        } else {
                          widget.onArtistSelected(
                              artist.artist, null, null);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: secondaryAccent
                                    .withValues(alpha: 0.16),
                                border: Border.all(
                                  color: secondaryAccent
                                      .withValues(alpha: 0.45),
                                  width: 1.2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    color: secondaryAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          artist.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected
                                                ? secondaryAccent
                                                : textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 4.5,
                                            vertical: 1),
                                        decoration: BoxDecoration(
                                          color: accent
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                          BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          index % 2 == 0
                                              ? '24-BIT'
                                              : 'FLAC',
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${artist.numberOfTracks ?? artistSongs.length} Tracks • ${artist.numberOfAlbums ?? 1} Albums • Lossless Studio',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: secondaryAccent
                                    .withValues(alpha: 0.18),
                                border: Border.all(
                                  color: secondaryAccent
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: secondaryAccent,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded,
                                color: theme.textTertiaryColor, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroSpectrumPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color secondaryAccent;

  const _MicroSpectrumPainter({
    required this.progress,
    required this.accent,
    required this.secondaryAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int barCount = 10;
    final double barWidth = size.width / (barCount * 1.8);
    const List<double> baseHeights = <double>[
      0.3,
      0.7,
      1.0,
      0.5,
      0.85,
      0.9,
      0.4,
      0.75,
      0.6,
      0.35
    ];

    final Paint evenPaint = Paint()..color = accent;
    final Paint oddPaint = Paint()..color = secondaryAccent;

    for (int i = 0; i < barCount; i++) {
      final double factor = progress == 0.0
          ? 0.0
          : math.sin((progress * math.pi) + (i * 0.5)).abs();
      final double h = (size.height * baseHeights[i] * (0.35 + 0.65 * factor))
          .clamp(3.0, size.height);
      final double left = i * (barWidth * 1.8);
      final double top = size.height - h;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, barWidth, h), const Radius.circular(2)),
        i % 2 == 0 ? evenPaint : oddPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MicroSpectrumPainter oldDelegate) =>
      oldDelegate.progress != progress ||
          oldDelegate.accent != accent ||
          oldDelegate.secondaryAccent != secondaryAccent;
}