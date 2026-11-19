import 'dart:async';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../services/lotus_artwork_cache.dart';

class LotusArtworkImage extends StatefulWidget {
  final int songId;
  final double size;
  final double borderRadius;
  final Widget? nullArtworkWidget;
  final bool keepOldArtwork;

  const LotusArtworkImage({
    super.key,
    required this.songId,
    this.size = 46,
    this.borderRadius = 10,
    this.nullArtworkWidget,
    this.keepOldArtwork = false,
  });

  @override
  State<LotusArtworkImage> createState() => _LotusArtworkImageState();
}

class _LotusArtworkImageState extends State<LotusArtworkImage> {
  Uint8List? _bytes;
  bool _resolved = false;
  Object? _activeKey;
  StreamSubscription<int>? _evictionSub;

  @override
  void initState() {
    super.initState();
    _evictionSub =
        LotusArtworkCache.instance.evictionStream.listen((int evictedId) {
          if (!mounted) return;
          if (evictedId == widget.songId || evictedId == -1) {
            setState(() {
              _bytes = null;
              _resolved = false;
            });
            _loadArtwork();
          }
        });
    _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant LotusArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      if (!widget.keepOldArtwork) {
        _bytes = null;
        _resolved = false;
      }
      _loadArtwork();
    }
  }

  @override
  void dispose() {
    _evictionSub?.cancel();
    super.dispose();
  }

  void _loadArtwork() {
    final LotusArtworkCache cache = LotusArtworkCache.instance;

    if (cache.isResolved(widget.songId)) {
      _activeKey = null;
      _bytes = cache.get(widget.songId);
      _resolved = true;
      return;
    }

    final Object requestKey = Object();
    _activeKey = requestKey;
    final int decodeDim = (widget.size * 2).round().clamp(256, 768);

    cache.requestArtwork(
      widget.songId,
      targetSize: decodeDim,
      onLoaded: (Uint8List? bytes) {
        if (!mounted || _activeKey != requestKey) return;

        setState(() {
          _bytes = bytes;
          _resolved = true;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final artwork = _bytes;

    if (_resolved && artwork != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.memory(
          artwork,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: false,
          cacheWidth: (widget.size * 2).round().clamp(1, 768),
          errorBuilder: (BuildContext ctx, Object err, StackTrace? stack) {
            debugPrint(
                '⚠️ Failed to load artwork for song ${widget.songId}: $err');
            return _fallback();
          },
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return widget.nullArtworkWidget ??
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: Colors.white10,
          ),
          child: const Icon(Icons.music_note_rounded, color: Colors.white38),
        );
  }
}