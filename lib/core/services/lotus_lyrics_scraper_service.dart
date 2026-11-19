import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:url_launcher/url_launcher.dart';

/// Single parsed lyric line model supporting millisecond-precise timestamps
class LotusLyricLine {
  final Duration timestamp;
  final String text;
  final String? phoneticRomanized;
  final String? translationEnglish;
  final List<LotusWordTiming>? words;

  const LotusLyricLine({
    required this.timestamp,
    required this.text,
    this.phoneticRomanized,
    this.translationEnglish,
    this.words,
  });

  int get milliseconds => timestamp.inMilliseconds;

  /// Formatted standard LRC line tag: `[mm:ss.xx]`
  String get formattedTimestamp {
    final int safeMs = timestamp.inMilliseconds.clamp(0, 359999999);
    final int minutes = safeMs ~/ 60000;
    final int seconds = (safeMs % 60000) ~/ 1000;
    final int hundredths = (safeMs % 1000) ~/ 10;
    return '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}]';
  }
}

/// Word-by-word timing metadata for kinetic karaoke highlighting
class LotusWordTiming {
  final String word;
  final Duration startOffset;
  final Duration duration;

  const LotusWordTiming({
    required this.word,
    required this.startOffset,
    required this.duration,
  });
}

/// Complete parsed lyrics document with source telemetry and LRC exporter
class LotusLyricsDocument {
  final String title;
  final String artist;
  final String album;
  final String source;
  final bool isBilingual;
  final bool isWordByWord;
  final int offsetMilliseconds;
  final List<LotusLyricLine> lines;

  const LotusLyricsDocument({
    required this.title,
    required this.artist,
    required this.album,
    required this.source,
    required this.lines,
    this.isBilingual = false,
    this.isWordByWord = false,
    this.offsetMilliseconds = 0,
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  String toLrcString() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('[ti:$title]');
    buffer.writeln('[ar:$artist]');
    buffer.writeln('[al:$album]');
    buffer.writeln('[by:Lotus Player Harmonic Audio Engine]');
    if (offsetMilliseconds != 0) {
      buffer.writeln('[offset:$offsetMilliseconds]');
    }
    for (final LotusLyricLine line in lines) {
      buffer.writeln('${line.formattedTimestamp}${line.text}');
      if (line.translationEnglish != null &&
          line.translationEnglish!.isNotEmpty) {
        buffer.writeln(
            '${line.formattedTimestamp}[en] ${line.translationEnglish}');
      }
    }
    return buffer.toString();
  }
}

/// Core service handling metadata sanitization, physical .LRC checks, and LRCLIB cloud fetching
class LotusLyricsScraperService {
  static final LotusLyricsScraperService _instance =
  LotusLyricsScraperService._internal();
  factory LotusLyricsScraperService() => _instance;
  LotusLyricsScraperService._internal();

  static final RegExp _domainGarbageRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?(?:sm3na\.com|melody4arab\.com|dndnha\.com|nogomi\.com|myegy\.com|mp3clan|songs\.pk|mp3juices?|salmiya\.net|mawaly\.com)',
    caseSensitive: false,
  );

  static final RegExp _qualityGarbageRegex = RegExp(
    r'\b(?:320kbps|128kbps|256kbps|flac|mp3|wav|m4a|ogg|hd|4k|1080p|720p|rip|cdrip|web-dl|lossless)\b',
    caseSensitive: false,
  );

  static final RegExp _bracketJunkRegex = RegExp(
    r'\[(?:official\s*(?:video|audio|lyrics|music\s*video)?|lyrics|audio|video|remix|hd|4k|bonus\s*track|explicit|clean)?\]|\((?:official\s*(?:video|audio|lyrics|music\s*video)|lyrics\s*video|remastered(?:\s*\d{4})?|video\s*clip|mono|stereo)\)',
    caseSensitive: false,
  );

  static Map<String, String> sanitizeMetadata(SongModel song) {
    String rawTitle = song.title;
    String rawArtist = song.artist ?? '';

    rawTitle = rawTitle.replaceAll(_domainGarbageRegex, ' ').trim();
    rawArtist = rawArtist.replaceAll(_domainGarbageRegex, ' ').trim();
    rawTitle = rawTitle.replaceAll(_qualityGarbageRegex, ' ').trim();
    rawArtist = rawArtist.replaceAll(_qualityGarbageRegex, ' ').trim();

    rawTitle = rawTitle.replaceAll(_bracketJunkRegex, ' ').trim();

    rawTitle = rawTitle
        .replaceAll(
        RegExp(r'^(?:track\s*)?\d{1,2}[\s\._\-\–\—]+',
            caseSensitive: false),
        '')
        .trim();

    rawTitle = rawTitle.replaceAll(RegExp(r'[_.]+'), ' ').trim();
    rawArtist = rawArtist.replaceAll(RegExp(r'[_.]+'), ' ').trim();

    rawTitle = rawTitle
        .replaceAll(RegExp(r'^\s*[-_–—]+\s*|\s*[-_–—]+\s*$'), '')
        .trim();
    rawArtist = rawArtist
        .replaceAll(RegExp(r'^\s*[-_–—]+\s*|\s*[-_–—]+\s*$'), '')
        .trim();

    if (rawArtist.isEmpty ||
        rawArtist.toLowerCase().contains('unknown') ||
        rawArtist.toLowerCase() == '<unknown>') {
      final List<String> parts = rawTitle.split(RegExp(r'\s*[-–—]\s*'));
      if (parts.length >= 2) {
        rawArtist = parts[0].trim();
        rawTitle = parts.sublist(1).join(' ').trim();
      }
    }

    rawTitle = rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    rawArtist = rawArtist.replaceAll(RegExp(r'\s+'), ' ').trim();

    final String finalTitle =
    rawTitle.isEmpty ? (song.title.isNotEmpty ? song.title : 'Track') : rawTitle;
    final String finalArtist =
    (rawArtist.isEmpty || rawArtist.toLowerCase().contains('unknown'))
        ? ''
        : rawArtist;

    return <String, String>{
      'title': finalTitle,
      'artist': finalArtist,
    };
  }

  static String buildCleanSearchQuery(SongModel song) {
    final Map<String, String> cleaned = sanitizeMetadata(song);
    final String title = cleaned['title']!;
    final String artist = cleaned['artist']!;

    if (artist.isNotEmpty) {
      return '$title $artist lyrics';
    }
    return '$title lyrics';
  }

  static Uri buildGoogleSearchUri(SongModel song) {
    final String query = buildCleanSearchQuery(song);
    return Uri.https('www.google.com', '/search', <String, String>{'q': query});
  }

  static Future<bool> launchGoogleLyricsSearch(SongModel song) async {
    final Uri uri = buildGoogleSearchUri(song);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Lotus Player Google Search Launch Notice: $e');
      return false;
    }
  }

  /// Multi-tier lyrics retrieval:
  /// 1. Physical .LRC companion file on phone storage
  /// 2. Exact LRCLIB match (/api/get) via safe Uri.https
  /// 3. Fuzzy LRCLIB search (/api/search)
  /// 4. Clean empty state ready for manual paste/Google
  Future<LotusLyricsDocument> fetchLyricsForSong(SongModel song) async {
    final Map<String, String> cleaned = sanitizeMetadata(song);
    final String cleanTitle = cleaned['title']!;
    final String cleanArtist = cleaned['artist']!;
    final int? durationSec = (song.duration != null && song.duration! > 0)
        ? (song.duration! / 1000).round()
        : null;

    if (song.data.isNotEmpty) {
      try {
        final int lastDot = song.data.lastIndexOf('.');
        if (lastDot != -1) {
          final String lrcPath = '${song.data.substring(0, lastDot)}.lrc';
          final File localLrc = File(lrcPath);
          if (await localLrc.exists()) {
            final String content = await localLrc.readAsString();
            final LotusLyricsDocument doc = parseLrcContent(content,
                song: song, source: 'Local Storage (.LRC file)');
            if (doc.isNotEmpty) return doc;
          }
        }
      } catch (e) {
        debugPrint('Lotus Local .LRC file inspection notice: $e');
      }
    }

    if (cleanTitle.isNotEmpty) {
      try {
        final Map<String, String> queryParams = <String, String>{
          'track_name': cleanTitle,
          if (cleanArtist.isNotEmpty) 'artist_name': cleanArtist,
          if (durationSec != null && durationSec > 0)
            'duration': durationSec.toString(),
        };

        final Uri exactApiUrl = Uri.https('lrclib.net', '/api/get', queryParams);

        final http.Response response =
        await http.get(exactApiUrl, headers: <String, String>{
          'User-Agent':
          'LotusPlayer/3.2.0 (Android; Flutter; Bit-Perfect Audio Engine)',
        }).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final String? syncedLyrics = decoded['syncedLyrics'] as String?;
            if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
              return parseLrcContent(syncedLyrics,
                  song: song, source: 'LRCLIB Synced Cloud');
            }

            final String? plainLyrics = decoded['plainLyrics'] as String?;
            if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
              return _parsePlainLyricsToTimed(plainLyrics,
                  song: song, source: 'LRCLIB Plain Text');
            }
          }
        }
      } catch (e) {
        debugPrint('LRCLIB exact match notice: $e');
      }

      try {
        final String searchTerms =
        cleanArtist.isNotEmpty ? '$cleanTitle $cleanArtist' : cleanTitle;

        final Uri searchApiUrl = Uri.https('lrclib.net', '/api/search', <String, String>{
          'q': searchTerms,
        });

        final http.Response searchResponse =
        await http.get(searchApiUrl, headers: <String, String>{
          'User-Agent':
          'LotusPlayer/3.2.0 (Android; Flutter; Bit-Perfect Audio Engine)',
        }).timeout(const Duration(seconds: 4));

        if (searchResponse.statusCode == 200) {
          final dynamic decodedList = jsonDecode(searchResponse.body);
          if (decodedList is List && decodedList.isNotEmpty) {
            Map<String, dynamic>? bestCandidate;
            for (final dynamic item in decodedList) {
              if (item is Map<String, dynamic>) {
                final String? synced = item['syncedLyrics'] as String?;
                if (synced != null && synced.trim().isNotEmpty) {
                  bestCandidate = item;
                  break;
                }
              }
            }
            bestCandidate ??= decodedList.first as Map<String, dynamic>;

            final String? syncedLyrics =
            bestCandidate['syncedLyrics'] as String?;
            if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
              return parseLrcContent(syncedLyrics,
                  song: song, source: 'LRCLIB Synced Cloud (Matched)');
            }

            final String? plainLyrics =
            bestCandidate['plainLyrics'] as String?;
            if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
              return _parsePlainLyricsToTimed(plainLyrics,
                  song: song, source: 'LRCLIB Plain Text (Matched)');
            }
          }
        }
      } catch (e) {
        debugPrint('LRCLIB search fallback notice: $e');
      }
    }

    return LotusLyricsDocument(
      title: cleanTitle,
      artist: cleanArtist.isNotEmpty ? cleanArtist : (song.artist ?? ''),
      album: song.album ?? '',
      source: 'Google Search Ready',
      lines: <LotusLyricLine>[],
    );
  }

  /// Parses standard or variant .LRC timestamped string into a structured LotusLyricsDocument
  static LotusLyricsDocument parseLrcContent(
      String rawText, {
        required SongModel song,
        String source = 'Custom Paste',
      }) {
    final List<LotusLyricLine> parsedLines = <LotusLyricLine>[];
    final RegExp timeTagRegex =
    RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]');
    final List<String> rawLines = rawText.split('\n');

    int detectedOffset = 0;

    for (final String line in rawLines) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('[offset:')) {
        final String offsetStr =
        trimmed.replaceAll(RegExp(r'\[offset:|\]'), '');
        detectedOffset = int.tryParse(offsetStr) ?? 0;
        continue;
      }

      final Iterable<RegExpMatch> matches = timeTagRegex.allMatches(trimmed);
      if (matches.isEmpty) continue;

      final String lyricText = trimmed.replaceAll(timeTagRegex, '').trim();

      for (final RegExpMatch match in matches) {
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        int milliseconds = 0;

        if (match.group(3) != null) {
          final String rawFraction = match.group(3)!;
          final String padded = rawFraction.padRight(3, '0').substring(0, 3);
          milliseconds = int.parse(padded);
        }

        final Duration lineTime = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        parsedLines.add(
          LotusLyricLine(
            timestamp: lineTime,
            text: lyricText.isNotEmpty ? lyricText : '♪',
          ),
        );
      }
    }

    parsedLines.sort(
            (LotusLyricLine a, LotusLyricLine b) => a.timestamp.compareTo(b.timestamp));

    return LotusLyricsDocument(
      title: song.title,
      artist: song.artist ?? '',
      album: song.album ?? '',
      source: source,
      lines: parsedLines,
      offsetMilliseconds: detectedOffset,
    );
  }

  /// Converts un-timed plain text lyrics into evenly distributed lines across track duration
  static LotusLyricsDocument _parsePlainLyricsToTimed(
      String plainText, {
        required SongModel song,
        required String source,
      }) {
    final List<String> rawLines = plainText
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();

    final int totalDurationMs =
    (song.duration != null && song.duration! > 0) ? song.duration! : 240000;

    final List<LotusLyricLine> timedLines = <LotusLyricLine>[];

    if (rawLines.isNotEmpty) {
      final double intervalMs = totalDurationMs / (rawLines.length + 1);
      for (int i = 0; i < rawLines.length; i++) {
        final int lineMs = ((i + 1) * intervalMs).toInt();
        timedLines.add(
          LotusLyricLine(
            timestamp: Duration(milliseconds: lineMs),
            text: rawLines[i],
          ),
        );
      }
    }

    return LotusLyricsDocument(
      title: song.title,
      artist: song.artist ?? '',
      album: song.album ?? '',
      source: source,
      lines: timedLines,
    );
  }
}