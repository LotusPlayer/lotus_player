import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/providers/lotus_playback_provider.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_artwork_image.dart';
import '../../core/widgets/lotus_widgets.dart';
import '../options/lotus_track_options_sheet.dart';
import '../playlists/lotus_add_to_playlist_dialog.dart';

/// Data model representing a physical device directory holding audio files
class AudioFolderInfo {
final String path;
final String folderName;
final List<SongModel> songs;
final String formatBadge;
final double totalSizeMb;
final int dateModified;

const AudioFolderInfo({
required this.path,
required this.folderName,
required this.songs,
this.formatBadge = 'FLAC DIRECT',
this.totalSizeMb = 0.0,
this.dateModified = 0,
});

int get songCount => songs.length;

AudioFolderInfo copyWith({
String? path,
String? folderName,
List<SongModel>? songs,
String? formatBadge,
double? totalSizeMb,
int? dateModified,
}) {
return AudioFolderInfo(
path: path ?? this.path,
folderName: folderName ?? this.folderName,
songs: songs ?? this.songs,
formatBadge: formatBadge ?? this.formatBadge,
totalSizeMb: totalSizeMb ?? this.totalSizeMb,
dateModified: dateModified ?? this.dateModified,
);
}
}

enum VaultSortOption {
name,
date,
count,
size,
}

enum DrilldownSortOption {
title,
artist,
duration,
date,
}

class LotusVaultFoldersScreen extends StatefulWidget {
final ValueChanged<SongModel>? onSongSelected;
final VoidCallback? onOpenNowPlaying;
final VoidCallback? onBack;

const LotusVaultFoldersScreen({
super.key,
this.onSongSelected,
this.onOpenNowPlaying,
this.onBack,
});

@override
State<LotusVaultFoldersScreen> createState() =>
_LotusVaultFoldersScreenState();
}

class _LotusVaultFoldersScreenState extends State<LotusVaultFoldersScreen> {
final OnAudioQuery _audioQuery = OnAudioQuery();
final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;
final LotusThemeController _theme = LotusThemeController.instance;

bool _isLoading = true;
bool _isScanningFolders = false;
List<AudioFolderInfo> _allFolders = <AudioFolderInfo>[];
List<AudioFolderInfo> _folders = <AudioFolderInfo>[];
AudioFolderInfo? _activeFolder;
AudioFolderInfo? _lastInspectedFolder;

StreamSubscription<HiddenSongsChangeEvent>? _hiddenSongsSub;

// Search Controllers
final TextEditingController _rootSearchController = TextEditingController();
final TextEditingController _drilldownSearchController =
TextEditingController();
final FocusNode _drilldownSearchFocusNode = FocusNode();
final ScrollController _rootScrollController = ScrollController();
final ScrollController _drilldownScrollController = ScrollController();
String _activeRootSearchQuery = '';
String _activeDrilldownSearchQuery = '';

// Layout View Modes & Sort Modes
bool _isRootGridView = false;
bool _isDrilldownGridView = false;
VaultSortOption _rootSort = VaultSortOption.count;
DrilldownSortOption _drilldownSort = DrilldownSortOption.title;

int _activeDrilldownFilterChip = 0;

// Smart Gesture Navigation States
String? _forwardFolderPath;
bool _wasOnRootViewBeforeJump = false;

// Edge Swipe Navigation Gesture States
double _leftDragExtent = 0.0;
double _rightDragExtent = 0.0;
double _leftDragY = 320.0;
double _rightDragY = 320.0;
bool _leftTriggered = false;
bool _rightTriggered = false;

@override
void initState() {
super.initState();
_rootSearchController.addListener(_onRootSearchChanged);
_drilldownSearchController.addListener(_onDrilldownSearchChanged);
_playback.addListener(_onPlaybackChanged);
_theme.addListener(_onPlaybackChanged);
_hiddenSongsSub = _playback.hiddenSongsChangeStream.listen((_) {
if (!mounted) return;
setState(() {
_rebuildVisibleFolders();
});
});

_scanDeviceFolders();
}

@override
void dispose() {
_hiddenSongsSub?.cancel();
_rootScrollController.dispose();
_drilldownScrollController.dispose();
_rootSearchController.removeListener(_onRootSearchChanged);
_rootSearchController.dispose();
_drilldownSearchController.removeListener(_onDrilldownSearchChanged);
_drilldownSearchController.dispose();
_drilldownSearchFocusNode.dispose();
_playback.removeListener(_onPlaybackChanged);
_theme.removeListener(_onPlaybackChanged);
super.dispose();
}

void _onPlaybackChanged() {
if (mounted) setState(() {});
}

void _onRootSearchChanged() {
final String q = _rootSearchController.text.trim();
if (_activeRootSearchQuery != q) {
setState(() {
_activeRootSearchQuery = q;
});
}
}

void _onDrilldownSearchChanged() {
final String q = _drilldownSearchController.text.trim();
if (_activeDrilldownSearchQuery != q) {
setState(() {
_activeDrilldownSearchQuery = q;
});
}
}

AudioFolderInfo? _findPlayingSourceFolder() {
final SongModel? current = _playback.activeSong;
if (current == null) return null;

for (final AudioFolderInfo f in _folders) {
if (f.songs.any((SongModel s) => s.id == current.id)) {
return f;
}
}
return null;
}

void _rebuildVisibleFolders() {
final List<AudioFolderInfo> visible = <AudioFolderInfo>[];

for (final AudioFolderInfo f in _allFolders) {
final List<SongModel> visibleSongs = f.songs
    .where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
    .toList();

if (visibleSongs.isEmpty) continue;

double folderBytes = 0;
for (final SongModel s in visibleSongs) {
folderBytes += s.size;
}
final double sizeMb = folderBytes > 0
? (folderBytes / (1024 * 1024))
    : (visibleSongs.length * 32.5);

visible.add(
f.copyWith(
songs: visibleSongs,
totalSizeMb: sizeMb,
),
);
}

_applyRootSort(visible, _rootSort);
_folders = visible;

if (_activeFolder != null) {
_activeFolder = visible.cast<AudioFolderInfo?>().firstWhere(
(AudioFolderInfo? f) => f?.path == _activeFolder!.path,
orElse: () => null,
);
}
}

Future<void> _scanDeviceFolders() async {
if (_isScanningFolders) return;
_isScanningFolders = true;

if (mounted) {
setState(() => _isLoading = true);
}

try {
List<SongModel> allSongs = <SongModel>[];
try {
allSongs = await _audioQuery.querySongs(
sortType: SongSortType.TITLE,
orderType: OrderType.ASC_OR_SMALLER,
uriType: UriType.EXTERNAL,
ignoreCase: true,
);
} catch (_) {
allSongs = _playback.currentQueue;
}

final Map<String, List<SongModel>> folderMap =
<String, List<SongModel>>{};

for (final SongModel song in allSongs) {
if ((song.duration ?? 0) < 10000) continue;

String folderPath = '/storage/emulated/0/Music/Vault';
if (song.data.isNotEmpty) {
final int lastSep = song.data.lastIndexOf(Platform.pathSeparator);
if (lastSep != -1) {
folderPath = song.data.substring(0, lastSep);
}
}
folderMap.putIfAbsent(folderPath, () => <SongModel>[]).add(song);
}

final List<AudioFolderInfo> folderList = <AudioFolderInfo>[];
for (final MapEntry<String, List<SongModel>> entry in folderMap.entries) {
final String name = entry.key.split(Platform.pathSeparator).last;
double folderBytes = 0;
int latestDate = 0;
final Set<String> codecs = <String>{};

for (final SongModel s in entry.value) {
folderBytes += s.size;
final int songDate = s.dateAdded ?? 0;
if (songDate > latestDate) latestDate = songDate;

if (s.fileExtension.isNotEmpty) {
codecs.add(s.fileExtension.toUpperCase());
}
}

final double sizeMb = folderBytes > 0
? (folderBytes / (1024 * 1024))
    : (entry.value.length * 32.5);
final String codecBadge =
codecs.isNotEmpty ? codecs.first : 'FLAC 24/96';

folderList.add(
AudioFolderInfo(
path: entry.key,
folderName: name.isEmpty ? 'Root Music Storage' : name,
songs: entry.value,
formatBadge: codecBadge,
totalSizeMb: sizeMb,
dateModified: latestDate,
),
);
}

if (mounted) {
setState(() {
_allFolders = folderList;
_rebuildVisibleFolders();
});
}
} catch (e) {
debugPrint('Lotus scan device folders notice: $e');
} finally {
_isScanningFolders = false;
if (mounted) setState(() => _isLoading = false);
}
}

void _handleTrackDeleted(SongModel deletedSong) {
HapticFeedback.mediumImpact();

setState(() {
final List<AudioFolderInfo> updatedAll = <AudioFolderInfo>[];
for (final AudioFolderInfo f in _allFolders) {
final List<SongModel> remaining = List<SongModel>.from(f.songs)
..removeWhere((SongModel s) => s.id == deletedSong.id);
if (remaining.isNotEmpty) {
updatedAll.add(f.copyWith(songs: remaining));
}
}
_allFolders = updatedAll;
_rebuildVisibleFolders();
});
}

void _handleTagsUpdated(SongModel updatedSong) {
setState(() {
final List<AudioFolderInfo> updatedAll = <AudioFolderInfo>[];
for (final AudioFolderInfo f in _allFolders) {
final int idx =
f.songs.indexWhere((SongModel s) => s.id == updatedSong.id);
if (idx != -1) {
final List<SongModel> songsCopy = List<SongModel>.from(f.songs);
songsCopy[idx] = updatedSong;
updatedAll.add(f.copyWith(songs: songsCopy));
} else {
updatedAll.add(f);
}
}
_allFolders = updatedAll;
_rebuildVisibleFolders();
});
}

void _openTrackOptions(SongModel song) {
HapticFeedback.lightImpact();
LotusTrackOptionsSheet.show(
context,
song: song,
onOpenPlaylistDialog: () =>
LotusAddToPlaylistDialog.show(context, song: song),
onTrackDeleted: _handleTrackDeleted,
onTagsUpdated: _handleTagsUpdated,
);
}

// ============================================================================
// SMART BIDIRECTIONAL GESTURES ENGINE
// ============================================================================
void _handleSmartBackGesture() {
final AudioFolderInfo? playingFolder = _findPlayingSourceFolder();

if (playingFolder != null && _activeFolder?.path != playingFolder.path) {
_forwardFolderPath = _activeFolder?.path;
_wasOnRootViewBeforeJump = (_activeFolder == null);

_openFolder(playingFolder);
WidgetsBinding.instance.addPostFrameCallback((_) {
_scrollToActiveSongInFolder();
});

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1600),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.folder_special_rounded,
color: _theme.primaryAccent, size: 18),
const SizedBox(width: 8),
Expanded(
child: Text(
'Back to "${playingFolder.folderName}" (Active Playback Source)',
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

if (_activeFolder != null) {
_forwardFolderPath = _activeFolder!.path;
_wasOnRootViewBeforeJump = false;
_closeFolder();
return;
}

if (widget.onBack != null) {
widget.onBack!();
} else {
Navigator.of(context).maybePop();
}
}

void _handleSmartForwardGesture() {
if (_wasOnRootViewBeforeJump && _activeFolder != null) {
_wasOnRootViewBeforeJump = false;
_closeFolder();
return;
}

if (_forwardFolderPath != null) {
final String targetPath = _forwardFolderPath!;
_forwardFolderPath = null;

final AudioFolderInfo? target =
_folders.cast<AudioFolderInfo?>().firstWhere(
(AudioFolderInfo? f) => f?.path == targetPath,
orElse: () => null,
);

if (target != null && _activeFolder?.path != target.path) {
_openFolder(target);
return;
}
}

if (_activeFolder == null && _folders.isNotEmpty) {
final AudioFolderInfo target = _lastInspectedFolder ??
_findPlayingSourceFolder() ??
_folders.first;
_openFolder(target);
return;
}

if (_activeFolder != null && _folders.length > 1) {
final int currentIndex =
_folders.indexWhere((AudioFolderInfo f) => f.path == _activeFolder!.path);
if (currentIndex >= 0) {
final int nextIndex = (currentIndex + 1) % _folders.length;
_openFolder(_folders[nextIndex]);
}
}
}

String _getBackGestureLabel() {
final AudioFolderInfo? source = _findPlayingSourceFolder();
if (source != null && _activeFolder?.path != source.path) {
return 'SOURCE';
}
return 'BACK';
}

String _getForwardGestureLabel() {
if (_wasOnRootViewBeforeJump || _forwardFolderPath != null) {
return 'RETURN';
}
return 'NEXT';
}

_SnapbackTargetData _getSnapbackTargetData(bool isLeft) {
if (isLeft) {
final AudioFolderInfo? source = _findPlayingSourceFolder();
if (source != null && _activeFolder?.path != source.path) {
return _SnapbackTargetData(
header: 'ACTIVE PLAYBACK SOURCE >>',
title: source.folderName,
subtitle: '${source.songCount} Stems // ${source.formatBadge}',
badgeText: source.formatBadge,
songId: source.songs.isNotEmpty ? source.songs.first.id : null,
isSourceOrReturn: true,
);
}
return _SnapbackTargetData(
header: 'NAVIGATE ROOT VAULT >>',
title: 'Music Vault Root',
subtitle: '${_folders.length} Indexed Directories',
badgeText: 'HI-RES VAULT',
songId: null,
isSourceOrReturn: false,
);
} else {
if (_wasOnRootViewBeforeJump || _forwardFolderPath != null) {
final AudioFolderInfo? prev = _lastInspectedFolder;
return _SnapbackTargetData(
header: 'SNAPBACK TARGET >>',
title: prev?.folderName ?? 'Previous Directory',
subtitle: '${prev?.songCount ?? 0} Stems // Cached Stash',
badgeText: prev?.formatBadge ?? 'RETURN',
songId: prev != null && prev.songs.isNotEmpty
? prev.songs.first.id
    : null,
isSourceOrReturn: true,
);
}
AudioFolderInfo? nextFolder;
if (_activeFolder != null && _folders.length > 1) {
final int currentIndex = _folders
    .indexWhere((AudioFolderInfo f) => f.path == _activeFolder!.path);
if (currentIndex >= 0) {
nextFolder = _folders[(currentIndex + 1) % _folders.length];
}
} else if (_folders.isNotEmpty) {
nextFolder = _folders.first;
}
return _SnapbackTargetData(
header: 'ADVANCE DIRECTORY >>',
title: nextFolder?.folderName ?? 'Next Directory',
subtitle:
'${nextFolder?.songCount ?? 0} Stems // ${nextFolder?.formatBadge ?? "FLAC"}',
badgeText: nextFolder?.formatBadge ?? 'NEXT',
songId: nextFolder != null && nextFolder.songs.isNotEmpty
? nextFolder.songs.first.id
    : null,
isSourceOrReturn: false,
);
}
}

void _applyRootSort(List<AudioFolderInfo> list, VaultSortOption sort) {
switch (sort) {
case VaultSortOption.name:
list.sort((AudioFolderInfo a, AudioFolderInfo b) =>
a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase()));
break;
case VaultSortOption.date:
list.sort((AudioFolderInfo a, AudioFolderInfo b) =>
b.dateModified.compareTo(a.dateModified));
break;
case VaultSortOption.count:
list.sort((AudioFolderInfo a, AudioFolderInfo b) =>
b.songCount.compareTo(a.songCount));
break;
case VaultSortOption.size:
list.sort((AudioFolderInfo a, AudioFolderInfo b) =>
b.totalSizeMb.compareTo(a.totalSizeMb));
break;
}
}

void _cycleRootSortMode() {
HapticFeedback.selectionClick();
setState(() {
switch (_rootSort) {
case VaultSortOption.count:
_rootSort = VaultSortOption.name;
break;
case VaultSortOption.name:
_rootSort = VaultSortOption.date;
break;
case VaultSortOption.date:
_rootSort = VaultSortOption.size;
break;
case VaultSortOption.size:
_rootSort = VaultSortOption.count;
break;
}
_applyRootSort(_folders, _rootSort);
});

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1100),
backgroundColor: _theme.containerHighColor,
content: Text(
'Vault Folders Sorted: ${_rootSortLabel(_rootSort)}',
style: TextStyle(
color: _theme.primaryAccent,
fontWeight: FontWeight.bold,
fontSize: 12,
),
),
),
);
}

String _rootSortLabel(VaultSortOption sort) {
switch (sort) {
case VaultSortOption.name:
return 'NAME (A-Z)';
case VaultSortOption.date:
return 'RECENT DATE';
case VaultSortOption.count:
return 'TRACK COUNT';
case VaultSortOption.size:
return 'STORAGE SIZE';
}
}

void _cycleDrilldownSortMode() {
HapticFeedback.selectionClick();
setState(() {
switch (_drilldownSort) {
case DrilldownSortOption.title:
_drilldownSort = DrilldownSortOption.artist;
break;
case DrilldownSortOption.artist:
_drilldownSort = DrilldownSortOption.duration;
break;
case DrilldownSortOption.duration:
_drilldownSort = DrilldownSortOption.date;
break;
case DrilldownSortOption.date:
_drilldownSort = DrilldownSortOption.title;
break;
}
});

ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1100),
backgroundColor: _theme.containerHighColor,
content: Text(
'Folder Stems Sorted: ${_drilldownSortLabel(_drilldownSort)}',
style: TextStyle(
color: _theme.primaryAccent,
fontWeight: FontWeight.bold,
fontSize: 12,
),
),
),
);
}

String _drilldownSortLabel(DrilldownSortOption sort) {
switch (sort) {
case DrilldownSortOption.title:
return 'TITLE (A-Z)';
case DrilldownSortOption.artist:
return 'ARTIST';
case DrilldownSortOption.duration:
return 'DURATION';
case DrilldownSortOption.date:
return 'DATE ADDED';
}
}

Future<void> _toggleFavoriteSong(SongModel song) async {
HapticFeedback.mediumImpact();
final bool isNowFav = !_playback.isSongFavorite(song.id);

await _playback.toggleFavoriteSong(song);

if (mounted) {
final Color secondaryAccent = _theme.secondaryAccent;
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1400),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(
isNowFav
? Icons.favorite_rounded
    : Icons.favorite_border_rounded,
color: secondaryAccent,
size: 20,
),
const SizedBox(width: 10),
Expanded(
child: Text(
isNowFav
? 'Added "${song.title}" to Favorites Vault'
    : 'Removed "${song.title}" from Favorites Vault',
style: TextStyle(
color: isNowFav
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
}

void _openFolder(AudioFolderInfo folder) {
HapticFeedback.selectionClick();
setState(() {
_lastInspectedFolder = folder;
_activeFolder = folder;
_activeDrilldownFilterChip = 0;
_drilldownSearchController.clear();
_activeDrilldownSearchQuery = '';
});
}

void _closeFolder() {
HapticFeedback.selectionClick();
setState(() {
if (_activeFolder != null) {
_lastInspectedFolder = _activeFolder;
}
_activeFolder = null;
_drilldownSearchController.clear();
_activeDrilldownSearchQuery = '';
});
}

void _playSong(SongModel song, {List<SongModel>? queue}) {
HapticFeedback.lightImpact();
_playback.playSong(song, queue: queue);
widget.onSongSelected?.call(song);
}

void _playAllInFolder(bool shuffle) {
final List<SongModel> current = _filteredDrilldownSongs;
if (current.isEmpty) return;
HapticFeedback.mediumImpact();
final List<SongModel> queue = List<SongModel>.from(current);
if (shuffle) queue.shuffle();
final SongModel lead = queue.first;
_playback.playSong(lead, queue: queue);
widget.onSongSelected?.call(lead);
}

void _playAllFolders() {
if (_folders.isEmpty) return;
HapticFeedback.mediumImpact();
final List<SongModel> all =
_folders.expand((AudioFolderInfo f) => f.songs).toList();
if (all.isNotEmpty) {
_playback.playSong(all.first, queue: all);
widget.onSongSelected?.call(all.first);
}
}

void _playFolderDirectly(AudioFolderInfo folder) {
if (folder.songs.isEmpty) return;
HapticFeedback.mediumImpact();
_lastInspectedFolder = folder;
final List<SongModel> queue = List<SongModel>.from(folder.songs);
final SongModel lead = queue.first;
_playback.playSong(lead, queue: queue);
widget.onSongSelected?.call(lead);
}

void _toggleFolderPlayback(AudioFolderInfo folder) {
final bool isFolderActive = _playback.isFolderActive(folder.path);
if (isFolderActive) {
_playback.togglePlayPause();
} else {
_playFolderDirectly(folder);
}
}

void _shuffleAllFolders() {
if (_folders.isEmpty) return;
HapticFeedback.heavyImpact();
final List<SongModel> all =
_folders.expand((AudioFolderInfo f) => f.songs).toList()..shuffle();
if (all.isNotEmpty) {
_playback.playSong(all.first, queue: all);
widget.onSongSelected?.call(all.first);
}
}

void _scrollToActiveSongInFolder() {
HapticFeedback.heavyImpact();
final SongModel? playing = _playback.activeSong;
if (playing == null) return;
if (!_drilldownScrollController.hasClients) return;

final int targetIndex = _filteredDrilldownSongs
    .indexWhere((SongModel s) => _playback.isActiveSong(s));
if (targetIndex == -1) return;

final double targetOffset;
if (_isDrilldownGridView) {
final int row = targetIndex ~/ 2;
const double rowHeight = 200.0;
targetOffset = (row * rowHeight).clamp(
0.0,
_drilldownScrollController.position.maxScrollExtent,
);
} else {
const double itemHeight = 74.0;
targetOffset = (targetIndex * itemHeight).clamp(
0.0,
_drilldownScrollController.position.maxScrollExtent,
);
}

_drilldownScrollController.animateTo(
targetOffset,
duration: const Duration(milliseconds: 550),
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
'Jumped to active track: "${playing.title}" (#${targetIndex + 1})',
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
}

void _scrollToActiveFolder() {
HapticFeedback.heavyImpact();
if (!_rootScrollController.hasClients) return;

final int targetIndex = _filteredFolders.indexWhere(
(AudioFolderInfo f) => _playback.isFolderActive(f.path),
);

if (targetIndex == -1) {
ScaffoldMessenger.of(context).hideCurrentSnackBar();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
duration: const Duration(milliseconds: 1400),
backgroundColor: _theme.containerHighColor,
content: Row(
children: <Widget>[
Icon(Icons.info_outline_rounded,
color: _theme.primaryAccent, size: 18),
const SizedBox(width: 8),
const Expanded(
child: Text(
'No active playback folder found',
style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
),
),
],
),
),
);
return;
}

final double targetOffset;
if (_isRootGridView) {
final int row = targetIndex ~/ 2;
const double rowHeight = 195.0;
targetOffset = (row * rowHeight).clamp(
0.0,
_rootScrollController.position.maxScrollExtent,
);
} else {
const double itemHeight = 82.0;
targetOffset = (targetIndex * itemHeight).clamp(
0.0,
_rootScrollController.position.maxScrollExtent,
);
}

_rootScrollController.animateTo(
targetOffset,
duration: const Duration(milliseconds: 550),
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
'Locating "${_filteredFolders[targetIndex].folderName}"',
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
}

void _showFolderOptionsMenu() {
if (_activeFolder == null) return;
HapticFeedback.mediumImpact();

final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

showModalBottomSheet<void>(
context: context,
backgroundColor: Colors.transparent,
builder: (BuildContext ctx) => Container(
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
decoration: BoxDecoration(
color: _theme.modalSurfaceColor,
borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.2),
boxShadow:
LotusDecorations.glowShadow(accent, intensity: 0.2, blur: 24),
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
Container(
padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
color: secondaryAccent.withValues(alpha: 0.15),
borderRadius: BorderRadius.circular(10),
),
child: Image.asset(
'assets/icons/vault_icon.png',
width: 22,
height: 22,
fit: BoxFit.contain,
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Text(
_activeFolder!.folderName,
style: TextStyle(
color: textPrimary,
fontSize: 16,
fontWeight: FontWeight.bold,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
Text(
'${_activeFolder!.songCount} Tracks • ${_activeFolder!.totalSizeMb.toStringAsFixed(1)} MB',
style: TextStyle(color: textSecondary, fontSize: 11),
),
],
),
),
],
),
Divider(color: _theme.cardBorderColor, height: 20),
_buildFolderOptionTile(
icon: Icons.sort_by_alpha_rounded,
color: LotusColors.voltLime,
title: 'Sort Songs in this Folder',
subtitle: 'Currently: ${_drilldownSortLabel(_drilldownSort)}',
textPrimary: textPrimary,
textSecondary: textSecondary,
onTap: () {
Navigator.of(ctx).pop();
_cycleDrilldownSortMode();
},
),
_buildFolderOptionTile(
icon: Icons.refresh_rounded,
color: LotusColors.solarGold,
title: 'Rescan Folder Contents',
subtitle: 'Verify stems checksum and format metadata',
textPrimary: textPrimary,
textSecondary: textSecondary,
onTap: () {
Navigator.of(ctx).pop();
_scanDeviceFolders();
},
),
_buildFolderOptionTile(
icon: Icons.playlist_add_rounded,
color: secondaryAccent,
title: 'Create Playlist from Entire Folder',
subtitle:
'Assemble custom playlist from all ${_activeFolder!.songCount} stems',
textPrimary: textPrimary,
textSecondary: textSecondary,
onTap: () {
Navigator.of(ctx).pop();
if (_activeFolder!.songs.isNotEmpty) {
LotusAddToPlaylistDialog.show(context,
song: _activeFolder!.songs.first);
}
},
),
],
),
),
);
}

void _showAudiophileProfileModal() {
HapticFeedback.selectionClick();
final Color accent = _theme.primaryAccent;
final Color textPrimary = _theme.textPrimaryColor;
final Color textSecondary = _theme.textSecondaryColor;

showModalBottomSheet<void>(
context: context,
backgroundColor: Colors.transparent,
builder: (BuildContext ctx) => Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
color: _theme.modalSurfaceColor,
borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.2),
boxShadow:
LotusDecorations.glowShadow(accent, intensity: 0.25, blur: 28),
),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Center(
child: Container(
width: 40,
height: 4,
margin: const EdgeInsets.only(bottom: 16),
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
Container(
width: 50,
height: 50,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: accent.withValues(alpha: 0.16),
border: Border.all(color: accent, width: 1.5),
),
child: Center(
child: Icon(Icons.person_rounded, color: accent, size: 28),
),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Text(
'Audiophile Studio Master',
style: TextStyle(
color: textPrimary,
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 2),
Text(
'Direct Device Storage Vault Mode',
style: TextStyle(color: textSecondary, fontSize: 11),
),
],
),
),
Container(
padding:
const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
decoration: BoxDecoration(
color: LotusColors.voltLime.withValues(alpha: 0.18),
borderRadius: BorderRadius.circular(6),
),
child: const Text(
'ALSA BIT-PERFECT',
style: TextStyle(
color: LotusColors.voltLime,
fontSize: 8.5,
fontWeight: FontWeight.w900,
),
),
),
],
),
const SizedBox(height: 16),
Divider(color: _theme.cardBorderColor, height: 1),
const SizedBox(height: 12),
_buildProfileStatRow(
Icons.folder_special_rounded,
'Indexed Music Folders',
'${_folders.length} active directories',
textPrimary,
textSecondary,
),
_buildProfileStatRow(
Icons.music_note_rounded,
'Current Folder Stems',
'${_activeFolder?.songCount ?? 0} audio files',
textPrimary,
textSecondary,
),
_buildProfileStatRow(
Icons.memory_rounded,
'Kernel DAC Protocol',
'384 kHz / 32-bit ALSA Direct Pass',
textPrimary,
textSecondary,
),
const SizedBox(height: 16),
SizedBox(
width: double.infinity,
child: ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: accent,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(16)),
padding: const EdgeInsets.symmetric(vertical: 12),
),
onPressed: () => Navigator.of(ctx).pop(),
child: const Text(
'DISMISS PROFILE',
style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
),
),
),
],
),
),
);
}

Widget _buildProfileStatRow(IconData icon, String label, String value,
Color textPrimary, Color textSecondary) {
final Color accent = _theme.primaryAccent;
return Padding(
padding: const EdgeInsets.symmetric(vertical: 6.0),
child: Row(
children: <Widget>[
Icon(icon, color: accent, size: 16),
const SizedBox(width: 10),
Text(
label,
style: TextStyle(
color: textSecondary,
fontSize: 12,
),
),
const SizedBox(width: 8),
Expanded(
child: Text(
value,
textAlign: TextAlign.end,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: textPrimary,
fontSize: 12,
fontWeight: FontWeight.bold,
),
),
),
],
),
);
}

Widget _buildFolderOptionTile({
required IconData icon,
required Color color,
required String title,
required String subtitle,
required Color textPrimary,
required Color textSecondary,
required VoidCallback onTap,
}) {
return ListTile(
dense: true,
contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
leading: Container(
padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
color: color.withValues(alpha: 0.15),
borderRadius: BorderRadius.circular(10),
),
child: Icon(icon, color: color, size: 18),
),
title: Text(
title,
style: TextStyle(
color: textPrimary,
fontSize: 13,
fontWeight: FontWeight.bold,
),
),
subtitle: Text(
subtitle,
style: TextStyle(color: textSecondary, fontSize: 10.5),
),
onTap: onTap,
);
}

String _formatDuration(int ms) {
final Duration d = Duration(milliseconds: ms);
return '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

List<AudioFolderInfo> get _filteredFolders {
if (_activeRootSearchQuery.isEmpty) return _folders;
final String q = _activeRootSearchQuery.toLowerCase();
return _folders.where((AudioFolderInfo f) {
return f.folderName.toLowerCase().contains(q) ||
f.path.toLowerCase().contains(q);
}).toList();
}

List<SongModel> get _filteredDrilldownSongs {
if (_activeFolder == null) return <SongModel>[];

List<SongModel> list = _activeFolder!.songs
    .where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
    .toList();

if (_activeDrilldownSearchQuery.isNotEmpty) {
final String q = _activeDrilldownSearchQuery.toLowerCase();
list = list.where((SongModel s) {
final String title = s.title.toLowerCase();
final String artist = (s.artist ?? '').toLowerCase();
return title.contains(q) || artist.contains(q);
}).toList();
}

if (_activeDrilldownFilterChip == 1) {
list = list.where((SongModel s) {
final String ext = s.fileExtension.toLowerCase();
return ext.contains('flac') ||
ext.contains('dsd') ||
ext.contains('wav') ||
ext.contains('alac');
}).toList();
} else if (_activeDrilldownFilterChip == 2) {
list = list.where((SongModel s) {
final String ext = s.fileExtension.toLowerCase();
return ext.contains('flac') || ext.contains('dsd');
}).toList();
}

switch (_drilldownSort) {
case DrilldownSortOption.title:
list.sort((SongModel a, SongModel b) =>
a.title.toLowerCase().compareTo(b.title.toLowerCase()));
break;
case DrilldownSortOption.artist:
list.sort((SongModel a, SongModel b) => (a.artist ?? '')
    .toLowerCase()
    .compareTo((b.artist ?? '').toLowerCase()));
break;
case DrilldownSortOption.duration:
list.sort((SongModel a, SongModel b) =>
(b.duration ?? 0).compareTo(a.duration ?? 0));
break;
case DrilldownSortOption.date:
list.sort((SongModel a, SongModel b) =>
(b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
break;
}

return list;
}

@override
Widget build(BuildContext context) {
return ListenableBuilder(
listenable: Listenable.merge(<Listenable>[_theme, _playback]),
builder: (BuildContext context, Widget? child) {
final Color bgColor = _theme.backgroundColor;
final Color accent = _theme.primaryAccent;
final Color containerLow = _theme.containerLowColor;

return Scaffold(
backgroundColor: bgColor,
body: Stack(
children: <Widget>[
SafeArea(
bottom: false,
child: Column(
children: <Widget>[
if (_activeFolder != null)
_buildDrilldownHeader()
else
_buildRootVaultHeader(),
Expanded(
child: _isLoading
? Center(
child: CircularProgressIndicator(
color: _theme.primaryAccent),
)
    : (_activeFolder == null
? _buildRootFoldersListView()
    : _buildDrilldownTrackListView()),
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
secondaryColor: _theme.secondaryAccent,
surfaceColor: _theme.surfaceColor,
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
secondaryColor: _theme.secondaryAccent,
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
secondaryColor: _theme.secondaryAccent,
surfaceColor: _theme.surfaceColor,
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
secondaryColor: _theme.secondaryAccent,
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
secondaryColor: _theme.secondaryAccent,
),
),
),
],
),
);
},
);
}

// ============================================================================
// ROOT VAULT HEADER
// ============================================================================
Widget _buildRootVaultHeader() {
final int totalTracks =
_folders.fold(0, (int sum, AudioFolderInfo f) => sum + f.songCount);
final Color accent = _theme.primaryAccent;
final Color surfaceColor = _theme.surfaceColor;
final Color containerLow = _theme.containerLowColor;
final Color textPrimary = _theme.textPrimaryColor;
final bool isWhitaniana = _theme.isWhitanianaActive;
final String? activeFolder = _playback.activeFolderName;

return Container(
padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 10.0),
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
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: <Widget>[
Row(
crossAxisAlignment: CrossAxisAlignment.center,
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
'assets/icons/vault_icon.png',
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
Text(
'Vault Library',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: textPrimary,
fontSize: 16.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.3,
),
),
const SizedBox(height: 1),
Row(
children: <Widget>[
CircleAvatar(radius: 2.5, backgroundColor: accent),
const SizedBox(width: 5),
Expanded(
child: Text(
activeFolder != null
? 'ACTIVE: ${activeFolder.toUpperCase()} • $totalTracks TRACKS'
    : '${_folders.length} FOLDERS • $totalTracks TRACKS',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.6,
),
),
),
],
),
],
),
),
const SizedBox(width: 6),
Container(
padding:
const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(8),
border: Border.all(color: _theme.cardBorderColor),
),
child: Text(
'DSD 512',
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 8.5,
fontFamily: 'monospace',
),
),
),
const SizedBox(width: 4),
IconButton(
padding: EdgeInsets.zero,
constraints:
const BoxConstraints(minWidth: 32, minHeight: 32),
icon: Icon(Icons.refresh_rounded, color: accent, size: 20),
tooltip: 'Rescan Storage',
onPressed: _scanDeviceFolders,
),
],
),
const SizedBox(height: 8),
Container(
height: 44,
padding: const EdgeInsets.symmetric(horizontal: 14),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(22),
border: Border.all(
color: _activeRootSearchQuery.isNotEmpty
? accent
    : _theme.cardBorderColor,
width: _activeRootSearchQuery.isNotEmpty ? 1.2 : 0.8,
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : null,
),
child: Row(
children: <Widget>[
const LotusSearchIcon(size: 19),
const SizedBox(width: 10),
Expanded(
child: TextField(
controller: _rootSearchController,
style: TextStyle(color: textPrimary, fontSize: 13),
cursorColor: accent,
decoration: InputDecoration(
hintText: 'Search folders, stems, archives...',
hintStyle: TextStyle(
color: _theme.textTertiaryColor, fontSize: 12.5),
border: InputBorder.none,
contentPadding: const EdgeInsets.symmetric(vertical: 10),
isDense: true,
),
),
),
if (_activeRootSearchQuery.isNotEmpty)
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () {
HapticFeedback.lightImpact();
_rootSearchController.clear();
},
child: Padding(
padding: const EdgeInsets.all(4.0),
child: Icon(Icons.close_rounded,
color: _theme.textTertiaryColor, size: 18),
),
),
],
),
),
const SizedBox(height: 8),
Row(
children: <Widget>[
Expanded(
child: ElevatedButton.icon(
style: ElevatedButton.styleFrom(
backgroundColor: accent,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(vertical: 9),
elevation: 0,
),
onPressed: _playAllFolders,
icon: const Icon(Icons.play_arrow_rounded, size: 18),
label: const Text(
'Play All',
style:
TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
),
),
),
const SizedBox(width: 10),
Expanded(
child: OutlinedButton.icon(
style: OutlinedButton.styleFrom(
foregroundColor: isWhitaniana
? _theme.textPrimaryColor
    : Colors.white,
side: BorderSide(color: accent.withValues(alpha: 0.6)),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(vertical: 9),
),
onPressed: _shuffleAllFolders,
icon: Icon(Icons.shuffle_rounded, size: 16, color: accent),
label: const Text(
'Shuffle Vault',
style:
TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
),
),
),
],
),
const SizedBox(height: 8),
Row(
children: <Widget>[
GestureDetector(
onTap: _cycleRootSortMode,
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 10, vertical: 5.5),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(14),
border: Border.all(color: accent.withValues(alpha: 0.4)),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(Icons.sort_rounded, color: accent, size: 14),
const SizedBox(width: 4),
Text(
'SORT: ${_rootSortLabel(_rootSort)}',
style: TextStyle(
color: accent,
fontSize: 9.5,
fontWeight: FontWeight.bold,
),
),
],
),
),
),
const SizedBox(width: 8),
Flexible(
fit: FlexFit.loose,
child: Text(
'${_filteredFolders.length} items',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 10,
fontWeight: FontWeight.bold,
),
),
),
const Spacer(),
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
_scrollToActiveFolder();
},
child: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: Colors.transparent,
borderRadius: BorderRadius.circular(8),
),
child: Icon(
Icons.my_location_rounded,
color: _folders.any((AudioFolderInfo f) =>
_playback.isFolderActive(f.path))
? accent
    : _theme.textSecondaryColor,
size: 18,
),
),
),
const SizedBox(width: 4),
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setState(() => _isRootGridView = true);
},
child: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: _isRootGridView
? accent.withValues(alpha: 0.2)
    : Colors.transparent,
borderRadius: BorderRadius.circular(8),
border: _isRootGridView
? Border.all(color: accent, width: 1.0)
    : null,
),
child: Icon(
Icons.grid_view_rounded,
color:
_isRootGridView ? accent : _theme.textSecondaryColor,
size: 18,
),
),
),
const SizedBox(width: 4),
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setState(() => _isRootGridView = false);
},
child: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: !_isRootGridView
? _theme.secondaryAccent.withValues(alpha: 0.2)
    : Colors.transparent,
borderRadius: BorderRadius.circular(8),
border: !_isRootGridView
? Border.all(
color: _theme.secondaryAccent, width: 1.0)
    : null,
),
child: Icon(
Icons.view_agenda_rounded,
color: !_isRootGridView
? _theme.secondaryAccent
    : _theme.textSecondaryColor,
size: 18,
),
),
),
],
),
],
),
);
}

// ============================================================================
// DRILLDOWN FOLDER HEADER (PURE GESTURE NAVIGATION)
// ============================================================================
Widget _buildDrilldownHeader() {
final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;
final Color surfaceColor = _theme.surfaceColor;
final Color containerLow = _theme.containerLowColor;
final Color textPrimary = _theme.textPrimaryColor;
final bool isWhitaniana = _theme.isWhitanianaActive;
final bool isFolderActive =
_playback.isFolderActive(_activeFolder!.path);
final SongModel? playing = _playback.activeSong;

return Container(
padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 10.0),
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
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: <Widget>[
Row(
children: <Widget>[
Container(
width: 44,
height: 44,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: containerLow,
border: Border.all(
color: isFolderActive ? accent : secondaryAccent,
width: 1.8),
boxShadow: LotusDecorations.glowShadow(
isFolderActive ? accent : secondaryAccent,
intensity: 0.35,
blur: 16,
),
),
child: ClipOval(
child: Image.asset(
'assets/icons/vault_icon.png',
fit: BoxFit.cover,
errorBuilder: (BuildContext context, Object error,
StackTrace? stackTrace) {
return Center(
child: Icon(Icons.folder_rounded,
color: accent, size: 28),
);
},
),
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Text(
_activeFolder!.folderName,
style: TextStyle(
color: textPrimary,
fontSize: 16.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.3,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
const SizedBox(height: 1),
Text(
'${_activeFolder!.songCount} TRACKS • ${_activeFolder!.totalSizeMb.toStringAsFixed(1)} MB',
style: TextStyle(
color: isFolderActive ? accent : secondaryAccent,
fontSize: 8.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.5,
),
),
],
),
),
IconButton(
padding: EdgeInsets.zero,
constraints:
const BoxConstraints(minWidth: 32, minHeight: 32),
icon: Icon(Icons.tune_rounded, color: textPrimary, size: 20),
tooltip: 'Sort Folder Stems',
onPressed: _cycleDrilldownSortMode,
),
const SizedBox(width: 2),
IconButton(
padding: EdgeInsets.zero,
constraints:
const BoxConstraints(minWidth: 32, minHeight: 32),
icon:
Icon(Icons.more_vert_rounded, color: textPrimary, size: 20),
tooltip: 'Folder Options',
onPressed: _showFolderOptionsMenu,
),
const SizedBox(width: 6),
GestureDetector(
onTap: _showAudiophileProfileModal,
child: Container(
width: 32,
height: 32,
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
shape: BoxShape.circle,
border: Border.all(color: accent.withValues(alpha: 0.6)),
),
child: Icon(Icons.person_rounded,
color: textPrimary, size: 18),
),
),
],
),
const SizedBox(height: 8),
Container(
height: 44,
padding: const EdgeInsets.symmetric(horizontal: 14),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(22),
border: Border.all(
color: _activeDrilldownSearchQuery.isNotEmpty
? accent
    : _theme.cardBorderColor,
width: _activeDrilldownSearchQuery.isNotEmpty ? 1.2 : 0.8,
),
boxShadow: isWhitaniana
? LotusDecorations.whitanianaCardShadow()
    : null,
),
child: Row(
children: <Widget>[
const LotusSearchIcon(size: 19),
const SizedBox(width: 10),
Expanded(
child: TextField(
controller: _drilldownSearchController,
focusNode: _drilldownSearchFocusNode,
style: TextStyle(color: textPrimary, fontSize: 13),
cursorColor: accent,
decoration: InputDecoration(
hintText:
'Search songs in "${_activeFolder!.folderName}"...',
hintStyle: TextStyle(
color: _theme.textTertiaryColor, fontSize: 12),
border: InputBorder.none,
contentPadding: const EdgeInsets.symmetric(vertical: 10),
isDense: true,
),
),
),
if (_activeDrilldownSearchQuery.isNotEmpty)
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () {
HapticFeedback.lightImpact();
_drilldownSearchController.clear();
},
child: Padding(
padding: const EdgeInsets.all(4.0),
child: Icon(Icons.close_rounded,
color: _theme.textTertiaryColor, size: 18),
),
)
else
Container(
padding:
const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
decoration: BoxDecoration(
color: isWhitaniana
? _theme.containerHighColor
    : _theme.containerColor,
borderRadius: BorderRadius.circular(8),
border: Border.all(color: _theme.cardBorderColor),
),
child: Text(
'${_filteredDrilldownSongs.length} STEMS',
style: TextStyle(
color: accent,
fontSize: 8.5,
fontWeight: FontWeight.bold,
),
),
),
],
),
),
const SizedBox(height: 8),
Row(
children: <Widget>[
Expanded(
child: ElevatedButton.icon(
style: ElevatedButton.styleFrom(
backgroundColor: accent,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(vertical: 9),
elevation: 0,
),
onPressed: () => _playAllInFolder(false),
icon: const Icon(Icons.play_arrow_rounded, size: 18),
label: const Text(
'Play All',
style:
TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
),
),
),
const SizedBox(width: 10),
Expanded(
child: OutlinedButton.icon(
style: OutlinedButton.styleFrom(
foregroundColor: isWhitaniana
? _theme.textPrimaryColor
    : Colors.white,
side: BorderSide(color: secondaryAccent, width: 1.2),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(vertical: 9),
),
onPressed: () => _playAllInFolder(true),
icon: Icon(Icons.shuffle_rounded,
size: 16, color: secondaryAccent),
label: const Text(
'Shuffle',
style:
TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
),
),
),
],
),
const SizedBox(height: 8),
FittedBox(
fit: BoxFit.scaleDown,
alignment: Alignment.center,
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: <Widget>[
_buildFilterOptionPill(
title: 'All Songs',
isSelected: _activeDrilldownFilterChip == 0,
accent: accent,
containerLow:
isWhitaniana ? _theme.containerColor : containerLow,
onTap: () => setState(() => _activeDrilldownFilterChip = 0),
),
const SizedBox(width: 8),
_buildFilterOptionPill(
title: 'High-Res Only',
isSelected: _activeDrilldownFilterChip == 1,
accent: accent,
containerLow:
isWhitaniana ? _theme.containerColor : containerLow,
onTap: () => setState(() => _activeDrilldownFilterChip = 1),
),
const SizedBox(width: 8),
_buildFilterOptionPill(
title: 'FLAC & DSD',
isSelected: _activeDrilldownFilterChip == 2,
accent: accent,
containerLow:
isWhitaniana ? _theme.containerColor : containerLow,
onTap: () => setState(() => _activeDrilldownFilterChip = 2),
),
],
),
),
const SizedBox(height: 8),
Row(
children: <Widget>[
GestureDetector(
onTap: _cycleDrilldownSortMode,
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 10, vertical: 5.5),
decoration: BoxDecoration(
color: isWhitaniana ? _theme.containerColor : containerLow,
borderRadius: BorderRadius.circular(14),
border: Border.all(color: accent.withValues(alpha: 0.4)),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(Icons.sort_rounded, color: accent, size: 14),
const SizedBox(width: 4),
Text(
'SORT: ${_drilldownSortLabel(_drilldownSort)}',
style: TextStyle(
color: accent,
fontSize: 9.5,
fontWeight: FontWeight.bold,
),
),
],
),
),
),
const SizedBox(width: 8),
Flexible(
fit: FlexFit.loose,
child: Text(
'${_filteredDrilldownSongs.length} stems',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 10,
fontWeight: FontWeight.bold,
),
),
),
const Spacer(),
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
_scrollToActiveSongInFolder();
},
child: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: Colors.transparent,
borderRadius: BorderRadius.circular(8),
),
child: Icon(
Icons.my_location_rounded,
color: (isFolderActive && playing != null)
? accent
    : _theme.textSecondaryColor,
size: 18,
),
),
),
const SizedBox(width: 4),
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setState(() => _isDrilldownGridView = true);
},
child: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: _isDrilldownGridView
? accent.withValues(alpha: 0.2)
    : Colors.transparent,
borderRadius: BorderRadius.circular(8),
border: _isDrilldownGridView
? Border.all(color: accent, width: 1.0)
    : null,
),
child: Icon(
Icons.grid_view_rounded,
color: _isDrilldownGridView
? accent
    : _theme.textSecondaryColor,
size: 18,
),
),
),
const SizedBox(width: 4),
GestureDetector(
onTap: () {
HapticFeedback.selectionClick();
setState(() => _isDrilldownGridView = false);
},
child: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: !_isDrilldownGridView
? secondaryAccent.withValues(alpha: 0.2)
    : Colors.transparent,
borderRadius: BorderRadius.circular(8),
border: !_isDrilldownGridView
? Border.all(color: secondaryAccent, width: 1.0)
    : null,
),
child: Icon(
Icons.view_agenda_rounded,
color: !_isDrilldownGridView
? secondaryAccent
    : _theme.textSecondaryColor,
size: 18,
),
),
),
],
),
],
),
);
}

Widget _buildFilterOptionPill({
required String title,
required bool isSelected,
required Color accent,
required Color containerLow,
required VoidCallback onTap,
}) {
final bool isWhitaniana = _theme.isWhitanianaActive;

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
color: isSelected ? accent : _theme.cardBorderColor,
width: isSelected ? 1.2 : 0.8,
),
),
child: Text(
title,
style: TextStyle(
color: isSelected
? (isWhitaniana ? accent : Colors.white)
    : _theme.textSecondaryColor,
fontSize: 10.5,
fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
),
),
),
);
}

// ============================================================================
// ROOT FOLDERS VIEW
// ============================================================================
Widget _buildRootFoldersListView() {
final List<AudioFolderInfo> list = _filteredFolders;
final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;
final Color containerLow = _theme.containerLowColor;

if (list.isEmpty) {
return Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: <Widget>[
Icon(Icons.folder_off_rounded,
size: 48, color: _theme.textTertiaryColor),
const SizedBox(height: 12),
Text(
_activeRootSearchQuery.isNotEmpty
? 'No folders matching "$_activeRootSearchQuery"'
    : 'No music directories found.',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 14,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 6),
Text(
'Ensure permissions are granted and storage is mounted.',
style: TextStyle(color: _theme.textSecondaryColor, fontSize: 11),
),
],
),
);
}

if (_isRootGridView) {
return RepaintBoundary(
child: GridView.builder(
controller: _rootScrollController,
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 10, 16, 140),
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
crossAxisCount: 2,
mainAxisSpacing: 12.0,
crossAxisSpacing: 12.0,
childAspectRatio: 0.90,
),
itemCount: list.length,
itemBuilder: (BuildContext context, int index) {
final AudioFolderInfo folder = list[index];
return _buildFolderGridCard(
folder, index, accent, secondaryAccent, containerLow);
},
),
);
}

return RepaintBoundary(
child: ListView.builder(
controller: _rootScrollController,
itemCount: list.length,
itemExtent: 82.0,
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
itemBuilder: (BuildContext context, int index) {
final AudioFolderInfo folder = list[index];
return _buildFolderListCard(
folder, index, accent, secondaryAccent, containerLow);
},
),
);
}

Widget _buildFolderGridCard(AudioFolderInfo folder, int index, Color accent,
Color secondaryAccent, Color containerLow) {
final bool isFolderActive = _playback.isFolderActive(folder.path);
final Color itemAccent = isFolderActive
? accent
    : (index % 2 == 0 ? accent : secondaryAccent);
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
decoration: BoxDecoration(
color: isFolderActive
? (isWhitaniana
? _theme.containerColor
    : _theme.containerHighColor)
    : containerLow,
borderRadius: BorderRadius.circular(18),
border: Border.all(
color: isFolderActive
? accent.withValues(alpha: 0.95)
    : _theme.cardBorderColor,
width: isFolderActive ? 1.6 : 0.8,
),
boxShadow: isFolderActive
? LotusDecorations.glowShadow(accent, intensity: 0.24, blur: 14)
    : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
),
child: Material(
color: Colors.transparent,
child: InkWell(
borderRadius: BorderRadius.circular(18),
onTap: () => _openFolder(folder),
child: Padding(
padding: const EdgeInsets.all(12.0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Container(
padding: const EdgeInsets.symmetric(
horizontal: 7, vertical: 3),
decoration: BoxDecoration(
color: isFolderActive
? accent.withValues(alpha: 0.16)
    : (isWhitaniana
? _theme.containerHighColor
    : itemAccent.withValues(alpha: 0.12)),
borderRadius: BorderRadius.circular(8),
border: Border.all(
color: isFolderActive
? accent.withValues(alpha: 0.5)
    : itemAccent.withValues(alpha: 0.25),
width: 0.8,
),
),
child: Text(
'${folder.totalSizeMb >= 1000 ? folder.totalSizeMb.toStringAsFixed(0) : folder.totalSizeMb.toStringAsFixed(1)} MB',
style: TextStyle(
color: isFolderActive
? accent
    : _theme.textSecondaryColor,
fontSize: 9.5,
fontWeight: FontWeight.bold,
letterSpacing: 0.3,
),
),
),
Flexible(
fit: FlexFit.loose,
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 6, vertical: 2),
decoration: BoxDecoration(
color: isFolderActive
? accent.withValues(alpha: 0.2)
    : (isWhitaniana
? _theme.containerHighColor
    : Colors.white10),
borderRadius: BorderRadius.circular(6),
border: isFolderActive
? Border.all(
color: accent.withValues(alpha: 0.6),
width: 0.6)
    : null,
),
child: Text(
isFolderActive ? 'PLAYING NOW' : folder.formatBadge,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: isFolderActive ? accent : itemAccent,
fontSize: 7.5,
fontWeight: FontWeight.w900,
),
),
),
),
],
),
Expanded(
child: Center(
child: Container(
width: 48,
height: 48,
decoration: BoxDecoration(
color: itemAccent.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: itemAccent.withValues(alpha: 0.4),
width: 1.2,
),
boxShadow: isFolderActive
? LotusDecorations.glowShadow(accent,
intensity: 0.22, blur: 12)
    : null,
),
child: Center(
child: Image.asset(
'assets/icons/vault_icon.png',
width: 36,
height: 36,
fit: BoxFit.contain,
),
),
),
),
),
Text(
folder.folderName,
style: TextStyle(
color: isFolderActive ? accent : _theme.textPrimaryColor,
fontSize: 13.5,
fontWeight: FontWeight.bold,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
const SizedBox(height: 3),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Flexible(
fit: FlexFit.loose,
child: Text(
'${folder.songCount} Tracks',
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 10,
fontWeight: FontWeight.bold,
),
),
),
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () {
HapticFeedback.selectionClick();
_toggleFolderPlayback(folder);
},
child: Padding(
padding: const EdgeInsets.only(left: 4.0),
child: Icon(
(isFolderActive && _playback.isPlaying)
? Icons.pause_circle_filled_rounded
    : Icons.play_circle_fill_rounded,
color: accent,
size: 26,
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
}

Widget _buildFolderListCard(AudioFolderInfo folder, int index, Color accent,
Color secondaryAccent, Color containerLow) {
final bool isFolderActive = _playback.isFolderActive(folder.path);
final Color itemAccent = isFolderActive
? accent
    : (index % 2 == 0 ? accent : secondaryAccent);
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
margin: const EdgeInsets.symmetric(vertical: 4.0),
decoration: BoxDecoration(
color: isFolderActive
? (isWhitaniana
? _theme.containerColor
    : _theme.containerHighColor)
    : containerLow,
borderRadius: BorderRadius.circular(16),
border: Border.all(
color: isFolderActive
? accent.withValues(alpha: 0.95)
    : _theme.cardBorderColor,
width: isFolderActive ? 1.5 : 0.8,
),
boxShadow: isFolderActive
? LotusDecorations.glowShadow(accent, intensity: 0.22, blur: 14)
    : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
),
child: Material(
color: Colors.transparent,
child: InkWell(
borderRadius: BorderRadius.circular(16),
onTap: () => _openFolder(folder),
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 12.0),
child: Row(
children: <Widget>[
Container(
width: 48,
height: 48,
decoration: BoxDecoration(
color: itemAccent.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: itemAccent.withValues(alpha: 0.4), width: 1.2),
),
child: Center(
child: Image.asset(
'assets/icons/vault_icon.png',
width: 36,
height: 36,
fit: BoxFit.contain,
),
),
),
const SizedBox(width: 14),
Expanded(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
Row(
children: <Widget>[
Expanded(
child: Text(
folder.folderName,
style: TextStyle(
color: isFolderActive
? accent
    : _theme.textPrimaryColor,
fontSize: 13.5,
fontWeight: FontWeight.bold,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
if (isFolderActive) ...<Widget>[
const SizedBox(width: 6),
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
'PLAYING NOW',
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
folder.formatBadge,
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
'${folder.songCount} Tracks • ${folder.totalSizeMb.toStringAsFixed(1)} MB',
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 10.5,
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
icon: Icon(
(isFolderActive && _playback.isPlaying)
? Icons.pause_circle_filled_rounded
    : Icons.play_circle_fill_rounded,
color: accent,
size: 32,
),
onPressed: () {
HapticFeedback.selectionClick();
_toggleFolderPlayback(folder);
},
),
],
),
),
),
),
);
}

// ============================================================================
// DRILLDOWN TRACK VIEW
// ============================================================================
Widget _buildDrilldownTrackListView() {
final List<SongModel> filtered = _filteredDrilldownSongs;
final Color accent = _theme.primaryAccent;
final Color secondaryAccent = _theme.secondaryAccent;
final Color containerLow = _theme.containerLowColor;

if (filtered.isEmpty) {
return Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: <Widget>[
Icon(Icons.music_off_rounded,
size: 44, color: _theme.textTertiaryColor),
const SizedBox(height: 10),
Text(
_activeDrilldownSearchQuery.isNotEmpty
? 'No stems matching "$_activeDrilldownSearchQuery"'
    : 'No stems found matching current filter.',
style: TextStyle(
color: _theme.textPrimaryColor,
fontSize: 13,
fontWeight: FontWeight.bold,
),
),
],
),
);
}

if (_isDrilldownGridView) {
return RepaintBoundary(
child: GridView.builder(
controller: _drilldownScrollController,
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
crossAxisCount: 2,
mainAxisSpacing: 12.0,
crossAxisSpacing: 12.0,
childAspectRatio: 0.82,
),
itemCount: filtered.length,
itemBuilder: (BuildContext context, int index) {
final SongModel song = filtered[index];
final bool isCurrent = _playback.isActiveSong(song);
return _buildDrilldownGridCard(song, isCurrent, index, accent,
secondaryAccent, containerLow);
},
),
);
}

return RepaintBoundary(
child: ListView.builder(
controller: _drilldownScrollController,
itemCount: filtered.length,
itemExtent: 74.0,
physics: const BouncingScrollPhysics(),
padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
itemBuilder: (BuildContext context, int index) {
final SongModel song = filtered[index];
final bool isCurrent = _playback.isActiveSong(song);
return _buildDrilldownSongRow(song, isCurrent, index, accent,
secondaryAccent, containerLow);
},
),
);
}

Widget _buildDrilldownGridCard(
SongModel song,
bool isCurrent,
int index,
Color accent,
Color secondaryAccent,
Color containerLow,
) {
final bool isFav = _playback.isSongFavorite(song.id);
final String codec = song.fileExtension.isNotEmpty
? song.fileExtension.toUpperCase()
    : 'FLAC';
final Color itemAccent = index % 2 == 0 ? accent : secondaryAccent;
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
decoration: BoxDecoration(
color: isCurrent
? (isWhitaniana ? _theme.containerColor : containerLow)
    : (isWhitaniana ? containerLow : _theme.containerLowestColor),
borderRadius: BorderRadius.circular(16),
border: Border.all(
color: isCurrent
? accent.withValues(alpha: 0.95)
    : _theme.cardBorderColor,
width: isCurrent ? 1.5 : 0.8,
),
boxShadow: isCurrent
? LotusDecorations.glowShadow(accent, intensity: 0.18, blur: 12)
    : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
),
child: Material(
color: Colors.transparent,
child: InkWell(
borderRadius: BorderRadius.circular(16),
onTap: () {
_playSong(song, queue: _filteredDrilldownSongs);
},
onLongPress: () => _openTrackOptions(song),
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
child: SizedBox.expand(
child: FittedBox(
fit: BoxFit.cover,
clipBehavior: Clip.hardEdge,
child: LotusArtworkImage(
songId: song.id,
size: 160,
borderRadius: 12,
keepOldArtwork: true,
nullArtworkWidget: Container(
width: 160,
height: 160,
color: _theme.containerHighColor,
child: Icon(
Icons.music_note_rounded,
color: itemAccent,
size: 34,
),
),
),
),
),
),
Positioned(
top: 4,
left: 4,
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 4, vertical: 1.5),
decoration: BoxDecoration(
color: Colors.black.withValues(alpha: 0.75),
borderRadius: BorderRadius.circular(4),
),
child: Text(
codec,
style: TextStyle(
color: accent,
fontSize: 7.5,
fontWeight: FontWeight.w900,
),
),
),
),
if (isFav)
Positioned(
top: 4,
right: 4,
child: Icon(Icons.favorite_rounded,
color: secondaryAccent, size: 14),
),
Positioned(
bottom: 4,
right: 4,
child: Container(
width: 26,
height: 26,
decoration: BoxDecoration(
color: isCurrent && _playback.isPlaying
? LotusColors.voltLime
    : accent,
shape: BoxShape.circle,
),
child: Icon(
isCurrent && _playback.isPlaying
? Icons.pause_rounded
    : Icons.play_arrow_rounded,
color: Colors.black,
size: 16,
),
),
),
],
),
),
const SizedBox(height: 6),
Text(
song.title,
style: TextStyle(
color: isCurrent ? accent : _theme.textPrimaryColor,
fontSize: 12,
fontWeight: FontWeight.bold,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
const SizedBox(height: 2),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: <Widget>[
Expanded(
child: Text(
song.artist ?? '<Unknown>',
style: TextStyle(
color: _theme.textSecondaryColor,
fontSize: 9.5,
),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
const SizedBox(width: 4),
Text(
_formatDuration(song.duration ?? 0),
style: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 9,
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
}

Widget _buildDrilldownSongRow(
SongModel song,
bool isCurrent,
int index,
Color accent,
Color secondaryAccent,
Color containerLow,
) {
final bool isFav = _playback.isSongFavorite(song.id);
final Color itemAccent = index % 2 == 0 ? accent : secondaryAccent;
final bool isWhitaniana = _theme.isWhitanianaActive;

return Container(
margin: const EdgeInsets.symmetric(vertical: 3.0),
decoration: BoxDecoration(
color: isCurrent
? (isWhitaniana ? _theme.containerColor : containerLow)
    : (isWhitaniana ? containerLow : _theme.containerLowestColor),
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: isCurrent
? accent.withValues(alpha: 0.95)
    : _theme.cardBorderColor,
width: isCurrent ? 1.5 : 0.8,
),
boxShadow: isCurrent
? LotusDecorations.glowShadow(accent, intensity: 0.18, blur: 12)
    : (isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null),
),
child: Material(
color: Colors.transparent,
child: InkWell(
borderRadius: BorderRadius.circular(14),
onTap: () {
_playSong(song, queue: _filteredDrilldownSongs);
},
onLongPress: () => _openTrackOptions(song),
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 10.0),
child: Row(
children: <Widget>[
SizedBox(
width: 24,
child: isCurrent && _playback.isPlaying
? Icon(Icons.graphic_eq_rounded, color: accent, size: 16)
    : Text(
(index + 1).toString().padLeft(2, '0'),
style: TextStyle(
color: _theme.textTertiaryColor,
fontSize: 11,
fontWeight: FontWeight.bold,
),
),
),
ClipRRect(
borderRadius: BorderRadius.circular(8),
child: SizedBox(
width: 42,
height: 42,
child: LotusArtworkImage(
songId: song.id,
size: 42,
borderRadius: 8,
keepOldArtwork: true,
nullArtworkWidget: Container(
width: 42,
height: 42,
color: _theme.containerHighColor,
child: Icon(Icons.music_note_rounded,
color: itemAccent, size: 20),
),
),
),
),
const SizedBox(width: 10),
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
const SizedBox(height: 2),
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
    : 'FLAC',
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
fontSize: 10,
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
child: Padding(
padding: const EdgeInsets.symmetric(
horizontal: 6.0, vertical: 8.0),
child: Icon(
isFav
? Icons.favorite_rounded
    : Icons.favorite_border_rounded,
color: isFav
? secondaryAccent
    : _theme.textSecondaryColor,
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
archPath.cubicTo(w - (extent * 0.15), y - 85.0,
w - (extent * 0.75), y - 35.0, pullX, y);
archPath.cubicTo(
w - (extent * 0.75), y + 35.0, w - (extent * 0.15), y + 85.0, w, botY);
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
final int pullPercent =
((extent / 48.0) * 100.0).clamp(0.0, 100.0).toInt();

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
    : Icons.folder_special_rounded,
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
final Color accent =
(label == 'SOURCE' || label == 'RETURN') ? secondaryColor : primaryColor;
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