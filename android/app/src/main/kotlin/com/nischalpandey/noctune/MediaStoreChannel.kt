package com.nischalpandey.noctune

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Lists the music Android has already indexed on this device. Read-only: it
 * never writes to MediaStore or touches the files.
 */
class MediaStoreChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            // A large library takes a while to read, so keep it off the UI thread.
            "queryAudio" -> executor.execute {
                try {
                    val rows = queryAudio()
                    mainHandler.post { result.success(rows) }
                } catch (e: SecurityException) {
                    mainHandler.post { result.error("permission_denied", e.message, null) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("query_failed", e.message, null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun queryAudio(): List<Map<String, Any?>> {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
        )
        val rows = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            collection,
            projection,
            // Skips ringtones, alarms and notification sounds.
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            null,
        )?.use { cursor ->
            val data = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val size = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val added = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val modified = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            val track = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val year = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            while (cursor.moveToNext()) {
                val path = cursor.getString(data) ?: continue
                rows += mapOf(
                    "path" to path,
                    "title" to cursor.getString(title),
                    "artist" to cursor.getString(artist).takeUnless { it == MediaStore.UNKNOWN_STRING },
                    "album" to cursor.getString(album).takeUnless { it == MediaStore.UNKNOWN_STRING },
                    "durationMs" to cursor.getLong(duration),
                    "sizeBytes" to cursor.getLong(size),
                    // MediaStore stores these two in seconds.
                    "addedMs" to cursor.getLong(added) * 1000,
                    "modifiedMs" to cursor.getLong(modified) * 1000,
                    // TRACK encodes the disc as thousands, e.g. 2005 is disc 2 track 5.
                    "trackNumber" to cursor.getInt(track).takeIf { it > 0 }?.rem(1000),
                    "year" to cursor.getInt(year).takeIf { it > 0 },
                )
            }
        }
        return rows
    }
}
