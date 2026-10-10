# Changelog

Versions follow [Semantic Versioning](https://semver.org). The number after
`+` in `pubspec.yaml` is the Android build number and goes up with every
build that is distributed.

Release channels:

- **Pre-release**: passes the automated checks, not yet confirmed on a device.
- **Stable**: also confirmed on a real device.

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
