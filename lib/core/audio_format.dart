import '../data/models/track.dart';

/// Display name for a stored codec id.
String codecLabel(String? codec) => switch (codec) {
  null => 'Unknown format',
  'flac' => 'FLAC',
  'alac' => 'Apple Lossless',
  'pcm' => 'WAV',
  'wav' => 'WAV',
  'aac' => 'AAC',
  'm4a' || 'mp4' => 'MPEG-4 audio',
  'mp3' => 'MP3',
  'opus' => 'Opus',
  'ogg' => 'Ogg Vorbis',
  'eac3-joc' => 'Dolby Atmos',
  'eac3' => 'Dolby Digital Plus',
  'ac3' => 'Dolby Digital',
  'ac4' => 'Dolby AC-4',
  _ => codec.toUpperCase(),
};

/// Whether the codec is one that stores audio without loss. The scanner only
/// records these ids after checking the file's contents: `flac` from the
/// stream marker, `alac` from inside the MP4 container, `pcm` from the
/// WAV header. A bare `wav` or `m4a` is unverified and is not lossless.
bool isLossless(String? codec) =>
    codec == 'flac' || codec == 'alac' || codec == 'pcm';

/// Whether the track is Dolby Atmos content: Dolby Digital Plus carrying the
/// Atmos (JOC) extension, as flagged inside the file.
bool isAtmosContent(String? codec) => codec == 'eac3-joc';

/// The format badges to show for the current track.
///
/// LOSSLESS depends only on the file. Dolby Atmos needs both Atmos content
/// and [deviceDecodesAtmos], the device reporting a decoder for that exact
/// format; without one the player falls back to plain surround or fails, so
/// the badge would be a claim nobody can back up.
({bool lossless, bool atmos}) formatBadges(
  String? codec, {
  required bool deviceDecodesAtmos,
}) => (
  lossless: isLossless(codec),
  atmos: isAtmosContent(codec) && deviceDecodesAtmos,
);

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

/// A short description of a track's audio for the player's quality pill:
/// `FLAC 24/96`, `AAC 256 kbps`, or `Dolby Atmos` when [atmos] is true.
///
/// [atmos] must come from [formatBadges], so an Atmos recording on a device
/// that can't decode it is described by its codec instead.
String qualityBadgeLabel(Track track, {required bool atmos}) {
  if (atmos) return 'Dolby Atmos';
  final codec = track.codec;
  final name = switch (codec) {
    'alac' => 'ALAC',
    'eac3-joc' || 'eac3' => 'Dolby Digital+',
    null => 'Audio',
    _ => codecLabel(codec),
  };
  final rate = track.sampleRate;
  final depth = track.bitDepth;
  final bitrate = track.bitrate;
  if (isLossless(codec)) {
    final resolution = [
      if (depth != null) '$depth',
      if (rate != null) _trimZeros(rate / 1000),
    ].join('/');
    return resolution.isEmpty ? name : '$name $resolution';
  }
  return bitrate == null
      ? name
      : '$name ${_thousands((bitrate / 1000).round())} kbps';
}

String _trimZeros(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

String _thousands(int value) => '$value'.replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);
