package com.nischalpandey.noctune

import android.app.Activity
import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Deletes one audio file from shared storage at the user's request. Android
 * asks the user itself before the file goes, and does the deleting; this only
 * finds the file in Android's index and passes the answer back.
 */
class DeleteAudioChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "delete") return result.notImplemented()
        val path = call.argument<String>("path")
            ?: return result.error("bad_request", "No file was named.", null)
        // Asking for a shared file to be deleted came with Android 11.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return result.error("unsupported", "Deleting needs Android 11 or later.", null)
        }
        if (pending != null) {
            return result.error("busy", "Another song is still waiting for an answer.", null)
        }
        try {
            val uri = indexed(path)
                ?: return result.error("not_found", "The phone no longer lists this file.", null)
            val question = MediaStore.createDeleteRequest(activity.contentResolver, listOf(uri))
            pending = result
            activity.startIntentSenderForResult(question.intentSender, REQUEST, null, 0, 0, 0)
        } catch (e: Exception) {
            pending = null
            result.error("delete_failed", e.message, null)
        }
    }

    /** Where Android's music index keeps the file at [path], if it does. */
    private fun indexed(path: String): Uri? {
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        activity.contentResolver.query(
            collection,
            arrayOf(MediaStore.Audio.Media._ID),
            "${MediaStore.Audio.Media.DATA} = ?",
            arrayOf(path),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return ContentUris.withAppendedId(collection, cursor.getLong(0))
            }
        }
        return null
    }

    /**
     * The user's answer to Android's question. True when it was this
     * channel's question, whatever the answer.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        // Yes means Android has already removed the file.
        pending?.success(resultCode == Activity.RESULT_OK)
        pending = null
        return true
    }

    private companion object {
        const val REQUEST = 0x4E54
    }
}
