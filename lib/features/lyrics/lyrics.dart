import 'package:flutter/foundation.dart';

/// A word of a lyric line that the file gives its own time.
@immutable
class LyricWord {
  const LyricWord(this.text, this.time);

  /// The word as written in the file, with any space after it.
  final String text;
  final Duration time;
}

/// One line of lyrics. [time] is when it starts being sung, for synced lyrics.
@immutable
class LyricLine {
  const LyricLine(this.text, [this.time, this.words = const [], this.end]);

  /// Empty for an instrumental gap in synced lyrics. May hold more than one
  /// line of text when the file gives several for the same moment.
  final String text;
  final Duration? time;

  /// The line's words with their own times, when the file times each word.
  /// Empty for the usual case of one time per line.
  final List<LyricWord> words;

  /// When the last word ends, if the file says.
  final Duration? end;
}

/// A track's lyrics, either time-synced or plain text.
@immutable
class Lyrics {
  const Lyrics(this.lines, {required this.synced});

  final List<LyricLine> lines;

  /// Whether every line carries a time, so the current one can be followed.
  final bool synced;

  /// Whether the file times individual words, not just lines.
  bool get wordSynced => lines.any((line) => line.words.isNotEmpty);

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
final _wordTime = RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');

/// How many untimed lines directly under a timed one are taken as part of
/// it. More than this is not a wrapped lyric but stray text.
const _maxContinuationLines = 2;

/// A timestamped line while the file is being read.
class _Timed {
  _Timed(this.time, this.text, this.order, this.words, this.end);

  Duration time;
  String text;

  /// Position in the file, which keeps equal times in the file's order.
  final int order;
  List<LyricWord> words;
  Duration? end;
  int continued = 0;
}

/// Parses LRC or plain-text lyrics. Returns null when the text has no lyric
/// lines at all, so callers can treat it as "no lyrics" or an invalid file.
///
/// Understands `[mm:ss]`, `[mm:ss.xx]` and `[mm:ss.xxx]` stamps, several
/// stamps on one line, the `[offset:±ms]` tag, and skips information tags
/// such as `[ar:…]`. Word-level `<mm:ss.xx>` stamps are kept as the times of
/// the line's words.
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

    final (:text, :words, :end) = _splitWords(rest);
    if (times.isNotEmpty) {
      // Word times belong to one singing of the line; a line stamped for
      // several moments keeps only its line times.
      final single = times.length == 1;
      open = [
        for (final (index, time) in times.indexed)
          _Timed(
            time,
            text,
            timed.length + index,
            single ? words : const [],
            single ? end : null,
          ),
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
            // The text is no longer what the word times describe.
            ..words = const []
            ..end = null
            ..continued += 1;
        }
      }
    }
  }

  if (timed.isNotEmpty) {
    // A positive offset means the lyrics should appear that much sooner.
    Duration shifted(Duration time) =>
        time > offset ? time - offset : Duration.zero;
    for (final line in timed) {
      line
        ..time = shifted(line.time)
        ..words = [
          for (final word in line.words)
            LyricWord(word.text, shifted(word.time)),
        ]
        ..end = line.end == null ? null : shifted(line.end!);
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
        // Two texts in one row: neither set of word times fits it.
        lines[lines.length - 1] = LyricLine(
          last.text.isEmpty ? line.text : '${last.text}\n${line.text}',
          last.time,
        );
      } else if (line.text.isEmpty && last != null && last.text.isEmpty) {
        continue;
      } else {
        lines.add(LyricLine(line.text, line.time, line.words, line.end));
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

/// Takes the `<mm:ss.xx>` stamps out of a line: its text without them, the
/// words they time, and the time of a closing stamp with nothing after it.
({String text, List<LyricWord> words, Duration? end}) _splitWords(String rest) {
  final stamps = _wordTime.allMatches(rest).toList();
  if (stamps.isEmpty) return (text: rest.trim(), words: const [], end: null);

  final words = <LyricWord>[];
  Duration? end;
  final text = StringBuffer(rest.substring(0, stamps.first.start));
  for (final (index, stamp) in stamps.indexed) {
    final next = index + 1 < stamps.length
        ? stamps[index + 1].start
        : rest.length;
    final piece = rest.substring(stamp.end, next);
    if (piece.trim().isNotEmpty) {
      words.add(LyricWord(piece, _duration(stamp)));
    } else if (index == stamps.length - 1) {
      end = _duration(stamp);
    }
    text.write(piece);
  }
  return (text: text.toString().trim(), words: words, end: end);
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
