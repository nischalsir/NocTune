# Decoder Choice and Output Sample Rate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner choose the decoder (System or FFmpeg) and the output sample rate (Original, 48, 96 or 192 kHz) in Settings › Audio, applied at once.

**Architecture:** A copy of `just_audio` 0.10.6 in `packages/just_audio` reads a static config when it builds its ExoPlayer: FFmpeg preferred with float output, and/or a `SonicAudioProcessor` resampling to a fixed rate. The FFmpeg decoder is media3 1.4.1's `decoder_ffmpeg` built here against an LGPL FFmpeg 6.0. Dart sends the config over a method channel and rebuilds the native player at the same position.

**Tech Stack:** Flutter/Dart, Riverpod, `just_audio` 0.10.6 (media3 1.4.1), Kotlin, Java, FFmpeg 6.0, Android NDK r26 (`26.x` in the SDK, or the newest installed), CMake 3.22.1 from the SDK, MSYS2 via Scoop.

**Spec:** `docs/superpowers/specs/2026-10-14-decoder-and-output-rate-design.md`

## Global Constraints

- Defaults change nothing: decoder `system`, output rate `0` (Original). With the defaults the app must behave exactly as 1.9.3.
- Choices: decoder `system` | `ffmpeg`; output rate `0`, `48000`, `96000`, `192000` Hz.
- FFmpeg: release/6.0, configured without `--enable-gpl`/`--enable-nonfree`; decoders exactly `aac mp3 flac alac opus vorbis`; ABIs `arm64-v8a armeabi-v7a x86_64`; `ANDROID_ABI` (API level) 24 = app `minSdk`.
- media3 decoder module at exactly 1.4.1, matching the plugin's `exoplayerVersion`.
- With FFmpeg and a rate other than Original, float output is off (Sonic is 16-bit only).
- The rows appear on Android only.
- Preference keys: `audio_decoder` (string `system`|`ffmpeg`), `audio_output_rate` (int Hz).
- Method channel `noctune/audio_output`, method `configure`, arguments `{'ffmpeg': bool, 'outputRate': int}`.
- Notices: FFmpeg (LGPL-2.1, version and configure line), media3 (Apache-2.0), plugin copy (MIT). README credits only Nischal Pandey.
- Never commit `*-main/` reference folders. Run tests with a wall-clock limit (`timeout 580 flutter test`).

## Review Focus

1. Switching while paused must not start playback; while playing it must resume at the same spot (± 1 s). Pinned by Task 4's apply-sequence test and Task 7's phone check.
2. Switching with nothing loaded must not crash or load anything; the choice applies to the next track. Pinned in Task 4.
3. FFmpeg chosen and a file it does not decode (AC-3/E-AC-3/Atmos, WAV PCM): it must still play through Android's decoder (extension mode PREFER falls back). Pinned in Task 7 with an E-AC-3 or WAV file if the library has one.
4. Equaliser and preamp after a switch must sound as before (the plugin rebuilds effects with their initial state). Pinned in Task 4 (applyEqualizer called again) and Task 7 (mixer dump shows effects enabled).
5. Toggling quickly: the last choice wins, and reloads do not overlap. Pinned in Task 4 (calls serialised).

---

### Task 1: Plugin copy wired in, no behaviour change

**Files:**
- Create: `packages/just_audio/` (copy of `%LOCALAPPDATA%/Pub/Cache/hosted/pub.dev/just_audio-0.10.6`, keeping its `LICENSE`)
- Create: `packages/just_audio/android/src/main/java/com/ryanheise/just_audio/NocTuneAudioConfig.java`
- Modify: `pubspec.yaml` (add `dependency_overrides: just_audio: { path: packages/just_audio }`)
- Modify: `analysis_options.yaml` (exclude `packages/**`)

**Interfaces:**
- Produces: `public final class NocTuneAudioConfig { public static volatile boolean ffmpeg; public static volatile int outputSampleRateHz; }` (defaults `false`, `0`).

- [ ] **Step 1:** Copy the plugin directory; add a one-line header comment to `README.md` of the copy saying it is NocTune's copy with Android player changes. Add the override and the analysis exclude.
- [ ] **Step 2:** Add `NocTuneAudioConfig` (fields above, Javadoc: read when the native player is built).
- [ ] **Step 3:** Verify: `flutter pub get` resolves `just_audio` to the path (`grep -A3 "just_audio:" pubspec.lock` shows `source: path`); `timeout 580 flutter test` passes; `flutter analyze` clean; `flutter build apk --release` succeeds.
- [ ] **Step 4:** Commit `feat(audio): use a copy of just_audio for the player setup`.

### Task 2: FFmpeg decoder libraries

**Files:**
- Create: `tool/build_ffmpeg_decoder.sh`
- Create: `packages/just_audio/android/src/main/java/androidx/media3/decoder/ffmpeg/*.java` (from media3 tag 1.4.1, `libraries/decoder_ffmpeg/src/main/java/androidx/media3/decoder/ffmpeg/`)
- Create: `packages/just_audio/android/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libffmpegJNI.so`
- Modify: `packages/just_audio/android/build.gradle.kts` (add `implementation("androidx.media3:media3-decoder:$exoplayerVersion")`)

**Interfaces:**
- Produces: `androidx.media3.decoder.ffmpeg.FfmpegLibrary.isAvailable()`, `FfmpegAudioRenderer`, loaded by `DefaultRenderersFactory` in extension mode.

- [ ] **Step 1:** Install MSYS2 with `scoop install msys2`, then in MSYS2: `pacman -S --noconfirm make diffutils pkgconf git`. If Scoop's MSYS2 cannot run `configure`, stop and ask the owner to install WSL; the script then runs there with the Linux NDK r26b.
- [ ] **Step 2:** Write `tool/build_ffmpeg_decoder.sh <work-dir>`: clones media3 at tag `1.4.1` (sparse: `libraries/decoder_ffmpeg`) and FFmpeg `release/6.0`; links FFmpeg into the module's `jni/ffmpeg`; runs media3's `build_ffmpeg.sh` with `HOST_PLATFORM` = `windows-x86_64` under MSYS2 (or `linux-x86_64`), API 24 and the six decoders; builds `libffmpegJNI.so` per ABI with the SDK's CMake and Ninja and the NDK's `build/cmake/android.toolchain.cmake` (`-DANDROID_ABI=<abi> -DANDROID_PLATFORM=android-24 -DCMAKE_BUILD_TYPE=Release`) from the module's `CMakeLists.txt`; copies each `.so` and the module's Java sources into the paths above. The script prints FFmpeg's configure line at the end.
- [ ] **Step 3:** Run it. Verify:
  - each `.so` exists;
  - `llvm-readelf -d` lists only system libraries as NEEDED;
  - `strings libffmpegJNI.so | grep -c -- "--enable-gpl"` prints `0`;
  - the APK from `flutter build apk --release` lists the three `lib/<abi>/libffmpegJNI.so` (`unzip -l`).
- [ ] **Step 4:** Commit `build(audio): FFmpeg 6.0 audio decoders (LGPL) for media3 1.4.1`, with the script, Java sources and libraries.

### Task 3: Player built from the config

**Files:**
- Modify: `packages/just_audio/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java` (`ensurePlayerInitialized`, around line 777)

**Interfaces:**
- Consumes: `NocTuneAudioConfig.ffmpeg`, `NocTuneAudioConfig.outputSampleRateHz` (Task 1); FFmpeg classes (Task 2).

- [ ] **Step 1:** Replace `new DefaultRenderersFactory(context)` with an anonymous subclass that:
  - uses `EXTENSION_RENDERER_MODE_PREFER` when `ffmpeg`, `EXTENSION_RENDERER_MODE_OFF` otherwise;
  - calls `setEnableAudioFloatOutput(ffmpeg && rate == 0)`;
  - when `rate > 0`, overrides `buildAudioSink(Context, boolean, boolean)` to return `new DefaultAudioSink.Builder(context).setEnableFloatOutput(enableFloat).setEnableAudioTrackPlaybackParams(params).setAudioProcessors(new AudioProcessor[] {sonic}).build()`, where `sonic` is a `SonicAudioProcessor` with `setOutputSampleRateHz(rate)`.
  Read the two fields once at the start of the method. Mark the method `@OptIn(markerClass = UnstableApi.class)` if lint asks.
- [ ] **Step 2:** Verify: `flutter build apk --release` succeeds; `timeout 580 flutter test` passes.
- [ ] **Step 3:** Commit `feat(audio): the player takes the decoder and output rate from its config`.

### Task 4: Settings model, channel and apply step

**Files:**
- Create: `lib/features/audio_output/audio_output_settings.dart`
- Create: `lib/features/audio_output/audio_output_controller.dart`
- Create: `android/app/src/main/kotlin/com/nischalpandey/noctune/AudioOutputChannel.kt`
- Modify: `android/app/src/main/kotlin/com/nischalpandey/noctune/MainActivity.kt` (register the channel beside the others, around line 45)
- Modify: `lib/features/playback/noc_audio_handler.dart`
- Modify: `lib/main.dart` (apply the saved choice before `runApp`, with `reload: false`)
- Test: `test/audio_output/audio_output_settings_test.dart`, `test/audio_output/audio_output_controller_test.dart`

**Interfaces:**
- Produces:
  - `enum AudioDecoder { system, ffmpeg }`.
  - `class AudioOutputSettings { const AudioOutputSettings({AudioDecoder decoder = AudioDecoder.system, int outputRateHz = 0}); static const List<int> rates = [0, 48000, 96000, 192000]; factory AudioOutputSettings.load(SharedPreferences); Future<void> save(SharedPreferences); AudioOutputSettings copyWith({AudioDecoder? decoder, int? outputRateHz}); bool get floatOutput; }`. Unknown saved values fall back to the defaults.
  - `Future<void> NocAudioHandler.applyAudioOutput(AudioOutputSettings settings, {bool reload = true})`. It:
    1. invokes the channel;
    2. if `reload` and the queue is not empty, notes the index, position and whether it is playing;
    3. `stop()`s, then `setAudioSources(<current queue>, initialIndex: index, initialPosition: position)`;
    4. plays again only if it was playing;
    5. re-applies the last `EqualizerSettings`.

    Calls are serialised: a call made while one runs waits for it.
  - `final audioOutputProvider = NotifierProvider<AudioOutputController, AudioOutputSettings>(...)` with `Future<void> setDecoder(AudioDecoder)` and `Future<void> setOutputRate(int hz)`; each saves, then calls `applyAudioOutput`.
  - Kotlin `AudioOutputChannel.handle(call, result)`: on `configure`, sets `NocTuneAudioConfig.ffmpeg` and `.outputSampleRateHz`, then replies `null`.

- [ ] **Step 1: Write failing tests.**
  - Settings: `'defaults are System and Original'` (empty prefs → `system`, `0`, `floatOutput` false); `'saves and loads both choices'` (ffmpeg + 96000 round-trip); `'an unknown saved rate falls back to Original'` (`audio_output_rate: 44100` → `0`); `'float output only with FFmpeg at the original rate'` (ffmpeg+0 → true, ffmpeg+48000 → false).
  - Controller, with a fake handler recording calls: `'choosing FFmpeg saves it and applies it'` (prefs `audio_decoder` == `ffmpeg`, one apply call with decoder ffmpeg); `'choosing a rate saves it and applies it'`.
  - Channel, with `TestDefaultBinaryMessengerBinding` mocking `noctune/audio_output`: `'applying sends the decoder and rate'` (`{'ffmpeg': true, 'outputRate': 48000}`); `'with nothing loaded only the config is sent'` (no reload calls on the fake player seam).
- [ ] **Step 2:** Run `timeout 300 flutter test test/audio_output`. Expected: compile failure on the missing classes.
- [ ] **Step 3:** Implement the interfaces above. Following `EqualizerSettings`/`EqualizerController`, the controller reads `sharedPreferencesProvider` and `audioHandlerProvider`.
- [ ] **Step 4:** Run `timeout 300 flutter test test/audio_output` and the full suite. Expected: PASS.
- [ ] **Step 5:** Commit `feat(audio): decoder and output rate settings, applied to the player`.

### Task 5: Settings rows

**Files:**
- Modify: `lib/features/settings/settings_screen.dart` (Audio group, after the Equaliser row)
- Test: `test/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `audioOutputProvider` (Task 4).

- [ ] **Step 1: Write failing tests** (with `debugDefaultTargetPlatformOverride = TargetPlatform.android`):
  - `'offers the decoder and the output rate on Android'`: finds `Decoder`, `System`, `FFmpeg`, `Output sample rate`, `Original`, `48k`, `96k`, `192k`.
  - `'choosing FFmpeg is saved'`: tap `FFmpeg` → prefs `audio_decoder` == `ffmpeg`.
  - `'iOS has no decoder rows'`: `Decoder` not found.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Add two `_Block` rows, shown only on Android:
  - **Decoder** (icon `Icons.memory_rounded`): `MornyeSegmentedControl(labels: ['System', 'FFmpeg'])`.
  - **Output sample rate** (icon `Icons.tune_rounded`): labels `['Original', '48k', '96k', '192k']`.

  Each has a `bodySmall` note under its control:
  - Decoder: `'System uses Android's decoders. FFmpeg decodes inside NocTune with headroom, so loud files are not clipped.'`
  - Output sample rate: `'Android may convert again to what the speaker or headphones support. With FFmpeg, any rate other than Original gives up its headroom.'`
- [ ] **Step 4:** Run the settings tests and the full suite. Expected: PASS. Render `6_settings`/`7_settings_about` with the preview tool and check the rows line up with the others.
- [ ] **Step 5:** Commit `feat(settings): decoder and output sample rate rows`.

### Task 6: Notices and docs

**Files:**
- Modify: `THIRD_PARTY_NOTICES.md`, `lib/app/licenses.dart` (and its licence assets, following how SpotiFLAC's MIT text is registered), `README.md` (one line under "What it does" › Player, and the build script under "Running it"), `CHANGELOG.md`

- [ ] **Step 1:** Add entries:
  - FFmpeg 6.0, LGPL-2.1, with the configure line the script printed and where its source is;
  - media3 decoder module 1.4.1, Apache-2.0;
  - `just_audio` copy, MIT.

  Add the LGPL-2.1 text as a licence asset.
- [ ] **Step 2:** Verify: the licences page test (`test/settings/settings_screen_test.dart`, `LicensePage`) passes; `grep -c "FFmpeg" THIRD_PARTY_NOTICES.md` ≥ 1.
- [ ] **Step 3:** Commit `docs: FFmpeg and media3 notices`.

### Task 7: Phone check

- [ ] **Step 1:** Install the release build over adb (phone etiquette: check `mCurrentFocus` before any screenshot; ask the owner to tap).
- [ ] **Step 2:** For each of System/Original, FFmpeg/Original and FFmpeg/48k, play a FLAC and one of the loud AAC files, and record:
  - `adb logcat -d --pid=<pid> | grep -iE "c2\.|ffmpeg|AudioTrack"` (decoder used, `maxAmplitude`);
  - `dumpsys media.audio_flinger` (NocTune's track rate and format, effects enabled).

  Expected:
  - System → a `c2.` decoder at the file's rate;
  - FFmpeg/Original → no `c2.` audio decoder, float track format (`00000005`);
  - FFmpeg/48k → a 16-bit 48000 Hz track.
- [ ] **Step 3:** Pause, switch, and confirm it stays paused at the same spot; play, switch, and confirm it carries on.
- [ ] **Step 4:** Write the results into `CHANGELOG.md` and report to the owner; a release only on their word.
