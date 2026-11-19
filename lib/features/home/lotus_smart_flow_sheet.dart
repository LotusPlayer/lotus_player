import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/lotus_playback_provider.dart';
import '../../core/services/lotus_equalizer_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_widgets.dart';

class LotusSmartFlowSheet extends StatefulWidget {
  final List<SongModel> allSongs;
  final SongModel? referenceSong;
  final ValueChanged<List<SongModel>>? onFlowCompiled;

  const LotusSmartFlowSheet({
    super.key,
    required this.allSongs,
    this.referenceSong,
    this.onFlowCompiled,
  });

  static Future<void> show(
      BuildContext context, {
        required List<SongModel> allSongs,
        SongModel? referenceSong,
        ValueChanged<List<SongModel>>? onFlowCompiled,
      }) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      elevation: 0,
      builder: (BuildContext ctx) => LotusSmartFlowSheet(
        allSongs: allSongs,
        referenceSong: referenceSong,
        onFlowCompiled: onFlowCompiled,
      ),
    );
  }

  @override
  State<LotusSmartFlowSheet> createState() => _LotusSmartFlowSheetState();
}

class _LotusSmartFlowSheetState extends State<LotusSmartFlowSheet> {
  final LotusThemeController _theme = LotusThemeController.instance;
  final LotusPlaybackProvider _playback = LotusPlaybackProvider.instance;

  static const String _kSmartFlowRulesKey = 'lotus_smart_flow_rules_v2';
  static const String _kRecentSongIdsKey = 'lotus_recent_song_history_ids';

  // Configurable Rule Parameters
  int _queueSize = 25;
  double _artistAffinity = 0.4;
  String _formatPriority = 'LOSSLESS';
  bool _autoEngagePeq = true;
  bool _avoidRecentHistory = false;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
    _loadSavedRules();
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedRules() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kSmartFlowRulesKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
        _queueSize = decoded['queueSize'] as int? ?? 25;
        _artistAffinity =
            (decoded['artistAffinityRatio'] as num?)?.toDouble() ?? 0.4;
        _formatPriority = decoded['formatPriority'] as String? ?? 'LOSSLESS';
        _autoEngagePeq = decoded['autoEngagePeq'] as bool? ?? true;
        _avoidRecentHistory = decoded['avoidRecentHistory'] as bool? ?? false;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _persistRules() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> rules = <String, dynamic>{
        'queueSize': _queueSize,
        'artistAffinityRatio': _artistAffinity,
        'formatPriority': _formatPriority,
        'autoEngagePeq': _autoEngagePeq,
        'avoidRecentHistory': _avoidRecentHistory,
      };
      await prefs.setString(_kSmartFlowRulesKey, jsonEncode(rules));
    } catch (_) {}
  }

  Future<void> _compileAndLaunchFlow() async {
    HapticFeedback.heavyImpact();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    await _persistRules();

    final List<SongModel> visibleSongs = widget.allSongs
        .where((SongModel s) => !_playback.isSongHidden(s.id, s.data))
        .toList();

    if (visibleSongs.isEmpty) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final SongModel? candidateLead = widget.referenceSong ?? _playback.activeSong;
    final SongModel leadSong = (candidateLead != null &&
        !_playback.isSongHidden(candidateLead.id, candidateLead.data))
        ? candidateLead
        : visibleSongs.first;

    final String targetArtist = (leadSong.artist ?? '').toLowerCase().trim();
    final List<SongModel> compiledQueue = <SongModel>[];
    final Set<int> addedIds = <int>{leadSong.id};

    final Set<int> recentExcludedIds = <int>{};
    if (_avoidRecentHistory) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final List<String> recentStrings =
            prefs.getStringList(_kRecentSongIdsKey) ?? <String>[];
        for (final String s in recentStrings) {
          final int? id = int.tryParse(s);
          if (id != null && id != leadSong.id) recentExcludedIds.add(id);
        }
      } catch (_) {}
    }

    List<SongModel> eligibleSongs = visibleSongs.where((SongModel s) {
      if (s.id == leadSong.id) return false;
      if (_avoidRecentHistory && recentExcludedIds.contains(s.id)) return false;
      return true;
    }).toList();

    if (eligibleSongs.length < _queueSize) {
      eligibleSongs =
          visibleSongs.where((SongModel s) => s.id != leadSong.id).toList();
    }

    final int artistQuota =
    ((_queueSize - 1) * _artistAffinity).round().clamp(0, _queueSize - 1);

    if (artistQuota > 0 &&
        targetArtist.isNotEmpty &&
        !targetArtist.contains('<unknown>')) {
      final List<SongModel> artistMatches = eligibleSongs.where((SongModel s) {
        return (s.artist ?? '').toLowerCase().contains(targetArtist);
      }).toList()
        ..shuffle();

      for (final SongModel s in artistMatches.take(artistQuota)) {
        if (addedIds.add(s.id)) {
          compiledQueue.add(s);
        }
      }
    }

    final List<SongModel> formatCandidates = eligibleSongs.where((SongModel s) {
      if (addedIds.contains(s.id)) return false;
      final String ext = s.fileExtension.toLowerCase();
      if (_formatPriority == 'STUDIO_DSD') {
        return ext.contains('dsd') || ext.contains('dff') || ext.contains('dsf');
      } else if (_formatPriority == 'LOSSLESS') {
        return ext.contains('flac') ||
            ext.contains('dsd') ||
            ext.contains('wav') ||
            ext.contains('alac');
      }
      return true;
    }).toList()
      ..shuffle();

    final int remainingNeeded =
    (_queueSize - compiledQueue.length - 1).clamp(0, _queueSize);
    for (final SongModel s in formatCandidates.take(remainingNeeded)) {
      if (addedIds.add(s.id)) {
        compiledQueue.add(s);
      }
    }

    final int deficit =
    (_queueSize - 1 - compiledQueue.length).clamp(0, _queueSize);
    if (deficit > 0) {
      final List<SongModel> fallbackFillers = eligibleSongs.where((SongModel s) {
        return !addedIds.contains(s.id);
      }).toList()
        ..shuffle();

      for (final SongModel s in fallbackFillers.take(deficit)) {
        if (addedIds.add(s.id)) {
          compiledQueue.add(s);
        }
      }
    }

    compiledQueue.insert(0, leadSong);

    if (_autoEngagePeq) {
      try {
        await LotusEqualizerService.instance.toggleEnabled(true);
      } catch (_) {}
    }

    _playback.playSong(leadSong, queue: compiledQueue);
    widget.onFlowCompiled?.call(compiledQueue);

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    final Color accent = _theme.primaryAccent;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: _theme.containerHighColor,
        content: Row(
          children: <Widget>[
            Icon(Icons.all_inclusive_rounded, color: accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Smart Flow Compiled: ${compiledQueue.length} stems queued • ${_autoEngagePeq ? "10-Band EQ Engaged" : "Bit-Perfect Direct"}',
                style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetToHarmonicDefaults() {
    HapticFeedback.selectionClick();
    setState(() {
      _queueSize = 25;
      _artistAffinity = 0.4;
      _formatPriority = 'LOSSLESS';
      _autoEngagePeq = true;
      _avoidRecentHistory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (BuildContext context, Widget? child) {
        final Color accent = _theme.primaryAccent;
        final Color secondaryAccent = _theme.secondaryAccent;
        final bool isWhitaniana = _theme.isWhitanianaActive;

        final Color modalShieldSurface = _theme.modalSurfaceColor;
        final Color modalContainerLow = _theme.modalContainerLowColor;

        final Color dialogBorderColor = isWhitaniana
            ? _theme.cardBorderColor
            : accent.withValues(alpha: 0.85);

        final SongModel? targetLead =
            widget.referenceSong ?? _playback.activeSong;

        const BorderRadius topRadius =
        BorderRadius.vertical(top: Radius.circular(30));

        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.86,
            decoration: BoxDecoration(
              borderRadius: topRadius,
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
              borderRadius: topRadius,
              child: Container(
                color: modalShieldSurface,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: topRadius,
                    border: Border.all(
                      color: dialogBorderColor,
                      width: 1.6,
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      _buildDragHandle(),
                      _buildHeader(accent, secondaryAccent),
                      Divider(color: _theme.cardBorderColor, height: 1),
                      Expanded(
                        child: _isLoading
                            ? Center(
                            child:
                            CircularProgressIndicator(color: accent))
                            : SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18.0, vertical: 12.0),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                            children: <Widget>[
                              if (targetLead != null)
                                _buildReferenceTrackCard(
                                    targetLead,
                                    accent,
                                    secondaryAccent,
                                    modalContainerLow),
                              const SizedBox(height: 14),
                              _buildQueueSizeSliderCard(
                                  accent, modalContainerLow),
                              const SizedBox(height: 14),
                              _buildArtistAffinityCard(accent,
                                  secondaryAccent, modalContainerLow),
                              const SizedBox(height: 14),
                              _buildFormatPrioritySelector(accent,
                                  secondaryAccent, modalContainerLow),
                              const SizedBox(height: 14),
                              _buildHarmonicTuningSwitches(accent,
                                  secondaryAccent, modalContainerLow),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      _buildBottomActionButtons(accent, modalShieldSurface),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Padding(
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
    );
  }

  Widget _buildHeader(Color accent, Color secondaryAccent) {
    final Color textPrimary = _theme.textPrimaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 10),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border:
              Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
            ),
            child: Icon(Icons.all_inclusive_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Smart Flow Rules',
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Automated Queue & Calibrated Stems',
                  style: TextStyle(
                      color: accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _resetToHarmonicDefaults,
            child: Text(
              'DEFAULTS',
              style: TextStyle(
                  color: secondaryAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close_rounded,
                color: _theme.textSecondaryColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceTrackCard(SongModel song, Color accent,
      Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isWhitaniana
                ? _theme.cardBorderColor
                : accent.withValues(alpha: 0.4),
            width: 1.0),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Row(
        children: <Widget>[
          LotusArtworkThumb(
            songId: song.id,
            size: 44,
            borderRadius: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist ?? '<Unknown Artist>',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.5)),
              ),
              child: Text(
                'ANCHOR',
                style: TextStyle(
                  color: accent,
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

  Widget _buildQueueSizeSliderCard(Color accent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Container(
      padding: const EdgeInsets.all(14),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  'Generated Queue Size',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$_queueSize STEMS',
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total number of continuous lossless tracks compiled in the session.',
            style: TextStyle(color: textSecondary, fontSize: 10.5),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: accent,
              inactiveTrackColor:
              isWhitaniana ? const Color(0xFFCBD5E1) : Colors.white12,
              thumbColor: isWhitaniana ? accent : Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _queueSize.toDouble(),
              min: 10,
              max: 50,
              divisions: 8,
              onChanged: (double val) {
                HapticFeedback.selectionClick();
                setState(() => _queueSize = val.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistAffinityCard(
      Color accent, Color secondaryAccent, Color containerLow) {
    final int percentage = (_artistAffinity * 100).round();
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Container(
      padding: const EdgeInsets.all(14),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  'Artist Affinity Weight',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: secondaryAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$percentage% SAME ARTIST',
                    style: TextStyle(
                        color: secondaryAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            percentage == 0
                ? 'Eclectic Mode: Random variety across all vault artists.'
                : (percentage > 70
                ? 'Deep Dive Mode: Heavy concentration on the current performer.'
                : 'Balanced Flow: Smooth blend of the current artist and related stems.'),
            style: TextStyle(color: textSecondary, fontSize: 10.5),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: secondaryAccent,
              inactiveTrackColor:
              isWhitaniana ? const Color(0xFFCBD5E1) : Colors.white12,
              thumbColor: isWhitaniana ? secondaryAccent : Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _artistAffinity,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              onChanged: (double val) {
                HapticFeedback.selectionClick();
                setState(() => _artistAffinity = val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatPrioritySelector(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _theme.cardBorderColor),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Audio Format Priority',
            style: TextStyle(
                color: textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Filter which file encodings are prioritized when assembling the queue.',
            style: TextStyle(color: textSecondary, fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildPriorityChip(
                  keyId: 'LOSSLESS',
                  title: 'Lossless Only',
                  sub: 'FLAC/DSD/WAV',
                  isSelected: _formatPriority == 'LOSSLESS',
                  color: accent,
                  containerLow: containerLow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriorityChip(
                  keyId: 'STUDIO_DSD',
                  title: 'Studio DSD',
                  sub: 'DSD64 to 512',
                  isSelected: _formatPriority == 'STUDIO_DSD',
                  color: LotusColors.solarGold,
                  containerLow: containerLow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriorityChip(
                  keyId: 'ALL',
                  title: 'All Formats',
                  sub: 'Any Audio Stem',
                  isSelected: _formatPriority == 'ALL',
                  color: secondaryAccent,
                  containerLow: containerLow,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityChip({
    required String keyId,
    required String title,
    required String sub,
    required bool isSelected,
    required Color color,
    required Color containerLow,
  }) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _formatPriority = keyId);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isWhitaniana ? 0.16 : 0.18)
              : (isWhitaniana
              ? _theme.containerColor
              : _theme.containerLowestColor),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : _theme.cardBorderColor,
            width: isSelected ? 1.4 : 0.8,
          ),
          boxShadow: isWhitaniana && isSelected
              ? LotusDecorations.whitanianaCardShadow()
              : null,
        ),
        child: Column(
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected
                    ? (isWhitaniana ? color : Colors.white)
                    : (isWhitaniana ? textPrimary : textSecondary),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                sub,
                style: TextStyle(
                  color: isSelected ? color : _theme.textTertiaryColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHarmonicTuningSwitches(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _theme.cardBorderColor),
        boxShadow: isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
      ),
      child: Column(
        children: <Widget>[
          _buildSwitchRow(
            icon: Icons.tune_rounded,
            iconColor: LotusColors.solarGold,
            title: 'Auto-Engage 10-Band Equalizer',
            sub: 'Activates the 10-band graphic equalizer when Flow initiates',
            value: _autoEngagePeq,
            onChanged: (bool v) => setState(() => _autoEngagePeq = v),
          ),
          Divider(color: _theme.cardBorderColor, height: 16),
          _buildSwitchRow(
            icon: Icons.history_toggle_off_rounded,
            iconColor: secondaryAccent,
            title: 'Avoid Recently Played Stems',
            sub:
            'Excludes songs played within the last 48 hours for fresh variety',
            value: _avoidRecentHistory,
            onChanged: (bool v) => setState(() => _avoidRecentHistory = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textSecondary, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          activeThumbColor: iconColor,
          activeTrackColor: iconColor.withValues(alpha: 0.35),
          inactiveThumbColor: isWhitaniana
              ? const Color(0xFF94A3B8)
              : LotusColors.textSecondary,
          inactiveTrackColor:
          isWhitaniana ? const Color(0xFFCBD5E1) : Colors.white12,
          onChanged: (bool v) {
            HapticFeedback.lightImpact();
            onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _buildBottomActionButtons(Color accent, Color modalShieldSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
      decoration: BoxDecoration(
        color: modalShieldSurface,
        border: Border(top: BorderSide(color: _theme.cardBorderColor)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextButton(
              onPressed: () {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                'CANCEL',
                style: TextStyle(
                    color: _theme.textSecondaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: _theme.activeGradient,
                boxShadow: LotusDecorations.glowShadow(accent,
                    intensity: 0.35, blur: 16),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(23),
                  onTap: _compileAndLaunchFlow,
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'LAUNCH SMART FLOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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