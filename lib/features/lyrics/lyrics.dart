import 'package:flutter/foundation.dart';

/// One line of lyrics. [time] is when it starts being sung, for synced lyrics.
@immutable
class LyricLine {
  const LyricLine(this.text, [this.time]);

  /// Empty for an instrumental gap in synced lyrics. May hold more than one
  /// line of text when the file gives several for the same moment.
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

/// How many untimed lines directly under a timed one are taken as part of
/// it. More than this is not a wrapped lyric but stray text.
const _maxContinuationLines = 2;

/// A timestamped line while the file is being read.
class _Timed {
  _Timed(this.time, this.text, this.order);

  Duration time;
  String text;

  /// Position in the file, which keeps equal times in the file's order.
  final int order;
  int continued = 0;
}

/// Parses LRC or plain-text lyrics. Returns null when the text has no lyric
/// lines at all, so callers can treat it as "no lyrics" or an invalid file.
///
/// Understands `[mm:ss]`, `[mm:ss.xx]` and `[mm:ss.xxx]` stamps, several
/// stamps on one line, the `[offset:±ms]` tag, and skips information tags
/// such as `[ar:…]`. Word-level `<mm:ss.xx>` stamps are dropped, keeping the
/// line's own time.
///
/// Files in the wild are untidy, so for synced lyrics:
/// - lines that share a timestamp (a lyric and its translation, say) become
///   one row in the file's order, and exact repeats are dropped;
/// - an untimed line directly under a timed one is taken as the rest of it;
/// - several gaps in a row count as one.
/// No timestamp is ever made up: every row keeps a time the file gave.
Lyrics? parseLyrics(String source) {
  final timed = <_Timed>[];
  final plain = <String>[];
  var offset = Duration.zero;
  // What the previous line of the file produced, while untimed lines under
  // it can still continue it.
  var open = const <_Timed>[];

  for (final raw
      in source.replaceFirst('\u{FEFF}', '').split(RegExp(r'\r?\n'))) {
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
      open = [
        for (final (index, time) in times.indexed)
          _Timed(time, text, timed.length + index),
      ];
      timed.addAll(open);
    } else if (isMetadata) {
      open = const [];
    } else {
      plain.add(text);
      if (text.isEmpty) {
        open = const [];
      } else {
        for (final line in open) {
          if (line.continued >= _maxContinuationLines) continue;
          line
            ..text = line.text.isEmpty ? text : '${line.text}\n$text'
            ..continued += 1;
        }
      }
    }
  }

  if (timed.isNotEmpty) {
    for (final line in timed) {
      // A positive offset means the lyrics should appear that much sooner.
      line.time = line.time > offset ? line.time - offset : Duration.zero;
    }
    timed.sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });

    final lines = <LyricLine>[];
    for (final line in timed) {
      final last = lines.lastOrNull;
      if (last != null && last.time == line.time) {
        if (line.text.isEmpty || last.text.split('\n').contains(line.text)) {
          continue;
        }
        lines[lines.length - 1] = LyricLine(
          last.text.isEmpty ? line.text : '${last.text}\n${line.text}',
          last.time,
        );
      } else if (line.text.isEmpty && last != null && last.text.isEmpty) {
        continue;
      } else {
        lines.add(LyricLine(line.text, line.time));
      }
    }
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
