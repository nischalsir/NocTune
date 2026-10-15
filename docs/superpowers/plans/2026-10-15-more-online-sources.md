# More Online Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search asks Audius and the Internet Archive beside Jamendo in one mixed list; Archive items open a track list page; Spotify and YouTube Music get "search there" buttons.

**Architecture:** A common `OnlineSource` shape in `lib/features/online/online_source.dart`; Jamendo, Audius and Archive each implement it in their own file. Search, the offline cache, playback and downloads become per-source but are written once. The Search screen interleaves the sources' answers.

**Tech Stack:** Flutter, Riverpod 3 (`Notifier`, `FutureProvider.autoDispose.family`), `dart:io` `HttpClient`, `shared_preferences`, `url_launcher` (already a dependency), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-15-more-online-sources-design.md`

## Global Constraints

- No new packages.
- Branch `feat/decoder-output-rate`; commit per task; **never push or release** (owner approves those separately).
- Commit messages end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01XiSQucbu5kLHQf6sbW8wV6`
  (commit through Git Bash with a heredoc; PowerShell mangles `-F -`).
- Audius: `app_name=NocTune` on every request, no key, base `https://api.audius.co/v1`.
- Search limit 20 per source. Search wait 450 ms (`onlineSearchDelayProvider`, unchanged).
- Jamendo download paths unchanged: `Jamendo/jamendo-<id>.mp3`, cover `jamendo-<id>.jpg`.
- Copy is fixed by the spec (notes, switch titles, button labels); use it verbatim.
- `flutter test` hangs on never-settling animations: run every test command with a wall-clock limit (`Start-Job` + `Wait-Job -Timeout 900`), as the project's memory notes.
- Match surrounding style: doc comments in plain sentences, `const` where possible, no new abstraction layers beyond those listed.

## Review Focus

1. **Archive item and file names with spaces, `#`, `?`, non-Latin letters** must still stream and download: the URL path segment is percent-encoded with `Uri(pathSegments: …)`, never string-joined. Test in Task 3.
2. **An Archive item title with `/`, `:`, `?` or only dots** must still make a valid download folder; fall back to the identifier when cleaning leaves nothing. Test in Task 6.
3. **Old saved Jamendo cache and downloads after the update:** cached JSON without `source` reads as Jamendo, and songs already downloaded to `Jamendo/` still show as downloaded. Tests in Tasks 1 and 6.
4. **One source offline or failing while another answers:** the answering source's rows still play and its songs queue; the failing one shows only its own line. Test in Task 7.
5. **An Audius download that is FLAC though Audius calls it `.mp3`** is saved as `.flac` and later recognised as downloaded. Test in Task 6.

---

### Task 1: Common source shape; Jamendo moved onto it

**Files:**
- Create: `lib/features/online/online_source.dart`
- Create: `lib/features/online/jamendo_source.dart` (from `jamendo_client.dart`)
- Delete: `lib/features/online/jamendo_client.dart`
- Modify (imports and names only): `lib/features/online/online_search.dart`, `lib/features/online/online_playback.dart`, `lib/features/search/search_screen.dart`, `lib/features/settings/settings_screen.dart`
- Test: rename `test/online/jamendo_client_test.dart` → `test/online/jamendo_source_test.dart`; update imports in `test/online/online_search_test.dart`, `test/online/online_playback_test.dart`, `test/search/search_screen_test.dart`

**Interfaces:**
- Produces (in `online_source.dart`):
  - `enum OnlineSourceId { jamendo, audius, archive }` with `String get label` (`'Jamendo'`, `'Audius'`, `'Internet Archive'`) and `String get badge` (`'JAMENDO'`, `'AUDIUS'`, `'ARCHIVE'`).
  - `enum OnlineFailure { offline, rateLimited, unavailable }`, `class OnlineSearchException` — moved verbatim.
  - `sealed class OnlineItem { OnlineSourceId get source; String get id; String get title; Uri? get imageUrl; String get key => '${source.name}:$id'; Map<String, Object?> toJson(); static OnlineItem fromJson(Map<String, Object?> json); }`. `fromJson` returns `OnlineAlbum` when `json['type'] == 'album'`, else `OnlineTrack`.
  - `final class OnlineTrack extends OnlineItem`: today's fields plus `final OnlineSourceId source` (constructor default `OnlineSourceId.jamendo`). `toJson` adds `'source': source.name`; `fromJson` reads a missing `source` as `jamendo`. `fromJamendo` moves to `jamendo_source.dart` as a private parser.
  - `final class OnlineAlbum extends OnlineItem`: `source`, `id`, `title`, `String? creator`, `OnlineAlbumKind kind`, `Uri? imageUrl`, `String? licenceUrl`; `toJson` writes `'type': 'album'`; `==`/`hashCode` on `key` (it is a provider family argument).
  - `enum OnlineAlbumKind { show, album }`.
  - `abstract interface class OnlineSource { OnlineSourceId get id; Future<List<OnlineItem>> search(String words); }`
  - `typedef HttpResponse = ({int status, String body}); typedef HttpFetch = Future<HttpResponse> Function(Uri url); Future<HttpResponse> fetchOverHttps(Uri url)` — today's `JamendoResponse`/`JamendoFetch`/`fetchOverHttps`, renamed, same timeouts.
  - `Future<Object?> fetchJson(HttpFetch fetch, Uri url)`: maps `SocketException`/`HandshakeException`/`TimeoutException` → `offline`, `HttpException` → `offline`, status 429 → `rateLimited`, other non-200 → `unavailable`, `FormatException` → `unavailable`; returns the decoded JSON.
  - `Uri? httpsUrl(Object? value)` and `String? text(Object? value)`: today's `_https`/`_text`, made public for the three sources.
- Produces (in `jamendo_source.dart`): `const kJamendoClientId` (moved), `class JamendoSource implements OnlineSource { JamendoSource({required String clientId, HttpFetch fetch = fetchOverHttps, Duration retryDelay = const Duration(seconds: 1)}); static const limit = 20; }`.

- [ ] **Step 1: Move and rename the existing Jamendo tests**

`git mv test/online/jamendo_client_test.dart test/online/jamendo_source_test.dart`, then switch it to `JamendoSource`, `HttpResponse`, and results typed `List<OnlineItem>` (cast with `.cast<OnlineTrack>()` where a test reads track fields). Add:

```dart
test('asks once more when Jamendo answers with nothing', () async {
  var calls = 0;
  final results = await source((_) {
    calls++;
    return (status: 200, body: _body(results: calls == 1 ? [] : [_track()]));
  }).search('jazz');
  expect(calls, 2);
  expect(results, hasLength(1));
});

test('two empty answers are no match, not an error', () async {
  final results = await source((_) => (status: 200, body: _body())).search('zzz');
  expect(asked, hasLength(2));
  expect(results, isEmpty);
});

test('old cached JSON without a source reads as Jamendo', () {
  final track = OnlineItem.fromJson({
    'id': '9', 'title': 'Wanderer', 'stream': 'https://prod-1.storage.jamendo.com/?trackid=9',
  }) as OnlineTrack;
  expect(track.source, OnlineSourceId.jamendo);
  expect(track.key, 'jamendo:9');
});
```

`source(...)` is today's `client(...)` helper building `JamendoSource(clientId: 'test-id', retryDelay: Duration.zero, fetch: …)`.

- [ ] **Step 2: Run, expect compile failure**

Run: `flutter test test/online/jamendo_source_test.dart`
Expected: FAIL — `jamendo_source.dart` / `OnlineItem` not found.

- [ ] **Step 3: Create `online_source.dart` and `jamendo_source.dart` per Interfaces; delete `jamendo_client.dart`**

`JamendoSource.search` sends today's exact query parameters, parses with `fetchJson`, keeps today's Jamendo-header error handling (move it as is), and on an empty result waits `retryDelay` and asks once more. Fix every import listed under Files; `online_search.dart` keeps working for Jamendo only in this task (its provider becomes `jamendoSourceProvider = Provider<JamendoSource?>`, same null rule).

- [ ] **Step 4: Run the whole online and search suites**

Run: `flutter test test/online test/search test/settings`
Expected: all pass (existing behaviour unchanged).

- [ ] **Step 5: Commit** — `refactor(online): one shape for online sources; Jamendo on it, asked again when empty`

---

### Task 2: Audius source

**Files:**
- Create: `lib/features/online/audius_source.dart`
- Create: `test/online/fixtures/audius_search.json` (one real answer trimmed to 4 tracks: one plain streamable, one `is_streamable: false`, one `is_stream_gated: true`, one `is_downloadable: true`; record with `curl "https://api.audius.co/v1/tracks/search?query=lofi&app_name=NocTune&limit=20"` and edit)
- Test: `test/online/audius_source_test.dart`

**Interfaces:**
- Consumes: Task 1's `OnlineSource`, `OnlineTrack`, `fetchJson`, `HttpFetch`.
- Produces: `class AudiusSource implements OnlineSource { AudiusSource({HttpFetch fetch = fetchOverHttps}); static const appName = 'NocTune'; static const limit = 20; }`

- [ ] **Step 1: Write the failing tests**

```dart
test('searches with the app name and keeps only playable tracks', () async {
  final results = await source(fixture).search(' lofi ');
  final url = asked.single;
  expect(url.toString(), startsWith('https://api.audius.co/v1/tracks/search'));
  expect(url.queryParameters, {'query': 'lofi', 'app_name': 'NocTune', 'limit': '20'});
  expect(results.map((t) => t.id), ['<plain id>', '<downloadable id>']);
});

test('plays from the stable stream address', () async {
  final track = (await source(fixture).search('lofi')).first as OnlineTrack;
  expect(track.source, OnlineSourceId.audius);
  expect(track.streamUrl.toString(),
      'https://api.audius.co/v1/tracks/${track.id}/stream?app_name=NocTune');
  expect(track.artist, '<user.name from fixture>');
  expect(track.imageUrl.toString(), '<artwork 480x480 from fixture>');
  expect(track.duration, Duration(seconds: <duration from fixture>));
});

test('download address only when the artist allows it', () async {
  final [plain, free] = (await source(fixture).search('lofi')).cast<OnlineTrack>();
  expect(plain.downloadUrl, isNull);
  expect(free.downloadUrl.toString(),
      'https://api.audius.co/v1/tracks/${free.id}/download?app_name=NocTune');
});
```

Plus one test each: 429 → `OnlineSearchException` with `rateLimited`; 500 → `unavailable`; body `'<html>'` → `unavailable`; `SocketException` → `offline`; `{"data": []}` → empty list.

- [ ] **Step 2: Run, expect failure** — `flutter test test/online/audius_source_test.dart` → FAIL, `AudiusSource` undefined.

- [ ] **Step 3: Implement `AudiusSource.search`**

Keep a track when `is_streamable == true`, `is_stream_gated != true` and `access?['stream'] != false`. `downloadUrl` when `is_downloadable == true && is_download_gated != true`. Title `title`, artist `user.name`, album null, `duration` seconds, image `artwork['480x480']` via `httpsUrl`, no licence. Ignore the signed `stream.url` in the answer.

- [ ] **Step 4: Run** — same command, all pass.

- [ ] **Step 5: Commit** — `feat(online): Audius search`

---

### Task 3: Internet Archive source

**Files:**
- Create: `lib/features/online/archive_source.dart`
- Create: `test/online/fixtures/archive_search.json` (3 docs: one `mediatype: etree`, one `audio` with a CC `licenseurl`, one where `creator` is a list) and `test/online/fixtures/archive_item.json` (a real `/metadata/` answer trimmed: 3 `VBR MP3` files out of `track` order with one `"private": "true"`, one `Ogg Vorbis`, one `64Kbps MP3 ZIP`)
- Test: `test/online/archive_source_test.dart`

**Interfaces:**
- Consumes: Task 1's types and helpers.
- Produces: `class ArchiveSource implements OnlineSource { ArchiveSource({HttpFetch fetch = fetchOverHttps}); static const limit = 20; Future<List<OnlineTrack>> tracks(OnlineAlbum album); }`. Archive track `id` is `'<identifier>/<file name>'`.

- [ ] **Step 1: Write the failing tests**

```dart
test('asks only for shareable recordings', () async {
  await source(searchFixture).search('grateful dead');
  final url = asked.single;
  expect(url.host, 'archive.org');
  expect(url.path, '/advancedsearch.php');
  expect(url.queryParameters['q'],
      '(grateful dead) AND ((mediatype:audio AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)) OR (collection:etree AND format:"VBR MP3")) AND NOT collection:stream_only');
  expect(url.queryParametersAll['fl[]'], ['identifier', 'title', 'creator', 'mediatype', 'licenseurl']);
  expect(url.queryParameters['rows'], '20');
  expect(url.queryParameters['output'], 'json');
});

test('results are albums and shows with covers', () async {
  final albums = (await source(searchFixture).search('x')).cast<OnlineAlbum>();
  expect(albums.map((a) => a.kind), [OnlineAlbumKind.show, OnlineAlbumKind.album, OnlineAlbumKind.album]);
  expect(albums.first.imageUrl.toString(), 'https://archive.org/services/img/${albums.first.id}');
  expect(albums[2].creator, '<first creator in the list>');
});

test('an item lists its MP3s in track order, skipping private files', () async {
  final tracks = await source(itemFixture).tracks(album);
  expect(asked.single.toString(), 'https://archive.org/metadata/${album.id}');
  expect(tracks.map((t) => t.title), ['<track 01 title>', '<track 02 title>']);
  expect(tracks.first.album, album.title);
  expect(tracks.first.artist, album.creator);
  expect(tracks.first.source, OnlineSourceId.archive);
  expect(tracks.first.downloadUrl, tracks.first.streamUrl);
});

test('lengths in seconds and mm:ss; title falls back to the file name', ...);
test('128Kbps then 64Kbps MP3 when there is no VBR MP3', ...);
test('an item with no MP3 has no tracks', ...);

test('file names with spaces and # are encoded in the address', () async {
  // fixture file name: "01 Iko #1 Iko.mp3", identifier "gd77 x"
  expect(track.streamUrl.toString(), 'https://archive.org/download/gd77%20x/01%20Iko%20%231%20Iko.mp3');
});
```

Plus 503 → `unavailable` and `SocketException` → `offline` for both `search` and `tracks`.

- [ ] **Step 2: Run, expect failure** — `flutter test test/online/archive_source_test.dart`.

- [ ] **Step 3: Implement**

`search`: `Uri.https('archive.org', '/advancedsearch.php', {'q': …, 'fl[]': [...], 'rows': '20', 'output': 'json'})`; read `response.docs`; `title`/`creator` may be a string or a list (take the first string); `kind` is `show` for `mediatype == 'etree'`. `tracks`: pick files whose `format` equals `'VBR MP3'`; if none, `'128Kbps MP3'`; if none, `'64Kbps MP3'`; drop `private == 'true' || private == true`. Sort by the leading integer of `track` (`'01'`, `'3/12'`), files without one last, then by name. `length`: `num.tryParse` as seconds, else `m:ss`/`h:mm:ss`. URL: `Uri(scheme: 'https', host: 'archive.org', pathSegments: ['download', identifier, ...fileName.split('/')])`; same URL for stream and download.

- [ ] **Step 4: Run** — all pass.

- [ ] **Step 5: Commit** — `feat(online): Internet Archive search and item tracks`

---

### Task 4: Per-source search, switches, cache and mixed order

**Files:**
- Modify: `lib/features/online/online_search.dart`
- Test: `test/online/online_search_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `final jamendoSourceProvider = Provider<JamendoSource?>` (null without `kJamendoClientId`), `final audiusSourceProvider = Provider<AudiusSource>`, `final archiveSourceProvider = Provider<ArchiveSource>`.
  - `class OnlineSourceEnabled extends Notifier<bool> { OnlineSourceEnabled(this.source); final OnlineSourceId source; void set(bool enabled); }` and `final onlineSourceEnabledProvider = NotifierProvider.family<OnlineSourceEnabled, bool, OnlineSourceId>(OnlineSourceEnabled.new);` (Riverpod 3 family form; the project is on `flutter_riverpod ^3.4.3`). Prefs key `online_source_<source.name>`, default `true`.
  - `onlineSearchEnabledProvider` unchanged (key `online_search_enabled`).
  - `final onlineSourcesProvider = Provider<List<OnlineSource>>`: empty when the main switch is off; otherwise Jamendo (if configured), Audius, Archive, each only if its switch is on, in that order.
  - `class OnlineResults { const OnlineResults(this.items, {this.failure, this.fromCache = false}); final List<OnlineItem> items; List<OnlineTrack> get tracks; ... }`
  - `final onlineSourceSearchProvider = FutureProvider.autoDispose.family<OnlineResults?, (OnlineSourceId, String)>` — today's provider body per source (delay, `ref.mounted`, cache fallback). Returns null when words are empty or the source is not in `onlineSourcesProvider`.
  - `OnlineSearchCache`: prefs key `online_search_cache_v2`; entries keyed `'<source>:<normalised words>'`; `limit = 20` **per source**; `get(OnlineSourceId, String)` / `put(OnlineSourceId, String, List<OnlineItem>)`; removes the old `online_search_cache` key on first read.
  - `List<OnlineItem> interleave(List<List<OnlineItem>> lists)`.
  - The old single `onlineSearchProvider` and `jamendoClientProvider` are removed.

- [ ] **Step 1: Update and add tests**

Rewrite the existing tests against `onlineSourceSearchProvider((OnlineSourceId.jamendo, words))` with `jamendoSourceProvider` overridden (retryDelay zero). Add:

```dart
test('interleaves sources, first of each, then second of each', () {
  expect(interleave([[a1, a2, a3], [b1], [], [c1, c2]]).map((i) => i.id),
      ['a1', 'b1', 'c1', 'a2', 'c2', 'a3']);
});
test('a source switched off is not asked', ...);           // audius off → provider returns null, fake fetch never called
test('main switch off asks no source', ...);
test('without a Jamendo id, Audius and Archive are still asked', ...);
test('the cache keeps 20 searches per source', ...);        // 21 Jamendo puts + 1 Audius put → Jamendo has 20, Audius 1
test('the old cache key is removed', ...);                  // prefs start with online_search_cache → gone after a get
test('offline, a source falls back to its own saved results', ...);
```

- [ ] **Step 2: Run, expect failures** — `flutter test test/online/online_search_test.dart`.

- [ ] **Step 3: Implement per Interfaces.** `interleave` is a round-robin over indices until every list is exhausted.

- [ ] **Step 4: Run** — passes. Then `flutter test test/search test/settings` still compiles (fix references to the removed providers minimally; Task 7/9 rewrite those screens).

- [ ] **Step 5: Commit** — `feat(online): search each source on its own, switches per source, mixed order`

---

### Task 5: Archive item track lists with an offline copy

**Files:**
- Create: `lib/features/online/online_album.dart`
- Test: `test/online/online_album_test.dart`

**Interfaces:**
- Consumes: `ArchiveSource.tracks`, `archiveSourceProvider`, `OnlineResults`, `sharedPreferencesProvider`.
- Produces: `final onlineAlbumProvider = FutureProvider.autoDispose.family<OnlineResults, OnlineAlbum>` — fetched tracks, saved under prefs key `online_album_cache` (map `album.key` → track JSON list, last 20 albums kept); on `OnlineSearchException` returns the saved list with `failure` and `fromCache: true`, or an empty `OnlineResults` with the failure.

- [ ] **Step 1: Tests:** `loads and saves the tracks`; `offline shows the saved tracks with fromCache`; `offline with nothing saved gives the failure and no tracks`; `keeps the last 20 albums`.
- [ ] **Step 2: Run, expect failure** — `flutter test test/online/online_album_test.dart`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — passes.
- [ ] **Step 5: Commit** — `feat(online): Internet Archive track lists, kept for offline`

---

### Task 6: Playback and downloads for every source

**Files:**
- Modify: `lib/features/online/online_playback.dart`
- Test: `test/online/online_playback_test.dart`

**Interfaces:**
- Consumes: `OnlineTrack.source`, `OnlineTrack.key`.
- Produces:
  - `File downloadedFile(AppPaths paths, OnlineTrack track)`: Jamendo `Jamendo/jamendo-<id>.mp3`; Archive `Internet Archive/<safeName(album ?? identifier)>/<safeName(file name)>`; Audius: the first existing `Audius/audius-<id>.<ext>` for ext in `flac, wav, ogg, m4a, mp3`, else the `.mp3` path.
  - `File coverFile(AppPaths paths, OnlineTrack track)`: `jamendo-<id>.jpg`, `audius-<id>.jpg`, `archive-<identifier>.jpg`.
  - `String safeName(String name, {required String fallback})`: replaces `<>:"/\|?*` and control characters with `_`, trims spaces and trailing dots, returns `fallback` if empty.
  - `String audioExtension(List<int> head)`: `fLaC` → `flac`, `RIFF` → `wav`, `OggS` → `ogg`, `ftyp` at offset 4 → `m4a`, else `mp3`.
  - `Track streamedTrack(OnlineTrack track, {String? artPath})`: `folder` = source label folder (`Jamendo`, `Audius`, `Internet Archive`), `fileName` = basename of `downloadedFile`'s default name, codec `mp3`.
  - `OnlineDownloads` state keyed by `track.key`; `Future<bool> download(OnlineTrack track, {bool scan = true})`; `Future<int> downloadAll(List<OnlineTrack> tracks)` — one after another, skipping ones already downloaded or without `downloadUrl`, carrying on past failures, one `refreshIfPermitted()` at the end; returns how many failed. Audius downloads are renamed from `.part` to the extension `audioExtension` reads from the first 12 bytes.

- [ ] **Step 1: Tests** (keep all existing ones passing):

```dart
test('Jamendo paths are unchanged', () {
  expect(p.relative(downloadedFile(paths, jamendo('7')).path, from: paths.musicDir),
      p.join('Jamendo', 'jamendo-7.mp3'));
});
test('an Archive track goes in a folder named after its item', ...);   // album 'Live: 1977/05/08?' → 'Live_ 1977_05_08_'
test('a name that cleans to nothing uses the identifier', ...);        // album '...' → identifier
test('an Audius FLAC is saved as .flac and counts as downloaded', () async {
  // fakeFetch writes 'fLaC' + bytes
  expect(await downloads.download(audius('x')), isTrue);
  expect(File(p.join(paths.musicDir, 'Audius', 'audius-x.flac')).existsSync(), isTrue);
  expect(player().isDownloaded(audius('x')), isTrue);
});
test('download all goes in order, carries on after a failure, scans once', ...);
test('downloads are keyed by source, so equal ids from two sources differ', ...);
```

- [ ] **Step 2: Run, expect failures** — `flutter test test/online/online_playback_test.dart`.
- [ ] **Step 3: Implement per Interfaces.**
- [ ] **Step 4: Run** — passes.
- [ ] **Step 5: Commit** — `feat(online): play and download from every source`

---

### Task 7: Search screen — one mixed Online list and the two buttons

**Files:**
- Modify: `lib/features/search/search_screen.dart`
- Create: `lib/features/online/external_search.dart`
- Test: `test/search/search_screen_test.dart`

**Interfaces:**
- Consumes: `onlineSourcesProvider`, `onlineSourceSearchProvider`, `interleave`, `OnlinePlayer.play`, `onlineDownloadsProvider` (keyed by `track.key`), `downloadedFile`, `streamedTrack`.
- Produces (in `external_search.dart`):
  - `typedef LinkOpener = Future<bool> Function(Uri url);`
  - `final linkOpenerProvider = Provider<LinkOpener>((ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication));`
  - `Future<bool> searchOnSpotify(LinkOpener open, String words)`: tries `Uri.parse('spotify:search:${Uri.encodeComponent(words)}')`, then `https://open.spotify.com/search/${Uri.encodeComponent(words)}`; a throw counts as false.
  - `Future<bool> searchOnYouTubeMusic(LinkOpener open, String words)`: `Uri.https('music.youtube.com', '/search', {'q': words})`.

Screen behaviour (copy verbatim from the spec):
- Heading `Online` when `onlineSourcesProvider` is non-empty; while any source loads, one `_Progress('Searching…')` under the rows already in.
- Rows from `interleave` over the sources' `items`, in `onlineSourcesProvider` order. Each row ends with a small badge (`source.badge`, `bodySmall`, `palette.textTertiary`) before its action.
- `OnlineTrack` row: today's `TrackTile` + `_DownloadAction`. Tapping plays `songs = items.whereType<OnlineTrack>()` from the tapped song. `offline` = any source's failure is `offline`.
- `OnlineAlbum` row: `ListTile` with `▸`-style leading cover, title, `'${album.creator} · show'` or `'… · album'`; taps push `OnlineAlbumScreen(album: album)` (Task 8; until then a placeholder `Scaffold`).
- Notes above the list: one shared offline line — with any `fromCache`: `"You're offline. These are from an earlier search; only downloaded songs can play."`, else `"You're offline. Online results appear once you're connected; songs you downloaded are in your library."`. Per failing source: `'<label> is busy right now. Try again in a minute.'` / `"<label> couldn't be reached right now."`. No line for a source with no match.
- When the library and every source have nothing and no failure: the `EmptyState` with `'Nothing in your library or online matches "$query".'` (or today's library-only line when no source is on), **with the two buttons under it**.
- Always, last: two `PillButton`s side by side, `Search on Spotify` and `Search on YouTube Music`; on false, snackbar `Couldn't open Spotify.` / `Couldn't open YouTube Music.`
- Empty-history hint when sources are on: `'Find a track by its title, artist, album or file name, and free music online.'`
- Remove the old Jamendo heading, its CC footer note and `_asksOnlineProvider`.

- [ ] **Step 1: Tests** (update existing Jamendo ones to the new copy; add):

```dart
testWidgets('mixes the sources in turn with their badges', ...);          // jamendo [J1,J2], audius [A1] → J1, A1, J2; badges JAMENDO, AUDIUS
testWidgets('one source failing still shows and plays the others', ...);  // audius 500, jamendo ok → "Audius couldn't be reached right now." and tapping J1 plays J1
testWidgets('tapping a song queues only the songs', ...);                 // archive album between songs is not in the queue
testWidgets('the Spotify button tries the app, then the website', ...);   // fake opener false for spotify: → second call open.spotify.com/search/love%20song
testWidgets('the YouTube Music button opens its search', ...);
testWidgets('the buttons show even when nothing matches', ...);
testWidgets('a failing opener says so', ...);                             // snackbar "Couldn't open Spotify."
```

Override `audiusSourceProvider`/`archiveSourceProvider` with fake-fetch sources in `pump`, plus `linkOpenerProvider`.

- [ ] **Step 2: Run, expect failures** — `flutter test test/search/search_screen_test.dart`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — passes.
- [ ] **Step 5: Commit** — `feat(search): one online list from every source, and Spotify / YouTube Music buttons`

---

### Task 8: Internet Archive track list page

**Files:**
- Create: `lib/features/online/online_album_screen.dart`
- Modify: `lib/features/search/search_screen.dart` (point the album row at it)
- Test: `test/online/online_album_screen_test.dart`

**Interfaces:**
- Consumes: `onlineAlbumProvider`, `OnlinePlayer.play`, `OnlineDownloads.downloadAll`, `PillButton`, `TrackTile`, the search screen's `_DownloadAction` (move it to `lib/features/online/download_action.dart` as public `DownloadAction` so both screens use it), `linkOpenerProvider`.
- Produces: `class OnlineAlbumScreen extends ConsumerWidget { const OnlineAlbumScreen({super.key, required this.album}); final OnlineAlbum album; }`

Layout, top to bottom, in one scrolling list with a back button: cover (`album.imageUrl`), title, creator, `Internet Archive`, the licence as a tappable line when `licenceUrl` is set; `PillButton(filled: true, icon: play, label: 'Play all')` and `PillButton(icon: download, label: 'Download all')`; then each track as `TrackTile(track: streamedTrack(t))` with `DownloadAction`. Loading: a centred progress. Failure with no tracks: `'This needs an internet connection.'` (offline) or `"Internet Archive couldn't be reached right now."`, and a `Try again` `PillButton` that invalidates the provider. Loaded with no tracks: `'This item has nothing NocTune can play.'`. `Download all` reports `'<n> tracks couldn't be downloaded.'` in a snackbar when `downloadAll` returns n > 0.

- [ ] **Step 1: Tests:** `shows the tracks and plays from the tapped one`; `Play all starts at the first track`; `Download all downloads every track`; `offline with a saved list plays only downloaded tracks`; `offline with nothing saved offers Try again, which asks again`.
- [ ] **Step 2: Run, expect failure** — `flutter test test/online/online_album_screen_test.dart`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — passes; `flutter test test/search` still passes.
- [ ] **Step 5: Commit** — `feat(online): Internet Archive track list page`

---

### Task 9: Settings › Online switches

**Files:**
- Modify: `lib/features/settings/settings_screen.dart:407-424` and `_SwitchTile` (`:620-650`)
- Test: `test/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `onlineSearchEnabledProvider`, `onlineSourceEnabledProvider(id)`, `jamendoSourceProvider`.

- [ ] **Step 1: Tests:** `Online group shows without a Jamendo id, with Audius and Internet Archive only`; `turning Audius off saves online_source_audius = false`; `source switches are greyed out and do nothing while the main switch is off`.
- [ ] **Step 2: Run, expect failure** — `flutter test test/settings/settings_screen_test.dart`.
- [ ] **Step 3: Implement.** The group always shows. Main switch: title `Search online music`, subtitle `'Search also finds music on Jamendo, Audius and the Internet Archive, sending what you type to them. Off, search stays on this device.'` (drop `Jamendo, ` when there is no Jamendo id). Then `Jamendo` (only with an id), `Audius`, `Internet Archive` switches. `_SwitchTile.onChanged` becomes `ValueChanged<bool>?`; null disables both the tap and the switch.
- [ ] **Step 4: Run** — passes.
- [ ] **Step 5: Commit** — `feat(settings): a switch for each online source`

---

### Task 10: Docs, full checks, release-signed build, phone check

**Files:**
- Modify: `README.md` (Jamendo section → "Online sources": Jamendo needs the id, Audius and Archive need none, what is sent where, Spotify/YouTube Music are links only), `CHANGELOG.md` (1.10.0 entry: the new sources, Archive page, buttons, Jamendo retry)

- [ ] **Step 1: Update README and CHANGELOG** in the style of their existing entries (`- ` bullets).
- [ ] **Step 2: Analyse** — `flutter analyze` → `No issues found!`
- [ ] **Step 3: Full tests, both renderers, time-limited**
  - `flutter test` → all pass
  - `flutter test --enable-impeller` → all pass
- [ ] **Step 4: Commit** — `docs: online sources in the README and 1.10.0 notes`
- [ ] **Step 5: Release-signed build** —
  `flutter build apk --release --split-per-abi --dart-define=NOCTUNE_UPDATE_MANIFEST=https://api.github.com/repos/nischalsir/NocTune/releases/latest --dart-define=NOCTUNE_JAMENDO_CLIENT_ID=<contents of C:\Users\nisch\.noctune-signing\jamendo-client-id.txt>` (read the id into a variable; never print it). Verify `apksigner verify --print-certs` shows SHA-256 `91589a58…e5e240`.
- [ ] **Step 6: Phone check — ask the owner first** (their phone is in personal use; check the foreground app and whether music is playing). Then install with `adb install -r` and check: a search showing all three sources; an Audius song playing with the screen locked; an Archive show opening and playing; one download from each source appearing in the library; both buttons opening their apps; Settings switches removing a source from results. Report what was and was not seen.
