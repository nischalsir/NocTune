import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../data/repositories/library_repository.dart';
import 'playback_mapping.dart';

/// Keeps the library's listening data in step with playback: play counts,
/// "recently played", and track lengths the scanner couldn't read.
class PlayHistoryRecorder {
  PlayHistoryRecorder({
    required this._repository,
    required Stream<MediaItem?> mediaItems,
    required Stream<bool> playing,
  }) {
    _subscriptions = [
      mediaItems.listen(_onItem),
      playing.listen((playing) {
        _playing = playing;
        _recordPlay();
      }),
    ];
  }

  final LibraryRepository _repository;
  late final List<StreamSubscription<void>> _subscriptions;

  bool _playing = false;
  int? _currentId;
  int? _countedId;
  int? _lengthUnknownId;

  void _onItem(MediaItem? item) {
    final id = item?.extras?[kTrackIdExtra] as int?;
    if (id != _currentId) {
      _currentId = id;
      // Loading the same track again later counts as another play.
      _countedId = null;
      _lengthUnknownId = item?.duration == null ? id : null;
    }
    final duration = item?.duration;
    if (id != null && id == _lengthUnknownId && duration != null) {
      _lengthUnknownId = null;
      _repository.setDuration(id, duration);
    }
    _recordPlay();
  }

  // A track counts as played once it is the current one and audio is
  // actually running, so a queue restored paused at launch doesn't count.
  void _recordPlay() {
    final id = _currentId;
    if (!_playing || id == null || id == _countedId) return;
    _countedId = id;
    _repository.recordPlay(id);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }
}
