import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../data/repositories/library_repository.dart';
import 'playback_mapping.dart';

/// Keeps the library's listening data in step with playback: play counts,
/// time spent listening, "recently played", and track lengths the scanner
/// couldn't read.
class PlayHistoryRecorder {
  /// [resumedTrackId] is the track the last session stopped partway
  /// through. It was counted then, so playing on with it is not a new play.
  PlayHistoryRecorder({
    required this._repository,
    required Stream<MediaItem?> mediaItems,
    required Stream<bool> playing,
    int? resumedTrackId,
    this._now = DateTime.now,
  }) : _resumedId = resumedTrackId {
    _subscriptions = [
      mediaItems.listen(_onItem),
      playing.listen((playing) {
        _playing = playing;
        if (!playing) _saveListened();
        _startListening();
        _recordPlay();
      }),
    ];
  }

  final LibraryRepository _repository;
  final DateTime Function() _now;
  late final List<StreamSubscription<void>> _subscriptions;

  bool _playing = false;
  int? _currentId;
  int? _countedId;
  int? _resumedId;
  int? _lengthUnknownId;

  /// When the current stretch of listening began; null while not playing.
  DateTime? _listeningSince;

  /// Listening to the current track that isn't stored yet: the time since
  /// it last started or resumed playing.
  Duration get unsaved {
    final since = _listeningSince;
    return since == null ? Duration.zero : _now().difference(since);
  }

  void _onItem(MediaItem? item) {
    final id = item?.extras?[kTrackIdExtra] as int?;
    if (id != _currentId) {
      _saveListened();
      _currentId = id;
      // Loading the same track again later counts as another play.
      _countedId = id != null && id == _resumedId ? id : null;
      if (id != null) _resumedId = null;
      _lengthUnknownId = item?.duration == null ? id : null;
      _startListening();
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

  void _startListening() {
    if (_playing && _currentId != null) _listeningSince ??= _now();
  }

  // Called on pause, skip or track change, so only the time that was
  // actually listened to is added, and each stretch only once.
  void _saveListened() {
    final id = _currentId;
    final listened = unsaved;
    _listeningSince = null;
    if (id != null && listened > Duration.zero) {
      _repository.addListenedTime(id, listened);
    }
  }

  void dispose() {
    _saveListened();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }
}
