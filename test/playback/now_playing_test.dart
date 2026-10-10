import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/playback/now_playing_screen.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:noctune/features/playback/queue_sheet.dart';

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

final _track = Track(
  id: 7,
  uri: '/music/Aashish.flac',
  fileName: 'Aashish.flac',
  folder: '/music',
  title: 'Aashish',
  artist: 'Bipul Chettri',
  album: 'Maya',
  duration: const Duration(minutes: 4),
  codec: 'flac',
  sampleRate: 44100,
  bitDepth: 16,
  bitrate: 1011000,
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

Future<_FakeHandler> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Widget child = const NowPlayingScreen(),
  PlaybackState? state,
  Track? track,
  bool nothingLoaded = false,
  List<MediaItem>? queue,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final handler = _FakeHandler();
  final current = track ?? _track;
  final item = mediaItemFromTrack(current);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(nothingLoaded ? null : item),
        ),
        currentTrackProvider.overrideWith((ref) => current),
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
  testWidgets('shows the track, its audio quality and the position', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Aashish'), findsOneWidget);
    expect(find.text('Bipul Chettri · Maya'), findsOneWidget);
    expect(find.text('FLAC · 16-BIT / 44.1 KHZ · 1,011 KBPS'), findsOneWidget);
    expect(find.text('1:01'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
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
    final unmeasured = Track(
      id: 9,
      uri: '/music/Cinema.m4a',
      fileName: 'Cinema.m4a',
      folder: '/music',
      title: 'Cinema',
      codec: 'eac3-joc',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );
    await _pump(tester, track: unmeasured);

    expect(find.text('–:––'), findsOneWidget);
    expect(find.text('DOLBY ATMOS'), findsOneWidget);
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

  for (final (name, size, scale) in [
    ('a small phone', const Size(320, 568), 1.0),
    ('a small phone with large text', const Size(320, 568), 2.0),
    ('a phone in landscape', const Size(844, 390), 1.0),
    ('a tablet in landscape', const Size(1280, 800), 1.0),
  ]) {
    testWidgets('lays out without overflow on $name', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(find.text('Aashish'), findsOneWidget);
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
