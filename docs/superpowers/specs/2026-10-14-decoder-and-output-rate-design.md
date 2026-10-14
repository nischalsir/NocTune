# Decoder choice and output sample rate

Date: 2026-10-14. Status: approved in conversation, awaiting review of this
written spec.

## Goal

Poweramp-style audio controls in NocTune's Settings: the owner can choose the
decoder and the output sample rate. The owner was told that on their phone
Android already converts all audio to its output rate (normally 48 kHz), so
upsampling in the app is not expected to change what is heard; they still
want the choice. The FFmpeg decoder is also the one option likely to stop the
known crackle in some loud AAC files (they overshoot full scale and Android's
16-bit decoder cannot hold the peaks), because it can decode into float.

## What the owner sees

Settings › Audio, two new rows under Equaliser:

- **Decoder**: *System* (default; Android's own decoders, today's
  behaviour) or *FFmpeg* (decoded inside NocTune, with headroom for loud
  files).
- **Output sample rate**: *Original* (default), *48 kHz*, *96 kHz*,
  *192 kHz*. Its note says Android may convert again to what the speaker or
  headphones support, and that with FFmpeg any rate other than Original
  gives up FFmpeg's headroom (see Limits).

Both are saved with the other settings and apply at once: the song carries
on from the same position after a short gap (under a second), with the
equaliser and preamp as they were. With the defaults nothing changes.

## How it is built

1. **Plugin copy.** `just_audio` 0.10.6 is copied to `packages/just_audio`
   and used through `dependency_overrides`. Only its Android player setup
   (`AudioPlayer.ensurePlayerInitialized`) changes, reading a small static
   config class in the copy:
   - FFmpeg: the renderers factory runs with extension renderers preferred
     (`EXTENSION_RENDERER_MODE_PREFER`) and float output enabled.
   - A sample rate: the audio sink gets a `SonicAudioProcessor` set to that
     output rate.
   The copy keeps its MIT licence and is listed in the notices.
2. **FFmpeg decoder, built here.** media3 1.4.1's `decoder_ffmpeg` module
   (Apache-2.0), built against FFmpeg configured without GPL or nonfree
   parts (LGPL-2.1), with only the audio decoders AAC, MP3, FLAC, ALAC,
   Opus and Vorbis. Built through WSL with the Linux Android NDK for
   arm64-v8a, armeabi-v7a and x86_64. The build script
   (`tool/build_ffmpeg_decoder.sh`) and its output (the module's Java
   sources and the `.so` libraries) are committed, so ordinary app builds
   need neither WSL nor the NDK. FFmpeg is linked dynamically (its own
   `.so`), as the LGPL requires to allow relinking.
3. **App side.**
   - `AudioOutputSettings` (decoder, output rate) with load/save in
     `SharedPreferences`, following `EqualizerSettings`.
   - A controller/provider in the style of the equaliser's.
   - A method channel `noctune/audio_output` in `MainActivity` that sets
     the plugin copy's static config.
   - `NocAudioHandler.applyAudioOutput(settings)`: sends the config, then,
     if a track is loaded, stops the player (which releases the native
     player), reloads the queue at the same index and position, resumes if
     it was playing, and re-applies the equaliser (the plugin rebuilds
     effects with their initial state only). The saved choice is applied
     at launch before the first track loads.
4. **Notices.** FFmpeg (LGPL-2.1, with the version and how it was
   configured), media3 decoder module (Apache-2.0) and the plugin copy
   (MIT) in `THIRD_PARTY_NOTICES.md` and the in-app licences page. The
   README still credits only the owner.

## Limits

- `SonicAudioProcessor` handles 16-bit audio only, so with FFmpeg and a
  rate other than Original, float output is turned off and FFmpeg decodes
  to 16-bit.
- Android's mixer may resample again to the device's output rate; the
  setting decides what NocTune hands Android, not what reaches the speaker.
- Other platforms (iOS) are unchanged; the rows show only on Android.

## Testing

- Automated: settings load/save and defaults; the Settings rows (choices,
  notes, saved values); the apply step in the handler with a fake channel
  (config sent, queue reloaded at the same position, equaliser re-applied,
  nothing reloaded when no track is loaded).
- On the owner's phone, read-only: `logcat` names the decoder in use
  (`c2.android.*` for System, FFmpeg's for FFmpeg); `dumpsys
  media.audio_flinger` shows NocTune's track sample rate and format; play
  one of the loud AAC files with FFmpeg and look for full-scale clipping in
  the log's `maxAmplitude`.

## Out of scope

Bit-depth choice, a 10-band equaliser of NocTune's own, the player screen,
iOS.
