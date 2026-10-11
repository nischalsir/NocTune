import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/models/playlist.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';
import '../features/playback/noc_audio_handler.dart';
import '../features/playback/playback_mapping.dart';

// ---- Services created in main() before the first frame ----

final databaseProvider = Provider<Database>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final audioHandlerProvider = Provider<NocAudioHandler>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Where NocTune keeps its own files on this device.
typedef AppPaths = ({
  /// Cached cover art; safe to delete, rebuilt by the next scan.
  String artworkDir,

  /// Imported audio. On iOS this is the folder shown in the Files app.
  String musicDir,

  /// Pictures the user chose as covers. Unlike the artwork cache, nothing
  /// rebuilds these.
  String coverDir,
});

final appPathsProvider = Provider<AppPaths>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

// ---- Library ----

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(databaseProvider)),
);

/// Watches the repository and re-runs the calling provider after any write.
LibraryRepository _liveRepository(Ref ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  final subscription = repository.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository;
}

typedef TrackOrder = ({TrackSort sort, bool ascending});

class TrackOrderController extends Notifier<TrackOrder> {
  @override
  TrackOrder build() => (sort: TrackSort.title, ascending: true);

  /// Picks a sort; choosing the current one again flips its direction.
  void select(TrackSort sort) {
    state = (
      sort: sort,
      ascending: sort == state.sort ? !state.ascending : true,
    );
  }
}

final trackOrderProvider = NotifierProvider<TrackOrderController, TrackOrder>(
  TrackOrderController.new,
);

final allTracksProvider = FutureProvider<List<Track>>((ref) {
  final order = ref.watch(trackOrderProvider);
  return _liveRepository(ref)
      .tracks(sort: order.sort, ascending: order.ascending);
});

final recentlyPlayedProvider = FutureProvider<List<Track>>(
  (ref) => _liveRepository(ref).recentlyPlayed(),
);

final mostPlayedProvider = FutureProvider<List<Track>>(
  (ref) => _liveRepository(ref).mostPlayed(limit: 100),
);

/// The play log, newest first.
final playLogProvider = FutureProvider<List<PlayedTrack>>(
  (ref) => _liveRepository(ref).playLog(),
);

/// The most played tracks of the last so-many days.
final topTracksInDaysProvider = FutureProvider.family<List<TrackPlays>, int>(
  (ref, days) =>
      _liveRepository(ref)
          .topTracksSince(DateTime.now().subtract(Duration(days: days))),
);

/// The albums added most recently.
final recentAlbumsProvider = FutureProvider<List<TrackGroupSummary>>(
  (ref) => _liveRepository(ref).recentAlbums(),
);

/// The most played albums or artists.
final topGroupsProvider =
    FutureProvider.family<List<TrackGroupSummary>, TrackGroup>(
      (ref, group) => _liveRepository(ref).topGroups(group),
    );

final recentlyAddedProvider = FutureProvider<List<Track>>(
  (ref) => _liveRepository(ref).recentlyAdded(),
);

final favoritesProvider = FutureProvider<List<Track>>(
  (ref) => _liveRepository(ref).favorites(),
);

final libraryStatsProvider = FutureProvider<LibraryStats>(
  (ref) => _liveRepository(ref).stats(),
);

final trackGroupsProvider =
    FutureProvider.family<List<TrackGroupSummary>, TrackGroup>(
      (ref, group) => _liveRepository(ref).groups(group),
    );

final groupTracksProvider =
    FutureProvider.family<List<Track>, ({TrackGroup group, String name})>(
      (ref, key) => _liveRepository(ref).groupTracks(key.group, key.name),
    );

final playlistsProvider = FutureProvider<List<Playlist>>(
  (ref) => _liveRepository(ref).playlists(),
);

final playlistTracksProvider = FutureProvider.family<List<Track>, int>(
  (ref, playlistId) => _liveRepository(ref).playlistTracks(playlistId),
);

final duplicatesProvider = FutureProvider<List<List<Track>>>(
  (ref) => _liveRepository(ref).duplicates(),
);

final searchResultsProvider = FutureProvider.family<List<Track>, String>(
  (ref, query) => _liveRepository(ref).search(query),
);

// ---- Playback ----

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final currentMediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

/// Library id of the track loaded in the player, if any.
final currentTrackIdProvider = Provider<int?>(
  (ref) =>
      ref.watch(currentMediaItemProvider).value?.extras?[kTrackIdExtra] as int?,
);

/// The library's record of the track loaded in the player: its favourite
/// state, audio format and so on.
final currentTrackProvider = FutureProvider<Track?>((ref) async {
  final id = ref.watch(currentTrackIdProvider);
  return id == null ? null : _liveRepository(ref).trackById(id);
});

final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);

final playbackPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);

/// The position at a finer grain, for the lyrics highlight. Only listened
/// to while lyrics are on screen.
final lyricsPositionProvider = StreamProvider.autoDispose<Duration>(
  (ref) => ref.watch(audioHandlerProvider).precisePositionStream,
);

final playbackErrorProvider = StreamProvider<String>(
  (ref) => ref.watch(audioHandlerProvider).errors,
);
