import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../core/services/lotus_lyrics_scraper_service.dart';
import '../../core/theme/lotus_theme.dart';
import '../../core/widgets/lotus_widgets.dart';

class LotusLyricsSyncDialog extends StatefulWidget {
  final SongModel song;
  final int initialOffsetMs;
  final ValueChanged<int> onOffsetChanged;
  final ValueChanged<String> onCustomLrcPasted;

  const LotusLyricsSyncDialog({
    super.key,
    required this.song,
    required this.initialOffsetMs,
    required this.onOffsetChanged,
    required this.onCustomLrcPasted,
  });

  static Future<void> show(
      BuildContext context, {
        required SongModel song,
        required int initialOffsetMs,
        required ValueChanged<int> onOffsetChanged,
        required ValueChanged<String> onCustomLrcPasted,
      }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (BuildContext ctx) => LotusLyricsSyncDialog(
        song: song,
        initialOffsetMs: initialOffsetMs,
        onOffsetChanged: onOffsetChanged,
        onCustomLrcPasted: onCustomLrcPasted,
      ),
    );
  }

  @override
  State<LotusLyricsSyncDialog> createState() => _LotusLyricsSyncDialogState();
}

class _LotusLyricsSyncDialogState extends State<LotusLyricsSyncDialog> {
  final LotusThemeController _theme = LotusThemeController.instance;
  late int _currentOffsetMs;
  final TextEditingController _pasteController = TextEditingController();
  bool _isPasteMode = false;

  @override
  void initState() {
    super.initState();
    _currentOffsetMs = widget.initialOffsetMs;
    _theme.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    _pasteController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _adjustOffset(int deltaMs) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentOffsetMs = (_currentOffsetMs + deltaMs).clamp(-15000, 15000);
    });
    widget.onOffsetChanged(_currentOffsetMs);
  }

  void _resetOffset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentOffsetMs = 0;
    });
    widget.onOffsetChanged(0);
  }

  Future<void> _handleClipboardPaste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _pasteController.text = data.text!;
      });
    }
  }

  void _commitPastedLrc() {
    final String content = _pasteController.text.trim();
    if (content.isEmpty) return;

    HapticFeedback.heavyImpact();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    widget.onCustomLrcPasted(content);

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      LotusSnackBar.create(
        borderColor: _theme.primaryAccent,
        content: Text(
          'Custom Lyrics Synced & Committed to Track Vault',
          style: TextStyle(
              color: _theme.isWhitanianaActive
                  ? LotusColors.whitanianaTextPrimary
                  : _theme.primaryAccent,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _theme.primaryAccent;
    final Color secondaryAccent = _theme.secondaryAccent;
    final bool isWhitaniana = _theme.isWhitanianaActive;

    final Color modalShieldSurface = _theme.modalSurfaceColor;
    final Color modalContainerLow = _theme.modalContainerLowColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: modalShieldSurface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isWhitaniana
                ? _theme.cardBorderColor
                : accent.withValues(alpha: 0.85),
            width: 1.6,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isWhitaniana ? 0.15 : 0.85),
              blurRadius: 36,
              spreadRadius: 8,
              offset: const Offset(0, 4),
            ),
            ...LotusDecorations.glowShadow(accent, intensity: 0.28, blur: 28),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildDialogHeader(accent),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _isPasteMode
                    ? _buildPasteBody(
                    accent, secondaryAccent, modalContainerLow)
                    : _buildCalibrateBody(
                    accent, secondaryAccent, modalContainerLow),
              ),
            ),
            _buildBottomButtons(accent, modalShieldSurface),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(Color accent) {
    final Color textPrimary = _theme.textPrimaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.sync_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isPasteMode
                  ? 'Paste & Parse Lyrics'
                  : 'Sync & Time Offset Calibrator',
              style: TextStyle(
                color: textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded,
                color: _theme.textSecondaryColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrateBody(
      Color accent, Color secondaryAccent, Color containerLow) {
    final double offsetSec = _currentOffsetMs / 1000.0;
    final String offsetText =
        '${offsetSec >= 0 ? "+" : ""}${offsetSec.toStringAsFixed(1)}s';
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: containerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isWhitaniana
                    ? _theme.cardBorderColor
                    : accent.withValues(alpha: 0.35)),
            boxShadow:
            isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.music_note_rounded, color: accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.song.title} • ${widget.song.artist ?? "Lotus Sanctuary"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isWhitaniana
                ? _theme.containerColor
                : _theme.containerLowestColor,
            border: Border.all(
              color: _currentOffsetMs != 0 ? secondaryAccent : accent,
              width: 1.8,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: isWhitaniana ? 0.08 : 0.6),
                blurRadius: 16,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: (_currentOffsetMs != 0 ? secondaryAccent : accent)
                    .withValues(alpha: 0.35),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('OFFSET',
                  style: TextStyle(
                      color: textSecondary,
                      fontSize: 9.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(
                offsetText,
                style: TextStyle(
                  color: _currentOffsetMs != 0 ? secondaryAccent : accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text('PRECISE SYNC',
                  style: TextStyle(
                      color: _theme.textTertiaryColor,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            _buildNudgeButton(
                '-0.5s', () => _adjustOffset(-500), containerLow),
            _buildNudgeButton(
                '-0.1s', () => _adjustOffset(-100), containerLow),
            _buildNudgeButton('RESET', _resetOffset, containerLow,
                isAction: true),
            _buildNudgeButton('+0.1s', () => _adjustOffset(100), containerLow),
            _buildNudgeButton('+0.5s', () => _adjustOffset(500), containerLow),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent, width: 1.0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  LotusLyricsScraperService.launchGoogleLyricsSearch(
                      widget.song);
                },
                icon: const Icon(Icons.travel_explore_rounded, size: 15),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Google Search',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryAccent.withValues(alpha: 0.22),
                  foregroundColor: secondaryAccent,
                  side: BorderSide(color: secondaryAccent, width: 1.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  visualDensity: VisualDensity.compact,
                  elevation: 0,
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isPasteMode = true);
                },
                icon: const Icon(Icons.content_paste_rounded, size: 15),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Paste Custom LRC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPasteBody(
      Color accent, Color secondaryAccent, Color containerLow) {
    final bool isWhitaniana = _theme.isWhitanianaActive;
    final Color textPrimary = _theme.textPrimaryColor;
    final Color textSecondary = _theme.textSecondaryColor;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: containerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isWhitaniana
                    ? _theme.cardBorderColor
                    : accent.withValues(alpha: 0.35)),
            boxShadow:
            isWhitaniana ? LotusDecorations.whitanianaCardShadow() : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded, color: accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Supports raw text or synchronized [mm:ss.xx] lines. Automatic parser aligns verses.',
                  style: TextStyle(color: textSecondary, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 130,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isWhitaniana
                ? _theme.containerColor
                : _theme.containerLowestColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _theme.cardBorderColor),
          ),
          child: Stack(
            children: <Widget>[
              TextField(
                controller: _pasteController,
                maxLines: null,
                expands: true,
                style: TextStyle(
                    color: textPrimary,
                    fontSize: 11.5,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText:
                  'Paste lyrics or .LRC content here...\n[00:15.20] First line of song...',
                  hintStyle:
                  TextStyle(color: _theme.textTertiaryColor, fontSize: 11),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(bottom: 36),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: _handleClipboardPaste,
                  icon: const Icon(Icons.paste_rounded, size: 13),
                  label: const Text('PASTE',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 9.5)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            TextButton(
              onPressed: () => setState(() => _isPasteMode = false),
              child: Text('Back to Offset',
                  style: TextStyle(color: textSecondary, fontSize: 11)),
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: secondaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: _commitPastedLrc,
              child: const Text('APPLY & PARSE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildNudgeButton(String label, VoidCallback onTap, Color containerLow,
      {bool isAction = false}) {
    final bool isWhitaniana = _theme.isWhitanianaActive;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isAction
              ? (isWhitaniana
              ? _theme.containerHighColor
              : _theme.modalContainerHighColor)
              : (isWhitaniana ? _theme.containerColor : containerLow),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAction ? LotusColors.solarGold : _theme.cardBorderColor,
          ),
          boxShadow: isWhitaniana && !isAction
              ? LotusDecorations.whitanianaCardShadow()
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isAction ? LotusColors.solarGold : _theme.textPrimaryColor,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(Color accent, Color modalShieldSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: modalShieldSurface,
        border: Border(top: BorderSide(color: _theme.cardBorderColor)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: _theme.textSecondaryColor),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CLOSE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: _theme.activeGradient,
                boxShadow: LotusDecorations.glowShadow(accent,
                    intensity: 0.3, blur: 14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(21),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).pop();
                  },
                  child: const Center(
                    child: Text(
                      'COMMIT SYNC',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                        letterSpacing: 0.5,
                      ),
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