import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/track.dart';

/// Key in [MediaItem.extras] holding the library id of the track.
const kTrackIdExtra = 'trackId';

/// Describes a library track to the system media session.
MediaItem mediaItemFromTrack(Track track) => MediaItem(
  id: track.playbackUri.toString(),
  title: track.title,
  artist: track.displayArtist,
  album: track.album,
  genre: track.genre,
  duration: track.duration > Duration.zero ? track.duration : null,
  artUri: track.artPath == null ? null : Uri.file(track.artPath!),
  extras: {kTrackIdExtra: track.id},
);

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
