import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/playback/playback_mapping.dart';

PlaybackState _state({
  bool playing = false,
  ProcessingState processingState = ProcessingState.ready,
  LoopMode loopMode = LoopMode.off,
  bool shuffleEnabled = false,
}) => buildPlaybackState(
  playing: playing,
  processingState: processingState,
  position: const Duration(seconds: 12),
  bufferedPosition: const Duration(seconds: 40),
  speed: 1,
  queueIndex: 2,
  loopMode: loopMode,
  shuffleEnabled: shuffleEnabled,
);

void main() {
  group('mediaItemFromTrack', () {
    final added = DateTime(2026);

    test('maps a file track, encoding awkward path characters', () {
      final track = Track(
        id: 7,
        uri: '/music/Agar Tum Saath Ho (From Tamasha ) #1.flac',
        fileName: 'Agar Tum Saath Ho (From Tamasha ) #1.flac',
        folder: '/music',
        title: 'Agar Tum Saath Ho',
        artist: 'Alka Yagnik',
        album: 'Tamasha',
        duration: const Duration(minutes: 5),
        artPath: '/cache/art/7.jpg',
        dateAdded: added,
        dateModified: added,
      );

      final item = mediaItemFromTrack(track);

      expect(Uri.parse(item.id).toFilePath(windows: false), track.uri);
      expect(item.title, 'Agar Tum Saath Ho');
      expect(item.artist, 'Alka Yagnik');
      expect(item.duration, const Duration(minutes: 5));
      expect(item.artUri!.toFilePath(windows: false), '/cache/art/7.jpg');
      expect(item.extras![kTrackIdExtra], 7);
    });

    test('keeps content URIs and tolerates missing metadata', () {
      final track = Track(
        uri: 'content://media/external/audio/media/42',
        fileName: 'unknown.opus',
        folder: '',
        title: 'unknown',
        dateAdded: added,
        dateModified: added,
      );

      final item = mediaItemFromTrack(track);

      expect(item.id, 'content://media/external/audio/media/42');
      expect(item.artist, 'Unknown artist');
      expect(item.duration, isNull);
      expect(item.artUri, isNull);
    });
  });

  group('buildPlaybackState', () {
    test('offers Pause while playing and Play while paused', () {
      expect(_state(playing: true).controls[1], MediaControl.pause);
      expect(_state().controls[1], MediaControl.play);
      expect(_state().controls.first, MediaControl.skipToPrevious);
      expect(_state().controls.last, MediaControl.skipToNext);
    });

    test('allows seeking from the system controls', () {
      expect(_state().systemActions, contains(MediaAction.seek));
    });

    test('carries position, queue index and processing state', () {
      final state = _state(processingState: ProcessingState.buffering);

      expect(state.updatePosition, const Duration(seconds: 12));
      expect(state.bufferedPosition, const Duration(seconds: 40));
      expect(state.queueIndex, 2);
      expect(state.processingState, AudioProcessingState.buffering);
    });

    test('maps repeat and shuffle modes', () {
      expect(_state().repeatMode, AudioServiceRepeatMode.none);
      expect(
        _state(loopMode: LoopMode.one).repeatMode,
        AudioServiceRepeatMode.one,
      );
      expect(
        _state(loopMode: LoopMode.all).repeatMode,
        AudioServiceRepeatMode.all,
      );
      expect(
        _state(shuffleEnabled: true).shuffleMode,
        AudioServiceShuffleMode.all,
      );
    });
  });

  group('relativeQueueIndex', () {
    int? step(
      int offset, {
      List<int> order = const [0, 1, 2],
      int? current = 1,
      bool wrap = false,
    }) => relativeQueueIndex(
      playOrder: order,
      currentIndex: current,
      offset: offset,
      wrap: wrap,
    );

    test('moves through the queue in order', () {
      expect(step(1), 2);
      expect(step(-1), 0);
    });

    test('stops at either end when repeat is off', () {
      expect(step(1, current: 2), isNull);
      expect(step(-1, current: 0), isNull);
    });

    test('wraps around when repeat is on', () {
      expect(step(1, current: 2, wrap: true), 0);
      expect(step(-1, current: 0, wrap: true), 2);
    });

    test('follows the shuffled play order', () {
      expect(step(1, order: [2, 0, 1], current: 2), 0);
      expect(step(1, order: [2, 0, 1], current: 1), isNull);
    });

    test('has nowhere to go with an empty queue', () {
      expect(step(1, order: [], current: null), isNull);
      expect(step(1, order: [], current: 0, wrap: true), isNull);
    });
  });
}
