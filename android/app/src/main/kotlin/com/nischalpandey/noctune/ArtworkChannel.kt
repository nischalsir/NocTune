package com.nischalpandey.noctune

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * Shrinks embedded cover art for the artwork cache. Album covers are often
 * several megabytes; the cache keeps a screen-sized JPEG instead.
 */
class ArtworkChannel : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "downscale") {
            result.notImplemented()
            return
        }
        val source = call.argument<String>("source")!!
        val target = call.argument<String>("target")!!
        val maxSize = call.argument<Int>("maxSize")!!
        executor.execute {
            val written = try {
                downscale(source, target, maxSize)
            } catch (e: Exception) {
                false
            }
            mainHandler.post { result.success(written) }
        }
    }

    /** Returns false when the image can't be decoded, leaving [target] unwritten. */
    private fun downscale(source: String, target: String, maxSize: Int): Boolean {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source, bounds)
        val longest = max(bounds.outWidth, bounds.outHeight)
        if (longest <= 0) return false

        // Decode at a power-of-two fraction first so a huge cover never sits
        // in memory at full size.
        var sample = 1
        while (longest / (sample * 2) >= maxSize) sample *= 2
        val decoded = BitmapFactory.decodeFile(
            source,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return false

        val scale = maxSize.toFloat() / max(decoded.width, decoded.height)
        val bitmap = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt().coerceAtLeast(1),
                (decoded.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            decoded
        }
        File(target).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        return true
    }
}
