# Changelog

Versions follow [Semantic Versioning](https://semver.org). The number after
`+` in `pubspec.yaml` is the Android build number and goes up with every
build that is distributed.

Release channels:

- **Pre-release**: passes the automated checks, not yet confirmed on a device.
- **Stable**: also confirmed on a real device.

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
