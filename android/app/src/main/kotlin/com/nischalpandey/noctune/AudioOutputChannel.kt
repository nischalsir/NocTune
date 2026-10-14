package com.nischalpandey.noctune

import com.ryanheise.just_audio.NocTuneAudioConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Takes the decoder and output sample rate chosen in Settings. The player
 * reads them when it is next built; Dart rebuilds it after sending them.
 */
class AudioOutputChannel : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                NocTuneAudioConfig.ffmpeg = call.argument<Boolean>("ffmpeg") ?: false
                NocTuneAudioConfig.outputSampleRateHz = call.argument<Int>("outputRate") ?: 0
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
