# Changelog

Versions follow [Semantic Versioning](https://semver.org). The number after
`+` in `pubspec.yaml` is the Android build number and goes up with every
build that is distributed.

Release channels:

- **Pre-release**: passes the automated checks, not yet confirmed on a device.
- **Stable**: also confirmed on a real device.

## 1.9.2 (build 17) - 2026-10-14

Published at the owner's request. The automated checks pass, with and
without Impeller. Most of it was run on the owner's phone while it was
built (the Library header, the menus, the Home table, the player cover
and the light player); the last changes (the cover drawn at the screen's
width, Equaliser alignment, the Devanagari and "v1:" lyrics fixes, and
Settings titles level with the tops of their icons) were installed on the
phone but not yet looked at there.

### Changed

- Library: the title "Your library" is at the top of the page. Under it
  the buttons say what they do: a wide Search, with Scan and Sort on its
  right, each a glass pill with its icon and a word. Import is no longer
  among them; it is still offered when the library is empty.
- Menus (the Favourites and playlist "⋯" menu with Change cover, and the
  Library's Sort menu) look like the Home list's menu: a rounded solid
  panel in the theme's colours. The Favourites and playlist items have
  icons.
- Home: the List card is a table. Column headings (#, Song, Played or
  Plays) sit over numbered rows; Recent shows the time each song was
  played, with "3×" under it for repeats that day, and the other lists
  their play counts, albums and artists included. The card is about
  seven rows tall and scrolls by itself, so the page no longer grows
  with every song played.
- Player: the cover is no longer enlarged. It still runs from the top of
  the screen and fades into the backdrop, but it is drawn at the
  screen's width, so none of its sides is cut off.
- Player and lyrics follow the app's theme. In the light theme the
  washes over the cover are white, text and icons near black, and the
  glass buttons frosted white; the dark theme is unchanged.
- Lyrics: the "LINE SYNC • Embedded in the audio file" label is gone.
- Settings: the title, the section headings and the cards share one left
  edge, and the title matches the Library's. Every row's title starts
  level with the top of its icon, switches sit on the title's line,
  sliders run the width of the text, and all controls end on the same
  right edge.
- Equaliser: the switch ends where the preamp figure does, the preamp
  slider runs the width of the text, and the buttons start on the
  cards' text edge.
- Library: the sort order of the tracks and the tab last open (Tracks,
  Albums, Artists, Playlists, Genres or Folders) are kept when the app
  is closed. A first launch opens on Tracks by title, as before.

### Fixed

- Home: the plays number and the other numbers on the statistics card
  show their saved value when the card appears. They used to count up
  from zero every time the app opened, which looked like the total was
  climbing. A new play while the card is showing still counts up.
- Pressing play on the song brought back from the last session carries
  on that play instead of counting a new one, when the last session had
  stopped partway through it.
- Listening time adds only the time actually listened. Skipping a
  3-minute song after 40 seconds adds 40 seconds; time spent paused is
  not counted, and pausing and resuming adds each stretch once. It used
  to add every play at the song's full length.
- Lyrics: a dimmed line in Devanagari (Nepali, Hindi) no longer shows
  lighter seams along the top line where letters join; dimmed lines are
  drawn solid and faded as a whole.
- Lyrics: duet lyrics that mark each line's singer with "v1:", "v2:" and
  so on (converted from Apple Music) no longer show those marks.

### Database

- Schema 5 adds the listening time of each track. The total from before
  the update was only an estimate (every play at full length); it is
  kept as the starting amount, so nothing drops on update. Clearing the
  listening history also clears it.

### Tests

- The recorder is checked for skips, pausing, cued-up tracks and the
  resumed song; the repository and the upgrade from schema 4 for the new
  listening time; the statistics card for showing its number at once;
  the Library for its title above labelled buttons and for remembering
  its sort order and tab; the lyrics reader for dropping "v1:" marks.

## 1.9.1 (build 16) - 2026-10-11

Published at the owner's request. The automated checks pass and the list
was looked at as a rendered frame; this build has not been run on a phone.

### Changed

- Library: the round button on the row of the song loaded in the player
  now pauses it, and carries on from where it stopped when it is paused.
  It shows a pause or a play sign to match. It used to start the song
  again from the beginning, which a tap on the row itself still does.
  The buttons on the other rows are unchanged.

### Tests

- The button is checked to show the right sign, to pause while playing
  and to resume while paused without starting the song again.

## 1.9.0 (build 15) - 2026-10-11

Published at the owner's request before deleting was tried on a phone. The
automated checks pass; the Android part that asks the system to remove a
file has not been run on a device.

### Added

- Delete a song. "Delete from device" is the last entry in a song's menu
  (press and hold a song in a list, or the menu in the player). NocTune asks
  first. For a file in shared storage Android then asks once more itself and
  does the removing. The song also leaves the library, its playlists, the
  favourites and the queue.
- Duplicates page: a delete button beside each copy.

### Changed

- The Duplicates page no longer says NocTune never deletes files.

### Known issues

- Deleting a file in shared storage needs Android 11 or later. On older
  versions NocTune says so and deletes nothing. Files NocTune imported
  itself can be deleted on any version.
- Some AAC songs crackle when loud. One was measured against the FLAC of
  the same song from the same phone. It is a 96 kbit/s AAC track inside a
  video file, and decoded exactly it goes up to 20% over full scale in
  6,656 samples, where the FLAC never does. Android's AAC decoder hands
  over 16-bit sound, which cannot hold those peaks, and it does so before
  the equaliser and the preamp, so neither can undo it. Repairing that
  takes a decoder of NocTune's own, which is the larger job listed under
  1.8.0. Not fixed.
- Such files carry a moving picture that the player decodes and throws
  away, which costs battery. The audio plugin has no setting for that.

### Tests

- Deleting is covered by 4 new tests: it asks first, Cancel changes
  nothing, a yes removes the file, the library entry and the queue entry,
  and a refusal or a failure keeps the song and says why.

## 1.8.0 (build 14) - 2026-10-11

Run on the owner's phone before release. The phone's mixer showed the
equaliser, the loudness enhancer and the preamp each taking effect, the
shapes were heard to change the sound, and the crackle its speaker made at
high volume was mostly gone with "Small speaker" and a lowered preamp.

### Added

- An equaliser, under Settings, Audio, Equaliser. It has a switch, a
  slider for each band the phone's own equaliser offers (five on most
  phones), ready-made shapes (Flat, Bass boost, Treble boost, Vocal, Rock,
  Pop, Jazz, Classical, Small speaker), shapes of your own saved under a
  name, and a preamp from -12 to +6 dB. Switched off, which is how it
  starts, nothing touches the sound. What you set is kept and applied
  again at launch.
- It uses Android's equaliser, which the player already had attached and
  switched off. A preamp below 0 turns the player's own level down; above
  0 it uses Android's loudness enhancer. The phone's own sound processing
  (Dolby, spatial sound) still comes after it.
- "Small speaker" takes the deepest band down and raises nothing, for
  a phone speaker that rattles when the volume is high.

### Changed

- Settings: the "Sound processing" line is now the Equaliser row, and
  says whether it is on and with which shape.

### Known issues

- Some AAC songs still crackle on the phone's speaker when the volume is
  high. Not yet looked into.
- The equaliser and the loudness enhancer have been run on one phone. A
  device that cannot create one of them would fail to load songs.

### Not done

- A choice of decoder was asked for together with the equaliser. It needs
  a modified copy of the audio plugin with FFmpeg inside the app, and it
  would not change how a FLAC file sounds: a lossless file decodes to the
  same samples whatever decodes it. Left for a later version if still
  wanted.

### Tests

- The shapes, storing and reading the settings, and the page's switch,
  sliders, shapes, saving and deleting are covered by 22 new tests.

## 1.7.1 (build 13) - 2026-10-11

Fixes what running 1.7.0 on the owner's phone showed. The cause was found
by timing frames on that phone with test builds, not by guessing. Build 13
was run on that phone, and the shade and the control centre are smooth
over the app again with music playing.

### Fixed

- With music playing, Home took more than the phone's whole frame time,
  which slowed the system's own animations over the app: the notification
  shade and the control centre moved as if the screen ran at a fraction of
  its 120 Hz. While music plays, the bars in the "Now playing" pill redraw
  the screen on every frame, and every one of those frames blurred the
  artwork again behind the search field and behind the pill. On the phone,
  18 to 31 frames in a hundred ran late; without those two blurs, 2 to 4,
  fewer than in 1.5.0. The pills now paint their glass without blurring
  what is behind them, and look the same over the dark scrim they sit on.
  The navigation bar that came in 1.6.0 added one more glass pass to each
  frame, which is what pushed an already heavy screen over the limit; with
  the blurs gone it costs nothing that can be measured, and it stays.
- That alone did not make the shade smooth (build 12, tried on the phone).
  While music played the app went on drawing a new frame on every tick of
  the screen even with the shade down over it, and the system had to draw
  each of those frames again behind its own blur. Now, while the app is
  not the one in front (under the notification shade or the control
  centre, behind a system dialog, unfocused in a split screen), its
  decoration holds still: the sound bars, the pulsing "Now Playing" pill,
  the seek bar's wave and the navigation bar. On the phone, over a page of
  the app that was holding still, the system drew about a quarter more
  frames of its own in the same time than over Home in motion. Lyrics keep
  moving, because their motion is the content.

### Changed

- The active tab in the navigation bar takes the app's accent colour,
  which follows the cover art while "Match the cover art" is on, in place
  of a red of its own.

### Tests

- Home's hero is checked to hold no backdrop blur while its bars move,
  and the bar's active colour is checked against the accent.
- Home and the player are checked to ask for no frames while the app is
  covered, and to carry on when it is back in front.

## 1.7.0 (build 11) - 2026-10-11

Published as a normal release at the owner's request. Version 1.6.0 was run
on the owner's phone and this release answers what was seen and asked for
there; this build itself has not yet been run on a phone.

### Added

- Favourites have a page of their own, in the album design: their covers,
  how many tracks there are and how long they run, Play and Shuffle. It
  opens from the Favourites chip in the library and from "See all" on
  Home. From its menu a picture of your own can be set as its cover, and
  removed again.
- Playlists are albums of your own making. A playlist's menu has "Add
  tracks", which lists the whole library with a search and lets many
  tracks be ticked at once, and "Change cover" and "Remove cover" for a
  picture of your own. A new playlist opens straight away, ready to be
  filled, and the library lists playlists by their covers.
- The library has a search of its own: a round button opens a field at
  the top, and matching tracks take the place of the list as you type.
  Back closes it.
- The Search page remembers the last ten searches and lists them while
  the field is empty. A tap runs one again, and Clear empties the list. A
  search is remembered when it is sent from the keyboard or one of its
  results is played, not on every letter.

### Changed

- Library: a new look. Round glass buttons at the top for searching,
  importing, rescanning and sorting, "Your library" under them, the
  sections as pills with the chosen one filled in the accent colour, and
  each track row ending in its length and a round play button. A track's
  menu is now a press and hold on its row.
- Album, artist, genre, folder, playlist and favourites pages take their
  colour from the main colour of the cover in front, deep in the dark
  theme and pale in the light one, in place of a blur of the cover that
  was barely visible behind dark covers. With only two covers, the second
  no longer leans out on one side alone.
- A page opened from Home, such as an album from the shelf, keeps the
  navigation bar and the mini-player, as pages opened from the library
  do. Back closes it first.
- Opening and closing the player move on springs that never pass their
  end: quick away and a long, soft arrival, about 0.55 s to open and 0.5 s
  to close, where they were 0.42 s and 0.3 s on fixed curves. Let go while
  it is being dragged, it carries on at the speed the finger gave it.

### Fixed

- Lyrics: the lit words stood about a pixel below the dim words under
  them. The dim copy is laid out for the app's language and the lit copy
  was not, and in the app's typeface that moves the letters. Both are now
  laid out the same way.

### Data

- The library database moves to version 4: a playlist can hold a cover.
  Existing playlists, tracks, favourites and history are kept. Covers you
  choose are copied into the app's own storage.

### Tests

- The lit copy of a lyric line is checked, letter for letter, against
  the dim copy in the app's typeface, theme and language.
- The favourites page, covers chosen and removed, tracks ticked into a
  playlist, the library's search and play buttons, the search history,
  and an album opened from Home keeping the navigation bar.
- The upgrade of a version 3 library.

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
