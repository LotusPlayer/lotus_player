import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_widgets.dart';
import '../home/lotus_search_modal.dart';
import '../options/lotus_track_options_sheet.dart';
import 'lotus_add_to_playlist_dialog.dart';

enum PlaylistViewMode {
cratesGrid,
flowList,
smartMixes,
}

class AppCrateEntry {
final int id;
final String name;
final List<int> songIds;
final int dateCreated;
final bool isFavorites;

AppCrateEntry({
required this.id,
required this.name,
required this.songIds,
required this.dateCreated,
this.isFavorites = false,
});

Map<String, dynamic> toJson() => <String, dynamic>{
'id': id,
'name': name,
'songIds': songIds,
'dateCreated': dateCreated,
'isFavorites': isFavorites,
};

factory AppCrateEntry.fromJson(Map<String, dynamic> json) {
return AppCrateEntry(
id: json['id'] as int? ?? DateTime.now().millisecondsSinceEpoch,
name: json['name'] as String? ?? 'Custom Playlist',
songIds: (json['songIds'] as List<dynamic>?)
    ?.map((dynamic e) => int.tryParse(e.toString()) ?? 0)
    .where((int id) => id > 0)
    .toList() ??
<int>[],
dateCreated:
json['dateCreated'] as int? ?? DateTime.now().millisecondsSinceEpoch,
isFavorites: json['isFavorites'] as bool? ?? false,
);
}
}

class RealDeviceCrate {
final int id;
String title;
List<SongModel> songs;
double totalSizeMb;
final String primaryFormat;
final int avgBitrateKbps;
final bool isPinned;
final bool isSdCardMount;
final bool isFavorites;
final bool isDynamicAutoCrate;
final String? autoCrateType;

RealDeviceCrate({
required this.id,
required this.title,
required this.songs,
required this.totalSizeMb,
required this.primaryFormat,
required this.avgBitrateKbps,
this.isPinned = false,
this.isSdCardMount = false,
this.isFavorites = false,
this.isDynamicAutoCrate = false,
this.autoCrateType,
});

int get trackCount => songs.length;
}

class LotusPlaylistsUnifiedScreen extends StatefulWidget {
final ValueChanged<SongModel>? onSongSelected;
final VoidCallback? onOpenNowPlaying;
final VoidCallback? onOpenEqualizer;
final VoidCallback? onBack;

const LotusPlaylistsUnifiedScreen({
super.key,
this.onSongSelected,
this.onOpenNowPlaying,
this.onOpenEqualizer,
this.onBack,
});

@override
State<LotusPlaylistsUnifiedScreen> createState() =>
_LotusPlaylistsUnifiedScreenState();
}

class _LotusPlaylistsUnifiedScreenState
extends State<LotusPlaylistsUnifiedScreen> with WidgetsBindingObserver {
final OnAudioQuery _audioQuery = OnAudioQuery();
final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
final LotusThemeController _theme = LotusThemeController.instance;

static const String _kFavoriteSongIdsKey = 'lotus_favorite_song_ids';
static const String _kPrivatePlaylistsStorageKey =
'lotus_private_app_playlists_v2';
static const String _kVerifiedPlaylistCountKey =
'lotus_verified_playlist_count';
static const String _kActivePlaybackCrateKey =
'lotus_active_playback_crate_id';

static const int kCrateIdFavorites = 999999;
static const int kCrateIdRecentlyAdded = 888881;
static const int kCrateIdStudioMasters = 888882;

SharedPreferences? _cachedPrefs;
StreamSubscription<FavoriteChangeEvent>? _favoriteChangeSub;
StreamSubscription<HiddenSongsChangeEvent>? _hiddenSongsChangeSub;

bool _isLoading = true;
bool _isScanningPlaylists = false;
PlaylistViewMode _viewMode = PlaylistViewMode.cratesGrid;

// Delete Vault State Machine
bool _isDeleteVaultMode = false;
final Set<int> _selectedCrateIdsToDelete = <int>{};

String _activeSortMode = 'NAME';
bool _losslessOnlyFilter = false;

final ScrollController _flowScrollController = ScrollController();
final ScrollController _crateDetailScrollController = ScrollController();

RealDeviceCrate? _activeOpenCrate;
RealDeviceCrate? _lastInspectedCrate;
bool _isReorderMode = false;

int? _playingSourceCrateId;
int? _forwardCrateId;
bool _wasOnMasterViewBeforeJump = false;
PlaylistViewMode _previousViewModeBeforeJump = PlaylistViewMode.cratesGrid;

double _leftDragExtent = 0.0;
double _rightDragExtent = 0.0;
double _leftDragY = 320.0;
double _rightDragY = 320.0;
bool _leftTriggered = false;
bool _rightTriggered = false;

List<SongModel> _deviceSongs = <SongModel>[];
Map<int, SongModel> _deviceSongMap = <int, SongModel>{};
List<RealDeviceCrate> _crates = <RealDeviceCrate>[];
final Set<int> _favoriteSongIds = <int>{};

final Set<int> _hiddenSongIds = <int>{};
final Set<String> _hiddenSongPaths = <String>{};

List<SongModel> _recentlyAddedSongs = <SongModel>[];
List<SongModel> _studioMastersSongs = <SongModel>[];

int? _lastActiveSongId;
bool _lastPlayState = false;

@override
void initState() {
super.initState();
WidgetsBinding.instance.addObserver(this);
_playback.addListener(_onPlaybackChanged);
_theme.addListener(_onThemeChanged);

_favoriteChangeSub =
_playback.favoriteChangeStream.listen(_onFavoriteEventReceived);

_hiddenSongsChangeSub =
_playback.hiddenSongsChangeStream.listen(_onHiddenSongsEventReceived);

_loadPrivateCratesAndAudio();
}

@override
void dispose() {
WidgetsBinding.instance.removeObserver(this);
_favoriteChangeSub?.cancel();
_hiddenSongsChangeSub?.cancel();
_flowScrollController.dispose();
_crateDetailScrollController.dispose();
_playback.removeListener(_onPlaybackChanged);
_theme.removeListener(_onThemeChanged);
super.dispose();
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
if (state == AppLifecycleState.resumed) {
_loadPrivateCratesAndAudio();
}
}

void _onHiddenSongsEventReceived(HiddenSongsChangeEvent event) {
if (!mounted) return;

setState(() {
_hiddenSongIds
..clear()
..addAll(event.hiddenIds);
_hiddenSongPaths
..clear()
..addAll(event.hiddenPaths);

for (final RealDeviceCrate crate in _crates) {
crate.songs.removeWhere((SongModel s) =>
_hiddenSongIds.contains(s.id) ||
(s.data.isNotEmpty &&
_hiddenSongPaths.contains(s.data.trim().toLowerCase())));
}

_deviceSongs.removeWhere((SongModel s) =>
_hiddenSongIds.contains(s.id) ||
(s.data.isNotEmpty &&
_hiddenSongPaths.contains(s.data.trim().toLowerCase())));

_recentlyAddedSongs.removeWhere((SongModel s) =>
_hiddenSongIds.contains(s.id) ||
(s.data.isNotEmpty &&
_hiddenSongPaths.contains(s.data.trim().toLowerCase())));

_studioMastersSongs.removeWhere((SongModel s) =>
_hiddenSongIds.contains(s.id) ||
(s.data.isNotEmpty &&
_hiddenSongPaths.contains(s.data.trim().toLowerCase())));

if (_activeOpenCrate != null) {
_activeOpenCrate!.songs.removeWhere((SongModel s) =>
_hiddenSongIds.contains(s.id) ||
(s.data.isNotEmpty &&
_hiddenSongPaths.contains(s.data.trim().toLowerCase())));
}
});
}

void _onFavoriteEventReceived(FavoriteChangeEvent event) {
if (!mounted) return;

final int songId = event.songId;
final bool isFav = event.isFavorite;
final SongModel? song =
event.song ?? _deviceSongMap[songId] ?? _playback.getSongById(songId);

setState(() {
if (isFav) {
_favoriteSongIds.add(songId);
} else {
_favoriteSongIds.remove(songId);
}

for (final RealDeviceCrate crate in _crates) {
if (crate.isFavorites) {
if (isFav) {
if (song != null &&
!crate.songs.any((SongModel s) => s.id == songId)) {
crate.songs.insert(0, song);
}
} else {
crate.songs.removeWhere((SongModel s) => s.id == songId);
}

double bytes = 0;
for (final SongModel s in crate.songs) {
bytes += s.size;
}
crate.totalSizeMb =
bytes > 0 ? (bytes / (1024 * 1024)) : (crate.songs.length * 32.0);
break;
}
}

if (_activeOpenCrate != null && _activeOpenCrate!.isFavorites) {
if (isFav) {
if (song != null &&
!_activeOpenCrate!.songs.any((SongModel s) => s.id == songId)) {
_activeOpenCrate!.songs.insert(0, song);
}
} else {
_activeOpenCrate!.songs.removeWhere((SongModel s) => s.id == songId);
}
}
});
}

void _onPlaybackChanged() {
final int? currentId = _playback.activeSong?.id;
final bool currentPlay = _playback.isPlaying;

if (currentId != _lastActiveSongId || currentPlay != _lastPlayState) {
_lastActiveSongId = currentId;
_lastPlayState = currentPlay;
if (mounted) setState(() {});
}
}

void _onThemeChanged() {
if (mounted) setState(() {});
}

Future<SharedPreferences> _getPrefs() async {
return _cachedPrefs ??= await SharedPreferences.getInstance();
}

void _setPlayingSourceCrate(int crateId) {
_playingSourceCrateId = crateId;
unawaited(_getPrefs().then((SharedPreferences prefs) {
if (!mounted) return;
prefs.setInt(_kActivePlaybackCrateKey, crateId);
}));
}

bool _isSongActiveMatch(SongModel s) {
final SongModel? playing = _playback.activeSong;
if (playing == null) return false;
if (s.id == playing.id) return true;
if (s.data.isNotEmpty && playing.data.isNotEmpty) {
return s.data.trim().toLowerCase() == playing.data.trim().toLowerCase();
}
return false;
}

RealDeviceCrate? _findPlayingSourceCrate() {
final SongModel? current = _playback.activeSong;
if (current == null) return null;

if (_playingSourceCrateId != null) {
for (final RealDeviceCrate c in _allInspectableCrates) {
if (c.id == _playingSourceCrateId) {
if (c.songs.any(_isSongActiveMatch)) {
return c;
}
}
}
}

for (final RealDeviceCrate c in _allInspectableCrates) {
if (c.songs.any(_isSongActiveMatch)) {
return c;
}
}

return null;
}

List<RealDeviceCrate> get _allInspectableCrates {
final List<RealDeviceCrate> combined = List<RealDeviceCrate>.from(_crates);
final RealDeviceCrate? recent = _buildRecentlyAddedCrateObj();
if (recent != null) combined.add(recent);
final RealDeviceCrate? masters = _buildStudioMastersCrateObj();
if (masters != null) combined.add(masters);
return combined;
}

RealDeviceCrate? _buildRecentlyAddedCrateObj() {
if (_recentlyAddedSongs.isEmpty) return null;
double bytes = 0;
for (final SongModel s in _recentlyAddedSongs) {
bytes += s.size;
}
final double mb = bytes > 0
? (bytes / (1024 * 1024))
    : (_recentlyAddedSongs.length * 32.0);

return RealDeviceCrate(
id: kCrateIdRecentlyAdded,
title: 'Recently Added',
songs: _recentlyAddedSongs,
totalSizeMb: mb,
primaryFormat: '384 KHZ DIRECT',
avgBitrateKbps: 4608,
isPinned: true,
isSdCardMount: false,
isFavorites: false,
isDynamicAutoCrate: true,
autoCrateType: 'RECENT',
);
}

RealDeviceCrate? _buildStudioMastersCrateObj() {
if (_studioMastersSongs.isEmpty) return null;
double bytes = 0;
for (final SongModel s in _studioMastersSongs) {
bytes += s.size;
}
final double mb = bytes > 0
? (bytes / (1024 * 1024))
    : (_studioMastersSongs.length * 48.0);

return RealDeviceCrate(
id: kCrateIdStudioMasters,
title: 'Studio Masters',
songs: _studioMastersSongs,
totalSizeMb: mb,
primaryFormat: 'DSD512 / 24-BIT',
avgBitrateKbps: 5644,
isPinned: true,
isSdCardMount: false,
isFavorites: false,
isDynamicAutoCrate: true,
autoCrateType: 'STUDIO_MASTERS',
);
}

bool _isLosslessMaster(SongModel s) {
final String ext = s.fileExtension.trim().toUpperCase();
return ext == 'FLAC' ||
ext == 'DSD' ||
ext == 'DSF' ||
ext == 'DFF' ||
ext == 'WAV' ||
ext == 'ALAC' ||
ext == 'AIFF';
}

Future<void> _loadPrivateCratesAndAudio() async {
if (_isScanningPlaylists) return;
_isScanningPlaylists = true;

if (mounted && _crates.isEmpty) {
setState(() => _isLoading = true);
}

try {
final SharedPreferences prefs = await _getPrefs();
_playingSourceCrateId = prefs.getInt(_kActivePlaybackCrateKey);

_hiddenSongIds
..clear()
..addAll(_playback.hiddenSongIds);
_hiddenSongPaths
..clear()
..addAll(_playback.hiddenSongPaths);

List<SongModel> allSongs = <SongModel>[];
try {
allSongs = await _audioQuery.querySongs(
sortType: SongSortType.DATE_ADDED,
orderType: OrderType.DESC_OR_GREATER,
uriType: UriType.EXTERNAL,
ignoreCase: true,
);
} catch (_) {
allSongs = _playback.currentQueue;
}

final List<SongModel> validSongs = allSongs.where((SongModel s) {
if ((s.duration ?? 0) <= 10000) return false;
if (_hiddenSongIds.contains(s.id)) return false;
if (s.data.isNotEmpty &&
_hiddenSongPaths.contains(s.data.trim().toLowerCase())) {
return false;
}
return true;
}).toList();

_deviceSongMap = <int, SongModel>{
for (final SongModel s in allSongs) s.id: s,
};

final List<SongModel> recentsSorted = List<SongModel>.from(validSongs)
..sort((SongModel a, SongModel b) =>
(b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));

final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
const int thirtyDaysSec = 30 * 24 * 60 * 60;
final List<SongModel> thirtyDaySongs = recentsSorted.where((SongModel s) {
final int added = s.dateAdded ?? 0;
return (nowSec - added) <= thirtyDaysSec && added > 0;
}).toList();

_recentlyAddedSongs = thirtyDaySongs.length >= 10
? thirtyDaySongs
    : recentsSorted.take(50).toList();

_studioMastersSongs = validSongs.where(_isLosslessMaster).toList();

final List<String> savedFavs =
prefs.getStringList(_kFavoriteSongIdsKey) ?? <String>[];
_favoriteSongIds.clear();
for (final String strId in savedFavs) {
final int? parsed = int.tryParse(strId);
if (parsed != null && !_hiddenSongIds.contains(parsed)) {
_favoriteSongIds.add(parsed);
}
}
_favoriteSongIds.addAll(
_playback.favoriteSongIds.where((int id) => !_hiddenSongIds.contains(id)),
);

final List<SongModel> favSongs = <SongModel>[];
for (final int favId in _favoriteSongIds) {
final SongModel? s =
_deviceSongMap[favId] ?? _playback.getSongById(favId);
if (s != null &&
!_hiddenSongIds.contains(s.id) &&
!_hiddenSongPaths.contains(s.data.trim().toLowerCase())) {
favSongs.add(s);
}
}

double favBytes = 0;
for (final SongModel s in favSongs) {
favBytes += s.size;
}
final double favMb =
favBytes > 0 ? (favBytes / (1024 * 1024)) : (favSongs.length * 32.0);

final List<RealDeviceCrate> loadedCrates = <RealDeviceCrate>[];

loadedCrates.add(
RealDeviceCrate(
id: kCrateIdFavorites,
title: 'Favorites Vault',
songs: favSongs,
totalSizeMb: favMb,
primaryFormat: 'FLAC 24/96',
avgBitrateKbps: 4608,
isPinned: true,
isSdCardMount: false,
isFavorites: true,
),
);

final String? rawJson = prefs.getString(_kPrivatePlaylistsStorageKey);
if (rawJson != null && rawJson.trim().isNotEmpty) {
final List<dynamic> decodedList = jsonDecode(rawJson) as List<dynamic>;
for (final dynamic item in decodedList) {
final AppCrateEntry entry =
AppCrateEntry.fromJson(item as Map<String, dynamic>);
if (entry.isFavorites ||
entry.name.toLowerCase() == 'favorites vault') {
continue;
}

final List<SongModel> playlistSongs = <SongModel>[];
double totalBytes = 0;
final Set<String> detectedCodecs = <String>{};

for (final int sId in entry.songIds) {
if (_hiddenSongIds.contains(sId)) continue;
final SongModel? song =
_deviceSongMap[sId] ?? _playback.getSongById(sId);
if (song != null) {
if (song.data.isNotEmpty &&
_hiddenSongPaths.contains(song.data.trim().toLowerCase())) {
continue;
}
playlistSongs.add(song);
totalBytes += song.size;
if (song.fileExtension.isNotEmpty) {
detectedCodecs.add(song.fileExtension.toUpperCase());
}
}
}

final double sizeMb = totalBytes > 0
? (totalBytes / (1024 * 1024))
    : (playlistSongs.length * 34.2);
final String formatBadge =
detectedCodecs.isNotEmpty ? detectedCodecs.first : 'FLAC 24/96';

loadedCrates.add(
RealDeviceCrate(
id: entry.id,
title: entry.name,
songs: playlistSongs,
totalSizeMb: sizeMb,
primaryFormat: formatBadge,
avgBitrateKbps: 4608,
isPinned: entry.name.toLowerCase().contains('mix'),
isSdCardMount: false,
isFavorites: false,
),
);
}
}

await prefs.setInt(_kVerifiedPlaylistCountKey, loadedCrates.length);
_applySorting(loadedCrates);

if (mounted) {
setState(() {
_deviceSongs = validSongs;
_crates = loadedCrates;
if (_activeOpenCrate != null) {
final int currentOpenId = _activeOpenCrate!.id;
if (currentOpenId == kCrateIdRecentlyAdded) {
_activeOpenCrate = _buildRecentlyAddedCrateObj();
} else if (currentOpenId == kCrateIdStudioMasters) {
_activeOpenCrate = _buildStudioMastersCrateObj();
} else {
_activeOpenCrate =
loadedCrates.cast<RealDeviceCrate?>().firstWhere(
(RealDeviceCrate? c) => c?.id == currentOpenId,
orElse: () =>
loadedCrates.isEmpty ? null : loadedCrates.first,
);
}
}
});
}
} catch (e) {
debugPrint('Lotus Private Crates loading notice: $e');
} finally {
_isScanningPlaylists = false;
if (mounted) {
setState(() => _isLoading = false);
}
}
}

void _applySorting(List<RealDeviceCrate> list) {
if (_activeSortMode == 'NAME') {
list.sort((RealDeviceCrate a, RealDeviceCrate b) =>
a.title.toLowerCase().compareTo(b.title.toLowerCase()));
} else if (_activeSortMode == 'COUNT') {
list.sort((RealDeviceCrate a, RealDeviceCrate b) =>
b.trackCount.compareTo(a.trackCount));
} else if (_activeSortMode == 'SIZE') {
list.sort((RealDeviceCrate a, RealDeviceCrate b) =>
b.totalSizeMb.compareTo(a.totalSizeMb));
}
}

void _cycleSortMode() {
HapticFeedback.selectionClick();
final Color accent = _theme.primaryAccent;

setState(() {
if (_activeSortMode == 'NAME') {
_activeSortMode = 'COUNT';
} else if (_activeSortMode == 'COUNT') {
_activeSortMode = 'SIZE';
} else {
_activeSortMode = 'NAME';
}
_applySorting(_crates);
});

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1200),
backgroundColor: _theme.containerHighColor,
content: Text(
'Sorted crates by: $_activeSortMode',
style: TextStyle(
color: accent, fontWeight: FontWeight.bold, fontSize: 12),
),
),
);
}

void _toggleFilterMode() {
HapticFeedback.selectionClick();
final Color secondaryAccent = _theme.secondaryAccent;

setState(() {
_losslessOnlyFilter = !_losslessOnlyFilter;
});

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1200),
backgroundColor: _theme.containerHighColor,
content: Text(
_losslessOnlyFilter
? 'Filtering: Hi-Res Lossless Crates Only'
    : 'Filtering: Showing All Crates',
style: TextStyle(
color:
_losslessOnlyFilter ? secondaryAccent : _theme.textPrimaryColor,
fontWeight: FontWeight.bold,
fontSize: 12),
),
),
);
}

Future<void> _handlePullToRefresh() async {
HapticFeedback.mediumImpact();
await _loadPrivateCratesAndAudio();
if (mounted) {
final Color accent = _theme.primaryAccent;
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1400),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.refresh_rounded, color: accent, size: 18),
const SizedBox(width: 8),
Expanded(
child: Text(
'Mixes Refreshed: ${_crates.length} custom crates.',
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

void _openSearchModal() {
HapticFeedback.selectionClick();
LotusSearchModalSafe.show(
context,
allSongs: _deviceSongs,
onSongSelected: (SongModel song) {
_playback.playSong(song, queue: _deviceSongs);
widget.onSongSelected?.call(song);
},
);
}

Future<void> _toggleFavoriteSong(SongModel targetSong) async {
HapticFeedback.mediumImpact();
await _playback.toggleFavoriteSong(targetSong);
}

void _removeSongFromCrate(RealDeviceCrate crate, SongModel song) async {
HapticFeedback.mediumImpact();

if (crate.isFavorites) {
await _toggleFavoriteSong(song);
return;
}

if (crate.isDynamicAutoCrate) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
content: Text(
'Dynamic Auto-Crates are live queries and cannot have tracks manually deleted.',
style: TextStyle(color: _theme.primaryAccent),
),
),
);
return;
}

setState(() {
crate.songs.removeWhere((SongModel s) => s.id == song.id);
double bytes = 0;
for (final SongModel s in crate.songs) {
bytes += s.size;
}
crate.totalSizeMb =
bytes > 0 ? (bytes / (1024 * 1024)) : (crate.songs.length * 32.0);
});

await _persistPrivateCrates();

if (mounted) {
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
content: Text(
'Removed "${song.title}" from "${crate.title}".',
style: TextStyle(
color: _theme.primaryAccent, fontWeight: FontWeight.bold),
),
),
);
}
}

void _handleTagsUpdated(SongModel updatedSong) {
if (!mounted) return;
setState(() {
_deviceSongMap[updatedSong.id] = updatedSong;

void replaceInList(List<SongModel> list) {
final int idx = list.indexWhere((SongModel s) => s.id == updatedSong.id);
if (idx != -1) list[idx] = updatedSong;
}

replaceInList(_deviceSongs);
replaceInList(_recentlyAddedSongs);
replaceInList(_studioMastersSongs);

for (final RealDeviceCrate crate in _crates) {
replaceInList(crate.songs);
}

if (_activeOpenCrate != null) {
replaceInList(_activeOpenCrate!.songs);
}
});
}

void _handleTrackDeleted(SongModel deletedSong) async {
HapticFeedback.mediumImpact();

setState(() {
_deviceSongs.removeWhere((SongModel s) => s.id == deletedSong.id);
_deviceSongMap.remove(deletedSong.id);
_favoriteSongIds.remove(deletedSong.id);
_recentlyAddedSongs.removeWhere((SongModel s) => s.id == deletedSong.id);
_studioMastersSongs.removeWhere((SongModel s) => s.id == deletedSong.id);

for (final RealDeviceCrate crate in _crates) {
final int initialLen = crate.songs.length;
crate.songs.removeWhere((SongModel s) => s.id == deletedSong.id);

if (crate.songs.length != initialLen) {
double bytes = 0;
for (final SongModel s in crate.songs) {
bytes += s.size;
}
crate.totalSizeMb =
bytes > 0 ? (bytes / (1024 * 1024)) : (crate.songs.length * 32.0);
}
}

if (_activeOpenCrate != null) {
_activeOpenCrate!.songs
    .removeWhere((SongModel s) => s.id == deletedSong.id);
}
});

await _persistPrivateCrates();

try {
final SharedPreferences prefs = await _getPrefs();
final List<String> updatedFavs =
_favoriteSongIds.map((int id) => id.toString()).toList();
await prefs.setStringList(_kFavoriteSongIdsKey, updatedFavs);
} catch (_) {}
}

void _onReorderSongsInCrate(int oldIndex, int newIndex) {
if (_activeOpenCrate == null) return;
if (_activeOpenCrate!.isDynamicAutoCrate) return;
HapticFeedback.mediumImpact();

setState(() {
final List<SongModel> currentSongs =
List<SongModel>.from(_activeOpenCrate!.songs);
if (oldIndex < newIndex) {
newIndex -= 1;
}
final SongModel moved = currentSongs.removeAt(oldIndex);
currentSongs.insert(newIndex, moved);
_activeOpenCrate!.songs = currentSongs;
});

if (_activeOpenCrate!.isFavorites) {
_favoriteSongIds
..clear()
..addAll(_activeOpenCrate!.songs.map((SongModel s) => s.id));

unawaited(_getPrefs().then((SharedPreferences prefs) {
if (!mounted) return;
final List<String> updatedFavs = _activeOpenCrate!.songs
    .map((SongModel s) => s.id.toString())
    .toList();
prefs.setStringList(_kFavoriteSongIdsKey, updatedFavs);
}));
} else {
_persistPrivateCrates();
}
}

Future<void> _showAddSongsToCrateSheet(RealDeviceCrate crate) async {
if (crate.isDynamicAutoCrate) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
content: Text(
'Dynamic Auto-Crates automatically index matching tracks from your storage.',
style: TextStyle(color: _theme.primaryAccent),
),
),
);
return;
}

HapticFeedback.mediumImpact();

final Color accent = _theme.primaryAccent;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;
final bool isWhitaniana = _theme.isWhitanianaActive;

final Color surfaceColor = _theme.modalSurfaceColor;
final Color containerLow = _theme.modalContainerLowColor;

final Set<int> existingIds = crate.songs.map((SongModel s) => s.id).toSet();
final List<SongModel> availableSongs = List<SongModel>.from(_deviceSongs)
..sort((SongModel a, SongModel b) =>
a.title.toLowerCase().compareTo(b.title.toLowerCase()));

final Set<int> selectedIds = <int>{};
final TextEditingController filterController = TextEditingController();

await showModalBottomSheet<void>(
context: context,
isScrollControlled: true,
useSafeArea: true,
backgroundColor: Colors.transparent,
barrierColor: Colors.black.withValues(alpha: 0.78),
elevation: 0,
builder: (BuildContext sheetCtx) {
return StatefulBuilder(
builder: (BuildContext ctx, StateSetter setSheetState) {
final String query = filterController.text.trim().toLowerCase();
final List<SongModel> displayed = query.isEmpty
? availableSongs
    : availableSongs.where((SongModel s) {
final String t = s.title.toLowerCase();
final String a = (s.artist ?? '').toLowerCase();
return t.contains(query) || a.contains(query);
}).toList();

const BorderRadius topCurvedRadius =
BorderRadius.vertical(top: Radius.circular(32));

return SafeArea(
top: false,
child: Container(
height: MediaQuery.sizeOf(sheetCtx).height * 0.85,
decoration: BoxDecoration(
borderRadius: topCurvedRadius,
boxShadow: <BoxShadow>[
BoxShadow(
color: Colors.black.withValues(
alpha: isWhitaniana ? 0.15 : 0.85),
blurRadius: 36,
spreadRadius: 8,
offset: const Offset(0, -6),
),
...LotusDecorations.glowShadow(
accent,
intensity: 0.28,
blur: 28,
),
],
),
child: ClipRRect(
borderRadius: topCurvedRadius,
child: Container(
color: surfaceColor,
child: Container(
decoration: BoxDecoration(
borderRadius: topCurvedRadius,
border: Border.all(
color: _theme.cardBorderColor,
width: 1.6,
),
),
child: Column(
children: <Widget>[
Padding(
padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
child: Column(
children: <Widget>[
Container(
width: 44,
height: 4.5,
decoration: BoxDecoration(
color: isWhitaniana
? LotusColors.whitanianaCardBorder
    : Colors.white24,
borderRadius: BorderRadius.circular(3),
),
),
const SizedBox(height: 12),
Text(
'ADD SONGS TO ${crate.title.toUpperCase()}',
style: TextStyle(
color: textPrimary,
fontSize: 14,
fontWeight: FontWeight.w900,
letterSpacing: 0.8,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
const SizedBox(height: 2),
Text(
'${selectedIds.length} songs selected',
style: TextStyle(
color: accent,
fontSize: 11,
fontWeight: FontWeight.bold,
),
),
],
),
),
Padding(
padding:
const EdgeInsets.symmetric(horizontal: 16.0),
child: Container(
height: 42,
padding:
const EdgeInsets.symmetric(horizontal: 14),
decoration: BoxDecoration(
color: containerLow,
borderRadius: BorderRadius.circular(22),
border: Border.all(
color: query.isNotEmpty
? accent
    : _theme.cardBorderColor,
width: query.isNotEmpty ? 1.2 : 0.8,
),
),
child: Row(
children: <Widget>[
const LotusSearchIcon(size: 18),
const SizedBox(width: 10),
Expanded(
child: TextField(
controller: filterController,
style: TextStyle(
color: textPrimary,
fontSize: 13,
),
cursorColor: accent,
onChanged: (_) => setSheetState(() {}),
decoration: InputDecoration(
hintText: 'Search audio files...',
hintStyle: TextStyle(
color: textSecondary,
fontSize: 12.5,
),
border: InputBorder.none,
contentPadding: const EdgeInsets.symmetric(vertical: 10),
isDense: true,
),
),
),
if (query.isNotEmpty)
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () {
HapticFeedback.lightImpact();
filterController.clear();
setSheetState(() {});
},
child: Padding(
padding: const EdgeInsets.all(4.0),
child: Icon(
Icons.close_rounded,
color: _theme.textTertiaryColor,
size: 18,
),
),
),
],
),
),
),
Divider(color: _theme.cardBorderColor, height: 16),
Expanded(
child: ListView.builder(
physics: const BouncingScrollPhysics(),
padding:
const EdgeInsets.symmetric(horizontal: 16),
itemCount: displayed.length,
itemBuilder: (BuildContext ctx, int index) {
final SongModel song = displayed[index];
final bool alreadyIn =
existingIds.contains(song.id);
final bool isSelected =
selectedIds.contains(song.id);

return Container(
margin:
const EdgeInsets.symmetric(vertical: 3.5),
decoration: BoxDecoration(
color: isSelected
? accent.withValues(alpha: 0.14)
    : containerLow,
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: isSelected
? accent.withValues(alpha: 0.5)
    : _theme.cardBorderColor,
),
),
child: ListTile(
dense: true,
enabled: !alreadyIn,
leading: Container(
width: 22,
height: 22,
decoration: BoxDecoration(
color: alreadyIn
? (isWhitaniana
? _theme.containerHighColor
    : Colors.white10)
    : (isSelected
? accent
    : Colors.transparent),
borderRadius: BorderRadius.circular(6),
border: Border.all(
color: alreadyIn
? (isWhitaniana
? _theme.cardBorderColor
    : Colors.white24)
    : (isSelected
? accent
    : _theme.cardBorderColor),
),
),
child: alreadyIn
? Icon(
Icons.lock_outline_rounded,
size: 13,
color: textSecondary,
)
    : (isSelected
? const Icon(
Icons.check_rounded,
size: 15,
color: Colors.white,
)
    : null),
),
title: Text(
song.title,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: alreadyIn
? _theme.textTertiaryColor
    : (isSelected
? accent
    : textPrimary),
fontWeight: FontWeight.bold,
fontSize: 13,
),
),
subtitle: Text(
song.artist ?? '<Unknown>',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: textSecondary,
fontSize: 10.5,
),
),
onTap: alreadyIn
? null
    : () {
HapticFeedback.lightImpact();
setSheetState(() {
if (isSelected) {
selectedIds.remove(song.id);
} else {
selectedIds.add(song.id);
}
});
},
),
);
},
),
),
Container(
padding: EdgeInsets.fromLTRB(
16,
10,
16,
MediaQuery.paddingOf(sheetCtx).bottom + 10,
),
decoration: BoxDecoration(
color: surfaceColor,
border: Border(
top: BorderSide(
color: _theme.cardBorderColor,
width: 0.9,
),
),
),
child: Row(
children: <Widget>[
Expanded(
child: OutlinedButton(
style: OutlinedButton.styleFrom(
foregroundColor: textSecondary,
side: BorderSide(
color: _theme.cardBorderColor,
),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20),
),
padding: const EdgeInsets.symmetric(
vertical: 12),
),
onPressed: () =>
Navigator.of(sheetCtx).pop(),
child: const Text(
'CANCEL',
style: TextStyle(
fontWeight: FontWeight.bold),
),
),
),
const SizedBox(width: 12),
Expanded(
flex: 2,
child: ElevatedButton.icon(
style: ElevatedButton.styleFrom(
backgroundColor: accent,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20),
),
padding: const EdgeInsets.symmetric(
vertical: 12),
),
onPressed: selectedIds.isEmpty
? null
    : () async {
HapticFeedback.mediumImpact();
final ScaffoldMessengerState
messenger =
ScaffoldMessenger.of(context);
final int addedCount =
selectedIds.length;

if (crate.isFavorites) {
for (final int id
in selectedIds) {
final SongModel? s =
_deviceSongMap[id] ??
_playback
    .getSongById(id);
if (s != null &&
!_playback.isSongFavorite(
s.id)) {
await _playback
    .toggleFavoriteSong(s);
}
}
} else {
final List<SongModel> newlyAdded =
<SongModel>[];
for (final int id
in selectedIds) {
final SongModel? s =
_deviceSongMap[id] ??
_playback
    .getSongById(id);
if (s != null &&
!crate.songs.any(
(SongModel existing) =>
existing.id ==
s.id)) {
newlyAdded.add(s);
}
}

setState(() {
crate.songs.addAll(newlyAdded);
double bytes = 0;
for (final SongModel s
in crate.songs) {
bytes += s.size;
}
crate.totalSizeMb = bytes > 0
? (bytes / (1024 * 1024))
    : (crate.songs.length *
32.0);
});

await _persistPrivateCrates();
}

if (mounted && sheetCtx.mounted) {
Navigator.of(sheetCtx).pop();
messenger.hideCurrentSnackBar();
messenger.showSnackBar(
SnackBar(
backgroundColor:
_theme.containerHighColor,
content: Text(
'Added $addedCount song(s) to "${crate.title}".',
style: TextStyle(
color: accent,
fontWeight:
FontWeight.bold,
),
),
),
);
}
},
icon: const Icon(Icons.check_rounded,
size: 18),
label: Text(
selectedIds.isEmpty
? 'SAVE'
    : 'SAVE (${selectedIds.length})',
style: const TextStyle(
fontWeight: FontWeight.w900),
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
);
},
);
},
);
}

Future<void> _persistPrivateCrates() async {
try {
final SharedPreferences prefs = await _getPrefs();
final List<AppCrateEntry> entriesToSave = _crates
    .where((RealDeviceCrate c) => !c.isFavorites && !c.isDynamicAutoCrate)
    .map((RealDeviceCrate c) => AppCrateEntry(
id: c.id,
name: c.title,
songIds: c.songs.map((SongModel s) => s.id).toList(),
dateCreated: DateTime.now().millisecondsSinceEpoch,
isFavorites: false,
))
    .toList();

final String encoded = jsonEncode(
entriesToSave.map((AppCrateEntry e) => e.toJson()).toList());
await prefs.setString(_kPrivatePlaylistsStorageKey, encoded);
await prefs.setInt(_kVerifiedPlaylistCountKey, _crates.length);
} catch (e) {
debugPrint('Error saving private crates: $e');
}
}

// ============================================================================
// DELETE VAULT EXECUTION & CONFIRMATION
// ============================================================================
Future<void> _confirmAndDeleteSelectedCrates() async {
HapticFeedback.heavyImpact();

final Color dialogSurface = _theme.modalSurfaceColor;
final Color cardContainer = _theme.modalContainerLowColor;
const Color alertColor = Color(0xFFFF5252);
final int count = _selectedCrateIdsToDelete.length;

final List<String> playlistNames = _crates
    .where((RealDeviceCrate c) => _selectedCrateIdsToDelete.contains(c.id))
    .map((RealDeviceCrate c) => c.title)
    .toList();

final bool? confirm = await showDialog<bool>(
context: context,
barrierDismissible: true,
barrierColor: Colors.black.withValues(alpha: 0.85),
builder: (BuildContext dCtx) {
return AlertDialog(
backgroundColor: dialogSurface,
clipBehavior: Clip.antiAlias,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(24),
side: BorderSide(
color: alertColor.withValues(alpha: 0.85),
width: 1.6,
),
),
shadowColor: Colors.black,
elevation: 28,
title: Row(
children: <Widget>[
Container(
padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
color: alertColor.withValues(alpha: 0.18),
shape: BoxShape.circle,
border: Border.all(color: alertColor.withValues(alpha: 0.5)),
),
child: Icon(Icons.delete_forever_rounded,
color: alertColor, size: 22),
),
const SizedBox(width: 12),
Expanded(
child: Text(
count == 1
? 'Delete Playlist?'
    : 'Delete $count Playlists?',
style: TextStyle(
color: _theme.textPrimaryColor,
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
count == 1
? 'Permanently delete "${playlistNames.first}" from your playlists?'
    : 'Permanently delete the $count selected playlists from your library?',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 13,
fontWeight: FontWeight.w600,
height: 1.4,
),
),
const SizedBox(height: 12),
Container(
padding: const EdgeInsets.all(10),
decoration: BoxDecoration(
color: cardContainer,
borderRadius: BorderRadius.circular(12),
border: Border.all(color: alertColor.withValues(alpha: 0.35)),
),
child: Row(
children: <Widget>[
const Icon(Icons.shield_outlined,
color: LotusColors.voltLime, size: 16),
const SizedBox(width: 8),
Expanded(
child: Text(
'Your actual audio files remain safe in phone storage. Only the playlist container is deleted.',
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 10.5,
),
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
Navigator.of(dCtx).pop(false);
},
child: Text(
'CANCEL',
style: TextStyle(
color: _theme.textSecondaryColor,
fontWeight: FontWeight.bold,
fontSize: 12,
),
),
),
ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: alertColor,
foregroundColor: Colors.white,
padding:
const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(14)),
elevation: 4,
shadowColor: alertColor.withValues(alpha: 0.5),
),
onPressed: () {
HapticFeedback.heavyImpact();
Navigator.of(dCtx).pop(true);
},
child: const Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(Icons.delete_rounded, size: 16),
SizedBox(width: 6),
Text(
'DELETE',
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

if (confirm == true) {
final int deletedCount = _selectedCrateIdsToDelete.length;

setState(() {
_crates.removeWhere((RealDeviceCrate c) =>
_selectedCrateIdsToDelete.contains(c.id) &&
!c.isFavorites &&
!c.isDynamicAutoCrate);

if (_activeOpenCrate != null &&
_selectedCrateIdsToDelete.contains(_activeOpenCrate!.id)) {
_activeOpenCrate = null;
}

_selectedCrateIdsToDelete.clear();
_isDeleteVaultMode = false;
});

await _persistPrivateCrates();

if (mounted) {
final Color accent = _theme.primaryAccent;
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
duration: const Duration(seconds: 2),
content: Row(
children: <Widget>[
Icon(Icons.delete_outline_rounded, color: accent, size: 18),
const SizedBox(width: 8),
Expanded(
child: Text(
'Successfully deleted $deletedCount playlist(s).',
style: TextStyle(
color: accent,
fontWeight: FontWeight.bold,
fontSize: 12,
),
),
),
],
),
),
);
}
} else {
setState(() {
_isDeleteVaultMode = false;
_selectedCrateIdsToDelete.clear();
});
}
}

void _handleDeleteVaultButtonTap() {
HapticFeedback.selectionClick();

if (!_isDeleteVaultMode) {
setState(() {
_isDeleteVaultMode = true;
_selectedCrateIdsToDelete.clear();
});
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1600),
backgroundColor: _theme.containerHighColor,
content: Text(
'Select playlists to delete. Favorites Vault is protected.',
style: TextStyle(
color: _theme.primaryAccent,
fontWeight: FontWeight.bold,
fontSize: 11.5,
),
),
),
);
} else if (_selectedCrateIdsToDelete.isEmpty) {
setState(() {
_isDeleteVaultMode = false;
_selectedCrateIdsToDelete.clear();
});
} else {
_confirmAndDeleteSelectedCrates();
}
}

// ============================================================================
// HIDDEN SONGS MODAL & RETRIEVAL WORKFLOW
// ============================================================================
void _openHiddenSongsManagementModal() {
HapticFeedback.heavyImpact();
final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;

final Set<int> currentHiddenIds = _playback.hiddenSongIds;
final Set<String> currentHiddenPaths = _playback.hiddenSongPaths;

final List<SongModel> hiddenList = <SongModel>[];

for (final SongModel s in _deviceSongMap.values) {
final bool isIdHidden = currentHiddenIds.contains(s.id);
final bool isPathHidden = s.data.isNotEmpty &&
currentHiddenPaths.contains(s.data.trim().toLowerCase());
if (isIdHidden || isPathHidden) {
if (!hiddenList.any((SongModel existing) => existing.id == s.id)) {
hiddenList.add(s);
}
}
}

for (final int hid in currentHiddenIds) {
if (!hiddenList.any((SongModel s) => s.id == hid)) {
final SongModel? s = _playback.getSongById(hid);
if (s != null) hiddenList.add(s);
}
}

final Set<int> stagedForRetrieval = <int>{};

showModalBottomSheet<void>(
context: context,
isScrollControlled: true,
backgroundColor: Colors.transparent,
builder: (BuildContext modalCtx) {
return StatefulBuilder(
builder: (BuildContext ctx, StateSetter setModalState) {
final Color solidBackground = _theme.modalSurfaceColor;
final Color containerLow = _theme.modalContainerLowColor;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
height: MediaQuery.sizeOf(ctx).height * 0.88,
decoration: BoxDecoration(
color: solidBackground,
borderRadius:
const BorderRadius.vertical(top: Radius.circular(28)),
border: Border(
top: BorderSide(
color: accent.withValues(alpha: 0.8),
width: 1.8,
),
),
boxShadow: LotusDecorations.glowShadow(accent,
intensity: 0.25, blur: 28),
),
child: Column(
children: <Widget>[
Padding(
padding: const EdgeInsets.symmetric(vertical: 10),
child: Container(
width: 44,
height: 4.5,
decoration: BoxDecoration(
color: isWhitaniana
? LotusColors.whitanianaCardBorder
    : Colors.white24,
borderRadius: BorderRadius.circular(2.5),
),
),
),
Padding(
padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
child: Row(
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
'assets/icons/hidden_songs_icon.png',
fit: BoxFit.cover,
errorBuilder: (BuildContext context, Object error,
StackTrace? stackTrace) {
return Center(
child: Icon(Icons.visibility_off_rounded,
color: accent, size: 22),
);
},
),
),
),
const SizedBox(width: 14),
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
'Hidden Songs',
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
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 6, vertical: 1.5),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.18),
borderRadius: BorderRadius.circular(6),
border: Border.all(
color:
accent.withValues(alpha: 0.4)),
),
child: Text(
'${hiddenList.length} HIDDEN',
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.w900,
),
),
),
],
),
const SizedBox(height: 2),
Text(
'Tap On Eye Icon To Restore The Song.',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: textSecondary,
fontSize: 10.0,
),
),
],
),
),
IconButton(
icon: Icon(Icons.close_rounded,
color: textSecondary, size: 20),
onPressed: () => Navigator.of(ctx).pop(),
),
],
),
),
Divider(color: _theme.cardBorderColor, height: 1),
Expanded(
child: hiddenList.isEmpty
? Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: <Widget>[
Icon(Icons.visibility_rounded,
color: accent, size: 48),
const SizedBox(height: 12),
Text(
'No Hidden Songs in Vault',
style: TextStyle(
color: textPrimary,
fontSize: 15,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 6),
Text(
'To hide a track, tap (•••) on any song and select "Hide from App".',
textAlign: TextAlign.center,
style: TextStyle(
color: textSecondary, fontSize: 11),
),
],
),
)
    : ListView.builder(
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
itemCount: hiddenList.length,
itemBuilder: (BuildContext context, int index) {
final SongModel song = hiddenList[index];
final bool isMarkedForRestoration =
stagedForRetrieval.contains(song.id);

return Container(
margin:
const EdgeInsets.symmetric(vertical: 4.0),
decoration: BoxDecoration(
color: isMarkedForRestoration
? accent.withValues(alpha: 0.16)
    : containerLow,
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: isMarkedForRestoration
? accent
    : _theme.cardBorderColor,
width: isMarkedForRestoration ? 1.4 : 0.8,
),
boxShadow: isMarkedForRestoration
? LotusDecorations.glowShadow(accent,
intensity: 0.2, blur: 10)
    : null,
),
child: Padding(
padding: const EdgeInsets.symmetric(
horizontal: 10.0, vertical: 8.0),
child: Row(
children: <Widget>[
ClipRRect(
borderRadius: BorderRadius.circular(10),
child: SizedBox(
width: 44,
height: 44,
child: LotusArtworkImage(
songId: song.id,
size: 44,
borderRadius: 10,
keepOldArtwork: true,
nullArtworkWidget: Container(
width: 44,
height: 44,
color: _theme.containerColor,
child: Icon(
Icons.music_note_rounded,
color: isMarkedForRestoration
? accent
    : _theme.textTertiaryColor,
),
),
),
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Text(
song.title,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isMarkedForRestoration
? accent
    : textPrimary,
fontSize: 13,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 2),
Text(
'${song.artist ?? "<Unknown>"} • ${song.fileExtension.toUpperCase()}',
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
GestureDetector(
onTap: () {
HapticFeedback.lightImpact();
setModalState(() {
if (isMarkedForRestoration) {
stagedForRetrieval
    .remove(song.id);
} else {
stagedForRetrieval.add(song.id);
}
});
},
child: AnimatedContainer(
duration:
const Duration(milliseconds: 200),
padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
color: isMarkedForRestoration
? accent.withValues(alpha: 0.22)
    : (isWhitaniana
? _theme.containerHighColor
    : Colors.white10),
shape: BoxShape.circle,
border: Border.all(
color: isMarkedForRestoration
? accent
    : _theme.cardBorderColor,
width: 1.0,
),
),
child: Icon(
isMarkedForRestoration
? Icons.visibility_rounded
    : Icons.visibility_off_rounded,
color: isMarkedForRestoration
? accent
    : secondaryAccent,
size: 20,
),
),
),
],
),
),
);
},
),
),
Container(
padding: EdgeInsets.fromLTRB(
16,
12,
16,
MediaQuery.paddingOf(ctx).bottom + 12,
),
decoration: BoxDecoration(
color: containerLow,
border: Border(
top: BorderSide(
color: _theme.cardBorderColor, width: 0.9),
),
),
child: Row(
children: <Widget>[
Expanded(
child: OutlinedButton(
style: OutlinedButton.styleFrom(
foregroundColor: textSecondary,
side: BorderSide(color: _theme.cardBorderColor),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20),
),
padding: const EdgeInsets.symmetric(vertical: 12),
),
onPressed: () => Navigator.of(ctx).pop(),
child: const Text(
'CANCEL',
style: TextStyle(
fontWeight: FontWeight.bold, fontSize: 11.5),
),
),
),
const SizedBox(width: 12),
Expanded(
flex: 2,
child: ElevatedButton.icon(
style: ElevatedButton.styleFrom(
backgroundColor: accent,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20),
),
padding: const EdgeInsets.symmetric(vertical: 12),
elevation: 0,
),
onPressed: stagedForRetrieval.isEmpty
? null
    : () async {
HapticFeedback.heavyImpact();

final List<String> pathsToRestore =
<String>[];
for (final int id in stagedForRetrieval) {
final SongModel? s =
_deviceSongMap[id] ??
_playback.getSongById(id);
if (s != null && s.data.isNotEmpty) {
pathsToRestore.add(s.data);
}
}

await _playback.unhideSongs(
stagedForRetrieval, pathsToRestore);

await _loadPrivateCratesAndAudio();

if (ctx.mounted) {
Navigator.of(ctx).pop();
}

if (mounted) {
ScaffoldMessenger.of(context)
    .hideCurrentSnackBar();
ScaffoldMessenger.of(context)
    .showSnackBar(
SnackBar(
duration: const Duration(seconds: 2),
backgroundColor:
_theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.visibility_rounded,
color: accent, size: 20),
const SizedBox(width: 10),
Expanded(
child: Text(
'Retrieved ${stagedForRetrieval.length} song(s) successfully back to your library.',
style: TextStyle(
color: accent,
fontWeight: FontWeight.bold,
fontSize: 12,
),
),
),
],
),
),
);
}
},
icon: const Icon(Icons.check_rounded, size: 18),
label: Text(
stagedForRetrieval.isEmpty
? 'SAVE CHANGES'
    : 'SAVE (${stagedForRetrieval.length} RETRIEVED)',
style: const TextStyle(
fontWeight: FontWeight.w900, fontSize: 11.5),
),
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
);
}

void _playCrate(RealDeviceCrate crate, {bool shuffle = false}) {
HapticFeedback.mediumImpact();
if (crate.songs.isNotEmpty) {
_setPlayingSourceCrate(crate.id);
final List<SongModel> queue = List<SongModel>.from(crate.songs);
if (shuffle) {
queue.shuffle();
}
final SongModel lead = queue.first;
_playback.playSong(
lead,
queue: queue,
);
widget.onSongSelected?.call(lead);
} else {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
content: Text(
crate.isFavorites
? 'Favorites Vault is empty. Tap ❤️ on songs to add them.'
    : 'Crate "${crate.title}" has no songs.',
style: TextStyle(color: _theme.primaryAccent),
),
),
);
}
}

void _toggleCratePlayback(RealDeviceCrate crate) {
HapticFeedback.mediumImpact();
if (crate.songs.isEmpty) {
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
content: Text(
crate.isFavorites
? 'Favorites Vault is empty. Tap ❤️ on songs to add them.'
    : 'Playlist "${crate.title}" has no songs.',
style: TextStyle(color: _theme.primaryAccent),
),
),
);
return;
}

final bool isThisCrateActive = crate.songs.any(_isSongActiveMatch);
if (isThisCrateActive) {
_playback.togglePlayPause();
} else {
_playCrate(crate, shuffle: false);
}
}

void _openCrateDetail(RealDeviceCrate crate) {
HapticFeedback.selectionClick();
setState(() {
_lastInspectedCrate = crate;
_activeOpenCrate = crate;
_isReorderMode = false;
});
}

void _closeCrateDetail() {
HapticFeedback.selectionClick();
setState(() {
if (_activeOpenCrate != null) {
_lastInspectedCrate = _activeOpenCrate;
}
_activeOpenCrate = null;
_isReorderMode = false;
});
}

void _handleSmartBackGesture() {
final RealDeviceCrate? playingCrate = _findPlayingSourceCrate();

if (playingCrate != null && _activeOpenCrate?.id != playingCrate.id) {
_forwardCrateId = _activeOpenCrate?.id;
_wasOnMasterViewBeforeJump = (_activeOpenCrate == null);
_previousViewModeBeforeJump = _viewMode;

_openCrateDetail(playingCrate);
WidgetsBinding.instance.addPostFrameCallback((_) {
_scrollToActiveSongInCrate();
});

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1600),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.album_rounded, color: _theme.primaryAccent, size: 18),
const SizedBox(width: 8),
Expanded(
child: Text(
'Back to "${playingCrate.title}" (Active Playback Source)',
style: TextStyle(
color: _theme.primaryAccent,
fontWeight: FontWeight.bold,
fontSize: 11.5,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
],
),
),
);
return;
}

if (_activeOpenCrate != null) {
_forwardCrateId = _activeOpenCrate!.id;
_wasOnMasterViewBeforeJump = false;
_closeCrateDetail();
return;
}

if (_playback.activeSong != null &&
_viewMode != PlaylistViewMode.flowList) {
setState(() => _viewMode = PlaylistViewMode.flowList);
WidgetsBinding.instance.addPostFrameCallback((_) {
_scrollToActiveSongInFlow();
});
return;
}

if (widget.onBack != null) {
widget.onBack!();
} else {
Navigator.of(context).maybePop();
}
}

void _handleSmartForwardGesture() {
if (_wasOnMasterViewBeforeJump && _activeOpenCrate != null) {
_wasOnMasterViewBeforeJump = false;
_viewMode = _previousViewModeBeforeJump;
_closeCrateDetail();
return;
}

if (_forwardCrateId != null) {
final int targetId = _forwardCrateId!;
_forwardCrateId = null;

final RealDeviceCrate? target =
_allInspectableCrates.cast<RealDeviceCrate?>().firstWhere(
(RealDeviceCrate? c) => c?.id == targetId,
orElse: () => null,
);

if (target != null && _activeOpenCrate?.id != target.id) {
_openCrateDetail(target);
return;
}
}

if (_activeOpenCrate == null && _crates.isNotEmpty) {
final RealDeviceCrate target =
_lastInspectedCrate ?? _findPlayingSourceCrate() ?? _crates.first;
_openCrateDetail(target);
return;
}

if (_activeOpenCrate != null && _allInspectableCrates.length > 1) {
final int currentIndex = _allInspectableCrates
    .indexWhere((RealDeviceCrate c) => c.id == _activeOpenCrate!.id);
if (currentIndex >= 0) {
final int nextIndex = (currentIndex + 1) % _allInspectableCrates.length;
_openCrateDetail(_allInspectableCrates[nextIndex]);
}
}
}

String _getBackGestureLabel() {
final RealDeviceCrate? source = _findPlayingSourceCrate();
if (source != null && _activeOpenCrate?.id != source.id) {
return 'SOURCE';
}
return 'BACK';
}

String _getForwardGestureLabel() {
if (_wasOnMasterViewBeforeJump || _forwardCrateId != null) {
return 'RETURN';
}
return 'NEXT';
}

_SnapbackTargetData _getSnapbackTargetData(bool isLeft) {
if (isLeft) {
final RealDeviceCrate? source = _findPlayingSourceCrate();
if (source != null && _activeOpenCrate?.id != source.id) {
return _SnapbackTargetData(
header: 'ACTIVE PLAYBACK SOURCE >>',
title: source.title,
subtitle: '${source.trackCount} Stems // ${source.primaryFormat}',
badgeText: source.primaryFormat,
songId: source.songs.isNotEmpty ? source.songs.first.id : null,
isSourceOrReturn: true,
);
}
return _SnapbackTargetData(
header: 'NAVIGATE ALL CRATES >>',
title: 'Playlists Master Deck',
subtitle: '${_crates.length} Custom Crates',
badgeText: 'CRATES',
songId: null,
isSourceOrReturn: false,
);
} else {
if (_wasOnMasterViewBeforeJump || _forwardCrateId != null) {
final RealDeviceCrate? prev = _lastInspectedCrate;
return _SnapbackTargetData(
header: 'SNAPBACK TARGET >>',
title: prev?.title ?? 'Previous Crate',
subtitle: '${prev?.trackCount ?? 0} Stems // Cached Crate',
badgeText: prev?.primaryFormat ?? 'RETURN',
songId: prev != null && prev.songs.isNotEmpty
? prev.songs.first.id
    : null,
isSourceOrReturn: true,
);
}
RealDeviceCrate? nextCrate;
if (_activeOpenCrate != null && _allInspectableCrates.length > 1) {
final int currentIndex = _allInspectableCrates
    .indexWhere((RealDeviceCrate c) => c.id == _activeOpenCrate!.id);
if (currentIndex >= 0) {
nextCrate = _allInspectableCrates[
(currentIndex + 1) % _allInspectableCrates.length];
}
} else if (_crates.isNotEmpty) {
nextCrate = _crates.first;
}
return _SnapbackTargetData(
header: 'ADVANCE CRATE >>',
title: nextCrate?.title ?? 'Next Mix Crate',
subtitle:
'${nextCrate?.trackCount ?? 0} Stems // ${nextCrate?.primaryFormat ?? "MIX"}',
badgeText: nextCrate?.primaryFormat ?? 'NEXT',
songId: nextCrate != null && nextCrate.songs.isNotEmpty
? nextCrate.songs.first.id
    : null,
isSourceOrReturn: false,
);
}
}

void _scrollToActiveSongInCrate() {
HapticFeedback.heavyImpact();
if (_activeOpenCrate == null) return;
if (!_crateDetailScrollController.hasClients) return;

final SongModel? playing = _playback.activeSong;
if (playing == null) return;

final int targetIndex =
_activeOpenCrate!.songs.indexWhere(_isSongActiveMatch);
if (targetIndex == -1) {
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
content: Text(
'Active track "${playing.title}" is not in this crate.',
style: TextStyle(color: _theme.primaryAccent),
),
),
);
return;
}

const double itemTotalHeight = 62.0;
const double listTopPadding = 4.0;
const double bottomDockHeight = 120.0;
final double viewportHeight =
_crateDetailScrollController.position.viewportDimension;
final double visibleHeight =
(viewportHeight - bottomDockHeight).clamp(160.0, viewportHeight);

final double cardCenter = listTopPadding +
(targetIndex * itemTotalHeight) +
(itemTotalHeight / 2);
final double targetOffset = (cardCenter - (visibleHeight / 2)).clamp(
0.0,
_crateDetailScrollController.position.maxScrollExtent,
);

_crateDetailScrollController.animateTo(
targetOffset,
duration: const Duration(milliseconds: 500),
curve: Curves.easeOutCubic,
);

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1400),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.my_location_rounded,
color: _theme.primaryAccent, size: 18),
const SizedBox(width: 8),
Expanded(
child: Text(
'Located: Track #${targetIndex + 1} "${playing.title}"',
style: TextStyle(
color: _theme.primaryAccent,
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

void _scrollToActiveSongInFlow() {
HapticFeedback.heavyImpact();
final SongModel? playing = _playback.activeSong;
if (playing == null) return;
if (!_flowScrollController.hasClients) return;

final int targetIndex = _deviceSongs.indexWhere(_isSongActiveMatch);
if (targetIndex == -1) return;

const double sliverPrecedingOffset = 360.0;
const double itemHeight = 74.0;
final double viewportHeight =
_flowScrollController.position.viewportDimension;

final double cardCenter =
sliverPrecedingOffset + (targetIndex * itemHeight) + (itemHeight / 2);
final double targetOffset = (cardCenter - (viewportHeight / 2)).clamp(
0.0,
_flowScrollController.position.maxScrollExtent,
);

_flowScrollController.animateTo(
targetOffset,
duration: const Duration(milliseconds: 500),
curve: Curves.easeOutCubic,
);

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1400),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.my_location_rounded,
color: _theme.primaryAccent, size: 18),
const SizedBox(width: 8),
Expanded(
child: Text(
'Located: Track #${targetIndex + 1} "${playing.title}"',
style: TextStyle(
color: _theme.primaryAccent,
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

String _formatDuration(int ms) {
final Duration d = Duration(milliseconds: ms);
final int minutes = d.inMinutes;
final int seconds = d.inSeconds.remainder(60);
return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatTotalDuration(int ms) {
final Duration d = Duration(milliseconds: ms);
final int hours = d.inHours;
final int minutes = d.inMinutes.remainder(60);
if (hours > 0) {
return '${hours}h ${minutes}m';
}
return '${minutes}m';
}

String _formatRecencyTime(int dateAddedSec) {
if (dateAddedSec <= 0) return 'NEW';
final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
final int diff = nowSec - dateAddedSec;

if (diff < 3600 * 24) return 'TODAY';
if (diff < 3600 * 48) return 'YESTERDAY';
final int days = diff ~/ (3600 * 24);
if (days < 30) return '${days}D AGO';
final int months = days ~/ 30;
return '${months}M AGO';
}

int _calculateCrateDuration(RealDeviceCrate crate) {
return crate.songs
    .fold(0, (int sum, SongModel s) => sum + (s.duration ?? 0));
}

List<RealDeviceCrate> get _filteredCrates {
if (!_losslessOnlyFilter) return _crates;
return _crates.where((RealDeviceCrate c) {
final String fmt = c.primaryFormat.toUpperCase();
return fmt.contains('FLAC') || fmt.contains('DSD') || fmt.contains('WAV');
}).toList();
}

@override
Widget build(BuildContext context) {
return ListenableBuilder(
listenable: _theme,
builder: (BuildContext context, Widget? child) {
final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;
final Color bgColor = _theme.backgroundColor;
final Color surfaceColor = _theme.surfaceColor;
final Color containerLow = _theme.containerLowColor;

return Scaffold(
backgroundColor: bgColor,
body: Stack(
children: <Widget>[
SafeArea(
bottom: false,
child: Column(
children: <Widget>[
_buildTopAppBar(accent, surfaceColor, containerLow),
Expanded(
child: _isLoading
? Center(
child: CircularProgressIndicator(color: accent),
)
    : (_activeOpenCrate != null
? _buildCrateDetailView(_activeOpenCrate!, accent,
secondaryAccent, containerLow)
    : RefreshIndicator(
color: accent,
backgroundColor: surfaceColor,
displacement: 28.0,
onRefresh: _handlePullToRefresh,
child: CustomScrollView(
controller: _flowScrollController,
physics: const BouncingScrollPhysics(
parent:
AlwaysScrollableScrollPhysics()),
slivers: <Widget>[
SliverToBoxAdapter(
child: _buildHeader(
_deviceSongs.length,
accent,
secondaryAccent),
),
SliverToBoxAdapter(
child: _buildSegmentedLayoutSwitcher(
accent,
secondaryAccent,
containerLow),
),
SliverToBoxAdapter(
child: _buildDynamicAutoCratesStream(
accent,
secondaryAccent,
containerLow),
),
SliverToBoxAdapter(
child: _buildCrateSectionHeader(
accent, secondaryAccent),
),
if (_viewMode ==
PlaylistViewMode.cratesGrid)
_buildCratesGridSliver(accent,
secondaryAccent, containerLow)
else if (_viewMode ==
PlaylistViewMode.flowList)
_buildFlowListSliver(accent,
secondaryAccent, containerLow)
else
_buildSmartMixesSliver(
accent, containerLow),
SliverToBoxAdapter(
child:
_buildDeleteVaultAndHiddenProcessDock(
accent, secondaryAccent),
),
const SliverToBoxAdapter(
child: SizedBox(height: 140),
),
],
),
)),
),
],
),
),

// ================================================================
// TACTILE KINETIC ARCH & SNAPBACK HUD — LEFT BEZEL (BACK / SOURCE)
// ================================================================
Positioned(
left: 0,
top: 60,
bottom: 80,
width: 28,
child: GestureDetector(
behavior: HitTestBehavior.translucent,
onHorizontalDragDown: (DragDownDetails details) {
_leftDragY = details.globalPosition.dy;
},
onHorizontalDragStart: (DragStartDetails details) {
_leftDragY = details.globalPosition.dy;
},
onHorizontalDragUpdate: (DragUpdateDetails details) {
_leftDragY = details.globalPosition.dy;
if (details.primaryDelta != null &&
details.primaryDelta! > 0) {
setState(() {
_leftDragExtent =
(_leftDragExtent + details.primaryDelta!)
    .clamp(0.0, 95.0);
if (_leftDragExtent >= 48.0 && !_leftTriggered) {
_leftTriggered = true;
HapticFeedback.mediumImpact();
}
});
}
},
onHorizontalDragEnd: (DragEndDetails details) {
if (_leftTriggered || _leftDragExtent >= 48.0) {
HapticFeedback.heavyImpact();
_handleSmartBackGesture();
}
setState(() {
_leftDragExtent = 0.0;
_leftTriggered = false;
});
},
onHorizontalDragCancel: () {
setState(() {
_leftDragExtent = 0.0;
_leftTriggered = false;
});
},
),
),

if (_leftDragExtent > 0) ...<Widget>[
Positioned.fill(
child: IgnorePointer(
child: CustomPaint(
painter: _LotusKineticParabolicArchPainter(
extent: _leftDragExtent,
touchY: _leftDragY,
isTriggered: _leftTriggered,
isLeft: true,
label: _getBackGestureLabel(),
primaryColor: accent,
secondaryColor: secondaryAccent,
surfaceColor: surfaceColor,
),
),
),
),
Positioned(
left: _leftDragExtent + 14.0,
top: (_leftDragY - 52.0).clamp(
110.0,
MediaQuery.sizeOf(context).height - 220.0,
),
child: _LotusKineticSnapbackCard(
isLeft: true,
extent: _leftDragExtent,
isTriggered: _leftTriggered,
target: _getSnapbackTargetData(true),
primaryColor: accent,
secondaryColor: secondaryAccent,
containerColor: containerLow,
),
),
],

// ================================================================
// TACTILE KINETIC ARCH & SNAPBACK HUD — RIGHT BEZEL (NEXT / RETURN)
// ================================================================
Positioned(
right: 0,
top: 60,
bottom: 80,
width: 28,
child: GestureDetector(
behavior: HitTestBehavior.translucent,
onHorizontalDragDown: (DragDownDetails details) {
_rightDragY = details.globalPosition.dy;
},
onHorizontalDragStart: (DragStartDetails details) {
_rightDragY = details.globalPosition.dy;
},
onHorizontalDragUpdate: (DragUpdateDetails details) {
_rightDragY = details.globalPosition.dy;
if (details.primaryDelta != null &&
details.primaryDelta! < 0) {
setState(() {
_rightDragExtent =
(_rightDragExtent - details.primaryDelta!)
    .clamp(0.0, 95.0);
if (_rightDragExtent >= 48.0 && !_rightTriggered) {
_rightTriggered = true;
HapticFeedback.mediumImpact();
}
});
}
},
onHorizontalDragEnd: (DragEndDetails details) {
if (_rightTriggered || _rightDragExtent >= 48.0) {
HapticFeedback.heavyImpact();
_handleSmartForwardGesture();
}
setState(() {
_rightDragExtent = 0.0;
_rightTriggered = false;
});
},
onHorizontalDragCancel: () {
setState(() {
_rightDragExtent = 0.0;
_rightTriggered = false;
});
},
),
),

if (_rightDragExtent > 0) ...<Widget>[
Positioned.fill(
child: IgnorePointer(
child: CustomPaint(
painter: _LotusKineticParabolicArchPainter(
extent: _rightDragExtent,
touchY: _rightDragY,
isTriggered: _rightTriggered,
isLeft: false,
label: _getForwardGestureLabel(),
primaryColor: accent,
secondaryColor: secondaryAccent,
surfaceColor: surfaceColor,
),
),
),
),
Positioned(
right: _rightDragExtent + 14.0,
top: (_rightDragY - 52.0).clamp(
110.0,
MediaQuery.sizeOf(context).height - 220.0,
),
child: _LotusKineticSnapbackCard(
isLeft: false,
extent: _rightDragExtent,
isTriggered: _rightTriggered,
target: _getSnapbackTargetData(false),
primaryColor: accent,
secondaryColor: secondaryAccent,
containerColor: containerLow,
),
),
],

if (_leftDragExtent > 0 || _rightDragExtent > 0)
Positioned(
top: MediaQuery.paddingOf(context).top + 8.0,
left: 0,
right: 0,
child: IgnorePointer(
child: _LotusKineticTelemetryBanner(
isLeft: _leftDragExtent > 0,
extent: _leftDragExtent > 0
? _leftDragExtent
    : _rightDragExtent,
isTriggered: _leftDragExtent > 0
? _leftTriggered
    : _rightTriggered,
label: _leftDragExtent > 0
? _getBackGestureLabel()
    : _getForwardGestureLabel(),
targetTitle:
_getSnapbackTargetData(_leftDragExtent > 0).title,
primaryColor: accent,
secondaryColor: secondaryAccent,
),
),
),
],
),
);
},
);
}

Widget _buildTopAppBar(Color accent, Color surfaceColor, Color containerLow) {
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

if (_activeOpenCrate != null) {
final RealDeviceCrate crate = _activeOpenCrate!;
final bool isRecentlyAdded =
crate.autoCrateType == 'RECENT' || crate.id == kCrateIdRecentlyAdded;

return Container(
padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
decoration: BoxDecoration(
color: surfaceColor,
border: Border(
bottom:
BorderSide(color: accent.withValues(alpha: 0.2), width: 0.8),
),
),
child: Row(
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
child: isRecentlyAdded
? Image.asset(
'assets/icons/recently_added_icon.png',
fit: BoxFit.cover,
errorBuilder: (BuildContext context, Object error,
StackTrace? stackTrace) {
return Center(
child: Icon(Icons.history_rounded,
color: accent, size: 24),
);
},
)
    : (crate.isFavorites
? Padding(
padding: const EdgeInsets.all(1.0),
child: Image.asset(
'assets/icons/heart_icon.png',
fit: BoxFit.contain,
errorBuilder: (BuildContext context, Object error,
StackTrace? stackTrace) {
return Center(
child: Icon(Icons.favorite_rounded,
color: _theme.secondaryAccent, size: 26),
);
},
),
)
    : (crate.isDynamicAutoCrate
? Center(
child: Icon(
crate.autoCrateType == 'STUDIO_MASTERS'
? Icons.album_rounded
    : Icons.waves_rounded,
color: accent,
size: 24,
),
)
    : Image.asset(
'assets/icons/mixes_icon.png',
fit: BoxFit.cover,
errorBuilder: (BuildContext context,
Object error, StackTrace? stackTrace) {
return Center(
child: Icon(Icons.queue_music_rounded,
color: accent, size: 24),
);
},
))),
),
),
const SizedBox(width: 14),
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
crate.title,
style: TextStyle(
color: textPrimary,
fontSize: 16,
fontWeight: FontWeight.bold,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
if (crate.isDynamicAutoCrate) ...<Widget>[
const SizedBox(width: 6),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 5, vertical: 1.5),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.2),
borderRadius: BorderRadius.circular(4),
),
child: Text(
'DYNAMIC',
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
const SizedBox(height: 1),
Text(
'${crate.trackCount} TRACKS • ${_formatTotalDuration(_calculateCrateDuration(crate))}',
style: TextStyle(
color: accent,
fontSize: 9.5,
fontWeight: FontWeight.bold,
),
),
],
),
),
if (!crate.isFavorites && !crate.isDynamicAutoCrate)
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setState(() => _isReorderMode = !_isReorderMode);
},
child: Container(
padding:
const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
decoration: BoxDecoration(
color: _isReorderMode ? accent : containerLow,
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: _isReorderMode ? accent : _theme.cardBorderColor,
),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(
Icons.swap_vert_rounded,
color: _isReorderMode ? Colors.white : accent,
size: 16,
),
const SizedBox(width: 4),
Text(
_isReorderMode ? 'DONE' : 'REORDER',
style: TextStyle(
color: _isReorderMode ? Colors.white : textPrimary,
fontSize: 10.5,
fontWeight: FontWeight.w900,
letterSpacing: 0.5,
),
),
],
),
),
),
],
),
);
}

return Container(
padding: const EdgeInsets.fromLTRB(14.0, 8.0, 16.0, 8.0),
decoration: BoxDecoration(
color: surfaceColor,
border: Border(
bottom: BorderSide(color: accent.withValues(alpha: 0.2), width: 0.8),
),
),
child: Row(
children: <Widget>[
Container(
width: 42,
height: 42,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: containerLow,
border: Border.all(color: accent, width: 1.8),
boxShadow: LotusDecorations.glowShadow(accent,
intensity: 0.35, blur: 16),
),
child: ClipOval(
child: Image.asset(
'assets/icons/mixes_icon.png',
fit: BoxFit.cover,
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
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Row(
children: <Widget>[
Text(
'Mixes',
style: TextStyle(
color: textPrimary,
fontSize: 16,
fontWeight: FontWeight.bold,
letterSpacing: 0.3,
),
),
const SizedBox(width: 6),
Text(
'DSD 512',
style: TextStyle(
color: accent,
fontSize: 9.5,
fontWeight: FontWeight.bold,
fontFamily: 'monospace',
),
),
],
),
const SizedBox(height: 1),
Text(
'384 kHz • 32-bit FLAC',
style: TextStyle(color: textSecondary, fontSize: 9.5),
),
],
),
),
Tooltip(
message: 'Search All Stems',
child: GestureDetector(
onTap: _openSearchModal,
child: Container(
width: 36,
height: 36,
decoration: BoxDecoration(
color: containerLow,
shape: BoxShape.circle,
border: Border.all(color: _theme.cardBorderColor),
),
child: const Center(
child: LotusSearchIcon(size: 20),
),
),
),
),
],
),
);
}

Widget _buildHeader(
int totalTrackCount, Color accent, Color secondaryAccent) {
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

return Padding(
padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(12),
border: Border.all(color: accent.withValues(alpha: 0.3)),
),
child: Row(
children: <Widget>[
CircleAvatar(radius: 3, backgroundColor: accent),
const SizedBox(width: 6),
Expanded(
child: Text(
'APP-PRIVATE VAULT • ZERO MEDIASTORE LEAKS',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: accent,
fontSize: 8.0,
fontWeight: FontWeight.w900,
letterSpacing: 0.5,
),
),
),
const SizedBox(width: 6),
const Text(
'IOPS 1,420 MB/s',
style: TextStyle(
color: LotusColors.solarGold,
fontSize: 8.0,
fontWeight: FontWeight.bold,
fontFamily: 'monospace',
),
),
],
),
),
const SizedBox(height: 10),
Row(
crossAxisAlignment: CrossAxisAlignment.center,
children: <Widget>[
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Row(
children: <Widget>[
Icon(Icons.auto_awesome_rounded,
color: secondaryAccent, size: 17),
const SizedBox(width: 6),
Flexible(
fit: FlexFit.loose,
child: Text(
'Blooming Mixes',
style: TextStyle(
color: textPrimary,
fontSize: 21,
fontWeight: FontWeight.w900,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
],
),
const SizedBox(height: 2),
Text(
'${_crates.length} PRIVATE CRATES • $totalTrackCount AUDIOPHILE STEMS',
style: TextStyle(
color: textSecondary,
fontSize: 8.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.6,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
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
borderRadius: BorderRadius.circular(20)),
padding:
const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
elevation: 0,
shadowColor: accent.withValues(alpha: 0.5),
),
onPressed: () {
HapticFeedback.lightImpact();
_showCreateNewCrateDialog(context, accent, secondaryAccent);
},
icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
label: const Text(
'+ CREATE NEW',
style: TextStyle(
fontWeight: FontWeight.w900,
fontSize: 10.5,
letterSpacing: 0.4,
),
),
),
],
),
],
),
);
}

Future<void> _showCreateNewCrateDialog(
BuildContext context, Color accent, Color secondaryAccent) async {
final TextEditingController nameController = TextEditingController();
final bool isWhitaniana = _theme.isWhitanianaActive;
final Color dialogSurface = _theme.modalSurfaceColor;
final Color cardContainer = _theme.modalContainerLowColor;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

const List<String> quickTags = <String>[
'Deep Focus',
'Studio Reference',
'Night Drive',
'Audiophile DSD',
'Chill Stems',
];

await showGeneralDialog<bool>(
context: context,
barrierDismissible: true,
barrierLabel: 'Dismiss Create Crate Dialog',
barrierColor: Colors.black.withValues(alpha: 0.82),
transitionDuration: const Duration(milliseconds: 220),
pageBuilder: (BuildContext ctx, Animation<double> anim1,
Animation<double> anim2) {
return const SizedBox.shrink();
},
transitionBuilder: (BuildContext ctx, Animation<double> anim,
Animation<double> secAnim, Widget child) {
final CurvedAnimation curved =
CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);

return ScaleTransition(
scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
child: FadeTransition(
opacity: curved,
child: Dialog(
backgroundColor: Colors.transparent,
insetPadding:
const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
elevation: 0,
child: StatefulBuilder(
builder: (BuildContext dCtx, StateSetter setDialogState) {
final String enteredTitle = nameController.text.trim();
final bool canSubmit = enteredTitle.isNotEmpty;

return Container(
constraints: const BoxConstraints(maxWidth: 420),
decoration: BoxDecoration(
color: dialogSurface,
borderRadius: BorderRadius.circular(28),
border: Border.all(
color: _theme.cardBorderColor,
width: 1.6,
),
boxShadow: <BoxShadow>[
BoxShadow(
color: Colors.black.withValues(
alpha: isWhitaniana ? 0.15 : 0.85),
blurRadius: 36,
spreadRadius: 8,
offset: const Offset(0, 10),
),
...LotusDecorations.glowShadow(
accent,
intensity: 0.28,
blur: 30,
),
],
),
child: ClipRRect(
borderRadius: BorderRadius.circular(28),
child: Container(
color: dialogSurface,
child: SingleChildScrollView(
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: <Widget>[
Row(
children: <Widget>[
Container(
width: 44,
height: 44,
decoration: BoxDecoration(
color: cardContainer,
shape: BoxShape.circle,
border: Border.all(
color: accent.withValues(alpha: 0.9),
width: 1.5,
),
boxShadow: LotusDecorations.glowShadow(
accent,
intensity: 0.25,
blur: 12,
),
),
child: Center(
child: Image.asset(
'assets/icons/create_new_icon.png',
width: 35,
height: 35,
fit: BoxFit.contain,
),
),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: <Widget>[
Text(
'Create Private Crate',
style: TextStyle(
color: textPrimary,
fontSize: 17,
fontWeight: FontWeight.w900,
letterSpacing: -0.2,
),
),
const SizedBox(height: 2),
Text(
'Isolated Sandbox • Zero MediaStore Leaks',
style: TextStyle(
color: secondaryAccent,
fontSize: 10.5,
fontWeight: FontWeight.w600,
),
),
],
),
),
IconButton(
onPressed: () =>
Navigator.of(dCtx).pop(false),
icon: Icon(Icons.close_rounded,
color: textSecondary, size: 20),
padding: EdgeInsets.zero,
constraints: const BoxConstraints(),
),
],
),
const SizedBox(height: 18),
Container(
decoration: BoxDecoration(
color: cardContainer,
borderRadius: BorderRadius.circular(18),
border: Border.all(
color: canSubmit
? accent
    : _theme.cardBorderColor,
width: canSubmit ? 1.4 : 1.0,
),
),
padding: const EdgeInsets.symmetric(
horizontal: 16, vertical: 4),
child: TextField(
controller: nameController,
autofocus: true,
textCapitalization: TextCapitalization.words,
style: TextStyle(
color: textPrimary,
fontSize: 14.5,
fontWeight: FontWeight.w700,
),
cursorColor: accent,
onChanged: (_) => setDialogState(() {}),
onSubmitted: (_) {
if (canSubmit) {
_executeCreateCrate(
context, dCtx, enteredTitle, accent);
}
},
decoration: InputDecoration(
hintText: 'Enter crate or playlist name...',
hintStyle: TextStyle(
color: textSecondary,
fontSize: 13,
fontWeight: FontWeight.normal,
),
border: InputBorder.none,
isDense: false,
suffixIcon: enteredTitle.isNotEmpty
? IconButton(
onPressed: () {
nameController.clear();
setDialogState(() {});
},
icon: Icon(Icons.cancel_rounded,
color: _theme.textTertiaryColor,
size: 18),
)
    : null,
),
),
),
const SizedBox(height: 12),
Text(
'QUICK SUGGESTIONS',
style: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 9.5,
fontWeight: FontWeight.w800,
letterSpacing: 0.8,
),
),
const SizedBox(height: 8),
Wrap(
spacing: 6,
runSpacing: 6,
children: quickTags.map((String tag) {
final bool isSelected = enteredTitle == tag;
return GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setDialogState(() {
nameController.text = tag;
nameController.selection =
TextSelection.fromPosition(
TextPosition(offset: tag.length),
);
});
},
child: AnimatedContainer(
duration:
const Duration(milliseconds: 150),
padding: const EdgeInsets.symmetric(
horizontal: 10, vertical: 5),
decoration: BoxDecoration(
color: isSelected
? accent.withValues(alpha: 0.22)
    : cardContainer,
borderRadius: BorderRadius.circular(12),
border: Border.all(
color: isSelected
? accent
    : _theme.cardBorderColor,
width: isSelected ? 1.2 : 0.8,
),
),
child: Text(
tag,
style: TextStyle(
color:
isSelected ? accent : textPrimary,
fontSize: 11,
fontWeight: isSelected
? FontWeight.w800
    : FontWeight.w500,
),
),
),
);
}).toList(),
),
const SizedBox(height: 22),
Row(
children: <Widget>[
Expanded(
child: OutlinedButton(
style: OutlinedButton.styleFrom(
foregroundColor: textSecondary,
side: BorderSide(
color: _theme.cardBorderColor),
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(16),
),
padding: const EdgeInsets.symmetric(
vertical: 13),
),
onPressed: () {
HapticFeedback.lightImpact();
Navigator.of(dCtx).pop(false);
},
child: const Text(
'CANCEL',
style: TextStyle(
fontWeight: FontWeight.bold,
fontSize: 12,
letterSpacing: 0.6,
),
),
),
),
const SizedBox(width: 12),
Expanded(
flex: 2,
child: ElevatedButton.icon(
style: ElevatedButton.styleFrom(
backgroundColor: accent,
foregroundColor: Colors.white,
disabledBackgroundColor:
accent.withValues(alpha: 0.25),
disabledForegroundColor: Colors.white38,
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(16),
),
padding: const EdgeInsets.symmetric(
vertical: 13),
elevation: canSubmit ? 6 : 0,
shadowColor:
accent.withValues(alpha: 0.5),
),
onPressed: canSubmit
? () => _executeCreateCrate(
context,
dCtx,
enteredTitle,
accent)
    : null,
icon: const Icon(
Icons.check_circle_rounded,
size: 18),
label: const Text(
'CREATE CRATE',
style: TextStyle(
fontWeight: FontWeight.w900,
fontSize: 12.5,
letterSpacing: 0.5,
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
),
);
},
),
),
),
);
},
);
}

Future<void> _executeCreateCrate(BuildContext parentContext,
BuildContext dialogContext, String title, Color accent) async {
HapticFeedback.mediumImpact();
Navigator.of(dialogContext).pop(true);

final int newId = DateTime.now().millisecondsSinceEpoch;

final RealDeviceCrate newCrate = RealDeviceCrate(
id: newId,
title: title,
songs: <SongModel>[],
totalSizeMb: 0.0,
primaryFormat: 'FLAC 24/96',
avgBitrateKbps: 4608,
isPinned: false,
isSdCardMount: false,
isFavorites: false,
isDynamicAutoCrate: false,
);

setState(() {
_crates.add(newCrate);
});

await _persistPrivateCrates();

if (!parentContext.mounted) return;

ScaffoldMessenger.of(parentContext).hideCurrentSnackBar();
ScaffoldMessenger.of(parentContext).showSnackBar(
SnackBar(
backgroundColor: _theme.containerHighColor,
duration: const Duration(seconds: 2),
content: Text(
'Created "$title". Select songs to add now.',
style: TextStyle(color: accent, fontWeight: FontWeight.bold),
),
),
);

_showAddSongsToCrateSheet(newCrate);
}

Widget _buildSegmentedLayoutSwitcher(
Color accent, Color secondaryAccent, Color containerLow) {
return Container(
margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
decoration: BoxDecoration(
color: containerLow,
borderRadius: BorderRadius.circular(24),
border: Border.all(color: _theme.cardBorderColor),
),
child: Row(
children: <Widget>[
_buildSegmentButton(
icon: Icons.grid_view_rounded,
label: 'GRID',
mode: PlaylistViewMode.cratesGrid,
accent: accent,
),
const SizedBox(width: 4),
_buildSegmentButton(
icon: Icons.view_headline_rounded,
label: 'FLOW',
mode: PlaylistViewMode.flowList,
accent: accent,
),
const SizedBox(width: 4),
_buildSegmentButton(
icon: Icons.psychology_rounded,
label: 'SMART',
mode: PlaylistViewMode.smartMixes,
accent: accent,
),
const Spacer(),
Tooltip(
message: 'Cycle Sort Mode (Name, Count, Size)',
child: IconButton(
icon: Icon(Icons.sort_rounded, color: accent, size: 19),
padding: EdgeInsets.zero,
constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
onPressed: _cycleSortMode,
),
),
Tooltip(
message: 'Filter Hi-Res Lossless Only',
child: IconButton(
icon: Icon(
Icons.tune_rounded,
color: _losslessOnlyFilter
? secondaryAccent
    : _theme.textSecondaryColor,
size: 19,
),
padding: EdgeInsets.zero,
constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
onPressed: _toggleFilterMode,
),
),
],
),
);
}

Widget _buildSegmentButton({
required IconData icon,
required String label,
required PlaylistViewMode mode,
required Color accent,
}) {
final bool isSelected = _viewMode == mode;
final bool isWhitaniana = _theme.isWhitanianaActive;

return GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setState(() => _viewMode = mode);
},
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
decoration: BoxDecoration(
color: isSelected ? _theme.containerHighColor : Colors.transparent,
borderRadius: BorderRadius.circular(18),
border: isSelected
? Border.all(color: accent.withValues(alpha: 0.8), width: 1.0)
    : null,
boxShadow: isSelected
? LotusDecorations.glowShadow(accent, intensity: 0.16, blur: 8)
    : null,
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(icon,
color: isSelected ? accent : _theme.textSecondaryColor,
size: 14),
const SizedBox(width: 4),
Text(
label,
style: TextStyle(
color: isSelected
? (isWhitaniana ? _theme.textPrimaryColor : Colors.white)
    : _theme.textSecondaryColor,
fontSize: 10.0,
fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
letterSpacing: 0.3,
),
),
],
),
),
);
}

Widget _buildDynamicAutoCratesStream(
Color accent, Color secondaryAccent, Color containerLow) {
final RealDeviceCrate? recentCrate = _buildRecentlyAddedCrateObj();

final String recentsSubtitle = _recentlyAddedSongs.isNotEmpty
? '+${_recentlyAddedSongs.length} New Imports'
    : 'Past 30 Days';
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Row(
children: <Widget>[
Icon(Icons.bolt_rounded, color: secondaryAccent, size: 15),
const SizedBox(width: 6),
Text(
'DYNAMIC AUTO-CRATES',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 11,
fontWeight: FontWeight.bold,
letterSpacing: 0.6,
),
),
],
),
Text(
'LIVE SYNCED',
style: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 9,
fontWeight: FontWeight.bold,
letterSpacing: 0.8,
),
),
],
),
const SizedBox(height: 8),
GestureDetector(
onTap: () {
if (recentCrate != null) {
_openCrateDetail(recentCrate);
}
},
child: Container(
width: double.infinity,
padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(16),
border: Border.all(
color: accent.withValues(alpha: 0.4),
width: 1.0,
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : LotusDecorations.glowShadow(accent,
intensity: 0.15, blur: 12),
),
child: Row(
children: <Widget>[
Container(
width: 44,
height: 44,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: accent.withValues(alpha: 0.16),
border: Border.all(color: accent, width: 1.4),
),
child: ClipOval(
child: Image.asset(
'assets/icons/recently_added_icon.png',
fit: BoxFit.cover,
errorBuilder: (BuildContext context, Object error,
StackTrace? stackTrace) {
return Center(
child: Icon(Icons.history_rounded,
color: accent, size: 24),
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
Text(
'Recently Added',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 14,
fontWeight: FontWeight.bold,
),
),
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 6, vertical: 2),
decoration: BoxDecoration(
color: accent.withValues(
alpha: isWhitaniana ? 0.15 : 0.2),
borderRadius: BorderRadius.circular(4),
border: Border.all(
color: accent.withValues(alpha: 0.5),
width: 0.6),
),
child: Text(
'384 KHZ',
style: TextStyle(
color: accent,
fontSize: 8,
fontWeight: FontWeight.w900),
),
),
],
),
const SizedBox(height: 3),
Text(
recentsSubtitle,
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 11,
),
),
],
),
),
Icon(
Icons.arrow_forward_ios_rounded,
color: accent.withValues(alpha: 0.7),
size: 15,
),
],
),
),
),
],
),
);
}

Widget _buildCrateSectionHeader(Color accent, Color secondaryAccent) {
final List<RealDeviceCrate> displayList = _filteredCrates;
final SongModel? playing = _playback.activeSong;

return Padding(
padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
child: Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Row(
children: <Widget>[
Text(
'Curated Crates',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
decoration: BoxDecoration(
color: _theme.containerHighColor,
borderRadius: BorderRadius.circular(6),
),
child: Text(
'${displayList.length} Active',
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 8.5,
fontWeight: FontWeight.bold,
),
),
),
],
),
if (_viewMode == PlaylistViewMode.flowList &&
playing != null) ...<Widget>[
GestureDetector(
onTap: _scrollToActiveSongInFlow,
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
Icon(Icons.my_location_rounded, color: accent, size: 12),
const SizedBox(width: 4),
Text(
'LOCATE',
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.w900,
letterSpacing: 0.6,
),
),
],
),
),
),
],
],
),
);
}

Widget _buildCratesGridSliver(
Color accent, Color secondaryAccent, Color containerLow) {
final List<RealDeviceCrate> list = _filteredCrates;

return SliverPadding(
padding: const EdgeInsets.symmetric(horizontal: 16.0),
sliver: SliverGrid(
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
crossAxisCount: 2,
mainAxisSpacing: 12.0,
crossAxisSpacing: 12.0,
childAspectRatio: 0.78,
),
delegate: SliverChildBuilderDelegate(
(BuildContext context, int index) {
final RealDeviceCrate crate = list[index];
final bool isSelectedForDeletion =
_selectedCrateIdsToDelete.contains(crate.id);
return _buildCrateGridCard(crate, isSelectedForDeletion, index,
accent, secondaryAccent, containerLow);
},
childCount: list.length,
),
),
);
}

Widget _buildCrateGridCard(
RealDeviceCrate crate,
bool isSelectedForDeletion,
int index,
Color accent,
Color secondaryAccent,
Color containerLow,
) {
final bool isCrateActive = crate.songs.any(_isSongActiveMatch);
final bool isThisCratePlaying = isCrateActive && _playback.isPlaying;
final Color itemAccent = isCrateActive
? accent
    : (crate.isFavorites
? secondaryAccent
    : (index % 2 == 0 ? accent : secondaryAccent));

final bool isDeletable = !crate.isFavorites && !crate.isDynamicAutoCrate;
const Color alertRed = Color(0xFFFF5252);
final bool isWhitaniana = _theme.isWhitanianaActive;

return RepaintBoundary(
child: Container(
decoration: BoxDecoration(
color: isSelectedForDeletion
? alertRed.withValues(alpha: 0.16)
    : (isCrateActive
? (isWhitaniana
? _theme.containerColor
    : _theme.containerHighColor)
    : containerLow),
borderRadius: BorderRadius.circular(18),
border: Border.all(
color: isSelectedForDeletion
? alertRed
    : (isCrateActive
? accent.withValues(alpha: 0.95)
    : (crate.isFavorites
? secondaryAccent.withValues(alpha: 0.5)
    : itemAccent.withValues(alpha: 0.35))),
width: isSelectedForDeletion || isCrateActive ? 1.8 : 0.8,
),
boxShadow: isSelectedForDeletion
? LotusDecorations.glowShadow(alertRed,
intensity: 0.28, blur: 14)
    : (isCrateActive
? LotusDecorations.glowShadow(accent,
intensity: 0.22, blur: 14)
    : (isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : null)),
),
child: Material(
color: Colors.transparent,
child: InkWell(
borderRadius: BorderRadius.circular(18),
onTap: () {
if (_isDeleteVaultMode) {
HapticFeedback.selectionClick();
if (!isDeletable) {
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1400),
backgroundColor: _theme.containerHighColor,
content: Text(
'Favorites Vault & Auto-Crates are protected and cannot be deleted.',
style: TextStyle(
color: _theme.secondaryAccent,
fontWeight: FontWeight.bold,
fontSize: 11),
),
),
);
return;
}
setState(() {
if (isSelectedForDeletion) {
_selectedCrateIdsToDelete.remove(crate.id);
} else {
_selectedCrateIdsToDelete.add(crate.id);
}
});
} else {
_openCrateDetail(crate);
}
},
child: Padding(
padding: const EdgeInsets.all(8.0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Expanded(
child: Stack(
children: <Widget>[
ClipRRect(
borderRadius: BorderRadius.circular(12),
child: Container(
width: double.infinity,
decoration: BoxDecoration(
gradient: RadialGradient(
colors: <Color>[
isSelectedForDeletion
? alertRed.withValues(alpha: 0.25)
    : itemAccent.withValues(alpha: 0.22),
_theme.containerLowestColor,
],
),
),
child: Center(
child: crate.isFavorites
? Image.asset(
'assets/icons/heart_icon.png',
width: 68,
height: 68,
fit: BoxFit.contain,
errorBuilder: (BuildContext context,
Object error,
StackTrace? stackTrace) {
return Icon(
Icons.favorite_rounded,
color: isSelectedForDeletion
? alertRed
    : itemAccent,
size: 50,
);
},
)
    : Image.asset(
'assets/icons/mixes_icon.png',
width: 68,
height: 68,
fit: BoxFit.contain,
errorBuilder: (BuildContext context,
Object error,
StackTrace? stackTrace) {
return Icon(
Icons.queue_music_rounded,
color: isSelectedForDeletion
? alertRed
    : itemAccent,
size: 50,
);
},
),
),
),
),
Positioned(
top: 6,
left: 6,
child: GestureDetector(
onTap: () => _toggleCratePlayback(crate),
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 5, vertical: 1.5),
decoration: BoxDecoration(
color: Colors.black.withValues(alpha: 0.75),
borderRadius: BorderRadius.circular(4),
border: Border.all(
color: isThisCratePlaying
? itemAccent
    : itemAccent.withValues(alpha: 0.35),
width: 0.8,
),
),
child: Text(
isThisCratePlaying
? 'PAUSE PLAYLIST'
    : (crate.isFavorites
? 'FAVORITES'
    : 'PLAYLIST'),
style: TextStyle(
color: itemAccent,
fontSize: 7.5,
fontWeight: FontWeight.w900),
),
),
),
),
if (_isDeleteVaultMode)
Positioned(
top: 6,
right: 6,
child: Container(
width: 24,
height: 24,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: isSelectedForDeletion
? alertRed
    : Colors.black54,
border: Border.all(
color: isSelectedForDeletion
? Colors.white
    : Colors.white38,
width: 1.2,
),
),
child: Icon(
isSelectedForDeletion
? Icons.check_rounded
    : (isDeletable
? Icons.circle_outlined
    : Icons.lock_outline_rounded),
color: isSelectedForDeletion
? Colors.black
    : Colors.white54,
size: 14,
),
),
)
else
Positioned(
bottom: 6,
right: 6,
child: GestureDetector(
onTap: () => _toggleCratePlayback(crate),
child: Container(
width: 32,
height: 32,
decoration: BoxDecoration(
color: itemAccent,
shape: BoxShape.circle,
boxShadow: isThisCratePlaying
? LotusDecorations.glowShadow(itemAccent,
intensity: 0.35, blur: 10)
    : null,
),
child: Icon(
isThisCratePlaying
? Icons.pause_rounded
    : Icons.play_arrow_rounded,
color: Colors.black,
size: 18,
),
),
),
),
],
),
),
const SizedBox(height: 8),
Text(
crate.title,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isSelectedForDeletion
? alertRed
    : (isCrateActive ? accent : _theme.textPrimaryColor),
fontSize: 12.5,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 2),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Text('${crate.trackCount} tracks',
style: TextStyle(
color: _theme.textSecondaryColor, fontSize: 9.5)),
Text('${crate.totalSizeMb.toStringAsFixed(0)} MB',
style: TextStyle(
color: _theme.textTertiaryColor, fontSize: 9)),
],
),
],
),
),
),
),
),
);
}

Widget _buildCreativePlayAllButton({
required VoidCallback onTap,
required Color accent,
required Color secondaryAccent,
required bool isWhitaniana,
bool isPlaying = false,
}) {
return Material(
color: Colors.transparent,
child: InkWell(
onTap: () {
HapticFeedback.mediumImpact();
onTap();
},
borderRadius: BorderRadius.circular(16),
child: Container(
height: 42,
padding: const EdgeInsets.symmetric(horizontal: 10),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: isWhitaniana
? <Color>[accent, accent.withValues(alpha: 0.88)]
    : <Color>[
accent,
Color.lerp(accent, secondaryAccent, 0.35) ?? accent,
],
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : <BoxShadow>[
BoxShadow(
color: accent.withValues(alpha: 0.4),
blurRadius: 14,
offset: const Offset(0, 3),
spreadRadius: -1,
),
],
border: Border.all(
color: Colors.white.withValues(alpha: isWhitaniana ? 0.35 : 0.45),
width: 1.0,
),
),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Container(
width: 22,
height: 22,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: (isWhitaniana ? Colors.white : Colors.black)
    .withValues(alpha: 0.22),
),
child: Center(
child: Icon(
isPlaying
? Icons.pause_rounded
    : Icons.play_arrow_rounded,
color: isWhitaniana ? Colors.white : Colors.black,
size: 16,
),
),
),
const SizedBox(width: 6),
Flexible(
child: Text(
isPlaying ? 'PAUSE PLAYLIST' : 'PLAY ALL',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isWhitaniana ? Colors.white : Colors.black,
fontSize: 10.5,
fontWeight: FontWeight.w900,
letterSpacing: 0.6,
),
),
),
],
),
),
),
);
}

Widget _buildCreativeActionButton({
required VoidCallback onTap,
required IconData icon,
required String label,
required Color accent,
required Color secondaryAccent,
required Color containerLow,
required bool isWhitaniana,
}) {
return Material(
color: Colors.transparent,
child: InkWell(
onTap: () {
HapticFeedback.lightImpact();
onTap();
},
borderRadius: BorderRadius.circular(16),
child: Container(
height: 42,
padding: const EdgeInsets.symmetric(horizontal: 8),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
color: isWhitaniana ? _theme.containerColor : containerLow,
gradient: isWhitaniana
? null
    : LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: <Color>[
containerLow,
containerLow.withValues(alpha: 0.75),
],
),
border: Border.all(
color: accent.withValues(alpha: 0.45),
width: 1.0,
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : <BoxShadow>[
BoxShadow(
color: accent.withValues(alpha: 0.12),
blurRadius: 8,
offset: const Offset(0, 2),
),
],
),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(
icon,
color: accent,
size: 15,
),
const SizedBox(width: 4),
Flexible(
child: Text(
label,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isWhitaniana
? _theme.textPrimaryColor
    : Colors.white.withValues(alpha: 0.92),
fontSize: 10.0,
fontWeight: FontWeight.w800,
letterSpacing: 0.5,
),
),
),
],
),
),
),
);
}

Widget _buildCreativeLocateButton({
required VoidCallback onTap,
required Color accent,
required Color secondaryAccent,
required Color containerLow,
required bool isWhitaniana,
}) {
return Material(
color: Colors.transparent,
child: InkWell(
onTap: () {
HapticFeedback.lightImpact();
onTap();
},
borderRadius: BorderRadius.circular(16),
child: Container(
height: 42,
padding: const EdgeInsets.symmetric(horizontal: 9),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
color: accent.withValues(alpha: isWhitaniana ? 0.15 : 0.18),
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: <Color>[
accent.withValues(alpha: 0.25),
secondaryAccent.withValues(alpha: 0.15),
],
),
border: Border.all(
color: accent,
width: 1.2,
),
boxShadow: LotusDecorations.glowShadow(accent,
intensity: 0.28, blur: 12),
),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(Icons.my_location_rounded, color: accent, size: 14),
const SizedBox(width: 4),
Text(
'LOCATE',
style: TextStyle(
color: accent,
fontSize: 9.0,
fontWeight: FontWeight.w900,
letterSpacing: 0.7,
),
),
],
),
),
),
);
}

Widget _buildCrateDetailView(RealDeviceCrate crate, Color accent,
Color secondaryAccent, Color containerLow) {
final SongModel? playing = _playback.activeSong;
final bool containsActive =
playing != null && crate.songs.any(_isSongActiveMatch);
final bool isThisCratePlaying = containsActive && _playback.isPlaying;
final bool isWhitaniana = _theme.isWhitanianaActive;

return Column(
children: <Widget>[
Padding(
padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
child: Row(
children: <Widget>[
Expanded(
flex: !crate.isDynamicAutoCrate ? 4 : 5,
child: _buildCreativePlayAllButton(
onTap: () => _toggleCratePlayback(crate),
accent: accent,
secondaryAccent: secondaryAccent,
isWhitaniana: isWhitaniana,
isPlaying: isThisCratePlaying,
),
),
const SizedBox(width: 6),
if (!crate.isDynamicAutoCrate) ...<Widget>[
Expanded(
flex: 3,
child: _buildCreativeActionButton(
onTap: () => _showAddSongsToCrateSheet(crate),
icon: Icons.add_rounded,
label: 'ADD',
accent: accent,
secondaryAccent: secondaryAccent,
containerLow: containerLow,
isWhitaniana: isWhitaniana,
),
),
const SizedBox(width: 6),
],
Expanded(
flex: 3,
child: _buildCreativeActionButton(
onTap: () => _playCrate(crate, shuffle: true),
icon: Icons.shuffle_rounded,
label: 'SHUFFLE',
accent: accent,
secondaryAccent: secondaryAccent,
containerLow: containerLow,
isWhitaniana: isWhitaniana,
),
),
if (containsActive) ...<Widget>[
const SizedBox(width: 6),
_buildCreativeLocateButton(
onTap: _scrollToActiveSongInCrate,
accent: accent,
secondaryAccent: secondaryAccent,
containerLow: containerLow,
isWhitaniana: isWhitaniana,
),
],
],
),
),
if (_isReorderMode && !crate.isDynamicAutoCrate)
Container(
margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.16),
borderRadius: BorderRadius.circular(12),
border: Border.all(color: accent.withValues(alpha: 0.6)),
),
child: Row(
children: <Widget>[
Icon(Icons.touch_app_rounded, color: accent, size: 16),
const SizedBox(width: 8),
Expanded(
child: Text(
'Drag by handle (⋮⋮) to reorder tracks in this crate.',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 11,
fontWeight: FontWeight.w600,
),
),
),
],
),
),
Expanded(
child: crate.songs.isEmpty
? Center(
child: Padding(
padding: const EdgeInsets.all(40.0),
child: Text(
crate.isFavorites
? 'No favorites yet.\nTap ❤️ on any song to add it here.'
    : (crate.isDynamicAutoCrate
? 'No matching audio stems detected for this dynamic crate.'
    : 'This playlist has no songs yet.\nTap "ADD" above to add songs.'),
style: TextStyle(color: _theme.textSecondaryColor),
textAlign: TextAlign.center,
),
),
)
    : (crate.isDynamicAutoCrate || crate.isFavorites
? ListView.builder(
controller: _crateDetailScrollController,
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
itemCount: crate.songs.length,
itemBuilder: (BuildContext context, int index) {
final SongModel song = crate.songs[index];
final bool isSelected = _isSongActiveMatch(song);
return _buildCrateTrackRow(
key: ValueKey<int>(song.id),
song: song,
isSelected: isSelected,
index: index,
crate: crate,
accent: accent,
secondaryAccent: secondaryAccent,
containerLow: containerLow,
);
},
)
    : Theme(
data: Theme.of(context).copyWith(
canvasColor: Colors.transparent,
shadowColor: Colors.transparent,
),
child: ReorderableListView.builder(
scrollController: _crateDetailScrollController,
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
itemCount: crate.songs.length,
onReorderItem: (int oldIndex, int newIndex) =>
_onReorderSongsInCrate(oldIndex, newIndex),
proxyDecorator: (Widget child, int index,
Animation<double> animation) {
return Material(
color: Colors.transparent,
elevation: 6,
shadowColor: Colors.black.withValues(alpha: 0.5),
child: Container(
decoration: BoxDecoration(
color: _theme.containerHighColor,
borderRadius: BorderRadius.circular(14),
border: Border.all(color: accent, width: 1.6),
boxShadow: LotusDecorations.glowShadow(accent,
intensity: 0.28, blur: 16),
),
child: child,
),
);
},
itemBuilder: (BuildContext context, int index) {
final SongModel song = crate.songs[index];
final bool isSelected = _isSongActiveMatch(song);
return _buildCrateTrackRow(
key: ValueKey<int>(song.id),
song: song,
isSelected: isSelected,
index: index,
crate: crate,
accent: accent,
secondaryAccent: secondaryAccent,
containerLow: containerLow,
);
},
),
)),
),
],
);
}

Widget _buildCrateTrackRow({
required Key key,
required SongModel song,
required bool isSelected,
required int index,
required RealDeviceCrate crate,
required Color accent,
required Color secondaryAccent,
required Color containerLow,
}) {
final bool isFav = _playback.isSongFavorite(song.id);
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
key: key,
height: 54.0,
margin: const EdgeInsets.symmetric(vertical: 4.0),
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
onTap: () {
HapticFeedback.lightImpact();
_setPlayingSourceCrate(crate.id);
_playback.playSong(
song,
queue: crate.songs,
);
widget.onSongSelected?.call(song);
},
onLongPress: () {
HapticFeedback.mediumImpact();
LotusTrackOptionsSheet.show(
context,
song: song,
onOpenPlaylistDialog: () async {
await LotusAddToPlaylistDialog.show(context, song: song);
await _loadPrivateCratesAndAudio();
},
onTrackDeleted: _handleTrackDeleted,
onTagsUpdated: _handleTagsUpdated,
);
},
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 10.0),
child: Row(
children: <Widget>[
Container(
width: 24,
alignment: Alignment.centerLeft,
child: Text(
'${index + 1}',
style: TextStyle(
color: isSelected ? accent : _theme.textTertiaryColor,
fontSize: 11,
fontWeight: FontWeight.bold,
fontFamily: 'monospace',
),
),
),
Stack(
alignment: Alignment.center,
children: <Widget>[
ClipRRect(
borderRadius: BorderRadius.circular(10),
child: SizedBox(
width: 44,
height: 44,
child: LotusArtworkImage(
songId: song.id,
size: 44,
borderRadius: 10,
keepOldArtwork: true,
nullArtworkWidget: Container(
width: 44,
height: 44,
color: _theme.containerColor,
child: Icon(
Icons.music_note_rounded,
color: isSelected
? accent
    : _theme.textTertiaryColor,
),
),
),
),
),
if (isSelected && _playback.isPlaying)
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
const SizedBox(height: 3),
Row(
children: <Widget>[
Container(
padding: const EdgeInsets.symmetric(
horizontal: 4, vertical: 1),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.15),
borderRadius: BorderRadius.circular(3),
),
child: Text(
song.fileExtension.isNotEmpty
? song.fileExtension.toUpperCase()
    : 'FLAC',
style: TextStyle(
color: accent,
fontSize: 8,
fontWeight: FontWeight.bold,
),
),
),
if (crate.autoCrateType == 'RECENT') ...<Widget>[
const SizedBox(width: 4),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 4, vertical: 1),
decoration: BoxDecoration(
color: LotusColors.solarGold
    .withValues(alpha: 0.18),
borderRadius: BorderRadius.circular(3),
),
child: Text(
_formatRecencyTime(song.dateAdded ?? 0),
style: const TextStyle(
color: LotusColors.solarGold,
fontSize: 7.5,
fontWeight: FontWeight.w900,
),
),
),
],
const SizedBox(width: 6),
Expanded(
child: Text(
song.artist ?? '<Unknown Artist>',
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
onLongPress: () async {
HapticFeedback.heavyImpact();
await LotusAddToPlaylistDialog.show(context, song: song);
await _loadPrivateCratesAndAudio();
},
child: Padding(
padding: const EdgeInsets.symmetric(
horizontal: 6.0, vertical: 8.0),
child: Icon(
isFav
? Icons.favorite_rounded
    : Icons.favorite_border_rounded,
color: isFav ? secondaryAccent : _theme.textSecondaryColor,
size: 20,
),
),
),
if (!crate.isDynamicAutoCrate) ...<Widget>[
const SizedBox(width: 2),
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () => _removeSongFromCrate(crate, song),
child: Container(
padding: const EdgeInsets.all(6),
child: Icon(
Icons.delete_outline_rounded,
color: secondaryAccent,
size: 18,
),
),
),
],
if (_isReorderMode && !crate.isDynamicAutoCrate)
ReorderableDragStartListener(
index: index,
child: Container(
padding: const EdgeInsets.all(8),
child: Icon(
Icons.drag_indicator_rounded,
color: accent,
size: 20,
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

Widget _buildFlowListSliver(
Color accent, Color secondaryAccent, Color containerLow) {
final List<SongModel> songs = _deviceSongs;
final bool isWhitaniana = _theme.isWhitanianaActive;

return SliverPadding(
padding: const EdgeInsets.symmetric(horizontal: 16.0),
sliver: SliverFixedExtentList(
itemExtent: 74.0,
delegate: SliverChildBuilderDelegate(
(BuildContext context, int index) {
final SongModel song = songs[index];
final bool isCurrent = _isSongActiveMatch(song);
final Color itemAccent = isCurrent
? accent
    : (index % 2 == 0 ? accent : secondaryAccent);

return RepaintBoundary(
child: Container(
margin: const EdgeInsets.symmetric(vertical: 3.0),
decoration: BoxDecoration(
color: isCurrent
? (isWhitaniana
? _theme.containerColor
    : _theme.containerHighColor)
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
intensity: 0.18, blur: 12)
    : (isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : null),
),
child: ListTile(
leading: Stack(
alignment: Alignment.center,
children: <Widget>[
ClipRRect(
borderRadius: BorderRadius.circular(10),
child: Container(
width: 44,
height: 44,
color: itemAccent.withValues(alpha: 0.15),
child: LotusArtworkImage(
songId: song.id,
size: 44,
borderRadius: 10,
keepOldArtwork: true,
nullArtworkWidget: Container(
width: 44,
height: 44,
color: itemAccent.withValues(alpha: 0.15),
child: Icon(Icons.music_note_rounded,
color: itemAccent, size: 22),
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
title: Row(
children: <Widget>[
Expanded(
child: Text(
song.title,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isCurrent ? accent : _theme.textPrimaryColor,
fontSize: 13,
fontWeight: FontWeight.bold,
),
),
),
if (isCurrent) ...<Widget>[
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
subtitle: Text(
'${song.artist ?? "<Unknown>"} • ${song.fileExtension.toUpperCase()}',
style: TextStyle(
color: _theme.textSecondaryColor, fontSize: 10),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
trailing: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
IconButton(
icon: Icon(
isCurrent && _playback.isPlaying
? Icons.pause_circle_filled_rounded
    : Icons.play_circle_fill_rounded,
size: 28,
color: itemAccent,
),
onPressed: () {
if (isCurrent) {
_playback.togglePlayPause();
} else {
_playback.playSong(song, queue: songs);
widget.onSongSelected?.call(song);
}
},
),
],
),
),
),
);
},
childCount: songs.length,
),
),
);
}

Widget _buildSmartMixesSliver(Color accent, Color containerLow) {
final bool isWhitaniana = _theme.isWhitanianaActive;

return SliverToBoxAdapter(
child: Container(
margin: const EdgeInsets.symmetric(horizontal: 16.0),
padding: const EdgeInsets.all(16.0),
decoration: BoxDecoration(
color: containerLow,
borderRadius: BorderRadius.circular(18),
border: Border.all(color: accent.withValues(alpha: 0.4)),
boxShadow:
isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
children: <Widget>[
Icon(Icons.psychology_rounded, color: accent, size: 20),
const SizedBox(width: 8),
Text(
'Dynamic Rule-Based Smart Crates',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 14,
fontWeight: FontWeight.bold,
),
),
],
),
const SizedBox(height: 8),
Text(
'Smart Mixes auto-compile your high-resolution local library based on criteria such as sample rate, format (FLAC vs DSD), and playback history.',
style: TextStyle(color: _theme.textSecondaryColor, fontSize: 11),
),
const SizedBox(height: 12),
ElevatedButton.icon(
style: ElevatedButton.styleFrom(
backgroundColor: accent, foregroundColor: Colors.white),
onPressed: () {},
icon: const Icon(Icons.add_rounded),
label: const Text('CREATE SMART RULE'),
),
],
),
),
);
}

Widget _buildDeleteVaultAndHiddenProcessDock(
Color accent, Color secondaryAccent) {
final Color solidCardContainer = _theme.modalContainerLowColor;
final Color solidButtonBg = _theme.modalContainerColor;
const Color alertRed = Color(0xFFFF5252);
final bool isWhitaniana = _theme.isWhitanianaActive;

final String deleteVaultLabel;
final String deleteVaultSub;
final IconData deleteVaultIcon;
final Color deleteVaultColor;
final bool isHighlighted;

if (!_isDeleteVaultMode) {
deleteVaultLabel = 'Delete Vault';
deleteVaultSub = 'Select Playlists';
deleteVaultIcon = Icons.delete_outline_rounded;
deleteVaultColor = accent;
isHighlighted = false;
} else if (_selectedCrateIdsToDelete.isEmpty) {
deleteVaultLabel = 'Abort';
deleteVaultSub = 'Cancel Operation';
deleteVaultIcon = Icons.close_rounded;
deleteVaultColor = secondaryAccent;
isHighlighted = true;
} else {
deleteVaultLabel = 'Delete (${_selectedCrateIdsToDelete.length})';
deleteVaultSub = 'Tap to Confirm';
deleteVaultIcon = Icons.delete_forever_rounded;
deleteVaultColor = alertRed;
isHighlighted = true;
}

return Container(
margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: solidCardContainer,
borderRadius: BorderRadius.circular(20),
border: Border.all(
color: (isHighlighted ? deleteVaultColor : accent)
    .withValues(alpha: 0.4),
width: 1.0,
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : LotusDecorations.glowShadow(
isHighlighted ? deleteVaultColor : accent,
intensity: 0.16,
blur: 16,
),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Flexible(
child: Text(
'DELETE VAULT & HIDDEN SONGS PROCESS',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 9.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.8,
),
),
),
const SizedBox(width: 6),
Container(
padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.18),
borderRadius: BorderRadius.circular(6),
),
child: Text(
'${_playback.hiddenSongIds.length} HIDDEN',
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.w900,
),
),
),
],
),
const SizedBox(height: 12),
Row(
children: <Widget>[
Expanded(
child: _buildProcessActionButton(
icon: deleteVaultIcon,
label: deleteVaultLabel,
sub: deleteVaultSub,
accentColor: deleteVaultColor,
solidBg: solidButtonBg,
isHighlighted: isHighlighted,
onTap: _handleDeleteVaultButtonTap,
),
),
const SizedBox(width: 12),
Expanded(
child: _buildProcessActionButton(
icon: Icons.visibility_off_rounded,
label: 'Hidden Songs',
sub: 'Manage Vault',
accentColor: accent,
solidBg: solidButtonBg,
isHighlighted: _playback.hiddenSongIds.isNotEmpty,
onTap: _openHiddenSongsManagementModal,
),
),
],
),
],
),
);
}

Widget _buildProcessActionButton({
required IconData icon,
required String label,
required String sub,
required Color accentColor,
required Color solidBg,
required VoidCallback onTap,
bool isHighlighted = false,
}) {
return GestureDetector(
onTap: onTap,
child: AnimatedContainer(
duration: const Duration(milliseconds: 180),
padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
decoration: BoxDecoration(
color: isHighlighted ? accentColor.withValues(alpha: 0.20) : solidBg,
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: isHighlighted
? accentColor.withValues(alpha: 0.85)
    : _theme.cardBorderColor,
width: isHighlighted ? 1.4 : 0.9,
),
boxShadow: isHighlighted
? LotusDecorations.glowShadow(accentColor,
intensity: 0.24, blur: 12)
    : null,
),
child: Column(
children: <Widget>[
Icon(icon,
color: isHighlighted ? accentColor : _theme.textPrimaryColor,
size: 20),
const SizedBox(height: 5),
Text(
label,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isHighlighted ? accentColor : _theme.textPrimaryColor,
fontSize: 11,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 2),
Text(
sub,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isHighlighted
? accentColor.withValues(alpha: 0.85)
    : _theme.textTertiaryColor,
fontSize: 8.5,
),
),
],
),
),
);
}
}

// ==============================================================================
// LOTUS TACTILE KINETIC ARCH & SNAPBACK TARGET HUD
// ==============================================================================

class _SnapbackTargetData {
final String header;
final String title;
final String subtitle;
final String badgeText;
final int? songId;
final bool isSourceOrReturn;

const _SnapbackTargetData({
required this.header,
required this.title,
required this.subtitle,
required this.badgeText,
this.songId,
required this.isSourceOrReturn,
});
}

class _LotusKineticParabolicArchPainter extends CustomPainter {
final double extent;
final double touchY;
final bool isTriggered;
final bool isLeft;
final String label;
final Color primaryColor;
final Color secondaryColor;
final Color surfaceColor;

_LotusKineticParabolicArchPainter({
required this.extent,
required this.touchY,
required this.isTriggered,
required this.isLeft,
required this.label,
required this.primaryColor,
required this.secondaryColor,
required this.surfaceColor,
});

@override
void paint(Canvas canvas, Size size) {
if (extent <= 0.0) return;

final double w = size.width;
final double h = size.height;
final double y = touchY.clamp(140.0, h - 200.0);
const double archHalfHeight = 135.0;
final double topY = y - archHalfHeight;
final double botY = y + archHalfHeight;
final double pullX = isLeft ? extent : (w - extent);

final Path archPath = Path();
if (isLeft) {
archPath.moveTo(0, topY);
archPath.cubicTo(
extent * 0.15, y - 85.0, extent * 0.75, y - 35.0, pullX, y);
archPath.cubicTo(
extent * 0.75, y + 35.0, extent * 0.15, y + 85.0, 0, botY);
archPath.close();
} else {
archPath.moveTo(w, topY);
archPath.cubicTo(w - (extent * 0.15), y - 85.0, w - (extent * 0.75),
y - 35.0, pullX, y);
archPath.cubicTo(w - (extent * 0.75), y + 35.0, w - (extent * 0.15),
y + 85.0, w, botY);
archPath.close();
}

final Paint glowPaint = Paint()
..color = (isTriggered ? secondaryColor : primaryColor)
    .withValues(alpha: isTriggered ? 0.35 : 0.18)
..maskFilter =
MaskFilter.blur(BlurStyle.normal, isTriggered ? 18.0 : 10.0)
..style = PaintingStyle.fill;
canvas.drawPath(archPath, glowPaint);

final Paint fillPaint = Paint()
..shader = LinearGradient(
begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
colors: <Color>[
primaryColor.withValues(alpha: isTriggered ? 0.28 : 0.14),
const Color(0xEE080B11),
],
).createShader(Rect.fromLTWH(0, topY, w, archHalfHeight * 2.0))
..style = PaintingStyle.fill;
canvas.drawPath(archPath, fillPaint);

final Paint borderPaint = Paint()
..shader = LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: <Color>[
primaryColor.withValues(alpha: 0.8),
secondaryColor,
primaryColor.withValues(alpha: 0.8),
],
).createShader(Rect.fromLTWH(0, topY, w, archHalfHeight * 2.0))
..strokeWidth = isTriggered ? 2.2 : 1.5
..style = PaintingStyle.stroke;
canvas.drawPath(archPath, borderPaint);

final String spacedText = label.split('').join(' · ');
final TextPainter tp = TextPainter(
text: TextSpan(
text: spacedText,
style: TextStyle(
color: (isTriggered ? secondaryColor : primaryColor)
    .withValues(alpha: 0.9),
fontSize: 9.0,
fontWeight: FontWeight.w900,
letterSpacing: 1.8,
),
),
textDirection: TextDirection.ltr,
)..layout();

canvas.save();
if (isLeft) {
canvas.translate(8.0, y + (tp.width / 2.0));
canvas.rotate(-1.57079632679);
} else {
canvas.translate(w - 18.0, y - (tp.width / 2.0));
canvas.rotate(1.57079632679);
}
tp.paint(canvas, Offset.zero);
canvas.restore();

final Paint ringPaint = Paint()
..color = (isTriggered ? secondaryColor : primaryColor)
    .withValues(alpha: isTriggered ? 0.9 : 0.6)
..strokeWidth = 1.6
..style = PaintingStyle.stroke;
canvas.drawCircle(Offset(pullX, y), isTriggered ? 18.0 : 14.0, ringPaint);

final Paint innerRingPaint = Paint()
..color = Colors.white.withValues(alpha: 0.75)
..strokeWidth = 1.0
..style = PaintingStyle.stroke;
canvas.drawCircle(
Offset(pullX, y), isTriggered ? 10.0 : 8.0, innerRingPaint);

final Paint centerDotPaint = Paint()
..color = isTriggered
? Colors.white
    : (isTriggered ? secondaryColor : primaryColor)
..style = PaintingStyle.fill;
canvas.drawCircle(Offset(pullX, y), 4.5, centerDotPaint);
}

@override
bool shouldRepaint(covariant _LotusKineticParabolicArchPainter oldDelegate) {
return oldDelegate.extent != extent ||
oldDelegate.touchY != touchY ||
oldDelegate.isTriggered != isTriggered ||
oldDelegate.label != label ||
oldDelegate.primaryColor != primaryColor ||
oldDelegate.secondaryColor != secondaryColor;
}
}

class _LotusKineticSnapbackCard extends StatelessWidget {
final bool isLeft;
final double extent;
final bool isTriggered;
final _SnapbackTargetData target;
final Color primaryColor;
final Color secondaryColor;
final Color containerColor;

const _LotusKineticSnapbackCard({
required this.isLeft,
required this.extent,
required this.isTriggered,
required this.target,
required this.primaryColor,
required this.secondaryColor,
required this.containerColor,
});

@override
Widget build(BuildContext context) {
if (extent <= 6.0) return const SizedBox.shrink();

final Color accent =
target.isSourceOrReturn ? secondaryColor : primaryColor;
final int pullPercent = ((extent / 48.0) * 100.0).clamp(0.0, 100.0).toInt();

return IgnorePointer(
child: Container(
width: 218.0,
decoration: BoxDecoration(
color: const Color(0xF212151F),
borderRadius: BorderRadius.circular(16.0),
border: Border.all(
color: isTriggered ? accent : accent.withValues(alpha: 0.4),
width: isTriggered ? 1.6 : 1.0,
),
boxShadow: <BoxShadow>[
BoxShadow(
color: accent.withValues(alpha: isTriggered ? 0.35 : 0.15),
blurRadius: isTriggered ? 20.0 : 10.0,
spreadRadius: isTriggered ? 2.0 : 0.0,
),
],
),
padding: const EdgeInsets.all(9.5),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
children: <Widget>[
Flexible(
child: Text(
target.header,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.w900,
letterSpacing: 1.0,
),
),
),
const SizedBox(width: 4),
Icon(
Icons.keyboard_double_arrow_right_rounded,
color: accent,
size: 14.0,
),
],
),
const SizedBox(height: 7.0),
Row(
children: <Widget>[
ClipRRect(
borderRadius: BorderRadius.circular(8.0),
child: Container(
width: 38.0,
height: 38.0,
color: Colors.white10,
child: target.songId != null
? LotusArtworkImage(
songId: target.songId!,
size: 38.0,
borderRadius: 8.0,
keepOldArtwork: true,
nullArtworkWidget: Center(
child: Icon(Icons.music_note_rounded,
color: accent, size: 20.0),
),
)
    : Center(
child: Icon(
target.isSourceOrReturn
? Icons.album_rounded
    : Icons.queue_music_rounded,
color: accent,
size: 22.0,
),
),
),
),
const SizedBox(width: 8.0),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Text(
target.title,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: Colors.white,
fontSize: 12.5,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 1.5),
Text(
target.subtitle,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: LotusColors.textSecondary,
fontSize: 10.0,
),
),
],
),
),
],
),
const SizedBox(height: 7.0),
Row(
children: <Widget>[
Flexible(
fit: FlexFit.loose,
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 5.5, vertical: 2.0),
decoration: BoxDecoration(
color: Colors.white.withValues(alpha: 0.08),
borderRadius: BorderRadius.circular(4.0),
),
child: Text(
target.badgeText,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: Colors.white70,
fontSize: 8.5,
fontWeight: FontWeight.bold,
),
),
),
),
const Spacer(),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 6.0, vertical: 2.0),
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.16),
borderRadius: BorderRadius.circular(4.0),
border: Border.all(
color: accent.withValues(alpha: 0.4), width: 0.8),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Text(
'PULL: $pullPercent%',
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.w900,
),
),
const SizedBox(width: 3.0),
Icon(Icons.graphic_eq_rounded,
color: accent, size: 10.0),
],
),
),
],
),
const SizedBox(height: 7.0),
AnimatedContainer(
duration: const Duration(milliseconds: 140),
width: double.infinity,
padding: const EdgeInsets.symmetric(vertical: 4.5),
decoration: BoxDecoration(
color: isTriggered
? accent
    : Colors.white.withValues(alpha: 0.06),
borderRadius: BorderRadius.circular(6.0),
boxShadow: isTriggered
? <BoxShadow>[
BoxShadow(
color: accent.withValues(alpha: 0.5),
blurRadius: 8.0,
spreadRadius: 1.0,
),
]
    : null,
),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: <Widget>[
Flexible(
fit: FlexFit.loose,
child: Text(
isTriggered
? 'READY TO EXECUTE'
    : 'PULL TO LATCH ($pullPercent%)',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isTriggered ? Colors.black : Colors.white54,
fontSize: 9.0,
fontWeight: FontWeight.w900,
letterSpacing: 0.8,
),
),
),
const SizedBox(width: 4.0),
Icon(
Icons.arrow_forward_rounded,
color: isTriggered ? Colors.black : Colors.white54,
size: 11.0,
),
],
),
),
],
),
),
);
}
}

class _LotusKineticTelemetryBanner extends StatelessWidget {
final bool isLeft;
final double extent;
final bool isTriggered;
final String label;
final String targetTitle;
final Color primaryColor;
final Color secondaryColor;

const _LotusKineticTelemetryBanner({
required this.isLeft,
required this.extent,
required this.isTriggered,
required this.label,
required this.targetTitle,
required this.primaryColor,
required this.secondaryColor,
});

@override
Widget build(BuildContext context) {
final Color accent = (label == 'SOURCE' || label == 'RETURN')
? secondaryColor
    : primaryColor;
final int pullPercent =
((extent / 48.0) * 100.0).clamp(0.0, 100.0).toInt();
final int dxVal = (isLeft ? extent : -extent).toInt();

return Container(
margin: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
decoration: BoxDecoration(
color: const Color(0xF210131B),
borderRadius: BorderRadius.circular(12.0),
border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.0),
boxShadow: <BoxShadow>[
BoxShadow(
color: accent.withValues(alpha: 0.18),
blurRadius: 12.0,
),
],
),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
children: <Widget>[
Container(
width: 7.0,
height: 7.0,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: accent,
boxShadow: <BoxShadow>[
BoxShadow(
color: accent, blurRadius: 6.0, spreadRadius: 1.0),
],
),
),
const SizedBox(width: 7.0),
Expanded(
child: Text(
'${isLeft ? "LEFT" : "RIGHT"} EDGE KINETIC ARCH [$label LATCH]',
style: TextStyle(
color: accent,
fontSize: 9.0,
fontWeight: FontWeight.w900,
letterSpacing: 0.8,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
Container(
padding:
const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
decoration: BoxDecoration(
color: accent.withValues(alpha: isTriggered ? 0.3 : 0.12),
borderRadius: BorderRadius.circular(4.0),
border: Border.all(color: accent, width: 0.8),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(
isTriggered
? Icons.lock_rounded
    : Icons.lock_open_rounded,
color: accent,
size: 9.5,
),
const SizedBox(width: 3.5),
Text(
isTriggered ? 'LOCKED' : 'ARMED',
style: TextStyle(
color: accent,
fontSize: 8.0,
fontWeight: FontWeight.w900,
),
),
],
),
),
],
),
const SizedBox(height: 5.0),
Row(
children: <Widget>[
Text(
'DX: ${dxVal}PX',
style: const TextStyle(
color: Colors.white70,
fontSize: 9.5,
fontWeight: FontWeight.bold,
),
),
const SizedBox(width: 10.0),
Text(
'$pullPercent% DEFLECTION',
style: const TextStyle(
color: Colors.white70,
fontSize: 9.5,
fontWeight: FontWeight.bold,
),
),
const SizedBox(width: 10.0),
Flexible(
child: Text(
isTriggered ? 'LATCH ENGAGED' : 'DEFLECTING',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isTriggered ? accent : Colors.white38,
fontSize: 9.5,
fontWeight: FontWeight.bold,
),
),
),
],
),
const SizedBox(height: 3.5),
Text(
'Release thumb to snap: $targetTitle',
style: const TextStyle(
color: LotusColors.textSecondary, fontSize: 9.5),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
],
),
);
}
}