import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// High-performance in-memory artwork cache that queries MediaStore/file tags
/// once per song ID and serves all subsequent requests from RAM.
class LotusArtworkCache {
  LotusArtworkCache._();
  static final LotusArtworkCache instance = LotusArtworkCache._();

  static const MethodChannel _channel =
  MethodChannel('com.souljalazian.lotus_player/artwork_cache');

  static const int _maxEntries = 500;
  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  final Set<int> _inflight = <int>{};
  final Map<int, List<void Function(Uint8List?)>> _callbacks = {};
  int _generation = 0;

  /// Broadcasts songId when evicted (-1 means all entries were evicted).
  final StreamController<int> _evictionController =
  StreamController<int>.broadcast();
  Stream<int> get evictionStream => _evictionController.stream;

  Uint8List? get(int songId) {
    final Uint8List? bytes = _cache.remove(songId);
    if (bytes != null) {
      _cache[songId] = bytes;
      return bytes.isEmpty ? null : bytes;
    }
    return null;
  }

  bool isResolved(int songId) => _cache.containsKey(songId);

  void requestArtwork(
      int songId, {
        int targetSize = 384,
        void Function(Uint8List?)? onLoaded,
      }) {
    if (songId <= 0) {
      onLoaded?.call(null);
      return;
    }

    if (_cache.containsKey(songId)) {
      onLoaded?.call(get(songId));
      return;
    }

    if (_inflight.contains(songId)) {
      if (onLoaded != null) {
        _callbacks.putIfAbsent(songId, () => []).add(onLoaded);
      }
      return;
    }

    final int requestGen = _generation;
    _inflight.add(songId);
    if (onLoaded != null) {
      _callbacks[songId] = [onLoaded];
    }

    _fetchArtwork(songId, targetSize: targetSize).then((Uint8List? bytes) {
      if (_generation != requestGen) return;
      _inflight.remove(songId);
      _put(songId, bytes);

      final callbacks = _callbacks.remove(songId) ?? [];
      for (final cb in callbacks) {
        cb(bytes);
      }
    }).catchError((Object e) {
      if (_generation != requestGen) return;
      _inflight.remove(songId);
      _put(songId, null);

      final callbacks = _callbacks.remove(songId) ?? [];
      for (final cb in callbacks) {
        cb(null);
      }

      if (kDebugMode) {
        debugPrint('⚠️ LotusArtworkCache: Error for song $songId: $e');
      }
    });
  }

  void _put(int songId, Uint8List? bytes) {
    _cache.remove(songId);
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[songId] = bytes ?? Uint8List(0);
  }

  Future<Uint8List?> _fetchArtwork(int songId, {int targetSize = 384}) async {
    try {
      final int dim = targetSize.clamp(128, 768);
      final dynamic result = await _channel.invokeMethod<dynamic>(
        'getArtwork',
        <String, dynamic>{
          'songId': songId,
          'width': dim,
          'height': dim,
        },
      );

      if (result is Uint8List && result.isNotEmpty) {
        return result;
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('❌ PlatformException for song $songId: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Unexpected error for song $songId: $e');
      return null;
    }
  }

  void prefetch(Iterable<int> songIds) {
    for (final int id in songIds) {
      if (id > 0 && !_cache.containsKey(id) && !_inflight.contains(id)) {
        requestArtwork(id);
      }
    }
  }

  Map<String, int> getStats() {
    return {
      'cached': _cache.length,
      'fetching': _inflight.length,
      'maxEntries': _maxEntries,
    };
  }

  void evict(int songId) {
    _cache.remove(songId);
    _inflight.remove(songId);
    _callbacks.remove(songId);
    if (!_evictionController.isClosed) {
      _evictionController.add(songId);
    }
  }

  void evictAll() {
    _generation++;
    _cache.clear();
    _inflight.clear();
    _callbacks.clear();
    if (!_evictionController.isClosed) {
      _evictionController.add(-1);
    }
  }
}