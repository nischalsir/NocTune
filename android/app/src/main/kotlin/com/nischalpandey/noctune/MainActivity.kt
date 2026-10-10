package com.nischalpandey.noctune

import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity shares one Flutter engine with the playback service, so
// audio keeps running when this activity is destroyed.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferFastestRefreshRate()
    }

    // Phones with 90 or 120 Hz screens may otherwise run the app at 60. Ask
    // for the fastest mode the screen has at its current resolution.
    private fun preferFastestRefreshRate() {
        runCatching {
            val screen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return
            val current = screen.mode
            val fastest = screen.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            window.attributes = window.attributes.apply {
                preferredDisplayModeId = fastest.modeId
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctune/media_store")
            .setMethodCallHandler(MediaStoreChannel(applicationContext))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctune/artwork")
            .setMethodCallHandler(ArtworkChannel())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctune/audio_capabilities")
            .setMethodCallHandler(AudioCapabilitiesChannel())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctune/device_profile")
            .setMethodCallHandler(DeviceProfileChannel(applicationContext))
    }
}
