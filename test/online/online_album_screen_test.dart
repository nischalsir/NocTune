import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/online/archive_source.dart';
import 'package:noctune/features/online/external_search.dart';
import 'package:noctune/features/online/online_album_screen.dart';
import 'package:noctune/features/online/online_playback.dart';
import 'package:noctune/features/online/online_search.dart';
import 'package:noctune/features/online/online_source.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final played = <String>[];
  List<String> queued = [];

  @override
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async {
    played.add(tracks[initialIndex].title);
    queued = [for (final track in tracks) track.title];
  }
}

class _Library extends Fake implements LibraryRepository {
  @override
  Future<Track?> trackByUri(String uri) async => null;
}

class _QuietScan extends ScanController {
  int refreshes = 0;

  @override
  ScanState build() => const ScanIdle();

  @override
  Future<void> refreshIfPermitted() async => refreshes++;
}

const _show = OnlineAlbum(
  source: OnlineSourceId.archive,
  id: 'samh2024',
  title: 'Live at Ashkenaz',
  creator: 'Mars Hotel',
  kind: OnlineAlbumKind.show,
  licenceUrl: 'http://creativecommons.org/licenses/by-nc-sa/3.0/',
);

final _item = jsonEncode({
  'files': [
    {'name': '01.Iko Iko.mp3', 'format': 'VBR MP3', 'track': '01'},
    {'name': '02.Might as Well.mp3', 'format': 'VBR MP3', 'track': '02'},
    {'name': '03.Tuning.mp3', 'format': 'VBR MP3', 'track': '03'},
  ],
});

void main() {
  late Directory root;
  late AppPaths paths;
  late OnlineResponse Function() answer;
  late int asked;
  late List<Uri> downloaded;
  late List<Uri> opened;
  late _QuietScan scan;

  setUp(() {
    root = Directory.systemTemp.createTempSync('noctune_album');
    paths = (
      artworkDir: '${root.path}/artwork',
      musicDir: '${root.path}/music',
      coverDir: '${root.path}/covers',
    );
    answer = () => (status: 200, body: _item);
    asked = 0;
    downloaded = [];
    opened = [];
    scan = _QuietScan();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<_FakeHandler> pump(
    WidgetTester tester, {
    Map<String, Object> saved = const {},
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    final preferences = await SharedPreferences.getInstance();
    final handler = _FakeHandler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appPathsProvider.overrideWithValue(paths),
          libraryRepositoryProvider.overrideWithValue(_Library()),
          scanControllerProvider.overrideWith(() => scan),
          archiveSourceProvider.overrideWithValue(
            ArchiveSource(
              fetch: (_) async {
                asked++;
                return answer();
              },
            ),
          ),
          fileFetcherProvider.overrideWithValue((url, target) async {
            if (url.path.contains('/services/img/')) {
              throw const SocketException('no covers in tests');
            }
            downloaded.add(url);
            await target.writeAsString('mp3');
          }),
          linkOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
          audioHandlerProvider.overrideWithValue(handler),
          currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp(
          theme: buildNocTheme(Brightness.dark, NocAccent.red),
          home: const OnlineAlbumScreen(album: _show),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return handler;
  }

  Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('shows the tracks and plays from the tapped one', (tester) async {
    final handler = await pump(tester);

    expect(find.text('Live at Ashkenaz'), findsOneWidget);
    expect(find.text('Mars Hotel'), findsOneWidget);
    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.text('01.Iko Iko'), findsOneWidget);

    await tapAndWait(tester, find.text('02.Might as Well'));

    expect(handler.played, ['02.Might as Well']);
    expect(handler.queued, ['01.Iko Iko', '02.Might as Well', '03.Tuning']);
  });

  testWidgets('Play all starts at the first track', (tester) async {
    final handler = await pump(tester);

    await tapAndWait(tester, find.text('Play all'));

    expect(handler.played, ['01.Iko Iko']);
  });

  testWidgets('Download all downloads every track and scans once', (
    tester,
  ) async {
    await pump(tester);

    await tapAndWait(tester, find.text('Download all'));

    expect(downloaded.map((url) => url.pathSegments.last), [
      '01.Iko Iko.mp3',
      '02.Might as Well.mp3',
      '03.Tuning.mp3',
    ]);
    expect(scan.refreshes, 1);
    expect(find.byTooltip('Downloaded'), findsNWidgets(3));
  });

  testWidgets('the licence opens', (tester) async {
    await pump(tester);

    await tester.tap(find.textContaining('Licence'));
    await tester.pumpAndSettle();

    expect(opened.single.toString(), _show.licenceUrl);
  });

  testWidgets('offline with a saved list plays only downloaded tracks', (
    tester,
  ) async {
    await pump(tester);
    final tracks = await ArchiveSource(
      fetch: (_) async => (status: 200, body: _item),
    ).tracks(_show);
    final copy = downloadedFile(paths, tracks[1])
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('mp3');
    expect(copy.existsSync(), isTrue);

    answer = () => throw const SocketException('offline');
    // A fresh scope, as when the page is opened again later.
    await tester.pumpWidget(const SizedBox());
    final preferences = await SharedPreferences.getInstance();
    final handler = await pump(
      tester,
      saved: {
        for (final key in preferences.getKeys()) key: preferences.get(key)!,
      },
    );

    expect(find.textContaining("You're offline."), findsOneWidget);
    await tapAndWait(tester, find.text('02.Might as Well'));
    expect(handler.played, ['02.Might as Well']);
    expect(handler.queued, ['02.Might as Well']);

    await tapAndWait(tester, find.text('01.Iko Iko'));
    expect(handler.played, ['02.Might as Well']);
    expect(find.textContaining('needs an internet connection'), findsOneWidget);
  });

  testWidgets('offline with nothing saved offers Try again, which asks again', (
    tester,
  ) async {
    answer = () => throw const SocketException('offline');
    await pump(tester);

    expect(find.text('This needs an internet connection.'), findsOneWidget);
    expect(asked, 1);

    answer = () => (status: 200, body: _item);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(asked, 2);
    expect(find.text('01.Iko Iko'), findsOneWidget);
  });

  testWidgets('offline, Play all starts at the first downloaded track', (
    tester,
  ) async {
    await pump(tester);
    final tracks = await ArchiveSource(
      fetch: (_) async => (status: 200, body: _item),
    ).tracks(_show);
    downloadedFile(paths, tracks[2])
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('mp3');
    answer = () => throw const SocketException('offline');
    await tester.pumpWidget(const SizedBox());
    final preferences = await SharedPreferences.getInstance();
    final handler = await pump(
      tester,
      saved: {
        for (final key in preferences.getKeys()) key: preferences.get(key)!,
      },
    );

    await tapAndWait(tester, find.text('Play all'));

    expect(handler.played, ['03.Tuning']);
  });

  testWidgets('an unexpected failure offers Try again', (tester) async {
    answer = () => throw ArgumentError('surprise');
    await pump(tester);

    expect(
      find.text("Internet Archive couldn't be reached right now."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an item with nothing to play says so', (tester) async {
    answer = () => (status: 200, body: jsonEncode({'files': []}));
    await pump(tester);

    expect(
      find.text('This item has nothing NocTune can play.'),
      findsOneWidget,
    );
  });
}
