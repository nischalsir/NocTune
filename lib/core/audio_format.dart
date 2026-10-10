import '../data/models/track.dart';

/// Display name for a stored codec id.
String codecLabel(String? codec) => switch (codec) {
  null => 'Unknown format',
  'flac' => 'FLAC',
  'alac' => 'Apple Lossless',
  'wav' => 'WAV',
  'aac' || 'm4a' => 'AAC',
  'mp3' => 'MP3',
  'opus' => 'Opus',
  'ogg' => 'Ogg Vorbis',
  'eac3-joc' => 'Dolby Atmos',
  'eac3' => 'Dolby Digital Plus',
  'ac3' => 'Dolby Digital',
  'ac4' => 'Dolby AC-4',
  _ => codec.toUpperCase(),
};

/// Whether the codec stores audio without loss.
bool isLossless(String? codec) =>
    codec == 'flac' || codec == 'alac' || codec == 'wav';

/// Lossless audio above CD resolution.
bool isHiRes(Track track) =>
    isLossless(track.codec) &&
    ((track.bitDepth ?? 0) > 16 || (track.sampleRate ?? 0) > 48000);

/// One-line description of a track's audio, e.g.
/// `FLAC · 24-bit / 96 kHz · 2,890 kbps`. Describes the file, not what the
/// device's output is able to reproduce.
String qualityLabel(Track track) {
  final rate = track.sampleRate;
  final depth = track.bitDepth;
  final bitrate = track.bitrate;
  final resolution = [
    if (depth != null) '$depth-bit',
    if (rate != null) '${_trimZeros(rate / 1000)} kHz',
  ].join(' / ');
  return [
    codecLabel(track.codec),
    if (resolution.isNotEmpty) resolution,
    if (bitrate != null) '${_thousands((bitrate / 1000).round())} kbps',
  ].join(' · ');
}

String _trimZeros(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

String _thousands(int value) => '$value'.replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);
