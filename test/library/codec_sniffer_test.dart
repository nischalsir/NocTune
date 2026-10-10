import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/audio_format.dart';
import 'package:noctune/features/library/scan/codec_sniffer.dart';

/// A WAV header declaring [formatTag], optionally in "extensible" form.
Uint8List _wav(int formatTag, {bool extensible = false}) {
  final bytes = BytesBuilder();
  void text(String value) => bytes.add(value.codeUnits);
  void u32(int value) => bytes.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u16(int value) => bytes.add(
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List(),
  );
  text('RIFF');
  u32(0);
  text('WAVE');
  // An unrelated chunk of odd length first, to exercise chunk walking.
  text('LIST');
  u32(3);
  bytes.add([1, 2, 3, 0]);
  text('fmt ');
  u32(extensible ? 40 : 16);
  u16(extensible ? 0xFFFE : formatTag);
  u16(2);
  u32(44100);
  u32(176400);
  u16(4);
  u16(16);
  if (extensible) {
    u16(22);
    u16(16);
    u32(3);
    u16(formatTag); // first two bytes of the sub-format
    bytes.add(List.filled(14, 0));
  }
  text('data');
  u32(0);
  return bytes.toBytes();
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('noctune_sniff'));
  tearDown(() => temp.deleteSync(recursive: true));

  String? sniff(String name, List<int> bytes) {
    final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
    return sniffCodec(file.path, name.split('.').last);
  }

  group('FLAC', () {
    test('is confirmed by its stream marker', () {
      expect(sniff('a.flac', [...'fLaC'.codeUnits, 0, 0, 0, 34]), 'flac');
    });

    test('is confirmed behind an ID3 tag', () {
      final id3 = [...'ID3'.codeUnits, 4, 0, 0, 0, 0, 0, 5, 9, 9, 9, 9, 9];

      expect(sniff('a.flac', [...id3, ...'fLaC'.codeUnits]), 'flac');
    });

    test('is not taken on the extension alone', () {
      expect(sniff('fake.flac', List.filled(64, 0x42)), isNull);
      expect(sniff('mp3-renamed.flac', [0xFF, 0xFB, 0x90, 0x00]), isNull);
      expect(sniff('empty.flac', const []), isNull);
    });
  });

  group('WAV', () {
    test('is lossless PCM when the header says so', () {
      expect(sniff('pcm.wav', _wav(1)), 'pcm');
      expect(sniff('float.wav', _wav(3)), 'pcm');
      expect(sniff('extensible.wav', _wav(1, extensible: true)), 'pcm');
    });

    test('is not lossless when it wraps a compressed format', () {
      expect(sniff('adpcm.wav', _wav(2)), 'wav');
      expect(sniff('mp3.wav', _wav(0x55)), 'wav');
      expect(sniff('ext-mp3.wav', _wav(0x55, extensible: true)), 'wav');
    });

    test('is unverified when the header is missing or broken', () {
      expect(sniff('junk.wav', List.filled(64, 7)), 'wav');
      expect(sniff('short.wav', 'RIFF'.codeUnits), 'wav');
    });
  });

  test('other extensions pass through unchanged', () {
    expect(sniff('a.mp3', [1, 2, 3]), 'mp3');
    expect(sniff('a.opus', [1, 2, 3]), 'opus');
  });

  test('a file that cannot be opened is unverified', () {
    expect(sniffCodec('${temp.path}/missing.flac', 'flac'), isNull);
  });

  group('format badges', () {
    ({bool lossless, bool atmos}) badges(
      String? codec, {
      bool decoder = true,
    }) => formatBadges(codec, deviceDecodesAtmos: decoder);

    test('verified lossless formats show LOSSLESS only', () {
      for (final codec in ['flac', 'alac', 'pcm']) {
        expect(badges(codec), (lossless: true, atmos: false), reason: codec);
      }
    });

    test('lossy formats show nothing', () {
      for (final codec in ['mp3', 'aac', 'opus', 'ogg', 'eac3', 'ac3']) {
        expect(badges(codec), (lossless: false, atmos: false), reason: codec);
      }
    });

    test('unverified and unknown formats show nothing', () {
      for (final codec in [null, 'wav', 'm4a', 'mp4', 'wma']) {
        expect(badges(codec), (
          lossless: false,
          atmos: false,
        ), reason: '$codec');
      }
    });

    test('Atmos needs Atmos content and a device that decodes it', () {
      expect(badges('eac3-joc'), (lossless: false, atmos: true));
      expect(badges('eac3-joc', decoder: false), (
        lossless: false,
        atmos: false,
      ));
    });

    test('a Dolby decoder never turns other audio into Atmos', () {
      for (final codec in ['flac', 'aac', 'eac3', 'ac3', null]) {
        expect(badges(codec).atmos, isFalse, reason: '$codec');
      }
    });
  });
}
