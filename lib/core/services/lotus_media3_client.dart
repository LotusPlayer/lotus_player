import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../providers/lotus_playback_provider.dart';

class LotusMedia3Client {
  static const String _tag = 'LotusMedia3Client';
  static final LotusMedia3Client instance = LotusMedia3Client._();

  LotusMedia3Client._() {
    _initEventListener();
  }

  static const MethodChannel _controlsChannel =
  MethodChannel('com.souljalazian.lotus_player/media3_controls');
  static const EventChannel _eventsChannel =
  EventChannel('com.souljalazian.lotus_player/media3_events');

  final StreamController<Map<String, dynamic>> _playbackEventsController =
  StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get playbackEvents =>
      _playbackEventsController.stream;

  StreamSubscription<dynamic>? _eventSub;
  bool _disposed = false;

  void _initEventListener() {
    _eventSub?.cancel();
    _eventSub = _eventsChannel.receiveBroadcastStream().listen(
          (dynamic data) {
        if (_disposed) return;
        if (data is Map) {
          final Map<String, dynamic> eventMap = Map<String, dynamic>.from(data);
          if (eventMap['event'] == 'onSkipRequested') {
            final bool forward = eventMap['forward'] != false;
            forward
                ? LotusPlaybackProvider.instance.skipNext()
                : LotusPlaybackProvider.instance
                .skipPrevious(forcePrevious: true);
            return;
          }
          _playbackEventsController.add(eventMap);
        }
      },
      onError: (Object error) {
        debugPrint('$_tag: Event stream error: $error');
      },
    );

    _controlsChannel.setMethodCallHandler((MethodCall call) async {
      if (_disposed) return;
      switch (call.method) {
        case 'onNotificationFavoriteToggle':
          LotusPlaybackProvider.instance.toggleFavorite();
          break;
        case 'onSkipToNext':
          LotusPlaybackProvider.instance.skipNext();
          break;
        case 'onSkipToPrevious':
          LotusPlaybackProvider.instance.skipPrevious();
          break;
      }
    });
  }

  Future<void> play() async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>('play');
    } catch (e) {
      debugPrint('$_tag: play() failed — $e');
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>('pause');
    } catch (e) {
      debugPrint('$_tag: pause() failed — $e');
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('$_tag: stop() failed — $e');
    }
  }

  Future<void> updateFavoriteStatus(bool isFavorite, {int? songId}) async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>(
        'updateFavoriteStatus',
        <String, dynamic>{
          'isFavorite': isFavorite,
          if (songId != null) 'songId': songId,
        },
      );
    } catch (e) {
      debugPrint('$_tag: updateFavoriteStatus() failed — $e');
    }
  }

  Future<void> syncFavoriteIds(Iterable<int> favoriteIds) async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>(
        'syncFavoriteIds',
        <String, dynamic>{
          'favoriteIds': favoriteIds.toList(growable: false),
        },
      );
    } catch (e) {
      debugPrint('$_tag: syncFavoriteIds() failed — $e');
    }
  }

  Future<bool> updateSongMetadata({
    required int songId,
    int? albumId,
    required String title,
    required String artist,
    required String album,
    String? coverPath,
    bool removeCover = false,
  }) async {
    if (_disposed || songId <= 0) return false;
    try {
      final bool? ok = await _controlsChannel.invokeMethod<bool>(
        'updateSongMetadata',
        <String, dynamic>{
          'id': songId,
          if (albumId != null && albumId > 0) 'albumId': albumId,
          'title': title.isNotEmpty ? title : 'Audio Track',
          'artist': artist.isNotEmpty ? artist : 'Unknown Artist',
          'album': album.isNotEmpty ? album : 'Unknown Album',
          'coverPath': coverPath ?? '',
          'removeCover': removeCover,
        },
      );
      return ok == true;
    } catch (e) {
      debugPrint('$_tag: updateSongMetadata() failed — $e');
      return false;
    }
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>(
        'seek',
        <String, dynamic>{'positionMs': position.inMilliseconds},
      );
    } catch (e) {
      debugPrint('$_tag: seek() failed — $e');
    }
  }

  Future<void> skipToNext() async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>('skipToNext');
    } catch (e) {
      debugPrint('$_tag: skipToNext() failed — $e');
    }
  }

  Future<bool> skipToNextWithResult() async {
    if (_disposed) return false;
    try {
      final dynamic result =
      await _controlsChannel.invokeMethod<dynamic>('skipToNext');
      return result == true;
    } catch (e) {
      debugPrint('$_tag: skipToNextWithResult() failed — $e');
      return false;
    }
  }

  Future<void> skipToPrevious() async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>('skipToPrevious');
    } catch (e) {
      debugPrint('$_tag: skipToPrevious() failed — $e');
    }
  }

  Future<bool> skipToPreviousWithResult() async {
    if (_disposed) return false;
    try {
      final dynamic result =
      await _controlsChannel.invokeMethod<dynamic>('skipToPrevious');
      return result == true;
    } catch (e) {
      debugPrint('$_tag: skipToPreviousWithResult() failed — $e');
      return false;
    }
  }

  Future<void> setRepeatMode(int mode) async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>(
        'setRepeatMode',
        <String, dynamic>{'mode': mode},
      );
    } catch (e) {
      debugPrint('$_tag: setRepeatMode() failed — $e');
    }
  }

  Future<void> setShuffle(bool enabled) async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>(
        'setShuffle',
        <String, dynamic>{'enabled': enabled},
      );
    } catch (e) {
      debugPrint('$_tag: setShuffle() failed — $e');
    }
  }

  Future<void> setSpeedAndPitch({double speed = 1.0, double pitch = 1.0}) async {
    if (_disposed) return;
    try {
      await _controlsChannel.invokeMethod<bool>(
        'setSpeedAndPitch',
        <String, dynamic>{
          'speed': speed,
          'pitch': pitch,
        },
      );
    } catch (e) {
      debugPrint('$_tag: setSpeedAndPitch() failed — $e');
    }
  }

  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final double safeVolume = volume.clamp(0.0, 1.0);
    try {
      await _controlsChannel.invokeMethod<bool>(
        'setVolume',
        <String, dynamic>{'volume': safeVolume},
      );
    } catch (e) {
      debugPrint('$_tag: setVolume() failed — $e');
    }
  }

  List<Map<String, dynamic>> _serializeSongs(
      List<SongModel> songs, {
        Set<int>? favoriteIds,
      }) {
    return List<Map<String, dynamic>>.generate(songs.length, (int index) {
      final SongModel s = songs[index];

      String resolvedUri = s.data;
      if (resolvedUri.isEmpty && s.uri != null && s.uri!.isNotEmpty) {
        resolvedUri = s.uri!;
      }
      if (resolvedUri.isEmpty && s.id > 0) {
        resolvedUri = 'content://media/external/audio/media/${s.id}';
      }

      final String title = s.title.isNotEmpty ? s.title : 'Audio Track';
      final String artist = (s.artist != null && s.artist!.isNotEmpty)
          ? s.artist!
          : 'Unknown Artist';
      final String album = (s.album != null && s.album!.isNotEmpty)
          ? s.album!
          : 'Unknown Album';
      final int durationMs = s.duration ?? 0;

      return <String, dynamic>{
        'id': s.id,
        if (s.albumId != null && s.albumId! > 0) 'albumId': s.albumId,
        'uri': resolvedUri,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        if (favoriteIds != null) 'isFavorite': favoriteIds.contains(s.id),
      };
    }, growable: false);
  }

  Future<void> setPlaylist({
    required List<SongModel> songs,
    int startIndex = 0,
    int startPosMs = 0,
    Set<int>? favoriteIds,
  }) async {
    if (_disposed || songs.isEmpty) return;

    final List<Map<String, dynamic>> serializedSongs =
    _serializeSongs(songs, favoriteIds: favoriteIds);

    try {
      await _controlsChannel.invokeMethod<bool>(
        'setPlaylist',
        <String, dynamic>{
          'songs': serializedSongs,
          'startIndex': startIndex.clamp(0, songs.length - 1),
          'startPosMs': startPosMs < 0 ? 0 : startPosMs,
        },
      );
    } catch (e) {
      debugPrint('$_tag: setPlaylist() failed — $e');
    }
  }

  Future<bool> appendPlaylistItems(
      List<SongModel> songs, {
        Set<int>? favoriteIds,
      }) async {
    if (_disposed || songs.isEmpty) return true;
    try {
      final bool? ok = await _controlsChannel.invokeMethod<bool>(
        'appendPlaylistItems',
        <String, dynamic>{
          'songs': _serializeSongs(songs, favoriteIds: favoriteIds),
        },
      );
      return ok == true;
    } catch (e) {
      debugPrint('$_tag: appendPlaylistItems() failed — $e');
      return false;
    }
  }

  Future<bool> prependPlaylistItems(
      List<SongModel> songs, {
        required int insertAt,
        Set<int>? favoriteIds,
      }) async {
    if (_disposed || songs.isEmpty) return true;
    try {
      final bool? ok = await _controlsChannel.invokeMethod<bool>(
        'prependPlaylistItems',
        <String, dynamic>{
          'songs': _serializeSongs(songs, favoriteIds: favoriteIds),
          'insertAt': insertAt < 0 ? 0 : insertAt,
        },
      );
      return ok == true;
    } catch (e) {
      debugPrint('$_tag: prependPlaylistItems() failed — $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getPlaybackSnapshot() async {
    if (_disposed) return <String, dynamic>{};
    try {
      final dynamic result =
      await _controlsChannel.invokeMethod<dynamic>('getPlaybackSnapshot');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('$_tag: getPlaybackSnapshot() failed — $e');
    }
    return <String, dynamic>{};
  }

  void dispose() {
    _disposed = true;
    _eventSub?.cancel();
    _eventSub = null;
    _controlsChannel.setMethodCallHandler(null);
    _playbackEventsController.close();
  }
}