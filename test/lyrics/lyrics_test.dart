import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/lyrics/lyrics.dart';
import 'package:noctune/features/lyrics/lyrics_source.dart';

void main() {
  group('synced lyrics', () {
    test('parses minutes, seconds and fractions of any precision', () {
      final lyrics = parseLyrics(
        '[00:05]no fraction\n'
        '[00:12.5]tenths\n'
        '[00:20.25]hundredths\n'
        '[01:02.345]milliseconds\n'
        '[100:00.00]long\n',
      )!;

      expect(lyrics.synced, isTrue);
      expect(lyrics.lines.map((l) => l.time), const [
        Duration(seconds: 5),
        Duration(seconds: 12, milliseconds: 500),
        Duration(seconds: 20, milliseconds: 250),
        Duration(minutes: 1, seconds: 2, milliseconds: 345),
        Duration(minutes: 100),
      ]);
      expect(lyrics.lines[2].text, 'hundredths');
    });

    test('skips information tags and keeps instrumental gaps', () {
      final lyrics = parseLyrics(
        '[ti:Song]\n[ar:Artist]\n[length: 03:45]\n[by:someone]\n\n'
        '[00:10.00]First line\n'
        '[00:15.00]\n'
        '[00:20.00]Second line\n',
      )!;

      expect(lyrics.lines.map((l) => l.text), [
        'First line',
        '',
        'Second line',
      ]);
    });

    test('drops the singer marks of duet lyrics, such as "v1:"', () {
      final lyrics = parseLyrics(
        "[00:10.00]v1: I just can't say I don't love you\n"
        "[00:15.00]v2:'Cause I love you, yeah\n"
        '[00:20.00]v1: <00:20.00>Word <00:21.00>timed\n'
        '[00:25.00]Not a mark: v1: stays\n',
      )!;

      expect(lyrics.lines.map((l) => l.text), [
        "I just can't say I don't love you",
        "'Cause I love you, yeah",
        'Word timed',
        'Not a mark: v1: stays',
      ]);
    });

    test('repeats a line that carries several timestamps', () {
      final lyrics = parseLyrics(
        '[00:30.00][01:30.00]Chorus\n[00:10.00]Verse\n',
      )!;

      expect(lyrics.lines.map((l) => '${l.time!.inSeconds} ${l.text}'), [
        '10 Verse',
        '30 Chorus',
        '90 Chorus',
      ]);
    });

    test('applies the offset tag, wherever it appears', () {
      final sooner = parseLyrics('[00:10.00]Line\n[offset:+500]\n')!;
      final later = parseLyrics('[offset: -1500]\n[00:10.00]Line\n')!;
      final clamped = parseLyrics('[offset:60000]\n[00:10.00]Line\n')!;

      expect(sooner.lines.single.time, const Duration(milliseconds: 9500));
      expect(later.lines.single.time, const Duration(milliseconds: 11500));
      expect(clamped.lines.single.time, Duration.zero);
    });

    test('drops word-level timestamps but keeps the words', () {
      final lyrics = parseLyrics(
        '[00:10.00]<00:10.00>Hello <00:10.60>there <00:11.20>world\n',
      )!;

      expect(lyrics.lines.single.text, 'Hello there world');
    });

    test('keeps bracketed words that are part of the lyric', () {
      final lyrics = parseLyrics('[00:10.00][Chorus] Sing it\n')!;

      expect(lyrics.lines.single.text, '[Chorus] Sing it');
    });

    test('handles Windows line endings and a byte-order mark', () {
      final lyrics = parseLyrics('﻿[00:01.00]One\r\n[00:02.00]Two\r\n')!;

      expect(lyrics.lines.map((l) => l.text), ['One', 'Two']);
    });
  });

  group('following playback', () {
    final lyrics = parseLyrics('[00:10.00]A\n[00:20.00]B\n[00:30.00]C\n')!;
    int at(int ms) => lyrics.indexAt(Duration(milliseconds: ms));

    test('no line is active before the first one starts', () {
      expect(at(0), -1);
      expect(at(9999), -1);
    });

    test('a line is active from its own time until the next', () {
      expect(at(10000), 0);
      expect(at(19999), 0);
      expect(at(20000), 1);
      expect(at(29999), 1);
    });

    test('the last line stays active to the end', () {
      expect(at(30000), 2);
      expect(at(600000), 2);
    });

    test('seeking backwards and forwards lands on the right line', () {
      expect([at(31000), at(11000), at(25000), at(500)], [2, 0, 1, -1]);
    });
  });

  group('plain lyrics', () {
    test('are kept as text with single blank lines between verses', () {
      final lyrics = parseLyrics(
        '\n\nFirst verse\nstill first\n\n\n\nSecond verse\n\n',
      )!;

      expect(lyrics.synced, isFalse);
      expect(lyrics.lines.map((l) => l.text), [
        'First verse',
        'still first',
        '',
        'Second verse',
      ]);
      expect(lyrics.indexAt(const Duration(minutes: 1)), -1);
    });
  });

  group('unusable text', () {
    test('is reported as no lyrics', () {
      expect(parseLyrics(''), isNull);
      expect(parseLyrics('   \n\n  '), isNull);
      expect(parseLyrics('[ti:Only tags]\n[ar:Nobody]\n'), isNull);
      expect(parseLyrics('[00:10.00]\n[00:20.00]\n'), isNull);
    });
  });

  group('decodeLyricsBytes', () {
    test('reads UTF-8, including non-Latin scripts', () {
      const text = '[00:01.00]तिमी बिना';

      expect(decodeLyricsBytes(const Utf8Codec().encode(text)), text);
    });

    test('falls back to Latin-1 for older files', () {
      expect(decodeLyricsBytes([0x63, 0x61, 0x66, 0xE9]), 'café');
    });
  });

  group('untidy files', () {
    List<String> texts(String source) => [
      for (final line in parseLyrics(source)!.lines) line.text,
    ];

    test('lines sharing a timestamp become one row, in the file order', () {
      final lyrics = parseLyrics(
        '[00:10.00]Original\n[00:10.00]Translation\n[00:20.00]Next',
      )!;

      expect(lyrics.lines.map((l) => l.text), [
        'Original\nTranslation',
        'Next',
      ]);
      // Both are lit together, from the moment the file gives.
      expect(lyrics.indexAt(const Duration(seconds: 12)), 0);
      expect(lyrics.lines.first.time, const Duration(seconds: 10));
    });

    test('equal timestamps keep the file order however many there are', () {
      final source = [
        for (var i = 0; i < 12; i++) '[00:10.00]line $i',
        '[00:20.00]end',
      ].join('\n');

      expect(texts(source).first.split('\n'), [
        for (var i = 0; i < 12; i++) 'line $i',
      ]);
    });

    test('an exact repeat at the same time is dropped', () {
      expect(texts('[00:10.00]Same\n[00:10.00]Same\n[00:20.00]Next'), [
        'Same',
        'Next',
      ]);
    });

    test('an untimed line under a timed one is the rest of that line', () {
      expect(texts('[00:10.00]First half\nsecond half\n\n[00:20.00]Next\n'), [
        'First half\nsecond half',
        'Next',
      ]);
    });

    test('a blank line ends the continuation', () {
      expect(texts('[00:10.00]Line\n\nstray note\n[00:20.00]Next'), [
        'Line',
        'Next',
      ]);
    });

    test('a long run of untimed text is not swallowed into one line', () {
      expect(texts('[00:10.00]A\nb\nc\nd\ne\n[00:20.00]Next').first, 'A\nb\nc');
    });

    test('several gaps in a row count as one', () {
      final lyrics = parseLyrics(
        '[00:10.00]A\n[00:15.00]\n[00:16.00]\n[00:17.00]\n[00:20.00]B',
      )!;

      expect(lyrics.lines.map((l) => l.text), ['A', '', 'B']);
      expect(lyrics.lines[1].time, const Duration(seconds: 15));
    });

    test('every row keeps a time the file gave; none is made up', () {
      const source =
          '[00:10.00]A\ncontinued\n[00:10.00]A again\n[00:30.50]B\n[01:00]C';
      final given = {
        const Duration(seconds: 10),
        const Duration(seconds: 30, milliseconds: 500),
        const Duration(minutes: 1),
      };

      for (final line in parseLyrics(source)!.lines) {
        expect(given, contains(line.time));
      }
    });

    test('a file with no timestamps at all stays plain', () {
      final lyrics = parseLyrics('Just words\nNo times')!;

      expect(lyrics.synced, isFalse);
      expect(lyrics.indexAt(const Duration(seconds: 5)), -1);
    });
  });

  group('word timing', () {
    test('word stamps become the times of the words', () {
      final lyrics = parseLyrics(
        '[00:10.00]<00:10.00>One <00:10.40>two <00:11.30>three<00:11.90>\n'
        '[00:20.00]Plain line',
      )!;
      final first = lyrics.lines.first;

      expect(first.text, 'One two three');
      expect(first.words.map((w) => w.text.trim()), ['One', 'two', 'three']);
      expect(
        first.words[1].time,
        const Duration(seconds: 10, milliseconds: 400),
      );
      expect(first.end, const Duration(seconds: 11, milliseconds: 900));
      expect(lyrics.wordSynced, isTrue);
      expect(lyrics.lines.last.words, isEmpty);
    });

    test('the offset tag moves word times with their line', () {
      final line = parseLyrics(
        '[offset:500]\n[00:10.00]<00:10.00>One <00:11.00>two',
      )!.lines.single;

      expect(line.time, const Duration(seconds: 9, milliseconds: 500));
      expect(
        line.words.last.time,
        const Duration(seconds: 10, milliseconds: 500),
      );
    });

    test('ordinary files are not word-synced', () {
      expect(parseLyrics('[00:10.00]One two three')!.wordSynced, isFalse);
    });

    test('word times are dropped when they no longer describe the row', () {
      // Two texts at one moment, and a line stamped for two moments.
      final merged = parseLyrics(
        '[00:10.00]<00:10.00>One <00:10.40>two\n[00:10.00]Uno dos',
      )!;
      final repeated = parseLyrics(
        '[00:10.00][00:50.00]<00:10.00>One <00:10.40>two',
      )!;

      expect(merged.lines.single.words, isEmpty);
      expect(repeated.lines.every((line) => line.words.isEmpty), isTrue);
      expect(repeated.lines.first.text, 'One two');
    });
  });
}
