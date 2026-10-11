# Changelog

Versions follow [Semantic Versioning](https://semver.org). The number after
`+` in `pubspec.yaml` is the Android build number and goes up with every
build that is distributed.

Release channels:

- **Pre-release**: passes the automated checks, not yet confirmed on a device.
- **Stable**: also confirmed on a real device.

## 1.6.0 (build 10) - 2026-10-11

Published as a normal release at the owner's request; not yet run on a
phone. The Library pages follow a design picture the owner supplied, and
the bottom bar's tabs are set up as in another app of the owner's.

### Changed

- Library: the page for a playlist, album, artist, genre or folder is new.
  Its covers are fanned out at the top, the first track's in front and up
  to two more leaning out from behind it, over a wash of that cover's
  colours that fades into the page. Under them are the name, how many
  tracks there are and how long they run, and two buttons: Play, which
  starts the list in order, and Shuffle. The whole page scrolls as one
  list, and the way back and a playlist's menu stay at the top as glass
  buttons.
- Bottom bar: on glass, the selection rests as a flat pill and travels
  between tabs as a lens that bends the bar under it, on a spring. Holding
  a tab picks the lens up so it can be slid along the bar. The fold on
  scroll, the order of the tabs, the mini-player and the glass clarity
  setting are as they were.
- Bottom bar: its labels stop growing at one and a half times the normal
  text size, because the glass capsule has a fixed height.
- Opening the player: it grows out of the mini-player, upwards and
  downwards until it fills the screen, and the tabs move down just under
  its lower edge instead of being covered. Closing it, by its button, the
  back key or a swipe down, shrinks it back into the mini-player. With
  reduced motion it fades in and nothing moves. The player itself is
  unchanged.

### Tests

- The player's opening is checked frame by frame: it starts as the
  mini-player's own rectangle with the tabs where they were, its top only
  rises and its bottom only falls, no edge crosses the screen in a single
  frame, and the tabs stay under its lower edge throughout.
- The Library page: its details line, Play and Shuffle, the covers it fans
  out, a playlist's menu, an empty playlist, and its layout on a small
  phone, with large text, in landscape and on a tablet.

## 1.5.0 (build 9) - 2026-10-11

Published as a normal release at the owner's request; not yet run on a
phone. The lyric motion was tuned against a screen recording the owner
supplied of the motion wanted, measured line by line and frame by frame.

### Changed

- Lyrics, moving to the next line: the list is carried there by a spring
  instead of a 900 ms glide. It is quick away, about half way after 150 ms
  and at rest within 600 ms, and it never overshoots. A line that arrives
  while the list is still moving sets the spring off at the speed the list
  already has.
- Lyrics: the lines below the new one trail behind the list and catch up
  one after another, the further down the later. They are never pushed
  down first: each simply rises on a softer spring.
- Lyrics: a line now brightens or dims in 320 ms (it was 700), and grows or
  shrinks on a spring with a slight overshoot.
- Lyrics: lines away from the one being sung are out of focus again, more
  so the further away. Each is blurred once and kept as a picture, and a
  change of focus fades one picture over another, so no blur is worked out
  on each frame. The lines come into focus while the list is moved by
  hand. Devices short of memory keep every line sharp.
- The word-by-word fill is as it was.
- Bottom bar: the selection travels to a tab on a spring that passes it by
  a touch and settles, and the glass lens springs up under the finger and
  settles back when let go.
- Settings: the theme is chosen with the same glass selector as the
  navigation bar, by a tap or by sliding across it. The switches are
  iOS-style: the thumb stretches under the finger and can be dragged.

### Tests

- A line change is checked frame by frame: no line moves more than a few
  pixels between frames, none moves backwards, the lower lines trail and
  then catch up, and a line arriving mid-move does not stop the list.

## 1.4.1 (build 8) - 2026-10-11

Published as a normal release at the owner's request; not yet run on a
phone.

### Fixed

- Lyrics: on every line change, the new line and the six below it were
  pushed down by 8 to 26 px in a single frame and then eased back. That
  jump is gone. A test now fails if any line moves more than a few pixels
  between two frames.
- Lyrics: a line that arrives while the list is still gliding to the one
  before no longer stops the list and starts it again. The glide carries on
  at the speed it had.
- Bottom bar: the grey pill is back under the selected tab. It gives way to
  the glass selector while the selection moves (a tap, a slide, or a page
  changed from elsewhere) and returns once the selection has stopped, so
  the two are never shown together. A quick tap keeps the glass for the
  whole trip instead of dropping it when the finger lifts.
- Bottom bar: it parts and closes on the same clock as the mini-player
  above it. In 1.4.0 the halves had reached the sides when the mini-player
  was 60% of the way down, and only began to fill in again after it had
  risen 40%.

### Changed

- Player: the blurred backdrop is drawn once for each cover and kept as a
  picture, instead of being blurred again on every frame the lyrics or the
  seek bar repaint.
- Lyrics: every line, the word fill and the seek bar are their own layers,
  so the fill redraws nothing but itself. While a line changes size it is
  scaled as a picture, so its letters are not drawn afresh at a new size on
  each frame; at rest it is text again.
- The buttons over the lyrics no longer blur the backdrop a second time,
  and the three over the cover share one blur.

### Tests

- The suite also passes with `flutter test --enable-impeller`, the renderer
  phones use. That run includes the glass selector, which the default test
  renderer cannot draw.

## 1.4.0 (build 7) - 2026-10-10

Published as a normal release at the owner's request; not yet run on a
phone.

### Added

- Home: typing in the search field shows the results on the home screen
  itself, in place of the feed, until the search is closed. Back closes it.
- Home: a shelf of the newest albums and a shelf of favourites, before the
  play statistics. Tapping an album opens it; tapping a favourite plays the
  favourites from there.
- The Search page opens with the keyboard up.

### Changed

- Bottom bar: the glass selector is back and the grey pill behind it is
  gone. 1.3.2 had removed the wrong one of the two.
- Folding the bar: it parts in the middle and each half draws back into the
  round button at its side, with the mini-player coming down over it.
  Unfolding fills it back in from the sides. Nothing fades through the page
  any more.
- Lyrics: when the line changes, only the lines near it are redrawn instead
  of the whole song, and the per-line blur is gone, so the change costs far
  less. The scroll and the easing are slower.
- One typeface on every screen, at its regular width, including the bottom
  bar. Pages share one left edge, and the pills and round buttons on Home
  are a little smaller.
- Light theme: cards, pills and menus on Home are white glass with a thin
  rim. Status and navigation bar icons are dark on light pages and light
  over the hero and the player. The hero's buttons keep their dark glass.

## 1.3.2 (build 6) - 2026-10-10

Published as a normal release at the owner's request; not yet run on a
phone.

### Changed

- Lyrics light up word by word instead of the whole line turning white at
  once, with a soft edge that moves across the word being sung. When a file
  times each word, those times are used and the view says "WORD SYNC". Most
  files only time whole lines ("LINE SYNC"); for those the line's time is
  shared between its words by length, which is an even sweep and not
  knowledge of when each word is sung.
- Lyric lines change over more slowly and smoothly: the scroll, the
  enlargement, the dimming and the blur all ease in and out without a snap.
  The fill itself moves on every frame.
- Folding the bottom bar no longer wipes the tabs away from the top. They
  fade out where they are while the two icons glide to the sides, and the
  fold takes a little longer.
- The app asks the phone for its fastest screen refresh rate, so motion can
  run at 90 or 120 Hz where the screen supports it.

### Fixed

- The selected tab in the bottom bar had a second, larger glass outline
  sitting off-centre around it, which swelled further when touched. It is
  gone; the selection is a single pill.

## 1.3.1 (build 5) - 2026-10-10

Published as a normal release at the owner's request; not yet run on a
phone.

### Changed

- The bottom bar now reads Home, Library, Search, Settings: Search and
  Settings swapped places. Settings, being last, is also the button the bar
  keeps on its right when it folds.

## 1.3.0 (build 4) - 2026-10-10

Published as a normal release at the owner's request. It passes the automated
checks and was reviewed as rendered screens; it has not yet been run on a
phone.

### Changed

- Navigation: Settings is in the bottom bar again, so the bar reads Home,
  Library, Settings, Search. Each tab is built the first time it is opened
  and keeps its place afterwards.
- Player: rebuilt. The cover fills the top of the screen edge to edge and
  melts into a blurred, darkened copy of itself; below it are the title and
  artist, the seek bar, previous / play / next with a wide labelled play
  button, and a row with shuffle, the audio quality and repeat. The player is
  always dark. The queue opens from the top bar.
- The lossless and Dolby Atmos labels moved into the quality pill of that
  row, which now also names the format, for example `FLAC 24/96`. The rules
  for when they appear are unchanged.
- Mini-player: taller, with a larger cover and room around it. A title or
  artist too long for the bar scrolls past instead of being cut off.
- The navigation bar's glass is more frosted, so lists passing behind it no
  longer clash with its labels. Settings > Appearance has a slider for it.
- Lyrics: the sync-offset button and the lyrics menu moved to the top bar.
- Settings: a Playback section with a switch between the wave seek bar and a
  plain thick one.
- Home and Settings cards share one set of corner radii, with inner panels
  rounded to match the card around them.

### Fixed

- Lyrics could light up a line late: the position was read five times a
  second. It is now read twenty times a second while lyrics are showing.
- Lyric files with several lines at one timestamp showed them as separate
  rows in an unpredictable order, only one of which ever lit up. They are now
  one row, in the file's order, and exact repeats are dropped.
- An untimed line directly under a timed one was thrown away; it is now kept
  as the rest of that line. Several empty gaps in a row count as one.
- The other lyric lines shifted slightly every time the active line changed.
- Lines other than the active one were dimmer than intended, a long active
  line could touch the edge of the screen, and a large system text size made
  lyrics oversized.
- The lyrics view built a blur layer for every line of the song; it now does
  so only for the lines near the one being sung.
- On screens with an empty library or no search results, the message and its
  buttons could sit behind the navigation bar.
- Covers are kept in the app's cache, and stayed missing if the phone cleared
  it. A track whose cover has gone is now read again at the next scan, which
  the app runs at launch.
- With very large text, the player's top bar clipped its title and the
  "Nothing is playing" message overflowed.

## 1.2.0 (build 3) - 2026-10-10

Published as a normal release at the owner's request. It passes the automated
checks and was reviewed as rendered screens; it has not yet been run on a
phone.

### Changed

- Navigation: the bottom bar is now a floating glass bar with Home, Library
  and Search. Its selection pill can be dragged between tabs, and while a
  page is scrolled down it folds into two round buttons either side of the
  mini-player. Settings opens as a page from the home screen instead of
  being a tab. A navigation rail replaces the bar only on desktop-width
  windows.
- Home: under the hero, a listening feed with the estimated listening time,
  a statistics card whose numbers count up, and a list that switches between
  Recent (grouped by day, with repeat counts), Most Played, Last 7 Days,
  Last 30 Days, Top Artists and Top Albums.
- Lyrics: a full view of its own, always dark. The line being sung is large,
  bright and sharp while the others recede; the view has a wave-shaped seek
  bar, previous / play / next, a text-size slider and a fullscreen mode.
- Settings: redesigned as grouped sections (appearance, lyrics, audio,
  notification, library, privacy, about).

### Added

- Play history: every play is logged, which is what the home lists are built
  from. Existing play counts are kept; the last play of each track is carried
  into the new log.
- Lyrics sync offset, saved per track, for files whose timestamps run early
  or late.
- Settings: lyrics text size, a switch for folding the navigation bar,
  "Check for updates", "Clear listening history" (asks first), the playback
  notification's permission, the version with its build number, and the
  open-source licences.
- The glass effect of the navigation bar adapts to the device: full on phones
  with 6 GB of memory or more, lighter on others.

### Notes

- Database schema 3 adds the play log. The upgrade is automatic and keeps
  everything.
- The navigation bar is open-source code used under the MIT licence; see
  THIRD_PARTY_NOTICES.md.
- Not included: lyrics downloaded from the internet, word-by-word lyric
  timing, an equalizer screen and a sleep timer.

## 1.1.0 (build 2) - 2026-10-10 - pre-release

### Added

- Bottom bar that folds its tabs away while a page is scrolled, leaving the
  mini-player between the current destination and search. Swiping the
  mini-player sideways stops playback and clears the queue.
- Home screen hero that shows "Now playing" with moving sound bars when the
  featured track is the one in the player, above library totals and a list
  that switches between recent, most played, recently added and favourites.
- Redesigned player with round frosted-glass buttons and a thicker seek bar
  showing time played and time left.
- Lyrics: from a file imported for a track, an `.lrc` file beside it, or
  lyrics embedded in its tags. Time-synced lyrics highlight the current line,
  follow playback and seek when a line is tapped. Text size is adjustable.
- Format labels above Play/Pause: LOSSLESS for files confirmed lossless by
  their contents, and Dolby Atmos for Atmos recordings on devices that report
  a decoder for them.
- Settings shows whether the device reports a Dolby Atmos decoder.

### Changed

- System back now leaves an opened album or playlist, then returns to Home,
  then asks for a second press before leaving the app.
- A `.flac` or `.wav` file is only described as FLAC or PCM when its contents
  confirm it.

### Data

- Local database schema 1 → 2, applied automatically on first launch. It adds
  a table for imported lyrics and records which version of the tag reader
  described each track. Nothing is removed. The first scan after updating
  re-reads every file once to apply the stricter format checks.

### Known issues

- Not yet run on a physical device; published as a pre-release for that
  reason.
- No iOS build: the build workflow could not run.
- Reading an `.lrc` file beside a track depends on Android allowing access to
  it; embedded and imported lyrics are unaffected.
- Dolby Atmos is never labelled on iOS, where the app cannot check for a
  decoder.

## 1.0.0 (build 1) - 2026-10-10

First release.

- Library scan of the device, file import, tags and artwork.
- Playback with queue, shuffle, repeat, background audio and system media
  controls.
- Library browsing, search, playlists and favourites.
- Accent colour taken from the cover art.
- First-run welcome and an update check against this repository's releases.
