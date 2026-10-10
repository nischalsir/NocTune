import 'package:flutter/foundation.dart';

/// One line of lyrics. [time] is when it starts being sung, for synced lyrics.
@immutable
class LyricLine {
  const LyricLine(this.text, [this.time]);

  /// Empty for an instrumental gap in synced lyrics.
  final String text;
  final Duration? time;
}

/// A track's lyrics, either time-synced or plain text.
@immutable
class Lyrics {
  const Lyrics(this.lines, {required this.synced});

  final List<LyricLine> lines;

  /// Whether every line carries a time, so the current one can be followed.
  final bool synced;

  /// Index of the line being sung at [position], or -1 before the first line
  /// and for lyrics that aren't synced.
  int indexAt(Duration position) {
    if (!synced) return -1;
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].time! <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }
}

final _tag = RegExp(r'\[([^\]]*)\]');
final _timeTag = RegExp(r'^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$');
final _offsetTag = RegExp(r'^offset\s*:\s*([+-]?\d+)$', caseSensitive: false);
final _metadataTag = RegExp(r'^[a-zA-Z#]+\s*:');
final _wordTime = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

/// Parses LRC or plain-text lyrics. Returns null when the text has no lyric
/// lines at all, so callers can treat it as "no lyrics" or an invalid file.
///
/// Understands `[mm:ss]`, `[mm:ss.xx]` and `[mm:ss.xxx]` stamps, several
/// stamps on one line, the `[offset:±ms]` tag, and skips information tags
/// such as `[ar:…]`. Word-level `<mm:ss.xx>` stamps are dropped, keeping the
/// line's own time.
Lyrics? parseLyrics(String source) {
  final timed = <LyricLine>[];
  final plain = <String>[];
  var offset = Duration.zero;

  for (final raw in source.replaceFirst('﻿', '').split(RegExp(r'\r?\n'))) {
    var rest = raw.trim();
    final times = <Duration>[];
    var isMetadata = false;

    // Peel the bracketed tags off the front of the line.
    while (true) {
      final match = _tag.matchAsPrefix(rest);
      if (match == null) break;
      final content = match[1]!.trim();
      final time = _timeTag.firstMatch(content);
      final shift = _offsetTag.firstMatch(content);
      if (time != null) {
        times.add(_duration(time));
      } else if (shift != null) {
        offset = Duration(milliseconds: int.parse(shift[1]!));
        isMetadata = true;
      } else if (_metadataTag.hasMatch(content)) {
        isMetadata = true;
      } else {
        // Not a tag we know: it is part of the lyric, e.g. "[Chorus]".
        break;
      }
      rest = rest.substring(match.end).trimLeft();
    }

    final text = rest.replaceAll(_wordTime, '').trim();
    if (times.isNotEmpty) {
      for (final time in times) {
        timed.add(LyricLine(text, time));
      }
    } else if (!isMetadata) {
      plain.add(text);
    }
  }

  if (timed.isNotEmpty) {
    // A positive offset means the lyrics should appear that much sooner.
    final lines = [
      for (final line in timed)
        LyricLine(
          line.text,
          line.time! > offset ? line.time! - offset : Duration.zero,
        ),
    ]..sort((a, b) => a.time!.compareTo(b.time!));
    return lines.any((line) => line.text.isNotEmpty)
        ? Lyrics(lines, synced: true)
        : null;
  }

  // Plain text: keep single blank lines as verse breaks, drop the rest.
  final lines = <LyricLine>[];
  for (final text in plain) {
    if (text.isEmpty && (lines.isEmpty || lines.last.text.isEmpty)) continue;
    lines.add(LyricLine(text));
  }
  while (lines.isNotEmpty && lines.last.text.isEmpty) {
    lines.removeLast();
  }
  return lines.isEmpty ? null : Lyrics(lines, synced: false);
}

Duration _duration(RegExpMatch match) {
  final fraction = match[3];
  // ".5" is half a second, ".50" fifty hundredths, ".500" five hundred ms.
  final milliseconds = fraction == null
      ? 0
      : int.parse(fraction.padRight(3, '0'));
  return Duration(
    minutes: int.parse(match[1]!),
    seconds: int.parse(match[2]!),
    milliseconds: milliseconds,
  );
}
