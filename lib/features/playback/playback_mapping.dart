import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/track.dart';

/// Key in [MediaItem.extras] holding the library id of the track.
const kTrackIdExtra = 'trackId';
const kCodecExtra = 'codec';
const kBitrateExtra = 'bitrate';
const kSampleRateExtra = 'sampleRate';
const kBitDepthExtra = 'bitDepth';
const kFolderExtra = 'folder';

/// Converts [MediaItem.artUri] back into a local file path or remote HTTP(S)
/// URL understood by `Artwork`.
String? artUriToPathOrUrl(Uri? uri) {
  if (uri == null) return null;
  return uri.isScheme('file') ? uri.toFilePath() : uri.toString();
}

Uri? _artUriFromPath(String? artPath) {
  if (artPath == null || artPath.isEmpty) return null;
  if (artPath.startsWith('http://') || artPath.startsWith('https://')) {
    return Uri.tryParse(artPath);
  }
  return Uri.file(artPath);
}

/// Describes a track to the system media session. A track not yet stored
/// in the library carries no library id.
MediaItem mediaItemFromTrack(Track track) => MediaItem(
  id: track.playbackUri.toString(),
  title: track.title,
  artist: track.displayArtist,
  album: track.album,
  genre: track.genre,
  duration: track.duration > Duration.zero ? track.duration : null,
  artUri: _artUriFromPath(track.artPath),
  extras: {
    if (track.id != 0) kTrackIdExtra: track.id,
    if (track.codec != null) kCodecExtra: track.codec,
    if (track.bitrate != null) kBitrateExtra: track.bitrate,
    if (track.sampleRate != null) kSampleRateExtra: track.sampleRate,
    if (track.bitDepth != null) kBitDepthExtra: track.bitDepth,
    if (track.folder.isNotEmpty) kFolderExtra: track.folder,
  },
);

/// Rebuilds a temporary [Track] from a playing [MediaItem] for online
/// streaming tracks (`id == 0`) that are not yet saved in the local database.
Track mediaItemToTrack(MediaItem item) {
  final now = DateTime.now();
  final extras = item.extras;
  final isHttp =
      item.id.startsWith('http://') || item.id.startsWith('https://');
  return Track(
    id: (extras?[kTrackIdExtra] as int?) ?? 0,
    uri: item.id,
    fileName: item.title,
    folder: (extras?[kFolderExtra] as String?) ?? '',
    title: item.title,
    artist: item.artist,
    album: item.album,
    genre: item.genre,
    duration: item.duration ?? Duration.zero,
    artPath: artUriToPathOrUrl(item.artUri),
    codec: (extras?[kCodecExtra] as String?) ?? (isHttp ? 'aac' : null),
    bitrate:
        (extras?[kBitrateExtra] as num?)?.toInt() ?? (isHttp ? 128000 : null),
    sampleRate:
        (extras?[kSampleRateExtra] as num?)?.toInt() ?? (isHttp ? 44100 : null),
    bitDepth: (extras?[kBitDepthExtra] as num?)?.toInt(),
    dateAdded: now,
    dateModified: now,
  );
}

/// Translates the player's state into what the OS media session shows on the
/// notification, lock screen and connected devices.
PlaybackState buildPlaybackState({
  required bool playing,
  required ProcessingState processingState,
  required Duration position,
  required Duration bufferedPosition,
  required double speed,
  required int? queueIndex,
  required LoopMode loopMode,
  required bool shuffleEnabled,
}) {
  return PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ],
    androidCompactActionIndices: const [0, 1, 2],
    systemActions: const {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    },
    processingState: switch (processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    },
    playing: playing,
    updatePosition: position,
    bufferedPosition: bufferedPosition,
    speed: speed,
    queueIndex: queueIndex,
    repeatMode: switch (loopMode) {
      LoopMode.off => AudioServiceRepeatMode.none,
      LoopMode.one => AudioServiceRepeatMode.one,
      LoopMode.all => AudioServiceRepeatMode.all,
    },
    shuffleMode: shuffleEnabled
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none,
  );
}

/// The queue position [offset] steps away from [currentIndex] in play order.
///
/// Unlike the player's own next/previous, repeat-one does not pin this to the
/// current track: pressing Next always moves on. Returns null at either end of
/// the queue when repeat is off.
int? relativeQueueIndex({
  required List<int> playOrder,
  required int? currentIndex,
  required int offset,
  required bool wrap,
}) {
  if (currentIndex == null) return null;
  final position = playOrder.indexOf(currentIndex);
  if (position < 0) return null;
  final target = position + offset;
  if (target >= 0 && target < playOrder.length) return playOrder[target];
  return wrap ? playOrder[target % playOrder.length] : null;
}
