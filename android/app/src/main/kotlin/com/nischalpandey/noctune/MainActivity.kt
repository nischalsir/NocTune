package com.nischalpandey.noctune

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity shares one Flutter engine with the playback service, so
// audio keeps running when this activity is destroyed.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctune/media_store")
            .setMethodCallHandler(MediaStoreChannel(applicationContext))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctune/artwork")
            .setMethodCallHandler(ArtworkChannel())
    }
}
