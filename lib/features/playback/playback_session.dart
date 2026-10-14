import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/library_repository.dart';
import 'noc_audio_handler.dart';
import 'playback_mapping.dart';

/// Remembers the queue, the current track, the position and the repeat and
/// shuffle modes, and brings them back the next time the app starts.
class PlaybackSession {
  PlaybackSession({
    required SharedPreferences preferences,
    required this._repository,
    required this._handler,
  }) : _prefs = preferences;

  static const _queueKey = 'session_queue';
  static const _trackKey = 'session_track';
  static const _positionKey = 'session_position_ms';
  static const _repeatKey = 'session_repeat';
  static const _shuffleKey = 'session_shuffle';
  static const _saveInterval = Duration(seconds: 5);

  final SharedPreferences _prefs;
  final LibraryRepository _repository;
  final NocAudioHandler _handler;

  bool _wasPlaying = false;

  /// The track the last session stopped partway through, which
  /// [restoreAndTrack] brings back. The position only moves on while
  /// playing, so a track with one was already counted as played.
  int? get resumedTrackId =>
      (_prefs.getInt(_positionKey) ?? 0) > 0 ? _prefs.getInt(_trackKey) : null;

  /// Reloads the saved queue, paused where it was left, then starts saving.
  Future<void> restoreAndTrack() async {
    final ids = [
      for (final id in _prefs.getStringList(_queueKey) ?? const <String>[])
        ?int.tryParse(id),
    ];
    // Tracks removed from the library since last time simply drop out.
    final tracks = await _repository.tracksByIds(ids);
    if (tracks.isNotEmpty) {
      final current = tracks.indexWhere(
        (track) => track.id == _prefs.getInt(_trackKey),
      );
      await _handler.setRepeatMode(
        AudioServiceRepeatMode.values.asNameMap()[_prefs.getString(
              _repeatKey,
            )] ??
            AudioServiceRepeatMode.none,
      );
      await _handler.loadTracks(
        tracks,
        index: current < 0 ? 0 : current,
        position: current < 0
            ? Duration.zero
            : Duration(milliseconds: _prefs.getInt(_positionKey) ?? 0),
      );
      if (_prefs.getBool(_shuffleKey) ?? false) {
        await _handler.setShuffleMode(AudioServiceShuffleMode.all);
      }
    }

    _handler.queue.listen(_saveQueue);
    _handler.mediaItem.listen(_saveCurrent);
    _handler.playbackState.listen(_onState);
    // Position changes constantly; saving it every few seconds while playing
    // is enough to resume close to where the user stopped.
    Timer.periodic(_saveInterval, (_) {
      if (_wasPlaying) _savePosition();
    });
  }

  void _saveQueue(List<MediaItem> items) {
    _prefs.setStringList(_queueKey, [
      for (final item in items) '${item.extras?[kTrackIdExtra]}',
    ]);
  }

  void _saveCurrent(MediaItem? item) {
    final id = item?.extras?[kTrackIdExtra] as int?;
    if (id == null || id == _prefs.getInt(_trackKey)) return;
    _prefs.setInt(_trackKey, id);
    _prefs.setInt(_positionKey, 0);
  }

  void _onState(PlaybackState state) {
    _prefs.setString(_repeatKey, state.repeatMode.name);
    _prefs.setBool(
      _shuffleKey,
      state.shuffleMode != AudioServiceShuffleMode.none,
    );
    // Pausing is the moment the position most needs to be exact.
    if (_wasPlaying && !state.playing) _savePosition();
    _wasPlaying = state.playing;
  }

  void _savePosition() =>
      _prefs.setInt(_positionKey, _handler.position.inMilliseconds);
}
