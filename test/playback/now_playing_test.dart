import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/lyrics/lyrics.dart';
import 'package:noctune/features/lyrics/lyrics_source.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/playback/now_playing_screen.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:noctune/features/playback/queue_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final calls = <String>[];

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> skipToNext() async => calls.add('next');

  @override
  Future<void> skipToPrevious() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async =>
      calls.add('shuffle ${shuffleMode.name}');

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async =>
      calls.add('repeat ${repeatMode.name}');

  @override
  Future<void> skipToQueueItem(int index) async => calls.add('jump $index');

  @override
  Future<void> removeQueueItemAt(int index) async => calls.add('remove $index');
}

Track _trackWith({
  int id = 7,
  String title = 'Aashish',
  String? codec = 'flac',
  Duration duration = const Duration(minutes: 4),
}) => Track(
  id: id,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  artist: 'Bipul Chettri',
  album: 'Maya',
  duration: duration,
  codec: codec,
  sampleRate: 44100,
  bitDepth: 16,
  bitrate: 1011000,
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

final _syncedLyrics = LoadedLyrics(
  parseLyrics('[00:10.00]First line\n[01:00.00]Second line\n[02:00.00]Third')!,
  LyricsOrigin.embedded,
);

Future<_FakeHandler> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Widget child = const NowPlayingScreen(),
  PlaybackState? state,
  Track? track,
  Track? libraryRecord,
  bool nothingLoaded = false,
  bool atmosDecoder = false,
  LoadedLyrics? lyrics,
  List<MediaItem>? queue,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final handler = _FakeHandler();
  final current = track ?? _trackWith();
  final item = mediaItemFromTrack(current);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        audioHandlerProvider.overrideWithValue(handler),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(nothingLoaded ? null : item),
        ),
        // What the library says about the "current" track; a test can make
        // it lag behind, as it briefly does when a track changes.
        currentTrackProvider.overrideWith((ref) => libraryRecord ?? current),
        deviceDecodesAtmosProvider.overrideWith((ref) => atmosDecoder),
        lyricsProvider.overrideWith((ref, key) => lyrics),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(state ?? PlaybackState()),
        ),
        playbackPositionProvider.overrideWith(
          (ref) => Stream.value(const Duration(seconds: 61)),
        ),
        queueProvider.overrideWith((ref) => Stream.value(queue ?? [item])),
      ],
      child: MaterialApp(
        theme: buildNocTheme(Brightness.dark, NocAccent.red),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return handler;
}

void main() {
  testWidgets('shows the track, its album and the time played and left', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Aashish'), findsOneWidget);
    expect(find.text('Bipul Chettri'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('1:01'), findsOneWidget);
    expect(find.text('-2:59'), findsOneWidget);
  });

  testWidgets('transport buttons drive the player', (tester) async {
    final handler = await _pump(tester);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byTooltip('Shuffle is off'));
    await tester.tap(find.byTooltip('Repeat is off'));

    expect(handler.calls, [
      'play',
      'next',
      'previous',
      'shuffle all',
      'repeat all',
    ]);
  });

  testWidgets('reflects playing, shuffle and repeat-one state', (tester) async {
    final handler = await _pump(
      tester,
      state: PlaybackState(
        playing: true,
        shuffleMode: AudioServiceShuffleMode.all,
        repeatMode: AudioServiceRepeatMode.one,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.tap(find.byTooltip('Shuffle is on'));
    await tester.tap(find.byTooltip('Repeating this track'));

    expect(handler.calls, ['pause', 'shuffle none', 'repeat none']);
  });

  testWidgets('dragging the scrubber seeks once, on release', (tester) async {
    final handler = await _pump(tester);

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(handler.calls, hasLength(1));
    expect(handler.calls.single, startsWith('seek '));
  });

  testWidgets('a track of unknown length cannot be scrubbed', (tester) async {
    await _pump(tester, track: _trackWith(duration: Duration.zero));

    expect(find.text('–:––'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('shows the favourite state', (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Add to favourites'), findsOneWidget);
  });

  testWidgets('says so when nothing is loaded', (tester) async {
    await _pump(tester, nothingLoaded: true);

    expect(find.text('Nothing is playing'), findsOneWidget);
  });

  group('format badges', () {
    testWidgets('verified FLAC is LOSSLESS and never Atmos', (tester) async {
      await _pump(tester, atmosDecoder: true);

      expect(find.text('LOSSLESS'), findsOneWidget);
      expect(find.text('Dolby Atmos'), findsNothing);
    });

    testWidgets('lossy audio shows no badge', (tester) async {
      for (final codec in ['aac', 'mp3', 'opus']) {
        await _pump(tester, track: _trackWith(codec: codec));

        expect(find.text('LOSSLESS'), findsNothing, reason: codec);
        expect(find.text('Dolby Atmos'), findsNothing, reason: codec);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('unknown or unverified formats show no badge', (tester) async {
      for (final codec in [null, 'wav', 'm4a']) {
        await _pump(tester, track: _trackWith(codec: codec));

        expect(find.text('LOSSLESS'), findsNothing, reason: '$codec');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Atmos content on a device that decodes it is labelled', (
      tester,
    ) async {
      await _pump(
        tester,
        track: _trackWith(codec: 'eac3-joc'),
        atmosDecoder: true,
      );

      expect(find.text('Dolby Atmos'), findsOneWidget);
      expect(find.text('LOSSLESS'), findsNothing);
    });

    testWidgets('Atmos content without a decoder is not labelled', (
      tester,
    ) async {
      await _pump(tester, track: _trackWith(codec: 'eac3-joc'));

      expect(find.text('Dolby Atmos'), findsNothing);
    });

    testWidgets("a previous track's format is never shown for the next", (
      tester,
    ) async {
      // The player has moved to an AAC track, but the library lookup still
      // holds the FLAC track that was playing a moment ago.
      await _pump(
        tester,
        track: _trackWith(id: 8, title: 'Next', codec: 'aac'),
        libraryRecord: _trackWith(),
      );

      expect(find.text('Next'), findsOneWidget);
      expect(find.text('LOSSLESS'), findsNothing);
    });

    testWidgets('sit directly above the Play button', (tester) async {
      await _pump(tester);

      final badge = tester.getRect(find.text('LOSSLESS'));
      final play = tester.getRect(find.bySemanticsLabel('Play'));
      final scrubber = tester.getRect(find.byType(Slider));

      expect(badge.top, greaterThan(scrubber.bottom));
      expect(badge.bottom, lessThanOrEqualTo(play.top));
      expect((badge.center.dx - play.center.dx).abs(), lessThan(2));
    });

    testWidgets('the controls do not move when the badge disappears', (
      tester,
    ) async {
      await _pump(tester);
      final withBadge = tester.getRect(find.bySemanticsLabel('Play'));
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, track: _trackWith(codec: 'mp3'));
      final withoutBadge = tester.getRect(find.bySemanticsLabel('Play'));

      expect(withoutBadge, withBadge);
    });
  });

  group('lyrics', () {
    Future<_FakeHandler> open(WidgetTester tester, LoadedLyrics? lyrics) async {
      final handler = await _pump(tester, lyrics: lyrics);
      await tester.tap(find.byTooltip('Show lyrics'));
      await tester.pumpAndSettle();
      return handler;
    }

    testWidgets('open in place of the cover and close again', (tester) async {
      await open(tester, _syncedLyrics);

      expect(find.text('Second line'), findsOneWidget);
      // The transport stays available while lyrics are showing.
      expect(find.bySemanticsLabel('Play'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide lyrics'));
      await tester.pumpAndSettle();
      expect(find.text('Second line'), findsNothing);
    });

    testWidgets('highlight the line at the playback position', (tester) async {
      await open(tester, _syncedLyrics);

      // Position is 1:01, inside the second line.
      double alpha(String line) =>
          tester.widget<Text>(find.text(line)).style?.color?.a ??
          DefaultTextStyle.of(tester.element(find.text(line))).style.color!.a;

      expect(alpha('Second line'), 1);
      expect(alpha('First line'), lessThan(0.5));
      expect(alpha('Third'), lessThan(0.5));
    });

    testWidgets('tapping a line seeks to it', (tester) async {
      final handler = await open(tester, _syncedLyrics);

      await tester.tap(find.text('Third'));
      await tester.pumpAndSettle();

      expect(handler.calls, ['seek 120']);
    });

    testWidgets('plain lyrics are shown without pretending to be synced', (
      tester,
    ) async {
      await open(
        tester,
        LoadedLyrics(
          parseLyrics('Just words\nNo times')!,
          LyricsOrigin.imported,
        ),
      );

      expect(find.text('Just words'), findsOneWidget);
      expect(find.textContaining('NOT TIME-SYNCED'), findsOneWidget);
    });

    testWidgets('a track without lyrics offers a local import', (tester) async {
      await open(tester, null);

      expect(find.text('No lyrics available'), findsOneWidget);
      expect(find.text('Import lyrics file'), findsOneWidget);
    });

    testWidgets('text size can be stepped up and down', (tester) async {
      await open(tester, _syncedLyrics);
      double size() =>
          DefaultTextStyle.of(tester.element(find.text('Second line')))
              .style
              .fontSize!;
      final before = size();

      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();

      expect(size(), greaterThan(before));
    });
  });

  for (final (name, size, scale) in [
    ('a small phone', const Size(320, 568), 1.0),
    ('a small phone with large text', const Size(320, 568), 2.0),
    ('a phone in landscape', const Size(844, 390), 1.0),
    ('a tablet in portrait', const Size(800, 1200), 1.0),
    ('a tablet in landscape', const Size(1280, 800), 1.0),
  ]) {
    testWidgets('lays out without overflow on $name', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(tester, size: size, lyrics: _syncedLyrics);
      expect(tester.takeException(), isNull);
      expect(find.text('Aashish'), findsOneWidget);

      await tester.tap(find.byTooltip('Show lyrics'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  group('queue', () {
    final queue = [
      for (final title in ['One', 'Two', 'Three'])
        MediaItem(id: 'file:///$title.flac', title: title, artist: 'Artist'),
    ];

    testWidgets('lists the queue and jumps to a tapped track', (tester) async {
      final handler = await _pump(
        tester,
        child: const QueueSheet(),
        queue: queue,
        state: PlaybackState(queueIndex: 1),
      );

      expect(find.text('Queue · 3 tracks'), findsOneWidget);
      await tester.tap(find.text('Three'));

      expect(handler.calls, ['jump 2']);
    });

    testWidgets('swiping a track away removes it', (tester) async {
      final handler = await _pump(
        tester,
        child: const QueueSheet(),
        queue: queue,
      );

      await tester.drag(find.text('One'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(handler.calls, ['remove 0']);
    });

    testWidgets('explains an empty queue', (tester) async {
      await _pump(tester, child: const QueueSheet(), queue: const []);

      expect(find.text('The queue is empty'), findsOneWidget);
    });
  });
}
