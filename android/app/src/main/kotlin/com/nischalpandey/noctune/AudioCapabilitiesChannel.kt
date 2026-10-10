package com.nischalpandey.noctune

import android.media.MediaCodecList
import android.media.MediaFormat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports which audio formats this device can actually decode. NocTune only
 * shows a "Dolby Atmos" label when the device has a decoder for the Atmos
 * flavour of Dolby Digital Plus; it never assumes one from the brand or model.
 */
class AudioCapabilitiesChannel : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodesAtmos" -> result.success(hasDecoder(ATMOS_MIME))
            else -> result.notImplemented()
        }
    }

    private fun hasDecoder(mime: String): Boolean {
        // 48 kHz 5.1 is the ordinary carrier format for Dolby Digital Plus.
        val format = MediaFormat.createAudioFormat(mime, 48000, 6)
        return MediaCodecList(MediaCodecList.REGULAR_CODECS)
            .findDecoderForFormat(format) != null
    }

    private companion object {
        /** Dolby Digital Plus with Joint Object Coding: Dolby Atmos. */
        const val ATMOS_MIME = "audio/eac3-joc"
    }
}
