package com.ryanheise.just_audio;

/**
 * NocTune's choices for how audio is decoded and handed to Android. Read
 * when the native player is built, so a change takes effect the next time
 * the player is created.
 */
public final class NocTuneAudioConfig {
    private NocTuneAudioConfig() {}

    /** Decode with FFmpeg in preference to Android's own decoders. */
    public static volatile boolean ffmpeg = false;

    /** The sample rate to resample to, in Hz, or 0 to keep each file's own. */
    public static volatile int outputSampleRateHz = 0;
}
