import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// What an MP4-family file (`.m4a`, `.mp4`) actually contains. The extension
/// alone can't tell AAC from Apple Lossless or Dolby audio.
typedef Mp4Info = ({String? audioCodec, Duration? duration});

/// Codec names NocTune stores for the MP4 sample formats it recognises.
const _codecNames = {
  'mp4a': 'aac',
  'alac': 'alac',
  'ec-3': 'eac3',
  'ac-3': 'ac3',
  'ac-4': 'ac4',
  'fLaC': 'flac',
  'Opus': 'opus',
};

const _containerBoxes = {'moov', 'trak', 'mdia', 'minf', 'stbl', 'mvex'};

/// Walks the box structure of an MP4 file to find its audio codec and length.
///
/// Returns nulls rather than throwing when the file is truncated or isn't
/// really an MP4.
Mp4Info inspectMp4(RandomAccessFile file) {
  String? handler;
  String? audioCodec;
  int? timescale;
  int? movieDuration;
  int? fragmentDuration;

  void visit(String type, int start, int end) {
    Uint8List read(int offset, int length) {
      file.setPositionSync(start + offset);
      return file.readSync(max(0, min(length, end - start - offset)));
    }

    switch (type) {
      case 'mvhd':
        final data = ByteData.sublistView(read(0, 32));
        if (data.lengthInBytes < 32) return;
        if (data.getUint8(0) == 1) {
          timescale = data.getUint32(20);
          movieDuration = data.getUint64(24);
        } else {
          timescale = data.getUint32(12);
          movieDuration = data.getUint32(16);
        }
      // Fragmented files keep their real length here; mvhd says 0.
      case 'mehd':
        final data = ByteData.sublistView(read(0, 12));
        if (data.lengthInBytes >= 12 && data.getUint8(0) == 1) {
          fragmentDuration = data.getUint64(4);
        } else if (data.lengthInBytes >= 8) {
          fragmentDuration = data.getUint32(4);
        }
      case 'hdlr':
        final data = read(8, 4);
        if (data.length == 4) handler = String.fromCharCodes(data);
      case 'stsd':
        // Only the sound track matters; files often carry a cover video too.
        if (handler != 'soun' || audioCodec != null) return;
        final entry = read(8, end - start - 8);
        if (entry.length < 8) return;
        final format = String.fromCharCodes(entry, 4, 8);
        audioCodec = _codecNames[format] ?? format.trim().toLowerCase();
        if (format == 'ec-3' && _carriesAtmos(entry)) audioCodec = 'eac3-joc';
    }
  }

  try {
    _walk(file, 0, file.lengthSync(), visit);
  } on FileSystemException {
    // Unreadable or truncated: report what was found before the failure.
  }

  // Null when neither header knows the length (some fragmented files); the
  // player reports it once the file is opened.
  final ticks = (movieDuration ?? 0) > 0 ? movieDuration : fragmentDuration;
  final scale = timescale;
  return (
    audioCodec: audioCodec,
    duration: ticks != null && ticks > 0 && scale != null && scale > 0
        ? Duration(microseconds: ticks * 1000000 ~/ scale)
        : null,
  );
}

void _walk(
  RandomAccessFile file,
  int start,
  int end,
  void Function(String type, int start, int end) visit,
) {
  var position = start;
  while (position + 8 <= end) {
    file.setPositionSync(position);
    final header = file.readSync(8);
    if (header.length < 8) return;
    var size = ByteData.sublistView(header).getUint32(0);
    var headerSize = 8;
    if (size == 1) {
      // A 64-bit size follows the type.
      final extended = file.readSync(8);
      if (extended.length < 8) return;
      size = ByteData.sublistView(extended).getUint64(0);
      headerSize = 16;
    } else if (size == 0) {
      size = end - position;
    }
    if (size < headerSize) return;

    final type = String.fromCharCodes(header, 4, 8);
    final payloadStart = position + headerSize;
    final boxEnd = min(position + size, end);
    visit(type, payloadStart, boxEnd);
    if (_containerBoxes.contains(type)) {
      _walk(file, payloadStart, boxEnd, visit);
    }
    position += size;
  }
}

/// Whether an `ec-3` sample entry declares Dolby Atmos (the "JOC" extension)
/// in its `dec3` configuration box.
bool _carriesAtmos(Uint8List entry) {
  // An audio sample entry is 36 bytes, followed by its child boxes.
  var offset = 36;
  while (offset + 8 <= entry.length) {
    final size = ByteData.sublistView(entry).getUint32(offset);
    if (size < 8) return false;
    if (String.fromCharCodes(entry, offset + 4, offset + 8) == 'dec3') {
      final end = min(offset + size, entry.length);
      return _dec3HasJoc(Uint8List.sublistView(entry, offset + 8, end));
    }
    offset += size;
  }
  return false;
}

bool _dec3HasJoc(Uint8List dec3) {
  var bit = 0;
  int take(int count) {
    var value = 0;
    for (var i = 0; i < count; i++, bit++) {
      final byte = bit ~/ 8 < dec3.length ? dec3[bit ~/ 8] : 0;
      value = (value << 1) | ((byte >> (7 - bit % 8)) & 1);
    }
    return value;
  }

  take(13); // data rate
  final substreams = take(3) + 1;
  for (var i = 0; i < substreams; i++) {
    take(19); // fscod, bsid, reserved, asvc, bsmod, acmod, lfeon, reserved
    final dependentSubstreams = take(4);
    take(dependentSubstreams > 0 ? 9 : 1);
  }
  // The Atmos extension is two optional bytes after the substream list.
  if (dec3.length * 8 - bit < 16) return false;
  take(7);
  return take(1) == 1;
}
