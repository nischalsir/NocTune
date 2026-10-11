import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/lyrics/lyric_fill.dart';
import 'package:noctune/features/lyrics/lyrics.dart';
import 'package:noctune/features/lyrics/lyrics_source.dart';
import 'package:noctune/features/lyrics/lyrics_view.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/playback/now_playing_screen.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:noctune/features/playback/player_seek_bar.dart';
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
  Stream<Duration>? lyricsPosition,
  List<MediaItem>? queue,
  Map<String, Object> preferences = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final handler = _FakeHandler();
  final current = track ?? _trackWith();
  final item = mediaItemFromTrack(current);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
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
        lyricsPositionProvider.overrideWith(
          (ref) => lyricsPosition ?? Stream.value(const Duration(seconds: 61)),
        ),
        queueProvider.overrideWith((ref) => Stream.value(queue ?? [item])),
      ],
      child: MaterialApp(
        theme: buildNocTheme(Brightness.dark, NocAccent.red),
        home: Scaffold(body: child),
      ),
    ),
  );
  if (state?.playing ?? false) {
    // The wave seek bar keeps moving while music plays, so this never
    // settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  } else {
    await tester.pumpAndSettle();
  }
  return handler;
}

void main() {
  testWidgets('shows the track, its album and the time played and left', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Aashish'), findsOneWidget);
    expect(find.text('Bipul Chettri'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('1:01'), findsOneWidget);
    expect(find.text('−2:59'), findsOneWidget);
  });

  testWidgets('transport buttons drive the player', (tester) async {
    final handler = await _pump(tester);

    // The wide button says what it will do.
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byTooltip('Shuffle off'));
    await tester.tap(find.byTooltip('Repeat off'));

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

    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Shuffle on'));
    await tester.tap(find.byTooltip('Repeat one'));

    expect(handler.calls, ['pause', 'shuffle none', 'repeat none']);
  });

  group('seek bar', () {
    testWidgets('dragging it seeks once, on release', (tester) async {
      final handler = await _pump(tester);
      expect(
        tester.widget<PlayerSeekBar>(find.byType(PlayerSeekBar)).wave,
        isTrue,
      );

      await tester.drag(find.byType(PlayerSeekBar), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(handler.calls, hasLength(1));
      expect(handler.calls.single, startsWith('seek '));
    });

    testWidgets('tapping it seeks to that point', (tester) async {
      final handler = await _pump(tester);

      final bar = tester.getRect(
        find
            .descendant(
              of: find.byType(PlayerSeekBar),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      await tester.tapAt(Offset(bar.left + bar.width / 2, bar.center.dy));
      await tester.pumpAndSettle();

      // Half way through a four-minute track.
      expect(handler.calls, ['seek 120']);
    });

    testWidgets('is the plain bar when the wave is switched off', (
      tester,
    ) async {
      final handler = await _pump(
        tester,
        preferences: {'wave_seek_bar': false},
      );
      expect(
        tester.widget<PlayerSeekBar>(find.byType(PlayerSeekBar)).wave,
        isFalse,
      );

      await tester.drag(find.byType(PlayerSeekBar), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(handler.calls.single, startsWith('seek '));
    });

    testWidgets('a track of unknown length cannot be scrubbed', (tester) async {
      final handler = await _pump(
        tester,
        track: _trackWith(duration: Duration.zero),
      );

      expect(find.text('–:––'), findsOneWidget);
      await tester.drag(find.byType(PlayerSeekBar), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(handler.calls, isEmpty);
    });
  });

  testWidgets('shows the favourite state', (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Add to favourites'), findsOneWidget);
  });

  testWidgets('the queue opens from the top bar', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();

    expect(find.byType(QueueSheet), findsOneWidget);
  });

  testWidgets('says so when nothing is loaded', (tester) async {
    await _pump(tester, nothingLoaded: true);

    expect(find.text('Nothing is playing'), findsOneWidget);
  });

  group('audio quality pill', () {
    Finder lossless() => find.bySemanticsLabel(RegExp('^Lossless quality'));

    testWidgets('verified FLAC is described as lossless, never as Atmos', (
      tester,
    ) async {
      await _pump(tester, atmosDecoder: true);

      expect(find.text('FLAC 16/44.1'), findsOneWidget);
      expect(lossless(), findsOneWidget);
      expect(find.byIcon(Icons.high_quality), findsOneWidget);
      expect(find.text('Dolby Atmos'), findsNothing);
    });

    testWidgets('lossy audio is not called lossless', (tester) async {
      for (final codec in ['aac', 'mp3', 'opus']) {
        await _pump(tester, track: _trackWith(codec: codec));

        expect(lossless(), findsNothing, reason: codec);
        expect(find.byIcon(Icons.high_quality), findsNothing, reason: codec);
        expect(find.text('Dolby Atmos'), findsNothing, reason: codec);
        expect(
          find.bySemanticsLabel(RegExp('^Audio quality')),
          findsOneWidget,
          reason: codec,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('unknown or unverified formats are not called lossless', (
      tester,
    ) async {
      for (final codec in [null, 'wav', 'm4a']) {
        await _pump(tester, track: _trackWith(codec: codec));

        expect(lossless(), findsNothing, reason: '$codec');
        expect(find.byIcon(Icons.high_quality), findsNothing, reason: '$codec');
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
      expect(find.byIcon(Icons.surround_sound), findsOneWidget);
      expect(lossless(), findsNothing);
    });

    testWidgets('Atmos content without a decoder is described by its codec', (
      tester,
    ) async {
      await _pump(tester, track: _trackWith(codec: 'eac3-joc'));

      expect(find.text('Dolby Atmos'), findsNothing);
      expect(find.byIcon(Icons.surround_sound), findsNothing);
      expect(find.textContaining('Dolby Digital+'), findsOneWidget);
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
      expect(find.text('FLAC 16/44.1'), findsNothing);
      expect(find.byIcon(Icons.high_quality), findsNothing);
    });

    testWidgets('sits between shuffle and repeat, under the transport', (
      tester,
    ) async {
      await _pump(tester);

      final pill = tester.getRect(find.text('FLAC 16/44.1'));
      final play = tester.getRect(find.byTooltip('Play'));
      final shuffle = tester.getRect(find.byTooltip('Shuffle off'));
      final repeat = tester.getRect(find.byTooltip('Repeat off'));

      expect(pill.top, greaterThan(play.bottom));
      expect(pill.left, greaterThan(shuffle.right));
      expect(pill.right, lessThan(repeat.left));
      expect((pill.center.dy - shuffle.center.dy).abs(), lessThan(2));
    });

    testWidgets('opens the details of the track', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('FLAC 16/44.1'));
      await tester.pumpAndSettle();

      expect(find.text('Track details'), findsOneWidget);
    });

    testWidgets('the controls sit in the same place whatever the format', (
      tester,
    ) async {
      await _pump(tester);
      final withLossless = tester.getRect(find.byTooltip('Play'));
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, track: _trackWith(codec: 'mp3'));

      expect(tester.getRect(find.byTooltip('Play')), withLossless);
    });
  });

  group('lyrics', () {
    Future<_FakeHandler> open(WidgetTester tester, LoadedLyrics? lyrics) async {
      final handler = await _pump(tester, lyrics: lyrics);
      await tester.tap(find.byTooltip('Show lyrics'));
      await tester.pumpAndSettle();
      return handler;
    }

    // Position is 1:01 in every test here.
    // How bright a line is drawn: its colour, dimmed by whatever fades it.
    double alpha(WidgetTester tester, String line) => tester
        .widgetList<Opacity>(
          find.ancestor(of: find.text(line), matching: find.byType(Opacity)),
        )
        .fold(
          tester.widget<Text>(find.text(line)).style!.color!.a,
          (shown, fade) => shown * fade.opacity,
        );

    testWidgets('take over the player and hand it back', (tester) async {
      await open(tester, _syncedLyrics);

      expect(find.text('Second line'), findsOneWidget);
      expect(
        find.text('LINE SYNC • Embedded in the audio file'),
        findsOneWidget,
      );
      // The lyrics view brings its own transport and times.
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.text('1:01'), findsOneWidget);
      expect(find.text('−2:59'), findsOneWidget);

      expect(find.text('LYRICS'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the player'));
      await tester.pumpAndSettle();
      expect(find.text('Second line'), findsNothing);
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
    });

    testWidgets('light up the line at the playback position, word by word', (
      tester,
    ) async {
      await open(tester, _syncedLyrics);

      // The line being sung is the brightest and is the one being filled.
      expect(
        alpha(tester, 'Second line'),
        greaterThan(alpha(tester, 'First line')),
      );
      expect(alpha(tester, 'Second line'), greaterThan(alpha(tester, 'Third')));
      final filling = tester.widgetList<LyricFill>(find.byType(LyricFill));
      expect(filling.map((fill) => fill.text), contains('Second line'));
      expect(filling.map((fill) => fill.text), isNot(contains('Third')));
      // It says what kind of timing the file has.
      expect(find.textContaining('LINE SYNC'), findsOneWidget);
    });

    testWidgets('files that time each word are labelled as such', (
      tester,
    ) async {
      await open(
        tester,
        LoadedLyrics(
          parseLyrics(
            '[00:10.00]<00:10.00>First <00:11.00>line\n'
            '[01:00.00]<01:00.00>Second <01:01.50>line\n[02:00.00]Third',
          )!,
          LyricsOrigin.sidecar,
        ),
      );

      expect(find.textContaining('WORD SYNC'), findsOneWidget);
      expect(find.textContaining('LINE SYNC'), findsNothing);
    });

    testWidgets('with reduced motion the line lights up at once', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester, _syncedLyrics);

      expect(alpha(tester, 'Second line'), 1);
      expect(find.byType(LyricFill), findsNothing);
    });
    group('moving to the next line', () {
      // Fourteen lines ten seconds apart: enough to scroll.
      final long = LoadedLyrics(
        parseLyrics(
          [for (var i = 0; i < 14; i++) '[0${i ~/ 6}:${i % 6}0.00]Line $i']
              .join('\n'),
        )!,
        LyricsOrigin.embedded,
      );

      // Music is playing, so nothing ever settles: frames are pumped by hand.
      Future<StreamController<Duration>> play(WidgetTester tester) async {
        final position = StreamController<Duration>.broadcast();
        addTearDown(position.close);
        await _pump(
          tester,
          lyrics: long,
          state: PlaybackState(playing: true),
          lyricsPosition: position.stream,
        );
        await tester.tap(find.byTooltip('Show lyrics'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        position.add(const Duration(seconds: 61));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        return position;
      }

      ScrollPosition list(WidgetTester tester) => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(LyricsPanel),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

      const frame = Duration(milliseconds: 16);

      // Where each of lines 4 to 11 is drawn. While a line is changing how
      // sharp it is, two pictures of it are on screen; either will do.
      List<double> tops(WidgetTester tester) => [
        for (var line = 4; line <= 11; line++)
          tester.getTopLeft(find.text('Line $line').first).dy,
      ];

      testWidgets('no line moves in a single step, or backwards', (
        tester,
      ) async {
        final position = await play(tester);

        final start = tops(tester);
        var before = start;
        var largest = 0.0;
        var furthestBack = 0.0;
        position.add(const Duration(seconds: 71));
        for (var i = 0; i < 110; i++) {
          await tester.pump(frame);
          final now = tops(tester);
          for (var line = 0; line < now.length; line++) {
            largest = math.max(largest, (now[line] - before[line]).abs());
            furthestBack = math.max(furthestBack, now[line] - before[line]);
          }
          before = now;
        }

        // Every line has gone up a row. None jumped on the way, and none
        // was pushed down first.
        for (var line = 0; line < start.length; line++) {
          expect(start[line] - before[line], greaterThan(60));
        }
        expect(largest, lessThan(9));
        expect(furthestBack, lessThan(1.5));
      });

      testWidgets('the lines below trail behind and catch up', (tester) async {
        final position = await play(tester);
        final start = tops(tester);
        // Lines 7 (the one about to be sung) and 11, four below it.
        double risen(int line) => start[line - 4] - tops(tester)[line - 4];

        position.add(const Duration(seconds: 71));
        await tester.pump(frame);
        await tester.pump(const Duration(milliseconds: 200));
        expect(risen(11), lessThan(risen(7) - 8));
        // Each line further down is further behind.
        expect(risen(11), lessThan(risen(10)));
        expect(risen(10), lessThan(risen(9)));

        await tester.pump(const Duration(seconds: 2));
        expect(risen(11), closeTo(risen(8), 1));
      });

      testWidgets('lines away from the one being sung are out of focus', (
        tester,
      ) async {
        await play(tester);
        // A blur, as opposed to the stretch a scrolling list can be given.
        Finder soft(int line) => find.ancestor(
          of: find.text('Line $line'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ImageFiltered &&
                '${widget.imageFilter}'.contains('blur'),
          ),
        );
        String blur(int line) =>
            '${tester.widget<ImageFiltered>(soft(line)).imageFilter}';

        expect(soft(6), findsNothing);
        expect(soft(5), findsOneWidget);
        expect(soft(7), findsOneWidget);
        // The further away, the softer.
        expect(blur(9), isNot(blur(7)));
        // Blurred once and kept as a picture, not blurred on every frame.
        expect(
          find.ancestor(
            of: find.text('Line 9'),
            matching: find.byType(SnapshotWidget),
          ),
          findsOneWidget,
        );

        // Moving the list by hand brings the lines into focus to be read.
        final finger = await tester.startGesture(
          tester.getCenter(find.text('Line 8')),
        );
        await finger.moveBy(const Offset(0, -30));
        await tester.pump(frame);
        await finger.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 600));
        expect(soft(7), findsNothing);
        expect(soft(9), findsNothing);

        // Let go, and they go back out of focus.
        await finger.up();
        await tester.pump(frame);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 600));
        expect(soft(7), findsOneWidget);
      });

      testWidgets('a line that arrives mid-glide does not stop the list', (
        tester,
      ) async {
        final position = await play(tester);
        final scroll = list(tester);

        position.add(const Duration(seconds: 71));
        await tester.pump(frame);
        await tester.pump(const Duration(milliseconds: 104));
        var at = scroll.pixels;
        await tester.pump(frame);
        final before = scroll.pixels - at;

        position.add(const Duration(seconds: 81));
        await tester.pump(frame);
        final steps = <double>[];
        for (var i = 0; i < 4; i++) {
          at = scroll.pixels;
          await tester.pump(frame);
          steps.add(scroll.pixels - at);
        }

        expect(before, greaterThan(1));
        // It carries on from the speed it had instead of starting again
        // from rest.
        for (final step in steps) {
          expect(step, greaterThan(before * 0.6));
          expect(step, lessThan(before * 2.2));
        }
      });

      testWidgets('a line changes size as a picture, and is text at rest', (
        tester,
      ) async {
        final position = await play(tester);
        // A line changing how sharp it is has two pictures of itself on
        // screen for a moment; they share the one scale.
        FilterQuality? resizing(int line) => tester
            .widget<AnimatedScale>(
              find
                  .ancestor(
                    of: find.text('Line $line').first,
                    matching: find.byType(AnimatedScale),
                  )
                  .first,
            )
            .filterQuality;
        expect(resizing(6), isNull);

        position.add(const Duration(seconds: 71));
        await tester.pump(frame);
        await tester.pump(frame);

        // The line coming in and the one going out are resizing.
        expect(resizing(7), isNotNull);
        expect(resizing(6), isNotNull);
        // A line far away keeps its size.
        expect(resizing(12), isNull);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump(frame);
        expect(resizing(7), isNull);
        expect(resizing(6), isNull);
      });
    });

    testWidgets('blurs nothing over its backdrop', (tester) async {
      await open(tester, _syncedLyrics);

      // The backdrop is already blurred; a blur per button on every frame
      // would add nothing but work.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('tapping a line seeks to it', (tester) async {
      final handler = await open(tester, _syncedLyrics);

      await tester.tap(find.text('Third'));
      await tester.pumpAndSettle();

      expect(handler.calls, ['seek 120']);
    });

    testWidgets('its transport drives the player', (tester) async {
      final handler = await open(tester, _syncedLyrics);

      await tester.tap(find.byTooltip('Play'));
      await tester.tap(find.byTooltip('Next'));
      await tester.tap(find.byTooltip('Previous'));

      expect(handler.calls, ['play', 'next', 'previous']);
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

      expect(find.text('Just words\nNo times'), findsOneWidget);
      expect(find.text('Lyrics not time-synced'), findsOneWidget);
      expect(find.textContaining('LINE SYNC'), findsNothing);
    });

    testWidgets('a track without lyrics offers a local import', (tester) async {
      await open(tester, null);

      expect(find.text('No lyrics'), findsOneWidget);
      expect(find.text('Import lyrics file'), findsOneWidget);
    });

    testWidgets('text size follows the slider and can be reset', (
      tester,
    ) async {
      await open(tester, _syncedLyrics);
      double size() =>
          tester.widget<Text>(find.text('Second line')).style!.fontSize!;
      final before = size();

      await tester.tap(find.byTooltip('Adjust lyrics text size'));
      await tester.pumpAndSettle();
      expect(find.text('Lyrics size: 100%'), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(size(), greaterThan(before));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getDouble('lyrics_scale'), greaterThan(1));

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(size(), before);
    });

    testWidgets('fullscreen leaves only the lyrics and its two buttons', (
      tester,
    ) async {
      await open(tester, _syncedLyrics);

      await tester.tap(find.byTooltip('Fullscreen lyrics'));
      await tester.pumpAndSettle();
      expect(find.text('Second line'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      expect(find.byTooltip('Back to the player'), findsNothing);

      await tester.tap(find.byTooltip('Exit fullscreen lyrics'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Back to the player'), findsOneWidget);
    });

    testWidgets('a saved sync offset moves the highlight, not playback', (
      tester,
    ) async {
      // "Late" starts half a second after the playback position.
      final handler = await open(
        tester,
        LoadedLyrics(
          parseLyrics('[00:10.00]Early\n[01:01.50]Late\n[02:00.00]End')!,
          LyricsOrigin.sidecar,
        ),
      );
      expect(alpha(tester, 'Early'), greaterThan(alpha(tester, 'Late')));

      await tester.tap(find.byTooltip('Lyrics sync offset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+1s'));
      await tester.pumpAndSettle();
      expect(find.text('+1000 ms'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(alpha(tester, 'Late'), greaterThan(alpha(tester, 'Early')));
      expect(handler.calls, isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where((key) => key.startsWith('lyrics_offset_')),
        hasLength(1),
      );
    });

    testWidgets('plain lyrics offer no sync offset', (tester) async {
      await open(
        tester,
        LoadedLyrics(parseLyrics('Just words')!, LyricsOrigin.imported),
      );

      expect(find.byTooltip('Lyrics sync offset'), findsNothing);
      await tester.tap(find.byTooltip('Lyrics options'));
      await tester.pumpAndSettle();

      expect(find.text('Import lyrics file…'), findsOneWidget);
      expect(find.text('Remove imported lyrics'), findsOneWidget);
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
      // A title too long for the line is drawn twice, to scroll round.
      expect(find.text('Aashish'), findsWidgets);

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
