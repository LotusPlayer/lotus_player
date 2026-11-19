import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/lotus_equalizer_service.dart';
import '../services/lotus_media3_client.dart';
import '../services/lotus_playback_persistence_service.dart';

enum LotusRepeatMode {
  off(0),
  all(1),
  one(2);

  final int rawValue;
  const LotusRepeatMode(this.rawValue);

  static LotusRepeatMode fromRaw(int value) {
    switch (value) {
      case 1:
        return LotusRepeatMode.all;
      case 2:
        return LotusRepeatMode.one;
      default:
        return LotusRepeatMode.off;
    }
  }
}

class FavoriteChangeEvent {
  final int songId;
  final bool isFavorite;
  final SongModel? song;
  const FavoriteChangeEvent(
      {required this.songId, required this.isFavorite, this.song});
}

class HiddenSongsChangeEvent {
  final Set<int> hiddenIds;
  final Set<String> hiddenPaths;
  const HiddenSongsChangeEvent(
      {required this.hiddenIds, required this.hiddenPaths});
}

class LotusPlaybackProvider extends ChangeNotifier with WidgetsBindingObserver {
  static final LotusPlaybackProvider instance = LotusPlaybackProvider._();

  LotusPlaybackProvider._() {
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _initFavoritesFromDisk();
    _initHiddenSongsFromDisk();
    _bindMedia3EventListener();
    _eagerLoadRecentHistoryCache();
  }

  static const String _kRecentSongIdsKey = 'lotus_recent_song_history_ids';
  static const String _kRecentSongRecordsKey =
      'lotus_recent_song_history_records_v2';
  static const String _kRecentSongTimestampsKey =
      'lotus_recent_song_timestamps_v1';
  static const String _kFavoriteSongIdsKey = 'lotus_favorite_song_ids';
  static const String _kHiddenSongIdsKey = 'lotus_hidden_song_ids';
  static const String _kHiddenSongPathsKey = 'lotus_hidden_song_paths';
  static const int _kMaxRecentHistory = 50;

  final LotusPlaybackPersistenceService _persistence =
      LotusPlaybackPersistenceService.instance;
  final LotusEqualizerService _eqService = LotusEqualizerService.instance;
  final LotusMedia3Client _media3 = LotusMedia3Client.instance;

  SharedPreferences? _cachedPrefs;
  Future<SharedPreferences> _getPrefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  final StreamController<FavoriteChangeEvent> _favoriteChangeController =
  StreamController<FavoriteChangeEvent>.broadcast();
  Stream<FavoriteChangeEvent> get favoriteChangeStream =>
      _favoriteChangeController.stream;

  final StreamController<HiddenSongsChangeEvent> _hiddenSongsChangeController =
  StreamController<HiddenSongsChangeEvent>.broadcast();
  Stream<HiddenSongsChangeEvent> get hiddenSongsChangeStream =>
      _hiddenSongsChangeController.stream;

  final List<SongModel> _recentSongs = <SongModel>[];
  List<SongModel> get recentSongs => List<SongModel>.unmodifiable(_recentSongs);

  final Map<int, int> _recentPlayedTimestampsMs = <int, int>{};
  int? getRecentPlayedTimestampMs(int songId) =>
      _recentPlayedTimestampsMs[songId];

  final Set<int> _favoriteSongIds = <int>{};
  Set<int> get favoriteSongIds => Set<int>.unmodifiable(_favoriteSongIds);

  final Set<int> _hiddenSongIds = <int>{};
  final Set<String> _hiddenSongPaths = <String>{};
  Set<int> get hiddenSongIds => Set<int>.unmodifiable(_hiddenSongIds);
  Set<String> get hiddenSongPaths => Set<String>.unmodifiable(_hiddenSongPaths);

  SongModel? _activeSong;
  int? _pendingNativeMediaId;
  int _pendingNativePosMs = 0;

  bool _isPlaying = false;
  int _currentPositionMs = 0;
  int _totalDurationMs = 0;
  bool _isFavorite = false;
  bool _isPreparingNative = false;
  bool _hasPreparedNativePlaylist = false;
  bool _isAppendingWindow = false;
  int _playlistGeneration = 0;
  int _consecutiveErrorCount = 0;
  final Stopwatch _playbackClock = Stopwatch();
  int _clockBasePosMs = 0;

  LotusRepeatMode _repeatMode = LotusRepeatMode.off;
  bool _isShuffle = false;

  List<SongModel> _currentQueue = <SongModel>[];
  List<SongModel> _fallbackLibrarySongs = <SongModel>[];

  int _nativeWindowStart = 0;
  int _nativeWindowEnd = 0;

  final Map<int, SongModel> _songLookupMap = <int, SongModel>{};
  final Map<String, SongModel> _songPathLookupMap = <String, SongModel>{};

  final ValueNotifier<int> positionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> progressRatioNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<LotusRepeatMode> repeatModeNotifier =
  ValueNotifier<LotusRepeatMode>(LotusRepeatMode.off);
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> activeSongIdNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<int> songMetadataRevisionNotifier = ValueNotifier<int>(0);

  void _setActiveSong(SongModel? song) {
    _activeSong = song;
    final int newId = song?.id ?? -1;
    if (activeSongIdNotifier.value != newId) activeSongIdNotifier.value = newId;
  }

  SongModel? get activeSong => _activeSong;
  bool get isPlaying => _isPlaying;
  int get currentPositionMs => _currentPositionMs;
  int get totalDurationMs => _totalDurationMs;
  bool get isFavorite => _isFavorite;
  LotusRepeatMode get repeatMode => _repeatMode;
  bool get isShuffle => _isShuffle;
  List<SongModel> get currentQueue => List<SongModel>.unmodifiable(_currentQueue);
  double get progressRatio => _totalDurationMs > 0
      ? (_currentPositionMs / _totalDurationMs).clamp(0.0, 1.0)
      : 0.0;

  String? get activeFolderPath {
    final String? path = _activeSong?.data;
    if (path == null || path.isEmpty) return null;
    final int separator = path.lastIndexOf(Platform.pathSeparator);
    return separator > 0 ? path.substring(0, separator) : null;
  }

  String? get activeFolderName {
    final String? path = activeFolderPath;
    if (path == null) return null;
    final List<String> segments = path.split(Platform.pathSeparator);
    return segments.isEmpty ? null : segments.last;
  }

  bool isFolderActive(String folderPath) {
    final String? currentPath = _activeSong?.data;
    if (currentPath == null || currentPath.isEmpty) return false;
    final String normalizedFolder = folderPath.endsWith(Platform.pathSeparator)
        ? folderPath
        : '$folderPath${Platform.pathSeparator}';
    return currentPath == folderPath ||
        currentPath.startsWith(normalizedFolder);
  }

  bool isActiveSong(SongModel song) {
    final SongModel? active = _activeSong;
    if (active == null) return false;
    return active.id == song.id ||
        (active.data.isNotEmpty &&
            song.data.isNotEmpty &&
            active.data == song.data);
  }

  bool isSongFavorite(int songId) => _favoriteSongIds.contains(songId);

  bool isSongHidden(int songId, [String? filePath]) {
    if (_hiddenSongIds.contains(songId)) return true;
    if (filePath != null && filePath.isNotEmpty) {
      return _hiddenSongPaths.contains(filePath.trim().toLowerCase());
    }
    return false;
  }

  SongModel? getSongById(int id) => _songLookupMap[id];

  StreamSubscription<Map<String, dynamic>>? _media3EventSub;
  Timer? _positionTicker;
  Timer? _recentSaveTimer;
  bool _disposed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startPositionTicker();
        Future<void>.delayed(const Duration(milliseconds: 50), () {
          if (!_disposed) _syncPositionFromNative(forceSnap: true);
        });
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _playbackClock.stop();
        _positionTicker?.cancel();
        _positionTicker = null;
        _persistence.updateLastPosition(_currentPositionMs, force: true);
        _flushRecentHistoryNow();
        break;
      case AppLifecycleState.detached:
        _playbackClock.stop();
        _positionTicker?.cancel();
        _positionTicker = null;
        break;
      default:
        break;
    }
  }

  void _anchorClockTo(int posMs, {required bool running}) {
    final int safePos = posMs < 0 ? 0 : posMs;
    _clockBasePosMs = safePos;
    _playbackClock.reset();
    if (running && !_isPreparingNative && !_disposed) {
      _playbackClock.start();
    } else {
      _playbackClock.stop();
    }
    _setPosition(safePos);
  }

  void _startPositionTicker() {
    _positionTicker?.cancel();
    _positionTicker =
        Timer.periodic(const Duration(milliseconds: 250), (Timer timer) {
          if (_isPlaying && !_isPreparingNative && !_disposed) {
            if (!_playbackClock.isRunning) _playbackClock.start();
            final int estimatedMs =
                _clockBasePosMs + _playbackClock.elapsedMilliseconds;
            final int clampedMs =
            (_totalDurationMs > 0 && estimatedMs > _totalDurationMs)
                ? _totalDurationMs
                : estimatedMs;
            _setPosition(clampedMs);
            _persistence.updateLastPosition(_currentPositionMs);
            if (timer.tick % 20 == 0) _syncPositionFromNative();
          }
        });
  }

  void _bindMedia3EventListener() {
    _media3EventSub?.cancel();
    _media3EventSub =
        _media3.playbackEvents.listen((Map<String, dynamic> event) {
          if (_disposed) return;
          final String eventName = event['event'] as String? ?? '';
          if (eventName == 'onPlayerError') {
            _isPreparingNative = false;
            final String errMsg =
                event['errorMessage'] as String? ?? 'Unknown error';
            debugPrint('Lotus Media3 onPlayerError: $errMsg');
            if (_currentQueue.length > 1 && _consecutiveErrorCount < 3) {
              _consecutiveErrorCount++;
              unawaited(skipNext());
            } else {
              _setPlaying(false);
            }
            return;
          }
          if (eventName == 'onFavoriteChanged') {
            final bool fav = event['isFavorite'] == true;
            final String mediaIdStr = (event['mediaId'] as String?) ??
                (event['currentMediaId'] as String?) ??
                '';
            final int? targetId = int.tryParse(mediaIdStr) ?? _activeSong?.id;
            if (targetId != null && targetId > 0) {
              _applyFavoriteFromNative(targetId, fav);
            }
            return;
          }
          if (eventName == 'onSkipRequested') {
            final bool forward = event['forward'] == true;
            unawaited(forward ? skipNext() : skipPrevious(forcePrevious: true));
            return;
          }
          if (event.containsKey('audioSessionId')) {
            final int sessionId = (event['audioSessionId'] as num?)?.toInt() ?? 0;
            if (sessionId > 0 && _eqService.audioSessionId != sessionId) {
              _eqService.attachAudioSession(sessionId);
            }
          }
          final bool playing = event['isPlaying'] == true;
          final int pos = (event['currentPositionMs'] as num?)?.toInt() ?? 0;
          final int dur = (event['durationMs'] as num?)?.toInt() ?? 0;
          final int playbackState = (event['playbackState'] as num?)?.toInt() ?? 0;
          if (playbackState == 3 && playing) _consecutiveErrorCount = 0;
          if (event.containsKey('repeatMode')) {
            final int rawRepeat = (event['repeatMode'] as num?)?.toInt() ?? 0;
            final LotusRepeatMode mode = LotusRepeatMode.fromRaw(rawRepeat);
            if (_repeatMode != mode) {
              _repeatMode = mode;
              repeatModeNotifier.value = mode;
              _notifySafely();
            }
          }
          if (event.containsKey('shuffleEnabled')) {
            final bool shuffle = event['shuffleEnabled'] == true;
            if (_isShuffle != shuffle) {
              _isShuffle = shuffle;
              shuffleNotifier.value = shuffle;
              _notifySafely();
            }
          }
          final String mediaIdStr = event['currentMediaId'] as String? ?? '';
          final int? incomingSongId = int.tryParse(mediaIdStr);
          if (playbackState != 1 && mediaIdStr.isNotEmpty) {
            _hasPreparedNativePlaylist = true;
          }
          SongModel? resolvedSong;
          if (incomingSongId != null && incomingSongId > 0) {
            resolvedSong =
                _songLookupMap[incomingSongId] ?? getSongById(incomingSongId);
            if (resolvedSong == null) {
              _pendingNativeMediaId = incomingSongId;
              _pendingNativePosMs = pos;
            } else {
              _pendingNativeMediaId = null;
            }
          }
          if (resolvedSong != null && _activeSong?.id != resolvedSong.id) {
            _setActiveSong(resolvedSong);
            _isPreparingNative = false;
            _anchorClockTo(pos > 0 ? pos : 0, running: playing);
            _totalDurationMs = dur > 0 ? dur : (resolvedSong.duration ?? 0);
            _isFavorite = _favoriteSongIds.contains(resolvedSong.id);
            _recordToRecentHistorySilently(resolvedSong);
            _persistence.saveLastPlayedSong(
                song: resolvedSong, positionMs: pos > 0 ? pos : 0);
            _notifySafely();
            _maybeExtendNativeWindow(resolvedSong);
          } else if (resolvedSong != null && _isPreparingNative) {
            _isPreparingNative = false;
            _anchorClockTo(pos > 0 ? pos : 0, running: playing);
            if (dur > 0 && _totalDurationMs != dur) {
              _totalDurationMs = dur;
              _updateProgressRatio();
            }
          }
          if (_isPlaying != playing) {
            if (playing || playbackState == 1 || playbackState == 4) {
              _setPlaying(playing);
            }
          }
          if (dur > 0 && _totalDurationMs != dur) {
            _totalDurationMs = dur;
            _updateProgressRatio();
          }
          if (!_isPreparingNative &&
              (!playing || (pos - _currentPositionMs).abs() > 120)) {
            _anchorClockTo(pos, running: playing);
          }
        });
    _startPositionTicker();
  }

  void _maybeExtendNativeWindow(SongModel current) {
    if (_isShuffle || _isAppendingWindow) return;
    if (_nativeWindowEnd >= _currentQueue.length) return;
    final int idx =
    _currentQueue.indexWhere((SongModel s) => s.id == current.id);
    if (idx < 0 || idx < _nativeWindowEnd - 3) return;
    final int gen = _playlistGeneration;
    final int start = _nativeWindowEnd;
    final int end = math.min(_currentQueue.length, start + 12);
    if (end <= start) return;
    _isAppendingWindow = true;
    final List<SongModel> nextBatch = _currentQueue.sublist(start, end);
    unawaited(() async {
      try {
        final bool ok = await _media3.appendPlaylistItems(nextBatch,
            favoriteIds: _favoriteSongIds);
        if (ok && !_disposed && gen == _playlistGeneration) {
          _nativeWindowEnd = end;
        }
      } catch (e) {
        debugPrint('Lotus append window failed: $e');
      } finally {
        _isAppendingWindow = false;
      }
    }());
  }

  void _applyFavoriteFromNative(int songId, bool isFav) {
    bool changed = false;
    if (isFav) {
      changed = _favoriteSongIds.add(songId);
    } else {
      changed = _favoriteSongIds.remove(songId);
    }
    if (_activeSong?.id == songId && _isFavorite != isFav) {
      _isFavorite = isFav;
      changed = true;
    }
    if (!changed) return;
    final SongModel? targetSong = _songLookupMap[songId] ??
        (_activeSong?.id == songId ? _activeSong : null);
    if (!_favoriteChangeController.isClosed) {
      try {
        _favoriteChangeController.add(FavoriteChangeEvent(
            songId: songId, isFavorite: isFav, song: targetSong));
      } catch (e) {
        debugPrint('Lotus favoriteChangeController add failed: $e');
      }
    }
    _notifySafely();
    unawaited(() async {
      try {
        final SharedPreferences prefs = await _getPrefs();
        await prefs.setStringList(_kFavoriteSongIdsKey,
            _favoriteSongIds.map((int id) => id.toString()).toList());
      } catch (e) {
        debugPrint('Error saving favorite songs from native: $e');
      }
    }());
  }

  Future<void> _syncPositionFromNative({bool forceSnap = false}) async {
    if (_disposed || _isPreparingNative) return;
    try {
      final Map<String, dynamic> snapshot = await _media3.getPlaybackSnapshot();
      if (snapshot.isEmpty || _disposed || _isPreparingNative) return;
      final int pos = (snapshot['currentPositionMs'] as num?)?.toInt() ?? 0;
      final int playbackState = (snapshot['playbackState'] as num?)?.toInt() ?? 1;
      final String? mid = snapshot['currentMediaId'] as String?;
      if (playbackState != 1 && mid != null && mid.isNotEmpty) {
        _hasPreparedNativePlaylist = true;
      }
      final bool nativePlaying = snapshot.containsKey('isPlaying')
          ? snapshot['isPlaying'] == true
          : _isPlaying;
      bool resyncChanged = nativePlaying != _isPlaying;
      _setPlayingSilently(nativePlaying);
      if (snapshot.containsKey('shuffleEnabled')) {
        final bool sh = snapshot['shuffleEnabled'] == true;
        if (_isShuffle != sh) {
          _isShuffle = sh;
          shuffleNotifier.value = sh;
          resyncChanged = true;
        }
      }
      if (snapshot.containsKey('repeatMode')) {
        final int raw = (snapshot['repeatMode'] as num?)?.toInt() ?? 0;
        final LotusRepeatMode rm = LotusRepeatMode.fromRaw(raw);
        if (_repeatMode != rm) {
          _repeatMode = rm;
          repeatModeNotifier.value = rm;
          resyncChanged = true;
        }
      }
      if (mid != null && mid.isNotEmpty) {
        final int? sid = int.tryParse(mid);
        if (sid != null && sid > 0 && _activeSong?.id != sid) {
          final SongModel? s = _songLookupMap[sid] ?? getSongById(sid);
          if (s != null) {
            _setActiveSong(s);
            _isFavorite = _favoriteSongIds.contains(s.id);
            if (s.duration != null && s.duration! > 0) {
              _totalDurationMs = s.duration!;
            }
            resyncChanged = true;
          }
        }
      }
      if (snapshot.containsKey('isFavorite')) {
        final bool fav = snapshot['isFavorite'] == true;
        if (_activeSong != null && _isFavorite != fav) {
          _applyFavoriteFromNative(_activeSong!.id, fav);
          resyncChanged = false;
        }
      }
      if (resyncChanged) _notifySafely();
      if (forceSnap || (pos - _currentPositionMs).abs() > 120) {
        _anchorClockTo(pos, running: nativePlaying);
        _persistence.updateLastPosition(pos);
      } else if (nativePlaying && !_playbackClock.isRunning) {
        _anchorClockTo(pos, running: true);
      }
    } catch (e) {
      debugPrint('Lotus _syncPositionFromNative failed: $e');
    }
  }

  void _setPlayingSilently(bool value) {
    if (_isPlaying == value) return;
    _isPlaying = value;
    isPlayingNotifier.value = value;
    _eqService.setPlaybackActive(value);
    if (value && !_isPreparingNative) {
      _clockBasePosMs = _currentPositionMs;
      _playbackClock
        ..reset()
        ..start();
    } else {
      _clockBasePosMs = _currentPositionMs;
      _playbackClock
        ..stop()
        ..reset();
    }
  }

  void _setPlaying(bool value) {
    if (_isPlaying == value) return;
    _isPlaying = value;
    isPlayingNotifier.value = value;
    _eqService.setPlaybackActive(value);
    if (value && !_isPreparingNative) {
      _clockBasePosMs = _currentPositionMs;
      _playbackClock
        ..reset()
        ..start();
    } else {
      _clockBasePosMs = _currentPositionMs;
      _playbackClock
        ..stop()
        ..reset();
    }
    if (!value) _persistence.updateLastPosition(_currentPositionMs, force: true);
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  void _setPosition(int milliseconds) {
    final int safePosition = milliseconds < 0 ? 0 : milliseconds;
    _currentPositionMs = safePosition;
    positionNotifier.value = safePosition;
    _updateProgressRatio();
  }

  void _updateProgressRatio() {
    final double ratio = _totalDurationMs > 0
        ? (_currentPositionMs / _totalDurationMs).clamp(0.0, 1.0)
        : 0.0;
    progressRatioNotifier.value = ratio;
  }

  String _normalizePath(String path) => path.trim().toLowerCase();

  List<SongModel> _deduplicateSongs(Iterable<SongModel> songs) {
    final Set<int> seenIds = <int>{};
    final Set<String> seenPaths = <String>{};
    final List<SongModel> result = <SongModel>[];
    for (final SongModel song in songs) {
      final String normPath = _normalizePath(song.data);
      final bool idAdded = seenIds.add(song.id);
      final bool pathAdded = normPath.isEmpty || seenPaths.add(normPath);
      if (idAdded && pathAdded) {
        result.add(song);
        _songLookupMap[song.id] = song;
        if (song.data.isNotEmpty) {
          _songPathLookupMap[song.data] = song;
          _songPathLookupMap[normPath] = song;
        }
      }
    }
    return result;
  }

  Future<void> toggleRepeatMode() async {
    final LotusRepeatMode next;
    switch (_repeatMode) {
      case LotusRepeatMode.off:
        next = LotusRepeatMode.all;
        break;
      case LotusRepeatMode.all:
        next = LotusRepeatMode.one;
        break;
      case LotusRepeatMode.one:
        next = LotusRepeatMode.off;
        break;
    }
    await setRepeatMode(next);
  }

  Future<void> setRepeatMode(LotusRepeatMode mode) async {
    _repeatMode = mode;
    repeatModeNotifier.value = mode;
    _notifySafely();
    try {
      await _media3.setRepeatMode(mode.rawValue);
    } catch (e) {
      debugPrint('Lotus RepeatMode error: $e');
    }
    if (!_disposed && _repeatMode != mode) {
      _repeatMode = mode;
      repeatModeNotifier.value = mode;
      _notifySafely();
    }
  }

  Future<void> toggleShuffle() async => await setShuffle(!_isShuffle);

  Future<void> setShuffle(bool enabled) async {
    _isShuffle = enabled;
    shuffleNotifier.value = enabled;
    _notifySafely();
    try {
      await _media3.setShuffle(enabled);
    } catch (e) {
      debugPrint('Lotus Shuffle error: $e');
    }
    if (!_disposed && _isShuffle != enabled) {
      _isShuffle = enabled;
      shuffleNotifier.value = enabled;
      _notifySafely();
    }
  }

  Future<void> playSong(
      SongModel song, {
        List<SongModel>? queue,
        bool autoPlay = true,
        int initialSeekMs = 0,
        bool isSkipAction = false,
      }) async {
    final int callGeneration = ++_playlistGeneration;
    _isAppendingWindow = false;
    _consecutiveErrorCount = 0;
    _pendingNativeMediaId = null;
    _setActiveSong(song);
    _songLookupMap[song.id] = song;
    if (song.data.isNotEmpty) {
      _songPathLookupMap[song.data] = song;
      _songPathLookupMap[_normalizePath(song.data)] = song;
    }
    if (queue != null && queue.isNotEmpty) {
      _currentQueue = List<SongModel>.from(queue);
    } else if (_currentQueue.isEmpty && _fallbackLibrarySongs.isNotEmpty) {
      _currentQueue = List<SongModel>.from(_fallbackLibrarySongs);
    }
    if (!_currentQueue.any((SongModel s) => s.id == song.id)) {
      _currentQueue = [..._currentQueue, song];
    }
    for (final SongModel s in _currentQueue) {
      _songLookupMap[s.id] = s;
      if (s.data.isNotEmpty) {
        _songPathLookupMap[s.data] = s;
        _songPathLookupMap[_normalizePath(s.data)] = s;
      }
    }
    _isFavorite = _favoriteSongIds.contains(song.id);
    _recordToRecentHistorySilently(song);
    _isPreparingNative = true;
    _hasPreparedNativePlaylist = true;
    _anchorClockTo(initialSeekMs, running: false);
    _totalDurationMs = song.duration ?? 0;
    _updateProgressRatio();
    _persistence.saveLastPlayedSong(song: song, positionMs: initialSeekMs);
    _persistence.updateLastPosition(initialSeekMs, force: true);
    _setPlayingSilently(autoPlay);
    _notifySafely();
    final int targetIndex =
    _currentQueue.indexWhere((SongModel s) => s.id == song.id);
    const int kWindowBefore = 6;
    const int kWindowAfter = 24;
    final int safeStart = math.max(0, targetIndex - kWindowBefore);
    final int safeEnd =
    math.min(_currentQueue.length, targetIndex + kWindowAfter + 1);
    final List<SongModel> nativeWindowQueue =
    _currentQueue.sublist(safeStart, safeEnd);
    final int nativeIndex = targetIndex - safeStart;
    _nativeWindowStart = safeStart;
    _nativeWindowEnd = safeEnd;
    try {
      await _media3.setPlaylist(
          songs: nativeWindowQueue,
          startIndex: nativeIndex >= 0 ? nativeIndex : 0,
          startPosMs: initialSeekMs,
          favoriteIds: _favoriteSongIds);
    } catch (e) {
      debugPrint('Lotus setPlaylist failed: $e');
    } finally {
      if (_playlistGeneration == callGeneration) {
        _isPreparingNative = false;
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!_disposed &&
              !_isPreparingNative &&
              _playlistGeneration == callGeneration) {
            _syncPositionFromNative(forceSnap: false);
          }
        });
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      _setPlaying(false);
      await _media3.pause();
      return;
    }
    final SongModel? song = _activeSong;
    if (song == null) {
      final List<SongModel> source =
      _currentQueue.isNotEmpty ? _currentQueue : _fallbackLibrarySongs;
      if (source.isNotEmpty) {
        await playSong(source.first, queue: source, isSkipAction: true);
      }
      return;
    }
    if (!_hasPreparedNativePlaylist) {
      final Map<String, dynamic> snapshot = await _media3.getPlaybackSnapshot();
      final int playbackState = (snapshot['playbackState'] as num?)?.toInt() ?? 1;
      if (playbackState == 1 || snapshot.isEmpty) {
        final List<SongModel> queue =
        _currentQueue.isNotEmpty ? _currentQueue : _fallbackLibrarySongs;
        await playSong(song, queue: queue, initialSeekMs: _currentPositionMs);
        return;
      }
      _hasPreparedNativePlaylist = true;
    }
    _setPlaying(true);
    await _media3.play();
  }

  Future<void> pause() async {
    if (!_isPlaying) return;
    _setPlaying(false);
    await _media3.pause();
  }

  Future<void> stop() async {
    _setPlaying(false);
    _hasPreparedNativePlaylist = false;
    _persistence.updateLastPosition(_currentPositionMs, force: true);
    await _media3.stop();
  }

  Future<void> skipNext() async {
    if (_currentQueue.isEmpty && _fallbackLibrarySongs.isNotEmpty) {
      _currentQueue = _deduplicateSongs(_fallbackLibrarySongs);
      for (final SongModel s in _currentQueue) {
        _songLookupMap[s.id] = s;
      }
    }
    if (_currentQueue.isEmpty) return;
    final int currentIndex =
    _currentQueue.indexWhere((SongModel s) => s.id == _activeSong?.id);
    final int nextIndex =
    currentIndex >= 0 ? (currentIndex + 1) % _currentQueue.length : 0;
    if (!_isShuffle &&
        nextIndex >= _nativeWindowStart &&
        nextIndex < _nativeWindowEnd &&
        currentIndex >= 0) {
      final SongModel nextSong = _currentQueue[nextIndex];
      _applyOptimisticTrackChange(nextSong);
      _maybeExtendNativeWindow(nextSong);
      try {
        final dynamic ok = await _controlsSkipToNext();
        _isPreparingNative = false;
        if (ok != true) {
          await playSong(nextSong, queue: currentQueue, isSkipAction: true);
        }
      } catch (e) {
        debugPrint('Lotus controlsSkipToNext failed: $e');
        _isPreparingNative = false;
        await playSong(nextSong, queue: _currentQueue, isSkipAction: true);
      }
      return;
    }
    try {
      final dynamic ok = await _controlsSkipToNext();
      if (ok == true) return;
    } catch (e) {
      debugPrint('Lotus controlsSkipToNext failed: $e');
    }
    if (_isShuffle && _activeSong != null) {
      await playSong(_activeSong!,
          queue: _currentQueue,
          initialSeekMs: _currentPositionMs,
          isSkipAction: true);
      try {
        final dynamic ok2 = await _controlsSkipToNext();
        if (ok2 == true) return;
      } catch (e) {
        debugPrint('Lotus controlsSkipToNext failed: $e');
      }
    }
    final SongModel nextSong = _currentQueue[nextIndex];
    await playSong(nextSong, queue: _currentQueue, isSkipAction: true);
  }

  Future<void> skipPrevious({bool forcePrevious = false}) async {
    if (_currentQueue.isEmpty && _fallbackLibrarySongs.isNotEmpty) {
      _currentQueue = _deduplicateSongs(_fallbackLibrarySongs);
      for (final SongModel s in _currentQueue) {
        _songLookupMap[s.id] = s;
      }
    }
    if (_currentQueue.isEmpty) return;
    if (!forcePrevious && _currentPositionMs > 3000) {
      await seek(Duration.zero);
      return;
    }
    final int currentIndex =
    _currentQueue.indexWhere((SongModel s) => s.id == _activeSong?.id);
    final int prevIndex =
    currentIndex > 0 ? (currentIndex - 1) : _currentQueue.length - 1;
    if (!_isShuffle &&
        prevIndex >= _nativeWindowStart &&
        prevIndex < _nativeWindowEnd &&
        currentIndex > 0) {
      final SongModel prevSong = _currentQueue[prevIndex];
      _applyOptimisticTrackChange(prevSong);
      try {
        final dynamic ok = await _controlsSkipToPrevious();
        _isPreparingNative = false;
        if (ok != true) {
          await playSong(prevSong, queue: currentQueue, isSkipAction: true);
        }
      } catch (e) {
        debugPrint('Lotus controlsSkipToPrevious failed: $e');
        _isPreparingNative = false;
        await playSong(prevSong, queue: _currentQueue, isSkipAction: true);
      }
      return;
    }
    try {
      final dynamic ok = await _controlsSkipToPrevious();
      if (ok == true) return;
    } catch (e) {
      debugPrint('Lotus controlsSkipToPrevious failed: $e');
    }
    if (_isShuffle && _activeSong != null) {
      await playSong(_activeSong!,
          queue: _currentQueue,
          initialSeekMs: _currentPositionMs,
          isSkipAction: true);
      try {
        final dynamic ok2 = await _controlsSkipToPrevious();
        if (ok2 == true) return;
      } catch (e) {
        debugPrint('Lotus controlsSkipToPrevious failed: $e');
      }
    }
    final SongModel prevSong = _currentQueue[prevIndex];
    await playSong(prevSong, queue: _currentQueue, isSkipAction: true);
  }

  void _applyOptimisticTrackChange(SongModel song) {
    _pendingNativeMediaId = null;
    _setActiveSong(song);
    _songLookupMap[song.id] = song;
    if (song.data.isNotEmpty) {
      _songPathLookupMap[song.data] = song;
      _songPathLookupMap[_normalizePath(song.data)] = song;
    }
    _isFavorite = _favoriteSongIds.contains(song.id);
    _recordToRecentHistorySilently(song);
    _anchorClockTo(0, running: true);
    _totalDurationMs = song.duration ?? 0;
    _updateProgressRatio();
    _setPlayingSilently(true);
    _notifySafely();
  }

  Future<dynamic> _controlsSkipToNext() => _media3.skipToNextWithResult();
  Future<dynamic> _controlsSkipToPrevious() =>
      _media3.skipToPreviousWithResult();

  Future<void> seek(Duration position) async {
    final int requestedMs = position.inMilliseconds;
    final bool isScrubbingForwardIntoEndZone = _totalDurationMs > 2500 &&
        requestedMs >= (_totalDurationMs - 1200) &&
        _currentPositionMs < (_totalDurationMs - 1500);
    if (isScrubbingForwardIntoEndZone) {
      await skipNext();
      return;
    }
    final int safeMs = requestedMs < 0
        ? 0
        : (_totalDurationMs > 0 && requestedMs > _totalDurationMs
        ? _totalDurationMs
        : requestedMs);
    _anchorClockTo(safeMs, running: _isPlaying);
    _persistence.updateLastPosition(safeMs, force: true);
    await _media3.seek(Duration(milliseconds: safeMs));
  }

  Future<void> _initFavoritesFromDisk() async {
    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.reload();
      final List<String> favorites =
          prefs.getStringList(_kFavoriteSongIdsKey) ?? <String>[];
      _favoriteSongIds.clear();
      for (final String s in favorites) {
        final int? id = int.tryParse(s);
        if (id != null) _favoriteSongIds.add(id);
      }
      if (_activeSong != null) {
        _isFavorite = _favoriteSongIds.contains(_activeSong!.id);
      }
      _media3.syncFavoriteIds(_favoriteSongIds);
      _notifySafely();
    } catch (e) {
      debugPrint('Lotus _initFavoritesFromDisk failed: $e');
    }
  }

  Future<void> toggleFavoriteSong(SongModel song) async {
    final int songId = song.id;
    final bool willBeFav = !_favoriteSongIds.contains(songId);
    _songLookupMap[song.id] = song;
    if (song.data.isNotEmpty) {
      _songPathLookupMap[song.data] = song;
      _songPathLookupMap[_normalizePath(song.data)] = song;
    }
    if (willBeFav) {
      _favoriteSongIds.add(songId);
    } else {
      _favoriteSongIds.remove(songId);
    }
    if (_activeSong?.id == songId) {
      _isFavorite = willBeFav;
      _media3.updateFavoriteStatus(willBeFav, songId: songId);
    } else {
      _media3.syncFavoriteIds(_favoriteSongIds);
    }
    if (!_favoriteChangeController.isClosed) {
      try {
        _favoriteChangeController.add(FavoriteChangeEvent(
            songId: songId, isFavorite: willBeFav, song: song));
      } catch (e) {
        debugPrint('Lotus favoriteChangeController add failed: $e');
      }
    }
    _notifySafely();
    unawaited(() async {
      try {
        final SharedPreferences prefs = await _getPrefs();
        await prefs.setStringList(_kFavoriteSongIdsKey,
            _favoriteSongIds.map((int id) => id.toString()).toList());
      } catch (e) {
        debugPrint('Error saving favorite songs: $e');
      }
    }());
  }

  Future<void> toggleFavorite() async {
    final SongModel? song = _activeSong;
    if (song != null) await toggleFavoriteSong(song);
  }

  void setFavoriteStatus(int songId, bool isFav, {SongModel? song}) {
    bool changed = false;
    if (isFav) {
      changed = _favoriteSongIds.add(songId);
    } else {
      changed = _favoriteSongIds.remove(songId);
    }
    final SongModel? targetSong = song ??
        _songLookupMap[songId] ??
        (_activeSong?.id == songId ? _activeSong : null);
    if (targetSong != null) _songLookupMap[songId] = targetSong;
    if (_activeSong?.id == songId) {
      _isFavorite = isFav;
      _media3.updateFavoriteStatus(isFav, songId: songId);
      changed = true;
    } else if (changed) {
      _media3.syncFavoriteIds(_favoriteSongIds);
    }
    if (changed) {
      if (!_favoriteChangeController.isClosed) {
        try {
          _favoriteChangeController.add(FavoriteChangeEvent(
              songId: songId, isFavorite: isFav, song: targetSong));
        } catch (e) {
          debugPrint('Lotus favoriteChangeController add failed: $e');
        }
      }
      _notifySafely();
      unawaited(() async {
        try {
          final SharedPreferences prefs = await _getPrefs();
          await prefs.setStringList(_kFavoriteSongIdsKey,
              _favoriteSongIds.map((int id) => id.toString()).toList());
        } catch (e) {
          debugPrint('Error saving favorite songs status: $e');
        }
      }());
    }
  }

  Future<void> _initHiddenSongsFromDisk() async {
    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.reload();
      final List<String> hiddenIds =
          prefs.getStringList(_kHiddenSongIdsKey) ?? <String>[];
      final List<String> hiddenPaths =
          prefs.getStringList(_kHiddenSongPathsKey) ?? <String>[];
      _hiddenSongIds.clear();
      _hiddenSongPaths.clear();
      for (final String strId in hiddenIds) {
        final int? id = int.tryParse(strId);
        if (id != null) _hiddenSongIds.add(id);
      }
      for (final String p in hiddenPaths) {
        if (p.trim().isNotEmpty) _hiddenSongPaths.add(p.trim().toLowerCase());
      }
      _notifySafely();
    } catch (e) {
      debugPrint('Lotus Error loading hidden songs from disk: $e');
    }
  }

  Future<void> hideSong(SongModel song) async {
    final int songId = song.id;
    final String path = song.data.trim().toLowerCase();
    _hiddenSongIds.add(songId);
    if (path.isNotEmpty) _hiddenSongPaths.add(path);
    if (_favoriteSongIds.contains(songId)) await toggleFavoriteSong(song);
    _currentQueue.removeWhere((SongModel s) => s.id == songId);
    if (activeSong?.id == songId) {
      try {
        await skipNext();
      } catch (e) {
        debugPrint('Lotus hideSong skipNext failed: $e');
      }
    }
    _notifySafely();
    if (!_hiddenSongsChangeController.isClosed) {
      try {
        _hiddenSongsChangeController.add(HiddenSongsChangeEvent(
            hiddenIds: Set<int>.from(_hiddenSongIds),
            hiddenPaths: Set<String>.from(hiddenSongPaths)));
      } catch (e) {
        debugPrint('Lotus hiddenSongsChangeController add failed: $e');
      }
    }
    unawaited(() async {
      try {
        final SharedPreferences prefs = await _getPrefs();
        await prefs.setStringList(_kHiddenSongIdsKey,
            _hiddenSongIds.map((int id) => id.toString()).toList());
        await prefs.setStringList(
            _kHiddenSongPathsKey, _hiddenSongPaths.toList());
      } catch (e) {
        debugPrint('Lotus Error saving hidden songs blacklist: $e');
      }
    }());
  }

  Future<void> unhideSongs(Iterable<int> songIds,
      [Iterable<String>? filePaths]) async {
    for (final int id in songIds) {
      _hiddenSongIds.remove(id);
      final SongModel? s = _songLookupMap[id];
      if (s != null && s.data.isNotEmpty) {
        _hiddenSongPaths.remove(s.data.trim().toLowerCase());
      }
    }
    if (filePaths != null) {
      for (final String p in filePaths) {
        _hiddenSongPaths.remove(p.trim().toLowerCase());
      }
    }
    _notifySafely();
    if (!_hiddenSongsChangeController.isClosed) {
      try {
        _hiddenSongsChangeController.add(HiddenSongsChangeEvent(
            hiddenIds: Set<int>.from(_hiddenSongIds),
            hiddenPaths: Set<String>.from(hiddenSongPaths)));
      } catch (e) {
        debugPrint('Lotus hiddenSongsChangeController add failed: $e');
      }
    }
    unawaited(() async {
      try {
        final SharedPreferences prefs = await _getPrefs();
        await prefs.setStringList(_kHiddenSongIdsKey,
            _hiddenSongIds.map((int id) => id.toString()).toList());
        await prefs.setStringList(
            _kHiddenSongPathsKey, _hiddenSongPaths.toList());
      } catch (e) {
        debugPrint('Lotus Error persisting unhidden songs: $e');
      }
    }());
  }

  void _loadTimestampsFromPrefs(SharedPreferences prefs) {
    final String? rawTs = prefs.getString(_kRecentSongTimestampsKey);
    if (rawTs == null || rawTs.isEmpty) return;
    try {
      final dynamic decoded = jsonDecode(rawTs);
      if (decoded is Map) {
        decoded.forEach((dynamic k, dynamic v) {
          final int? id = int.tryParse(k.toString());
          final int? ts = (v as num?)?.toInt();
          if (id != null && ts != null && ts > 0) {
            _recentPlayedTimestampsMs.putIfAbsent(id, () => ts);
          }
        });
      }
    } catch (e) {
      debugPrint('Lotus _loadTimestampsFromPrefs failed: $e');
    }
  }

  Future<void> _eagerLoadRecentHistoryCache() async {
    try {
      final SharedPreferences prefs = await _getPrefs();
      _loadTimestampsFromPrefs(prefs);
      final List<String>? rawRecords =
      prefs.getStringList(_kRecentSongRecordsKey);
      if (rawRecords != null && rawRecords.isNotEmpty && _recentSongs.isEmpty) {
        for (final String jsonStr in rawRecords) {
          try {
            final dynamic decoded = jsonDecode(jsonStr);
            if (decoded is! Map) continue;
            final SongModel cachedSong =
            SongModel(Map<dynamic, dynamic>.from(decoded));
            if (isSongHidden(cachedSong.id, cachedSong.data)) continue;
            if (!_recentSongs.any((SongModel s) =>
            s.id == cachedSong.id ||
                (s.data.isNotEmpty && s.data == cachedSong.data))) {
              _recentSongs.add(cachedSong);
              _songLookupMap[cachedSong.id] = cachedSong;
              if (cachedSong.data.isNotEmpty) {
                _songPathLookupMap[cachedSong.data] = cachedSong;
                _songPathLookupMap[_normalizePath(cachedSong.data)] =
                    cachedSong;
              }
            }
          } catch (e) {
            debugPrint('Lotus eager recent decode failed: $e');
          }
        }
        if (_recentSongs.isNotEmpty && _activeSong == null) {
          final Map<String, dynamic>? meta =
          await _persistence.getLastPlayedMetadata();
          final int targetId =
              _pendingNativeMediaId ?? (meta?['songId'] as num?)?.toInt() ?? -1;
          final int savedPos = _pendingNativeMediaId != null
              ? _pendingNativePosMs
              : ((meta?['positionMs'] as num?)?.toInt() ??
              prefs.getInt('lotus_last_position_ms') ??
              0);
          SongModel? restored = targetId > 0 ? _songLookupMap[targetId] : null;
          restored ??= _recentSongs.first;
          _setActiveSong(restored);
          if (_pendingNativeMediaId == restored.id) {
            _pendingNativeMediaId = null;
          }
          _totalDurationMs = restored.duration ?? 0;
          _isFavorite = _favoriteSongIds.contains(restored.id);
          _isPlaying = false;
          isPlayingNotifier.value = false;
          _anchorClockTo(savedPos, running: false);
          if (_currentQueue.isEmpty) {
            _currentQueue = List<SongModel>.from(_recentSongs);
          }
          _notifySafely();
        }
      }
    } catch (e) {
      debugPrint('Lotus _eagerLoadRecentHistoryCache failed: $e');
    }
  }

  void _recordToRecentHistorySilently(SongModel song) {
    if (isSongHidden(song.id, song.data)) return;
    _recentPlayedTimestampsMs[song.id] = DateTime.now().millisecondsSinceEpoch;
    _recentSongs.removeWhere((SongModel s) =>
    s.id == song.id ||
        (s.data.isNotEmpty && song.data.isNotEmpty && s.data == song.data));
    _recentSongs.insert(0, song);
    if (_recentSongs.length > _kMaxRecentHistory) {
      final List<SongModel> removed =
      _recentSongs.sublist(_kMaxRecentHistory);
      _recentSongs.removeRange(_kMaxRecentHistory, _recentSongs.length);
      for (final SongModel r in removed) {
        _recentPlayedTimestampsMs.remove(r.id);
      }
    }
    _recentSaveTimer?.cancel();
    _recentSaveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_persistRecentHistory());
    });
  }

  void _flushRecentHistoryNow() {
    final Timer? timer = _recentSaveTimer;
    if (timer != null && timer.isActive) {
      timer.cancel();
      unawaited(_persistRecentHistory());
    }
  }

  Future<void> _persistRecentHistory() async {
    try {
      final SharedPreferences prefs = await _getPrefs();
      final List<String> idStrings =
      _recentSongs.map((SongModel s) => s.id.toString()).toList();
      await prefs.setStringList(_kRecentSongIdsKey, idStrings);
      final List<String> recordStrings = _recentSongs.map((SongModel s) {
        final Map<String, dynamic> serializableMap = <String, dynamic>{};
        s.getMap.forEach((dynamic k, dynamic v) {
          if (v is num || v is String || v is bool || v == null) {
            serializableMap[k.toString()] = v;
          }
        });
        return jsonEncode(serializableMap);
      }).toList();
      await prefs.setStringList(_kRecentSongRecordsKey, recordStrings);

      final Map<String, int> tsMap = <String, int>{};
      for (final SongModel s in _recentSongs) {
        final int? ts = _recentPlayedTimestampsMs[s.id];
        if (ts != null) {
          tsMap[s.id.toString()] = ts;
        }
      }
      await prefs.setString(_kRecentSongTimestampsKey, jsonEncode(tsMap));
    } catch (e) {
      debugPrint('Error recording recent song history: $e');
    }
  }

  Future<void> shareSong(SongModel song, {BuildContext? context}) async {
    try {
      final String artist = song.artist ?? 'Unknown artist';
      final String text =
          'Listening to "${song.title}" by $artist — Lotus Player';
      if (song.data.isNotEmpty && await File(song.data).exists()) {
        await SharePlus.instance.share(ShareParams(
            files: <XFile>[XFile(song.data)], text: text, subject: song.title));
      } else {
        await SharePlus.instance
            .share(ShareParams(text: text, subject: song.title));
      }
    } catch (e) {
      debugPrint('Lotus share failed: $e');
    }
  }

  Future<void> updateActiveSongMetadata({
    String? title,
    String? artist,
    String? album,
    String? coverPath,
    bool removeCover = false,
  }) async {
    final SongModel? active = _activeSong;
    if (active == null) return;
    await _media3.updateSongMetadata(
      songId: active.id,
      albumId: active.albumId,
      title: title ?? active.title,
      artist: artist ?? active.artist ?? 'Unknown Artist',
      album: album ?? active.album ?? 'Unknown Album',
      coverPath: coverPath,
      removeCover: removeCover,
    );
    _notifySafely();
  }

  Future<void> applyDspPreset(String presetName) async {
    try {
      await _eqService.applyPreset(presetName);
    } catch (e) {
      debugPrint('Lotus applyDspPreset error: $e');
    }
  }

  Future<void> hydrateLastPlayed(List<SongModel> availableSongs) async {
    if (availableSongs.isEmpty) return;
    final List<SongModel> visibleSongs = availableSongs
        .where((SongModel s) => !isSongHidden(s.id, s.data))
        .toList();
    _fallbackLibrarySongs = _deduplicateSongs(visibleSongs);
    if (_currentQueue.isEmpty) {
      _currentQueue = List<SongModel>.from(_fallbackLibrarySongs);
    }
    try {
      final SharedPreferences prefs = await _getPrefs();
      await prefs.reload();
      _loadTimestampsFromPrefs(prefs);
      final List<String> savedRecentIds =
          prefs.getStringList(_kRecentSongIdsKey) ?? <String>[];
      final List<String>? savedRecords =
      prefs.getStringList(_kRecentSongRecordsKey);
      final List<SongModel> resolvedRecents = <SongModel>[];
      final Set<int> seenIds = <int>{};
      final Set<String> seenPaths = <String>{};
      final Map<int, SongModel> cachedRecordsById = <int, SongModel>{};
      final Map<String, SongModel> cachedRecordsByPath = <String, SongModel>{};
      if (savedRecords != null && savedRecords.isNotEmpty) {
        for (final String jsonStr in savedRecords) {
          try {
            final dynamic decoded = jsonDecode(jsonStr);
            if (decoded is! Map) continue;
            final SongModel cached =
            SongModel(Map<dynamic, dynamic>.from(decoded));
            if (isSongHidden(cached.id, cached.data)) continue;
            cachedRecordsById[cached.id] = cached;
            if (cached.data.isNotEmpty) {
              cachedRecordsByPath[cached.data] = cached;
              cachedRecordsByPath[_normalizePath(cached.data)] = cached;
            }
          } catch (e) {
            debugPrint('Lotus hydrate cached decode failed: $e');
          }
        }
      }
      for (final String idStr in savedRecentIds) {
        final int? id = int.tryParse(idStr);
        if (id == null) continue;
        SongModel? match = _songLookupMap[id];
        if (match == null && cachedRecordsById.containsKey(id)) {
          final String cachedPath = cachedRecordsById[id]!.data;
          if (cachedPath.isNotEmpty) {
            match = _songPathLookupMap[cachedPath] ??
                _songPathLookupMap[_normalizePath(cachedPath)];
          }
        }
        match ??= cachedRecordsById[id];
        if (match != null && !isSongHidden(match.id, match.data)) {
          final String norm = _normalizePath(match.data);
          final bool idAdded = seenIds.add(match.id);
          final bool pathAdded = norm.isEmpty || seenPaths.add(norm);
          if (idAdded && pathAdded) resolvedRecents.add(match);
        }
      }
      if (resolvedRecents.isNotEmpty) {
        _recentSongs.clear();
        _recentSongs.addAll(resolvedRecents.take(_kMaxRecentHistory));
        _notifySafely();
      }
    } catch (e) {
      debugPrint('Lotus hydrateLastPlayed failed: $e');
    }
    if (_pendingNativeMediaId != null &&
        _songLookupMap.containsKey(_pendingNativeMediaId)) {
      final SongModel liveSong = _songLookupMap[_pendingNativeMediaId]!;
      _pendingNativeMediaId = null;
      _setActiveSong(liveSong);
      _anchorClockTo(_pendingNativePosMs, running: _isPlaying);
      _totalDurationMs = liveSong.duration ?? 0;
      _isFavorite = _favoriteSongIds.contains(liveSong.id);
      _updateProgressRatio();
      _notifySafely();
      return;
    }
    if (_activeSong == null) {
      final Map<String, dynamic>? meta =
      await _persistence.getLastPlayedMetadata();
      final int savedPos = (meta?['positionMs'] as num?)?.toInt() ?? 0;
      final SongModel? restored =
      await _persistence.restoreLastPlayedSong(visibleSongs);
      final SongModel? target = restored ??
          (_recentSongs.isNotEmpty
              ? _recentSongs.first
              : (_fallbackLibrarySongs.isNotEmpty
              ? _fallbackLibrarySongs.first
              : null));
      if (target != null) _setActiveSong(target);
      if (_activeSong != null) {
        _anchorClockTo(savedPos, running: false);
        _totalDurationMs = _activeSong!.duration ?? 0;
        _isPlaying = false;
        isPlayingNotifier.value = false;
        _updateProgressRatio();
        _isFavorite = _favoriteSongIds.contains(_activeSong!.id);
        _notifySafely();
      }
    }
  }

  void notifySongUpdated(
      SongModel updatedSong, {
        String? coverPath,
        bool removeCover = false,
      }) {
    _songLookupMap[updatedSong.id] = updatedSong;
    if (updatedSong.data.isNotEmpty) {
      _songPathLookupMap[updatedSong.data] = updatedSong;
      _songPathLookupMap[_normalizePath(updatedSong.data)] = updatedSong;
    }
    final int libIndex = _fallbackLibrarySongs
        .indexWhere((SongModel s) => s.id == updatedSong.id);
    if (libIndex != -1) _fallbackLibrarySongs[libIndex] = updatedSong;

    final int queueIndex =
    _currentQueue.indexWhere((SongModel s) => s.id == updatedSong.id);
    if (queueIndex != -1) _currentQueue[queueIndex] = updatedSong;

    final int recentIndex =
    _recentSongs.indexWhere((SongModel s) => s.id == updatedSong.id);
    if (recentIndex != -1) {
      _recentSongs[recentIndex] = updatedSong;
      unawaited(_persistRecentHistory());
    }

    if (_activeSong?.id == updatedSong.id) {
      _setActiveSong(updatedSong);
      _totalDurationMs = updatedSong.duration ?? _totalDurationMs;
    }

    // Update Media3 timeline/notification whether the song is currently active or queued
    unawaited(_media3.updateSongMetadata(
      songId: updatedSong.id,
      albumId: updatedSong.albumId,
      title: updatedSong.title,
      artist: updatedSong.artist ?? 'Unknown Artist',
      album: updatedSong.album ?? 'Unknown Album',
      coverPath: coverPath,
      removeCover: removeCover,
    ));

    songMetadataRevisionNotifier.value++;
    _notifySafely();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _media3EventSub?.cancel();
    _positionTicker?.cancel();
    _recentSaveTimer?.cancel();
    _playbackClock.stop();
    _favoriteChangeController.close();
    _hiddenSongsChangeController.close();
    positionNotifier.dispose();
    progressRatioNotifier.dispose();
    isPlayingNotifier.dispose();
    repeatModeNotifier.dispose();
    shuffleNotifier.dispose();
    activeSongIdNotifier.dispose();
    songMetadataRevisionNotifier.dispose();
    super.dispose();
  }
}