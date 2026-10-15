# More online sources: Audius, Internet Archive, Spotify and YouTube Music buttons

Date: 2026-10-15. Status: approved in conversation, awaiting review of this
written spec. Part 1 of 2; part 2 is internet radio (Radio Browser) and gets
its own spec.

## Goal

More free music the owner can find and play from inside NocTune, beside
their own files. Search already asks Jamendo; it now also asks **Audius** and
the **Internet Archive**, in one list. **Spotify** and **YouTube Music** get
buttons that open those apps' own search for the same words.

Asked for and declined, for the record: YouTube audio played or downloaded
inside NocTune, JioSaavnAPI (cyberboysumanjay), and Spotify search results
inside NocTune. The first two take audio from those services without their
player. Spotify's Developer Policy forbids an app "integrated with streams or
content from another service" (III.5) and replicating Spotify's core
experience (III.11). Since February 2026 Spotify's development mode also
allows only 5 hand-added users.

## What the owner sees

### Search

- The library's matches first, as now, then one **Online** list.
- Each online row has a small source label: `JAMENDO`, `AUDIUS` or
  `ARCHIVE`.
- Order: the sources' results are interleaved. Jamendo's first, Audius's
  first, Archive's first, then each one's second, and so on. Each source
  gives at most 20.
- Each source loads on its own. Its rows join the list when it answers, and
  a slow or failing source never holds up the others or the library. While
  any source is still loading, one "Searching…" line shows under the list.
- **Songs** (Jamendo, Audius): tapping plays it and queues the other songs
  in the list, in list order. Archive rows are not queued. A song that may
  be downloaded has a download button, as Jamendo rows do now.
- **Archive rows** are albums or shows. They show `▸`, the title, the
  creator and "show" (Live Music Archive) or "album". Tapping opens the
  **track list page**.
- Under the list, two buttons: **Search on Spotify** and **Search on
  YouTube Music**. They open `spotify:search:<words>` and
  `https://music.youtube.com/search?q=<words>`. If no app handles the
  Spotify link, `https://open.spotify.com/search/<words>` opens in the
  browser instead. They show whenever there are search words, even with
  online search off or offline, because they don't use NocTune's
  connection. No Spotify or YouTube API is used and nothing from those
  services is shown inside NocTune.

### Archive track list page

- Cover, title, creator, "Internet Archive", and the licence when the item
  has one. Tapping the licence opens it.
- **Play all** and **Download all**, then every track with its number,
  title and length, and a download button on each.
- Tapping a track plays the item from that track, with the rest queued.
- The list is fetched when the page opens. Without a connection it shows
  what was saved the last time this item was opened. If nothing was saved,
  it says the page needs a connection. Downloaded tracks always play.

### Offline

Unchanged in kind and now true for every source. An earlier search of the
same words shows its saved results with the note it shows today. Only
downloaded songs play or are queued. Tapping one that isn't downloaded says
it needs a connection.

### Downloads

Into the music folder, so the next scan adds them to the library like any
imported file:

- Jamendo: `Jamendo/jamendo-<id>.mp3`. Same as now, so songs already
  downloaded are still recognised.
- Audius: `Audius/audius-<id>.<ext>`, with the extension taken from the
  file's first bytes (see Audius below).
- Archive: `Internet Archive/<item title>/<file name>`, with characters
  Windows or Android won't accept replaced by `_`.

**Download all** downloads the item's tracks one after another. Each row
shows its own progress, and a failed track can be retried on its own. After
the last one, or after a failure, one library scan runs.

### Settings › Online

- **Search online music**: today's switch, keeping its saved value. Its note
  names the three sources and says that what you type is sent to them.
- Under it, **Jamendo**, **Audius** and **Internet Archive**, each its own
  switch, on by default. They are greyed out while the main switch is off.
- In a build without a Jamendo client id the Jamendo switch is hidden, and
  the main switch still covers the other two.

## What each source contains

**Jamendo:** unchanged. Free Creative Commons music, through the official
API and the build's client id.

**Audius:** `GET https://api.audius.co/v1/tracks/search?query=<words>&app_name=NocTune&limit=20`,
no key.
- Kept: `is_streamable == true`, `is_stream_gated != true` and
  `access.stream == true`.
- Played from `https://api.audius.co/v1/tracks/<id>/stream?app_name=NocTune`.
  This stable address redirects to a seekable MP3 (checked on 2026-10-15:
  302, then 206 `audio/mpeg`). The time-stamped signed link in the search
  answer is not used.
- Downloadable only when `is_downloadable == true` and
  `is_download_gated != true`, from
  `https://api.audius.co/v1/tracks/<id>/download?app_name=NocTune`.
  Checked on 2026-10-15: 200 with the artist's **original upload**, which
  can be FLAC (or WAV, etc.) even when the suggested file name ends in
  `.mp3`. So the saved file's extension is chosen from its first bytes, not
  from the name: `fLaC` gives `.flac`, `RIFF` `.wav`, `OggS` `.ogg`,
  `ftyp` at offset 4 `.m4a`, and anything else `.mp3`.
- Cover: `artwork["480x480"]`. Artist: `user.name`. Length: `duration`
  (seconds). Genre and licence are not shown.

**Internet Archive:** `GET https://archive.org/advancedsearch.php` with
`rows=20`, `output=json` and fields `identifier, title, creator, mediatype,
licenseurl`, for the query
`(<words>) AND ((mediatype:audio AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)) OR (collection:etree AND format:"VBR MP3")) AND NOT collection:stream_only`.
- Creative Commons or public-domain audio, plus Live Music Archive shows that
  have MP3s. Nothing stream-only.
- An item opens with `GET https://archive.org/metadata/<identifier>`. Its
  tracks are its files with format `VBR MP3`. If there are none, the files
  with format `128Kbps MP3` or `64Kbps MP3` are used instead, preferring the
  higher bitrate. Files marked `private` are skipped.
- Tracks are in `track` order, then by file name. Each track uses the
  file's `title` (falling back to its name without the extension), its
  `length` (seconds or `mm:ss`), and the item's `creator` and `title` as
  artist and album.
- Stream and download URL:
  `https://archive.org/download/<identifier>/<file name>`, URL-encoded.
- Cover: `https://archive.org/services/img/<identifier>`.
- An item with no playable tracks says so on its page.

The words go to each service as typed, as they already go to Jamendo.

## How it is built

All in `lib/features/online/`:

- **`online_source.dart`** (new):
  - `OnlineSource`: an `id` (`jamendo`, `audius`, `archive`), a `label`, and
    `Future<List<OnlineItem>> search(String words)`.
  - `sealed class OnlineItem`, which is either `OnlineTrack` (gains a
    `source` field; JSON without one reads as `jamendo`) or `OnlineAlbum`
    (`source`, `id`, `title`, `creator`, `kind` show/album, `imageUrl`,
    `licenceUrl`).
  - `OnlineFailure` and `OnlineSearchException`, moved from
    `jamendo_client.dart` and unchanged.
  - The shared `HttpFetch` (today's `JamendoFetch`/`fetchOverHttps`, with
    the same timeouts) and a helper that turns a status and body into JSON
    or the right exception: 429 is `rateLimited`, other errors and
    unreadable JSON are `unavailable`, and connection or timeout failures
    are `offline`.
- **`jamendo_source.dart`**: today's `jamendo_client.dart` as an
  `OnlineSource`. Same request, same parsing.
- **`audius_source.dart`**, **`archive_source.dart`** (new): as described
  above. `ArchiveSource` also has `Future<List<OnlineTrack>> tracks(OnlineAlbum)`.
- **`online_search.dart`**:
  - `onlineSourcesProvider`: the enabled sources, in label order, from the
    main switch and the per-source switches. Jamendo is only included with
    a client id.
  - `onlineSourceSearchProvider(source, words)`: today's provider per
    source, with the same 450 ms wait, the same never-fails fallback to the
    cache, and its own failure.
  - `OnlineSearchCache` keys entries by `<source>:<words>` and keeps 20 per
    source, under a new preferences key. The old `online_search_cache` key
    is removed on first read.
  - `interleave(List<List<OnlineItem>>)` builds the mixed order.
- **`online_album.dart`** (new): `onlineAlbumProvider(album)`. It fetches
  the track list and saves it, with the last 20 opened items kept in
  preferences, so the page works offline after one visit.
- **`online_playback.dart`**:
  - `downloadedFile` and `coverFile` dispatch on the track's source using
    the paths above. Covers are `<source>-<id>.jpg` in the artwork folder,
    and `jamendo-<id>.jpg` stays as it is.
  - `OnlineDownloads` keys downloads by `<source>:<id>` and gains
    `downloadAll(List<OnlineTrack>)`.
  - `streamedTrack` takes the folder name and codec from the source.
- **`online_album_screen.dart`** (new): the Archive page, built from the
  app's existing page pieces (header, `PillButton`, track rows) so it
  matches the Library's album page.
- **`lib/features/search/search_screen.dart`**: one Online list built from
  every enabled source's provider through `interleave`, source labels on
  rows, one note per failing source, and the two buttons.
- **`lib/features/settings/settings_screen.dart`**: the three switches.
- **README and changelog**: the sources, what is sent where, and that
  Spotify and YouTube Music are links only.

No new packages. `url_launcher` is already a dependency.

## Errors

Each source fails on its own, with its own line above the list, named for
the source:

- **Offline:** "You're offline." With saved results: "Showing results saved
  from an earlier search." That wording is shared once rather than repeated
  per source.
- **Rate limited:** "<Source> is busy right now. Try again in a minute."
- **Unavailable:** "<Source> couldn't be reached right now."
- **No match** in one source: no line. If every source and the library find
  nothing: "Nothing in your library or online matches "<words>"."
- **Archive page:** a failed fetch with nothing saved shows "This needs an
  internet connection" or "Internet Archive couldn't be reached right now",
  plus a **Try again** button.
- **A download failing** marks that row as failed, as now. Tapping the
  button again retries.
- **Spotify or YouTube Music link with nothing to open it:** a snackbar,
  "Couldn't open Spotify."

Jamendo sometimes answers a search with no results when the same search
worked a moment before. When Jamendo answers with an empty list, the search
is asked once more after 1 second before it is treated as "no match".

## Testing

Unit tests, with recorded JSON answers in `test/online/fixtures/` and fake
fetches (the pattern `jamendo_client_test.dart` uses now):

- **Audius:** parsing; skipping unstreamable, gated and locked tracks; the
  download URL only for downloadable tracks; 429, 500 and bad JSON; the
  stream URL shape.
- **Archive:** the query string; parsing search results into albums; the
  file choice (VBR first, then fallbacks, skipping private files); track
  order; `mm:ss` and seconds lengths; URL-encoded file names; an item
  with no MP3.
- **Jamendo:** today's tests pass unchanged after the move, plus the
  retry-once-on-empty rule.
- **Search and cache:** `interleave` with uneven lengths and empty lists;
  per-source cache keys and limits; the old key removed; old cached
  Jamendo JSON without `source` read as Jamendo; the disabled-source and
  no-client-id cases.
- **Playback and downloads:** file and cover paths per source (Jamendo's
  unchanged); Archive folder names cleaned of bad characters;
  `downloadAll` doing them in order, carrying on after a failure, and
  scanning once.

Widget tests:
- **Search screen:** mixed list order and labels; one source failing while
  the others show; all offline with a cache; the two buttons launching the
  right URLs (fake launcher); a nothing-found message.
- **Archive page:** loads; plays from the tapped track; Download all; offline
  with and without a saved list.
- **Settings:** per-source switches saved, greyed out under the main switch,
  Jamendo hidden without a client id.

Both `flutter test` and `flutter test --enable-impeller` pass, run with a
time limit.

On the phone (release-signed build with the Jamendo id): a search showing
all three sources; an Audius song playing in the background and with the
screen locked; an Archive show opening and playing; one download from each
source arriving in the library; both buttons opening their apps; Settings
switches turning sources off.

## Not in this part

Internet radio (part 2). Online results on Home. Per-source search pages or
filters. Audius or Archive accounts, likes or playlists. Showing Audius
genres or licences.
