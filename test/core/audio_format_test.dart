import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/audio_format.dart';
import 'package:noctune/core/format.dart';
import 'package:noctune/data/models/track.dart';

Track _track({String? codec, int? sampleRate, int? bitDepth, int? bitrate}) =>
    Track(
      uri: '/a',
      fileName: 'a',
      folder: '/',
      title: 'a',
      codec: codec,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      bitrate: bitrate,
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  group('qualityLabel', () {
    test('describes CD-quality FLAC', () {
      final track = _track(
        codec: 'flac',
        sampleRate: 44100,
        bitDepth: 16,
        bitrate: 1011400,
      );

      expect(qualityLabel(track), 'FLAC · 16-bit / 44.1 kHz · 1,011 kbps');
      expect(isHiRes(track), isFalse);
    });

    test('describes hi-res FLAC', () {
      final track = _track(
        codec: 'flac',
        sampleRate: 96000,
        bitDepth: 24,
        bitrate: 2890000,
      );

      expect(qualityLabel(track), 'FLAC · 24-bit / 96 kHz · 2,890 kbps');
      expect(isHiRes(track), isTrue);
    });

    test('describes lossy and Dolby formats without calling them lossless', () {
      expect(
        qualityLabel(_track(codec: 'aac', sampleRate: 44100, bitrate: 256000)),
        'AAC · 44.1 kHz · 256 kbps',
      );
      expect(qualityLabel(_track(codec: 'eac3-joc')), 'Dolby Atmos');
      expect(isLossless('aac'), isFalse);
      expect(isLossless('eac3-joc'), isFalse);
      expect(isHiRes(_track(codec: 'aac', sampleRate: 96000)), isFalse);
    });

    test('copes with unknown formats', () {
      expect(qualityLabel(_track()), 'Unknown format');
      expect(codecLabel('wma'), 'WMA');
    });
  });

  group('formatDuration', () {
    test('formats minutes and hours', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(
        formatLongDuration(const Duration(hours: 12, minutes: 5)),
        '12 h 5 min',
      );
    });
  });
}
