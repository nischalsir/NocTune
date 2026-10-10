import 'dart:io';
import 'dart:typed_data';

/// Checks what a file really contains, for formats where the extension alone
/// proves nothing. Returns a codec id NocTune can vouch for, or null when the
/// contents don't confirm the extension.
///
/// - `.flac` must begin with the FLAC stream marker.
/// - `.wav` is only `pcm` (lossless) when its header says uncompressed PCM;
///   a WAV file can just as well wrap MP3 or ADPCM, which stays plain `wav`.
String? sniffCodec(String path, String extension) {
  try {
    final file = File(path).openSync();
    try {
      return switch (extension) {
        'flac' => _isFlac(file) ? 'flac' : null,
        'wav' => _wavCodec(file),
        _ => extension,
      };
    } finally {
      file.closeSync();
    }
  } on FileSystemException {
    return null;
  }
}

bool _isFlac(RandomAccessFile file) {
  var head = file.readSync(10);
  // Some taggers put an ID3v2 block in front of the stream; step over it.
  if (head.length == 10 && String.fromCharCodes(head, 0, 3) == 'ID3') {
    final size =
        (head[6] & 0x7F) << 21 |
        (head[7] & 0x7F) << 14 |
        (head[8] & 0x7F) << 7 |
        (head[9] & 0x7F);
    file.setPositionSync(10 + size);
    head = file.readSync(4);
  }
  return head.length >= 4 && String.fromCharCodes(head, 0, 4) == 'fLaC';
}

/// WAVE format tags that mean uncompressed samples.
const _pcm = 0x0001;
const _ieeeFloat = 0x0003;
const _extensible = 0xFFFE;

String _wavCodec(RandomAccessFile file) {
  final riff = file.readSync(12);
  if (riff.length < 12 ||
      String.fromCharCodes(riff, 0, 4) != 'RIFF' ||
      String.fromCharCodes(riff, 8, 12) != 'WAVE') {
    return 'wav';
  }
  // Walk the chunks to the format description.
  final length = file.lengthSync();
  var position = 12;
  while (position + 8 <= length) {
    file.setPositionSync(position);
    final header = file.readSync(8);
    if (header.length < 8) break;
    final size = ByteData.sublistView(header).getUint32(4, Endian.little);
    if (String.fromCharCodes(header, 0, 4) == 'fmt ') {
      final format = ByteData.sublistView(file.readSync(26));
      if (format.lengthInBytes < 2) break;
      var tag = format.getUint16(0, Endian.little);
      // "Extensible" defers to a sub-format, whose first two bytes are a
      // classic format tag.
      if (tag == _extensible && format.lengthInBytes >= 26) {
        tag = format.getUint16(24, Endian.little);
      }
      return tag == _pcm || tag == _ieeeFloat ? 'pcm' : 'wav';
    }
    // Chunks are padded to an even length.
    position += 8 + size + (size.isOdd ? 1 : 0);
  }
  return 'wav';
}
