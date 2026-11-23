package com.nischalpandey.noctune

import android.content.Context
import android.os.Environment
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Bridges Flutter's `noctune/extensions` channel to [MornyeExtensionRuntime]
 * on a background executor so JavaScript execution and network/file I/O never
 * block the UI thread.
 */
class ExtensionChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val runtime by lazy { MornyeExtensionRuntime(context.applicationContext) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val response: Any? = when (call.method) {
                    "init" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val musicDir = args["musicDir"] as? String ?: ""
                        runtime.init(musicDir)
                        runtime.autoDiscoverDeviceExtensions()
                        runtime.listExtensions()
                    }
                    "list" -> runtime.listExtensions()
                    "discoverDeviceExtensions" -> {
                        runtime.autoDiscoverDeviceExtensions()
                        runtime.listExtensions()
                    }
                    "installFile" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val path = args["path"] as? String
                            ?: throw IllegalArgumentException("Missing extension package path")
                        runtime.installPackage(File(path))
                        runtime.listExtensions()
                    }
                    "installFromUrl" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val url = args["url"] as? String
                            ?: throw IllegalArgumentException("Missing extension URL")
                        runtime.installFromUrl(url)
                        runtime.listExtensions()
                    }
                    "setEnabled" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val id = args["id"] as? String ?: ""
                        val enabled = args["enabled"] as? Boolean ?: false
                        runtime.setEnabled(id, enabled)
                        runtime.listExtensions()
                    }
                    "remove" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val id = args["id"] as? String ?: ""
                        runtime.removeExtension(id)
                        runtime.listExtensions()
                    }
                    "getSettings" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val id = args["id"] as? String ?: ""
                        runtime.getExtensionSettings(id)
                    }
                    "updateSettings" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val id = args["id"] as? String ?: ""
                        @Suppress("UNCHECKED_CAST")
                        val values = args["settings"] as? Map<String, Any?> ?: emptyMap()
                        runtime.updateExtensionSettings(id, values)
                        runtime.listExtensions()
                    }
                    "setPriority" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        @Suppress("UNCHECKED_CAST")
                        val ids = (args["ids"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                        runtime.setPriorityOrder(ids)
                        runtime.listExtensions()
                    }
                    "search" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val query = args["query"] as? String ?: ""
                        val limit = (args["limit"] as? Number)?.toInt() ?: 20
                        runtime.search(query, limit)
                    }
                    "handleUrl" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val url = args["url"] as? String ?: ""
                        runtime.handleUrl(url)
                    }
                    "download" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        @Suppress("UNCHECKED_CAST")
                        val track = args["track"] as? Map<String, Any?> ?: emptyMap()
                        val musicDir = args["musicDir"] as? String
                        runtime.downloadTrack(track, musicDir)
                    }
                    "fetchLyrics" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val title = args["title"] as? String ?: ""
                        val artist = args["artist"] as? String ?: ""
                        val album = args["album"] as? String ?: ""
                        val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 0L
                        runtime.fetchLyrics(title, artist, album, durationMs)
                    }
                    else -> {
                        mainHandler.post { result.notImplemented() }
                        return@execute
                    }
                }
                mainHandler.post { result.success(response) }
            } catch (e: Throwable) {
                mainHandler.post {
                    result.error("extension_error", e.message ?: e.toString(), null)
                }
            }
        }
    }
}
