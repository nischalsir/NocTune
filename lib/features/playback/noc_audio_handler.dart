import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/track.dart';
import 'playback_mapping.dart';

/// The playback engine. It owns the audio player and publishes its state to
/// the OS media session, so playback keeps working with the UI in the
/// background and responds to the notification, lock screen and headsets.
class NocAudioHandler extends BaseAudioHandler with SeekHandler {
  NocAudioHandler() {
    _init();
  }

  /// Android's per-session equalizer. Attached but disabled until the user
  /// turns it on, so NocTune never colours the sound by default.
  final AndroidEqualizer androidEqualizer = AndroidEqualizer();

  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(
      androidAudioEffects: Platform.isAndroid ? [androidEqualizer] : null,
    ),
  );

  final _errors = StreamController<String>.broadcast();

  /// Playback position, updated several times a second while playing.
  Stream<Duration> get positionStream => _player.positionStream;

  /// The position twenty times a second, for following lyrics line by line.
  /// The ordinary stream ticks five times a second, which is fine for a
  /// seek bar but makes a lyric highlight visibly late.
  Stream<Duration> get precisePositionStream => _player.createPositionStream(
    steps: 800,
    minPeriod: const Duration(milliseconds: 50),
    maxPeriod: const Duration(milliseconds: 50),
  );
  Duration get position => _player.position;

  /// Human-readable messages for tracks that failed to load or decode.
  Stream<String> get errors => _errors.stream;

  /// The Android audio session id, needed to query platform audio effects.
  int? get androidAudioSessionId => _player.androidAudioSessionId;

  Future<void> _init() async {
    // Declares this as a music app: other audio is paused while we play, and
    // just_audio then pauses or ducks for calls, alarms and unplugged headphones.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream.listen((_) => _broadcastState());
    _player.playingStream.listen((_) => _broadcastState());
    _player.loopModeStream.listen((_) => _broadcastState());
    _player.shuffleModeEnabledStream.listen((_) => _broadcastState());
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.durationStream.listen(_onDurationChanged);
    _player.processingStateStream.listen(_onProcessingState);
    _player.errorStream.listen(_onError);
  }

  void _broadcastState() {
    playbackState.add(
      buildPlaybackState(
        playing: _player.playing,
        processingState: _player.processingState,
        position: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
        loopMode: _player.loopMode,
        shuffleEnabled: _player.shuffleModeEnabled,
      ),
    );
  }

  void _onIndexChanged(int? index) {
    final items = queue.value;
    if (index == null || index >= items.length) return;
    mediaItem.add(items[index]);
  }

  // Some files carry no duration in their tags; once the decoder knows the
  // real length, pass it on so the lock screen scrubber is accurate.
  void _onDurationChanged(Duration? duration) {
    final current = mediaItem.value;
    if (duration == null || current == null || current.duration == duration) {
      return;
    }
    mediaItem.add(current.copyWith(duration: duration));
  }

  // Reaching the end of the queue with repeat off: rest at the start of the
  // queue, paused, so Play starts it again.
  Future<void> _onProcessingState(ProcessingState state) async {
    if (state != ProcessingState.completed) return;
    await _player.pause();
    final order = _player.effectiveIndices;
    if (order.isNotEmpty) {
      await _player.seek(Duration.zero, index: order.first);
    }
  }

  void _onError(PlayerException error) {
    final index = error.index;
    final items = queue.value;
    final title = index != null && index < items.length
        ? items[index].title
        : 'This track';
    _errors.add(
      "$title can't be played. The file may be corrupt or use a format "
      "this device doesn't support.",
    );
    // Move past the bad file rather than stalling the queue.
    final next = _relativeIndex(1);
    if (next != null && next != index) {
      _player.seek(Duration.zero, index: next);
    }
  }

  int? _relativeIndex(int offset) => relativeQueueIndex(
    playOrder: _player.effectiveIndices,
    currentIndex: _player.currentIndex,
    offset: offset,
    wrap: _player.loopMode != LoopMode.off,
  );

  AudioSource _sourceFor(MediaItem item) =>
      AudioSource.uri(Uri.parse(item.id), tag: item);

  // ---- Queue ----

  /// Replaces the queue with [tracks] and starts playing at [initialIndex].
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async {
    if (tracks.isEmpty) return;
    await loadTracks(tracks, index: initialIndex);
    await _player.play();
  }

  /// Replaces the queue with [tracks], cued at [index] and [position] but
  /// not playing. Used to bring back the previous session at launch.
  Future<void> loadTracks(
    List<Track> tracks, {
    int index = 0,
    Duration position = Duration.zero,
  }) async {
    if (tracks.isEmpty) return;
    final items = tracks.map(mediaItemFromTrack).toList();
    queue.add(items);
    mediaItem.add(items[index]);
    await _player.setAudioSources(
      items.map(_sourceFor).toList(),
      initialIndex: index,
      initialPosition: position,
    );
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    queue.add([...queue.value, mediaItem]);
    await _player.addAudioSource(_sourceFor(mediaItem));
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    queue.add([...queue.value]..insert(index, mediaItem));
    await _player.insertAudioSource(index, _sourceFor(mediaItem));
  }

  /// Queues [track] to play straight after the current one.
  Future<void> playNext(Track track) {
    final current = _player.currentIndex;
    final item = mediaItemFromTrack(track);
    return current == null
        ? addQueueItem(item)
        : insertQueueItem(current + 1, item);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final items = [...queue.value]..removeAt(index);
    queue.add(items);
    await _player.removeAudioSourceAt(index);
    // Removing the last track leaves nothing to show as "now playing".
    if (items.isEmpty) {
      mediaItem.add(null);
      await stop();
    }
  }

  /// Stops playback and empties the queue, which also dismisses the
  /// mini-player. Used when the user swipes the player away.
  Future<void> clearQueue() async {
    queue.add(const []);
    mediaItem.add(null);
    await _player.clearAudioSources();
    await stop();
  }

  /// Moves a queue entry from [from] to [to].
  Future<void> moveQueueItem(int from, int to) async {
    final items = [...queue.value];
    items.insert(to, items.removeAt(from));
    queue.add(items);
    await _player.moveAudioSource(from, to);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  // ---- Transport ----

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final next = _relativeIndex(1);
    if (next != null) await _player.seek(Duration.zero, index: next);
  }

  /// Restarts the current track if it is more than a few seconds in,
  /// otherwise goes to the previous one.
  @override
  Future<void> skipToPrevious() async {
    final previous = _relativeIndex(-1);
    if (_player.position > const Duration(seconds: 3) || previous == null) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seek(Duration.zero, index: previous);
    }
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _player.setLoopMode(switch (repeatMode) {
        AudioServiceRepeatMode.none => LoopMode.off,
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => LoopMode.all,
      });

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// Swiping the app away while paused ends the session; while playing, the
  /// music carries on in the background.
  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) await stop();
  }
}
