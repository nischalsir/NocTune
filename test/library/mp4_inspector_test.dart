import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/library/scan/mp4_inspector.dart';

List<int> _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

List<int> _box(String type, List<int> payload) => [
  ..._u32(8 + payload.length),
  ...type.codeUnits,
  ...payload,
];

List<int> _mvhd({required int timescale, required int duration}) =>
    _box('mvhd', [
      ...List.filled(12, 0),
      ..._u32(timescale),
      ..._u32(duration),
      ...List.filled(80, 0),
    ]);

/// A track whose sample description holds one entry of [format].
List<int> _trak(
  String handler,
  String format, {
  List<int> children = const [],
}) => _box(
  'trak',
  _box('mdia', [
    ..._box('hdlr', [...List.filled(8, 0), ...handler.codeUnits]),
    ..._box(
      'minf',
      _box(
        'stbl',
        _box('stsd', [
          ...List.filled(4, 0),
          ..._u32(1),
          ..._box(format, [...List.filled(28, 0), ...children]),
        ]),
      ),
    ),
  ]),
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('noctune_mp4'));
  tearDown(() => temp.deleteSync(recursive: true));

  Mp4Info inspect(List<int> bytes) {
    final file = File('${temp.path}/sample.m4a')..writeAsBytesSync(bytes);
    final handle = file.openSync();
    try {
      return inspectMp4(handle);
    } finally {
      handle.closeSync();
    }
  }

  List<int> movie(List<int> tracks, {int duration = 5000}) => [
    ..._box('ftyp', 'M4A '.codeUnits),
    ..._box('moov', [..._mvhd(timescale: 1000, duration: duration), ...tracks]),
  ];

  test('reads AAC and the movie duration', () {
    final info = inspect(movie(_trak('soun', 'mp4a')));

    expect(info.audioCodec, 'aac');
    expect(info.duration, const Duration(seconds: 5));
  });

  test('ignores a cover video track ahead of the audio', () {
    final info = inspect(
      movie([..._trak('vide', 'avc1'), ..._trak('soun', 'mp4a')]),
    );

    expect(info.audioCodec, 'aac');
  });

  test('tells Apple Lossless from AAC', () {
    expect(inspect(movie(_trak('soun', 'alac'))).audioCodec, 'alac');
  });

  test('recognises Dolby Digital Plus', () {
    final dec3 = _box('dec3', List.filled(5, 0));

    final info = inspect(movie(_trak('soun', 'ec-3', children: dec3)));

    expect(info.audioCodec, 'eac3');
  });

  test('recognises Dolby Atmos from the JOC flag', () {
    final dec3 = _box('dec3', [...List.filled(5, 0), 0x01, 0x10]);

    final info = inspect(movie(_trak('soun', 'ec-3', children: dec3)));

    expect(info.audioCodec, 'eac3-joc');
  });

  test('takes a fragmented file\'s duration from mehd', () {
    final info = inspect([
      ..._box('moov', [
        ..._mvhd(timescale: 1000, duration: 0),
        ..._box('mvex', _box('mehd', [...List.filled(4, 0), ..._u32(42000)])),
        ..._trak('soun', 'mp4a'),
      ]),
    ]);

    expect(info.duration, const Duration(seconds: 42));
  });

  test('reports no duration when no header knows it', () {
    final info = inspect(movie(_trak('soun', 'ec-3'), duration: 0));

    expect(info.audioCodec, 'eac3');
    expect(info.duration, isNull);
  });

  test('finds moov after a large media box', () {
    final info = inspect([
      ..._box('ftyp', 'M4A '.codeUnits),
      ..._box('mdat', List.filled(4096, 7)),
      ..._box('moov', [
        ..._mvhd(timescale: 44100, duration: 441000),
        ..._trak('soun', 'mp4a'),
      ]),
    ]);

    expect(info.audioCodec, 'aac');
    expect(info.duration, const Duration(seconds: 10));
  });

  test('returns nothing for files that are not MP4', () {
    expect(inspect(List.filled(64, 0xFF)), (audioCodec: null, duration: null));
    expect(inspect(const []), (audioCodec: null, duration: null));
  });

  test('survives a truncated file', () {
    final bytes = movie(_trak('soun', 'mp4a'));

    final info = inspect(bytes.sublist(0, bytes.length - 20));

    expect(info.duration, const Duration(seconds: 5));
  });
}
