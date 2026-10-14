import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/device_profile.dart';
import 'app/licenses.dart';
import 'app/providers.dart';
import 'data/db/app_database.dart';
import 'data/repositories/library_repository.dart';
import 'features/equalizer/equalizer_settings.dart';
import 'features/playback/noc_audio_handler.dart';
import 'features/playback/play_history_recorder.dart';
import 'features/playback/playback_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  registerBundledLicenses();

  // The few things the first screen can't be drawn without, started together
  // rather than one after another. Nothing here touches the network or scans
  // the library.
  final (
    database,
    preferences,
    cacheDir,
    documentsDir,
    supportDir,
    audioHandler,
  ) = await (
    AppDatabase.open(),
    SharedPreferences.getInstance(),
    getApplicationCacheDirectory(),
    getApplicationDocumentsDirectory(),
    getApplicationSupportDirectory(),
    // Registers the media session and background playback service with the OS.
    AudioService.init(
      builder: NocAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.nischalpandey.noctune.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationChannelDescription:
            'Controls for the music that is playing',
        androidNotificationIcon: 'drawable/ic_stat_noctune',
      ),
    ),
  ).wait;

  // These two live for the whole process, not just while the UI is showing,
  // so listening history and the saved session stay correct in the background.
  final repository = LibraryRepository(database);
  final session = PlaybackSession(
    preferences: preferences,
    repository: repository,
    handler: audioHandler,
  );
  final recorder = PlayHistoryRecorder(
    repository: repository,
    mediaItems: audioHandler.mediaItem,
    playing: audioHandler.playbackState
        .map((state) => state.playing)
        .distinct(),
    resumedTrackId: session.resumedTrackId,
  );
  // The equaliser as the user left it. It finishes once a first track is
  // loaded, so it is not waited for here.
  unawaited(audioHandler.applyEqualizer(EqualizerSettings.load(preferences)));

  runApp(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repository),
        sharedPreferencesProvider.overrideWithValue(preferences),
        audioHandlerProvider.overrideWithValue(audioHandler),
        playHistoryRecorderProvider.overrideWithValue(recorder),
        appPathsProvider.overrideWithValue((
          artworkDir: p.join(cacheDir.path, 'artwork'),
          musicDir: documentsDir.path,
          coverDir: p.join(supportDir.path, 'covers'),
        )),
        ...deviceProfileOverrides,
      ],
      child: const NocTuneApp(),
    ),
  );

  // Reloading the last queue means opening every file in it; do that once
  // the first frame is up, not before it.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => session.restoreAndTrack(),
  );
}
