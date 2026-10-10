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
}
