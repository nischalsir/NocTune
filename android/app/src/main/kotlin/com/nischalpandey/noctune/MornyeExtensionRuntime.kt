package com.nischalpandey.noctune

import android.content.Context
import android.os.Environment
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.javascript.Context as RhinoContext
import org.mozilla.javascript.Function as RhinoFunction
import org.mozilla.javascript.NativeArray
import org.mozilla.javascript.NativeObject
import org.mozilla.javascript.Scriptable
import org.mozilla.javascript.ScriptableObject
import org.mozilla.javascript.Undefined
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.Normalizer
import java.util.Locale
import java.util.zip.GZIPInputStream
import java.util.zip.ZipInputStream
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Executes Mornye / SpotiFLAC-Mobile extension packages (`.spotiflac-ext`,
 * `.sflx`, `.mornye-ext`), providing the synchronous host API (`registerExtension`,
 * `http`, `fetch`, `file`, `storage`, `credentials`, `utils`, `gobackend`,
 * `matching`, `log`, `auth`, `session`, `URL`, `URLSearchParams`, `TextEncoder`,
 * `TextDecoder`, `btoa`, `atob`) expected by extension `index.js` scripts.
 */
class MornyeExtensionRuntime(private val context: Context) {
    private val rootDir = File(context.noBackupFilesDir, "mornye_extensions").apply { mkdirs() }
    private val installedDir = File(rootDir, "installed").apply { mkdirs() }
    private val dataDir = File(rootDir, "data").apply { mkdirs() }
    private val tempDir = File(context.cacheDir, "mornye_ext_tmp").apply { mkdirs() }
    private val statePrefs = context.getSharedPreferences("noctune_mornye_extensions", Context.MODE_PRIVATE)

    @Volatile
    private var defaultMusicDir: File = File(context.filesDir, "music").apply { mkdirs() }

    private val lock = Any()
    private val extensions = linkedMapOf<String, LoadedExtension>()
    private val searchPool = java.util.concurrent.Executors.newCachedThreadPool()

    @Volatile
    private var compiledBootstrapScript: org.mozilla.javascript.Script? = null

    data class LoadedExtension(
        val id: String,
        val dir: File,
        val manifestJson: JSONObject,
        val name: String,
        val displayName: String,
        val version: String,
        val description: String,
        val hasMetadataProvider: Boolean,
        val hasDownloadProvider: Boolean,
        val hasLyricsProvider: Boolean,
        val hasCustomSearch: Boolean,
        val isPrimarySearch: Boolean,
        val hasUrlHandler: Boolean,
        val urlPatterns: List<String>,
        val searchPlaceholder: String,
        val settingsSchema: JSONArray,
        val qualityOptions: JSONArray,
        var enabled: Boolean,
        var status: String = "loaded",
        var errorMessage: String? = null,
        @Volatile var compiledScript: org.mozilla.javascript.Script? = null,
    )

    fun init(musicDirPath: String) {
        if (musicDirPath.isNotBlank()) {
            val dir = File(musicDirPath)
            dir.mkdirs()
            defaultMusicDir = dir
        }
        synchronized(lock) {
            reloadInstalledLocked()
        }
    }

    /**
     * Looks for `.spotiflac-ext`, `.sflx`, and `.mornye-ext` packages already
     * on the device (in the app's music folder, `Download/`, `Documents/`, or
     * `Music/`) and installs any that aren't installed yet.
     */
    fun autoDiscoverDeviceExtensions() {
        val candidates = mutableListOf<File>()
        val dirs = mutableListOf(
            defaultMusicDir,
            File(defaultMusicDir, "Extensions"),
            context.getExternalFilesDir(null),
        )
        runCatching {
            val extRoot = Environment.getExternalStorageDirectory()
            if (extRoot != null) {
                dirs.add(File(extRoot, "Download"))
                dirs.add(File(extRoot, "Downloads"))
                dirs.add(File(extRoot, "Documents"))
                dirs.add(File(extRoot, "Music"))
                dirs.add(File(extRoot, "Mornye"))
                dirs.add(File(extRoot, "SpotiFLAC"))
            }
        }
        for (dir in dirs.filterNotNull()) {
            collectExtensionFiles(dir, depth = 0, maxDepth = 4, out = candidates)
        }
        val importedMarkers = statePrefs.getStringSet("auto_imported_files", emptySet())?.toMutableSet() ?: mutableSetOf()
        var changed = false
        for (file in candidates) {
            val key = "${file.absolutePath}:${file.length()}:${file.lastModified()}"
            if (key in importedMarkers) continue
            runCatching {
                installPackage(file)
                importedMarkers.add(key)
                changed = true
            }
        }
        if (changed) {
            statePrefs.edit().putStringSet("auto_imported_files", importedMarkers).apply()
        }
    }

    private fun collectExtensionFiles(dir: File, depth: Int, maxDepth: Int, out: MutableList<File>) {
        if (depth > maxDepth) return
        runCatching {
            if (!dir.exists() || !dir.isDirectory) return
            dir.listFiles()?.forEach { file ->
                if (file.isFile && isExtensionPackageName(file.name)) {
                    out.add(file)
                } else if (file.isDirectory && !file.name.startsWith(".")) {
                    collectExtensionFiles(file, depth + 1, maxDepth, out)
                }
            }
        }
    }

    private fun isExtensionPackageName(name: String): Boolean {
        val lower = name.lowercase(Locale.ROOT)
        return lower.endsWith(".spotiflac-ext") ||
            lower.endsWith(".sflx") ||
            lower.endsWith(".mornye-ext")
    }

    fun installFromUrl(url: String) {
        val parsed = URI(url.trim())
        require(parsed.scheme == "https" || parsed.scheme == "http") {
            "Extension URL must be HTTP or HTTPS"
        }
        val bytes = httpRequestBytes(url.trim(), "GET", null, emptyMap())
        val text = String(bytes.body, StandardCharsets.UTF_8).trim()
        // Could be a registry index.json / repo URL or a direct .spotiflac-ext package URL.
        if (text.startsWith("{") || text.startsWith("[")) {
            val urls = extractPackageUrlsFromRegistryJson(url.trim(), text)
            require(urls.isNotEmpty()) { "No extension packages found at registry URL" }
            for (pkgUrl in urls) {
                val pkgBytes = httpRequestBytes(pkgUrl, "GET", null, emptyMap()).body
                val tmp = File(tempDir, "dl_${System.currentTimeMillis()}.spotiflac-ext")
                try {
                    tmp.writeBytes(pkgBytes)
                    installPackage(tmp)
                } finally {
                    tmp.delete()
                }
            }
        } else {
            val tmp = File(tempDir, "dl_${System.currentTimeMillis()}.spotiflac-ext")
            try {
                tmp.writeBytes(bytes.body)
                installPackage(tmp)
            } finally {
                tmp.delete()
            }
        }
    }

    private fun extractPackageUrlsFromRegistryJson(baseUrl: String, jsonText: String): List<String> {
        val result = mutableListOf<String>()
        val array = if (jsonText.startsWith("[")) {
            JSONArray(jsonText)
        } else {
            val obj = JSONObject(jsonText)
            obj.optJSONArray("extensions")
                ?: obj.optJSONArray("packages")
                ?: obj.optJSONArray("items")
                ?: JSONArray()
        }
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val rawUrl = item.optString("download_url")
                .ifBlank { item.optString("downloadUrl") }
                .ifBlank { item.optString("package_url") }
                .ifBlank { item.optString("packageUrl") }
                .ifBlank { item.optString("url") }
                .ifBlank { item.optString("file") }
            if (rawUrl.isNotBlank()) {
                val resolved = if (rawUrl.startsWith("http://") || rawUrl.startsWith("https://")) {
                    rawUrl
                } else {
                    URI(baseUrl).resolve(rawUrl).toString()
                }
                result.add(resolved)
            }
        }
        return result
    }

    fun installPackage(packageFile: File): String {
        require(packageFile.exists() && packageFile.isFile) {
            "Extension file not found: ${packageFile.path}"
        }
        val staging = File(tempDir, "stage_${System.nanoTime()}").apply { mkdirs() }
        try {
            ZipInputStream(FileInputStream(packageFile)).use { zis ->
                var entry = zis.nextEntry
                var count = 0
                while (entry != null) {
                    count++
                    require(count <= 2048) { "Extension archive has too many entries" }
                    val cleanName = entry.name.replace('\\', '/').trimStart('/')
                    require(!cleanName.contains("..")) { "Unsafe path in extension archive: ${entry.name}" }
                    if (cleanName.isNotEmpty()) {
                        val outFile = File(staging, cleanName)
                        if (entry.isDirectory) {
                            outFile.mkdirs()
                        } else {
                            outFile.parentFile?.mkdirs()
                            FileOutputStream(outFile).use { fos ->
                                zis.copyTo(fos)
                            }
                        }
                    }
                    zis.closeEntry()
                    entry = zis.nextEntry
                }
            }
            // If the archive had a single top-level folder containing manifest.json, unwrap it.
            val rootSource = findExtensionRoot(staging)
                ?: throw IllegalArgumentException("Invalid extension package: manifest.json and index.js not found")
            val manifestText = File(rootSource, "manifest.json").readText(StandardCharsets.UTF_8)
            val manifest = JSONObject(manifestText)
            val extId = manifest.optString("id").ifBlank { manifest.optString("name") }.trim()
            require(extId.isNotBlank() && extId.matches(Regex("^[a-zA-Z0-9._-]+$"))) {
                "Invalid extension ID in manifest.json: '$extId'"
            }
            synchronized(lock) {
                val targetDir = File(installedDir, extId)
                if (targetDir.exists()) targetDir.deleteRecursively()
                targetDir.mkdirs()
                rootSource.copyRecursively(targetDir, overwrite = true)
                // Enable newly installed extensions by default.
                statePrefs.edit().putBoolean("enabled_$extId", true).apply()
                reloadInstalledLocked()
            }
            return extId
        } finally {
            staging.deleteRecursively()
        }
    }

    private fun findExtensionRoot(dir: File): File? {
        if (File(dir, "manifest.json").isFile && File(dir, "index.js").isFile) return dir
        val subdirs = dir.listFiles()?.filter { it.isDirectory } ?: emptyList()
        if (subdirs.size == 1) {
            val sub = subdirs.first()
            if (File(sub, "manifest.json").isFile && File(sub, "index.js").isFile) return sub
        }
        return null
    }

    private fun reloadInstalledLocked() {
        extensions.clear()
        val dirs = installedDir.listFiles()?.filter { it.isDirectory }?.sortedBy { it.name } ?: emptyList()
        val parsed = mutableMapOf<String, LoadedExtension>()
        for (dir in dirs) {
            val manifestFile = File(dir, "manifest.json")
            val indexFile = File(dir, "index.js")
            if (!manifestFile.isFile || !indexFile.isFile) continue
            runCatching {
                val manifest = JSONObject(manifestFile.readText(StandardCharsets.UTF_8))
                val id = manifest.optString("id").ifBlank { dir.name }
                val name = manifest.optString("name").ifBlank { id }
                val displayName = manifest.optString("display_name")
                    .ifBlank { manifest.optString("displayName") }
                    .ifBlank { name }
                val version = manifest.optString("version", "1.0.0")
                val description = manifest.optString("description", "")
                val types = manifest.optJSONArray("type")
                    ?: manifest.optJSONArray("types")
                    ?: manifest.optJSONArray("capabilities_list")
                val typeSet = mutableSetOf<String>()
                if (types != null) {
                    for (i in 0 until types.length()) {
                        typeSet.add(types.optString(i).lowercase(Locale.ROOT))
                    }
                }
                val capabilities = manifest.optJSONObject("capabilities")
                val searchBehavior = manifest.optJSONObject("search_behavior")
                    ?: manifest.optJSONObject("searchBehavior")
                val urlHandler = manifest.optJSONObject("url_handler")
                    ?: manifest.optJSONObject("urlHandler")

                val hasCustomSearch = searchBehavior?.optBoolean("enabled", false) == true ||
                    capabilities?.optBoolean("customSearch", false) == true ||
                    capabilities?.optBoolean("custom_search", false) == true
                val isPrimarySearch = searchBehavior?.optBoolean("primary", false) == true
                val hasMetadata = manifest.optBoolean("has_metadata_provider", false) ||
                    manifest.optBoolean("hasMetadataProvider", false) ||
                    manifest.optBoolean("metadata_provider", false) ||
                    "metadata" in typeSet || "metadata_provider" in typeSet || "search" in typeSet ||
                    capabilities?.optBoolean("metadata", false) == true ||
                    capabilities?.optBoolean("search", false) == true ||
                    hasCustomSearch
                val hasDownload = manifest.optBoolean("has_download_provider", false) ||
                    manifest.optBoolean("hasDownloadProvider", false) ||
                    manifest.optBoolean("download_provider", false) ||
                    "download" in typeSet || "download_provider" in typeSet || "downloader" in typeSet ||
                    capabilities?.optBoolean("download", false) == true
                val hasLyrics = manifest.optBoolean("has_lyrics_provider", false) ||
                    manifest.optBoolean("hasLyricsProvider", false) ||
                    manifest.optBoolean("lyrics_provider", false) ||
                    "lyrics" in typeSet || "lyrics_provider" in typeSet ||
                    capabilities?.optBoolean("lyrics", false) == true
                val hasUrl = urlHandler?.optBoolean("enabled", false) == true
                val patterns = mutableListOf<String>()
                val patternArr = urlHandler?.optJSONArray("patterns")
                if (patternArr != null) {
                    for (i in 0 until patternArr.length()) {
                        val pat = patternArr.optString(i)
                        if (pat.isNotBlank()) patterns.add(pat)
                    }
                }
                val enabled = statePrefs.getBoolean("enabled_$id", true)
                // Also inspect index.js for methods if manifest didn't explicitly declare provider flags.
                val scriptSource = indexFile.readText(StandardCharsets.UTF_8)
                val inferredMetadata = hasMetadata ||
                    scriptSource.contains("searchTracks") ||
                    scriptSource.contains("customSearch")
                val inferredDownload = hasDownload ||
                    scriptSource.contains("download(") ||
                    scriptSource.contains("download:") ||
                    scriptSource.contains("checkAvailability")
                val inferredLyrics = hasLyrics ||
                    scriptSource.contains("fetchLyrics") ||
                    scriptSource.contains("getLyrics")
                val inferredCustomSearch = hasCustomSearch ||
                    scriptSource.contains("customSearch")

                parsed[id] = LoadedExtension(
                    id = id,
                    dir = dir,
                    manifestJson = manifest,
                    name = name,
                    displayName = displayName,
                    version = version,
                    description = description,
                    hasMetadataProvider = inferredMetadata,
                    hasDownloadProvider = inferredDownload,
                    hasLyricsProvider = inferredLyrics,
                    hasCustomSearch = inferredCustomSearch,
                    isPrimarySearch = isPrimarySearch,
                    hasUrlHandler = hasUrl || scriptSource.contains("handleUrl") || scriptSource.contains("handleURL"),
                    urlPatterns = patterns,
                    searchPlaceholder = searchBehavior?.optString("placeholder", "") ?: "",
                    settingsSchema = manifest.optJSONArray("settings") ?: JSONArray(),
                    qualityOptions = manifest.optJSONArray("quality_options")
                        ?: manifest.optJSONArray("qualityOptions")
                        ?: JSONArray(),
                    enabled = enabled,
                )
            }
        }
        val order = getPriorityOrderLocked()
        for (id in order) {
            parsed.remove(id)?.let { extensions[id] = it }
        }
        val preferredOrder = listOf(
            "deezer",
            "jiosaavn",
            "ytmusic-spotiflac",
            "soundcloud",
            "qobuz-web",
            "tidal-web",
            "apple-music",
            "spotify-web",
            "amzn",
            "bugs-music",
            "genie-music",
            "melon-music",
        )
        val remaining = parsed.values.sortedWith(
            compareBy<LoadedExtension> { !it.isPrimarySearch }
                .thenBy { ext ->
                    val idx = preferredOrder.indexOf(ext.id.lowercase(Locale.ROOT))
                    if (idx >= 0) idx else preferredOrder.size
                }
                .thenBy { it.displayName.lowercase(Locale.ROOT) }
        )
        for (ext in remaining) {
            extensions[ext.id] = ext
        }
    }

    private fun getPriorityOrderLocked(): List<String> {
        val raw = statePrefs.getString("priority_order", null) ?: return emptyList()
        return raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    }

    fun setPriorityOrder(ids: List<String>) {
        synchronized(lock) {
            statePrefs.edit().putString("priority_order", ids.joinToString(",")).apply()
            reloadInstalledLocked()
        }
    }

    fun setEnabled(id: String, enabled: Boolean) {
        synchronized(lock) {
            statePrefs.edit().putBoolean("enabled_$id", enabled).apply()
            extensions[id]?.enabled = enabled
        }
    }

    fun removeExtension(id: String) {
        synchronized(lock) {
            extensions.remove(id)
            File(installedDir, id).deleteRecursively()
            File(dataDir, id).deleteRecursively()
            statePrefs.edit().remove("enabled_$id").apply()
        }
    }

    fun listExtensions(): List<Map<String, Any?>> = synchronized(lock) {
        extensions.values.map { ext ->
            val currentSettings = loadExtensionSettingsMap(ext)
            val settingsList = mutableListOf<Map<String, Any?>>()
            for (i in 0 until ext.settingsSchema.length()) {
                val s = ext.settingsSchema.optJSONObject(i) ?: continue
                val key = s.optString("key")
                val options = mutableListOf<String>()
                val optArr = s.optJSONArray("options")
                if (optArr != null) {
                    for (j in 0 until optArr.length()) options.add(optArr.optString(j))
                }
                settingsList.add(
                    mapOf(
                        "key" to key,
                        "type" to s.optString("type", "string"),
                        "label" to s.optString("label", key),
                        "description" to s.optString("description", ""),
                        "required" to s.optBoolean("required", false),
                        "secret" to s.optBoolean("secret", false),
                        "default" to jsonToKotlin(s.opt("default")),
                        "value" to (currentSettings[key] ?: jsonToKotlin(s.opt("default"))),
                        "options" to options,
                        "action" to s.optString("action", ""),
                    )
                )
            }
            val qualities = mutableListOf<Map<String, Any?>>()
            for (i in 0 until ext.qualityOptions.length()) {
                val q = ext.qualityOptions.optJSONObject(i) ?: continue
                qualities.add(
                    mapOf(
                        "id" to q.optString("id"),
                        "label" to q.optString("label", q.optString("id")),
                        "description" to q.optString("description", ""),
                    )
                )
            }
            mapOf(
                "id" to ext.id,
                "name" to ext.name,
                "displayName" to ext.displayName,
                "version" to ext.version,
                "description" to ext.description,
                "enabled" to ext.enabled,
                "status" to ext.status,
                "errorMessage" to ext.errorMessage,
                "hasMetadataProvider" to ext.hasMetadataProvider,
                "hasDownloadProvider" to ext.hasDownloadProvider,
                "hasLyricsProvider" to ext.hasLyricsProvider,
                "hasCustomSearch" to ext.hasCustomSearch,
                "hasUrlHandler" to ext.hasUrlHandler,
                "searchPlaceholder" to ext.searchPlaceholder,
                "settings" to settingsList,
                "qualityOptions" to qualities,
            )
        }
    }

    fun getExtensionSettings(id: String): Map<String, Any?> = synchronized(lock) {
        val ext = extensions[id] ?: return emptyMap()
        loadExtensionSettingsMap(ext)
    }

    fun updateExtensionSettings(id: String, newValues: Map<String, Any?>) {
        synchronized(lock) {
            val ext = extensions[id] ?: return
            val file = File(File(dataDir, ext.id).apply { mkdirs() }, "settings.json")
            val current = if (file.isFile) {
                runCatching { JSONObject(file.readText(StandardCharsets.UTF_8)) }.getOrNull() ?: JSONObject()
            } else {
                JSONObject()
            }
            for ((k, v) in newValues) {
                if (v == null) current.remove(k) else current.put(k, v)
            }
            file.writeText(current.toString(), StandardCharsets.UTF_8)
        }
    }

    private fun loadExtensionSettingsMap(ext: LoadedExtension): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>()
        for (i in 0 until ext.settingsSchema.length()) {
            val s = ext.settingsSchema.optJSONObject(i) ?: continue
            val key = s.optString("key")
            if (key.isNotBlank() && s.has("default")) {
                result[key] = jsonToKotlin(s.opt("default"))
            }
        }
        val file = File(File(dataDir, ext.id), "settings.json")
        if (file.isFile) {
            runCatching {
                val obj = JSONObject(file.readText(StandardCharsets.UTF_8))
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    result[k] = jsonToKotlin(obj.opt(k))
                }
            }
        }
        return result
    }

    /**
     * Searches across a selected extension ([providerId]) or all enabled
     * search/metadata extensions in parallel. If the query is a URL, resolves
     * it via [handleUrl] too.
     */
    fun search(
        query: String,
        limit: Int,
        filter: String? = null,
        providerId: String? = null,
    ): List<Map<String, Any?>> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.startsWith("spotify:")) {
            val resolved = handleUrl(trimmed)
            val tracks = resolved["tracks"] as? List<*>
            if (!tracks.isNullOrEmpty()) {
                @Suppress("UNCHECKED_CAST")
                return tracks as List<Map<String, Any?>>
            }
        }
        val requestedProvider = providerId?.trim()?.takeIf { it.isNotEmpty() && it != "all" }
        val active = synchronized(lock) {
            if (requestedProvider != null) {
                listOfNotNull(extensions[requestedProvider]?.takeIf { it.enabled })
            } else {
                extensions.values.filter { it.enabled && (it.hasMetadataProvider || it.hasCustomSearch) }
            }
        }
        val hasEnabledDownloader = synchronized(lock) {
            extensions.values.any { it.enabled && it.hasDownloadProvider }
        }
        if (active.isEmpty() && !hasEnabledDownloader) return emptyList()

        val canonicalFilter = when (filter?.trim()?.lowercase(Locale.ROOT)) {
            "track", "tracks", "song", "songs" -> "tracks"
            "album", "albums" -> "albums"
            "artist", "artists" -> "artists"
            else -> "all"
        }

        val perSourceResults = mutableListOf<List<Map<String, Any?>>>()
        if (active.size == 1) {
            val ext = active.first()
            runCatching {
                val items = invokeExtensionSearch(ext, trimmed, limit, canonicalFilter)
                if (items.isNotEmpty()) perSourceResults.add(items)
            }.onFailure { err ->
                ext.errorMessage = err.message
            }
        } else if (active.size > 1) {
            // Run extensions in parallel with a short timeout so slow/unauthenticated
            // extensions never block fast ones.
            val tasks = active.map { ext ->
                java.util.concurrent.Callable {
                    runCatching {
                        invokeExtensionSearch(ext, trimmed, limit, canonicalFilter)
                    }.onFailure { err ->
                        ext.errorMessage = err.message
                    }.getOrDefault(emptyList())
                }
            }
            val futures = runCatching {
                searchPool.invokeAll(tasks, 4500L, java.util.concurrent.TimeUnit.MILLISECONDS)
            }.getOrDefault(emptyList())
            for (future in futures) {
                if (future.isDone && !future.isCancelled) {
                    val items = runCatching { future.get() }.getOrDefault(emptyList())
                    if (items.isNotEmpty()) perSourceResults.add(items)
                }
            }
        }
        // When only download extensions are installed (or metadata extensions returned nothing),
        // resolve track metadata with ISRC support via Deezer's public catalog so download
        // extensions can match and download the track.
        if (perSourceResults.isEmpty() && hasEnabledDownloader && (canonicalFilter == "all" || canonicalFilter == "tracks")) {
            val downloader = synchronized(lock) {
                (requestedProvider?.let { extensions[it] }?.takeIf { it.enabled && it.hasDownloadProvider })
                    ?: extensions.values.first { it.enabled && it.hasDownloadProvider }
            }
            runCatching {
                val fallbackItems = searchPublicCatalogForDownloader(trimmed, limit, downloader)
                if (fallbackItems.isNotEmpty()) perSourceResults.add(fallbackItems)
            }
        }
        // Interleave results across enabled extensions just like Mornye / NocTune.
        val combined = mutableListOf<Map<String, Any?>>()
        val maxLen = perSourceResults.maxOfOrNull { it.size } ?: 0
        for (i in 0 until maxLen) {
            for (sourceList in perSourceResults) {
                if (i < sourceList.size) {
                    combined.add(sourceList[i])
                }
            }
        }
        return combined.take(limit * max(1, active.size))
    }

    private fun searchPublicCatalogForDownloader(
        query: String,
        limit: Int,
        downloader: LoadedExtension,
    ): List<Map<String, Any?>> {
        val encoded = URLEncoder.encode(query, "UTF-8")
        val url = "https://api.deezer.com/search?q=$encoded&limit=$limit"
        val resp = httpRequestBytes(url, "GET", null, mapOf("User-Agent" to "NocTune/1.12.0"))
        if (resp.status !in 200..299) return emptyList()
        val root = JSONObject(String(resp.body, StandardCharsets.UTF_8))
        val data = root.optJSONArray("data") ?: return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        for (i in 0 until data.length()) {
            val item = data.optJSONObject(i) ?: continue
            val dzId = item.optLong("id").toString()
            val title = item.optString("title").ifBlank { item.optString("title_short") }
            val durationSec = item.optLong("duration", 0L)
            val artistObj = item.optJSONObject("artist")
            val artistName = artistObj?.optString("name") ?: ""
            val albumObj = item.optJSONObject("album")
            val albumTitle = albumObj?.optString("title") ?: ""
            val coverUrl = albumObj?.optString("cover_big")
                ?.ifBlank { albumObj.optString("cover_medium") }
                ?: ""
            results.add(
                mapOf(
                    "id" to dzId,
                    "deezer_id" to dzId,
                    "name" to title,
                    "title" to title,
                    "artists" to artistName,
                    "artist" to artistName,
                    "album_name" to albumTitle,
                    "album" to albumTitle,
                    "album_artist" to artistName,
                    "duration_ms" to (durationSec * 1000L),
                    "cover_url" to coverUrl,
                    "isrc" to item.optString("isrc", ""),
                    "provider_id" to downloader.id,
                    "provider_name" to downloader.displayName,
                )
            )
        }
        return results
    }

    private fun enrichTrackIsrcIfNeeded(track: Map<String, Any?>): Map<String, Any?> {
        val existingIsrc = track["isrc"]?.toString()?.trim() ?: ""
        if (existingIsrc.isNotEmpty()) return track
        val dzId = track["deezer_id"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: track["id"]?.toString()?.trim()?.takeIf { it.all(Char::isDigit) }
            ?: return track
        return runCatching {
            val resp = httpRequestBytes(
                "https://api.deezer.com/track/$dzId",
                "GET",
                null,
                mapOf("User-Agent" to "NocTune/1.12.0"),
            )
            if (resp.status !in 200..299) return@runCatching track
            val obj = JSONObject(String(resp.body, StandardCharsets.UTF_8))
            val isrc = obj.optString("isrc", "").trim()
            val releaseDate = obj.optString("release_date", "").trim()
            val trackPos = obj.optInt("track_position", 0)
            val discNum = obj.optInt("disk_number", 0)
            val updated = track.toMutableMap()
            if (isrc.isNotEmpty()) updated["isrc"] = isrc
            if (releaseDate.isNotEmpty() && updated["release_date"].toString().isBlank()) {
                updated["release_date"] = releaseDate
            }
            if (trackPos > 0 && (updated["track_number"] as? Number)?.toInt() == 0) {
                updated["track_number"] = trackPos
            }
            if (discNum > 0 && (updated["disc_number"] as? Number)?.toInt() == 0) {
                updated["disc_number"] = discNum
            }
            updated
        }.getOrDefault(track)
    }

    fun handleUrl(url: String): Map<String, Any?> {
        val trimmed = url.trim()
        val active = synchronized(lock) {
            extensions.values.filter { it.enabled }
        }
        for (ext in active) {
            if (!ext.hasUrlHandler) continue
            val matchesPattern = ext.urlPatterns.isEmpty() || ext.urlPatterns.any { pat ->
                trimmed.contains(pat, ignoreCase = true) ||
                    runCatching { Regex(pat, RegexOption.IGNORE_CASE).containsMatchIn(trimmed) }.getOrDefault(false)
            }
            if (!matchesPattern && ext.urlPatterns.isNotEmpty()) continue
            val res = runCatching {
                executeInExtension(ext) { cx, scope, extObj ->
                    val fn = ScriptableObject.getProperty(extObj, "handleUrl") as? RhinoFunction
                        ?: return@executeInExtension null
                    val raw = fn.call(cx, scope, extObj, arrayOf(trimmed))
                    jsToKotlin(raw)
                }
            }.getOrNull() as? Map<*, *> ?: continue

            val tracks = mutableListOf<Map<String, Any?>>()
            (res["track"] as? Map<*, *>)?.let { tracks.add(normalizeTrackMap(it, ext)) }
            (res["tracks"] as? List<*>)?.forEach { item ->
                (item as? Map<*, *>)?.let { tracks.add(normalizeTrackMap(it, ext)) }
            }
            ((res["album"] as? Map<*, *>)?.get("tracks") as? List<*>)?.forEach { item ->
                (item as? Map<*, *>)?.let { tracks.add(normalizeTrackMap(it, ext)) }
            }
            if (tracks.isNotEmpty()) {
                return mapOf(
                    "type" to (res["type"]?.toString() ?: "tracks"),
                    "name" to (res["name"]?.toString() ?: ""),
                    "providerId" to ext.id,
                    "providerName" to ext.displayName,
                    "tracks" to tracks,
                )
            }
        }
        return emptyMap()
    }

    private fun resolveExtensionFilterId(ext: LoadedExtension, canonicalFilter: String): String {
        if (canonicalFilter == "all") return ""
        val searchBehavior = ext.manifestJson.optJSONObject("searchBehavior")
            ?: ext.manifestJson.optJSONObject("search_behavior")
        val filters = searchBehavior?.optJSONArray("filters")
        if (filters != null) {
            for (i in 0 until filters.length()) {
                val f = filters.optJSONObject(i) ?: continue
                val id = f.optString("id").trim()
                val lower = id.lowercase(Locale.ROOT)
                when (canonicalFilter) {
                    "tracks" -> if (lower in setOf("track", "tracks", "song", "songs")) return id
                    "albums" -> if (lower in setOf("album", "albums")) return id
                    "artists" -> if (lower in setOf("artist", "artists")) return id
                }
            }
        }
        return when (canonicalFilter) {
            "tracks" -> "track"
            "albums" -> "album"
            "artists" -> "artist"
            else -> ""
        }
    }

    private fun invokeExtensionSearch(
        ext: LoadedExtension,
        query: String,
        limit: Int,
        canonicalFilter: String = "all",
    ): List<Map<String, Any?>> {
        val extFilterId = resolveExtensionFilterId(ext, canonicalFilter)
        val rawResult = executeInExtension(ext) { cx, scope, extObj ->
            val customFn = ScriptableObject.getProperty(extObj, "customSearch") as? RhinoFunction
            if (customFn != null) {
                val opts = cx.newObject(scope)
                ScriptableObject.putProperty(opts, "limit", limit)
                if (extFilterId.isNotEmpty()) {
                    ScriptableObject.putProperty(opts, "filter", extFilterId)
                }
                return@executeInExtension jsToKotlin(customFn.call(cx, scope, extObj, arrayOf<Any?>(query, opts)))
            }
            if (canonicalFilter == "albums" || canonicalFilter == "artists") {
                return@executeInExtension null
            }
            val searchFn = ScriptableObject.getProperty(extObj, "searchTracks") as? RhinoFunction
                ?: ScriptableObject.getProperty(extObj, "search") as? RhinoFunction
                ?: return@executeInExtension null
            jsToKotlin(searchFn.call(cx, scope, extObj, arrayOf<Any?>(query, limit)))
        }
        val list: List<*> = when (rawResult) {
            is List<*> -> rawResult
            is Map<*, *> -> (rawResult["tracks"] as? List<*>)
                ?: (rawResult["items"] as? List<*>)
                ?: (rawResult["results"] as? List<*>)
                ?: emptyList<Any?>()
            else -> emptyList<Any?>()
        }
        val defaultType = when (canonicalFilter) {
            "albums" -> "album"
            "artists" -> "artist"
            else -> "track"
        }
        return list.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val normalized = normalizeTrackMap(map, ext, defaultType)
            val itemType = normalized["item_type"]?.toString() ?: "track"
            when {
                itemType !in setOf("track", "album", "artist") -> null
                canonicalFilter == "tracks" && itemType != "track" -> null
                canonicalFilter == "albums" && itemType != "album" -> null
                canonicalFilter == "artists" && itemType != "artist" -> null
                else -> normalized
            }
        }
    }

    fun getAlbum(providerId: String, albumId: String): Map<String, Any?> {
        val ext = synchronized(lock) { extensions[providerId] }
            ?: throw IllegalArgumentException("Extension not found: $providerId")
        val raw = executeInExtension(ext) { cx, scope, extObj ->
            val fn = ScriptableObject.getProperty(extObj, "getAlbum") as? RhinoFunction
                ?: throw IllegalStateException("${ext.displayName} does not support album browsing")
            jsToKotlin(fn.call(cx, scope, extObj, arrayOf<Any?>(albumId)))
        } as? Map<*, *> ?: return emptyMap()
        val tracksRaw = (raw["tracks"] as? List<*>) ?: emptyList<Any?>()
        val tracks = tracksRaw.mapNotNull { item ->
            (item as? Map<*, *>)?.let { normalizeTrackMap(it, ext, "track") }
        }
        return mapOf(
            "id" to (raw["id"]?.toString() ?: albumId),
            "name" to ((raw["name"] ?: raw["title"])?.toString() ?: ""),
            "artist" to ((raw["artists"] ?: raw["artist"])?.toString() ?: ""),
            "cover_url" to ((raw["cover_url"] ?: raw["coverUrl"] ?: raw["images"])?.toString() ?: ""),
            "release_date" to ((raw["release_date"] ?: raw["releaseDate"])?.toString() ?: ""),
            "provider_id" to ext.id,
            "provider_name" to ext.displayName,
            "tracks" to tracks,
        )
    }

    fun getArtist(providerId: String, artistId: String): Map<String, Any?> {
        val ext = synchronized(lock) { extensions[providerId] }
            ?: throw IllegalArgumentException("Extension not found: $providerId")
        val raw = executeInExtension(ext) { cx, scope, extObj ->
            val fn = ScriptableObject.getProperty(extObj, "getArtist") as? RhinoFunction
                ?: throw IllegalStateException("${ext.displayName} does not support artist browsing")
            jsToKotlin(fn.call(cx, scope, extObj, arrayOf<Any?>(artistId)))
        } as? Map<*, *> ?: return emptyMap()
        val topTracksRaw = (raw["top_tracks"] as? List<*>)
            ?: (raw["topTracks"] as? List<*>)
            ?: (raw["tracks"] as? List<*>)
            ?: emptyList<Any?>()
        val albumsRaw = (raw["albums"] as? List<*>)
            ?: (raw["releases"] as? List<*>)
            ?: emptyList<Any?>()
        val topTracks = topTracksRaw.mapNotNull { item ->
            (item as? Map<*, *>)?.let { normalizeTrackMap(it, ext, "track") }
        }
        val albums = albumsRaw.mapNotNull { item ->
            (item as? Map<*, *>)?.let { normalizeTrackMap(it, ext, "album") }
        }
        return mapOf(
            "id" to (raw["id"]?.toString() ?: artistId),
            "name" to ((raw["name"] ?: raw["title"])?.toString() ?: ""),
            "cover_url" to ((raw["image_url"] ?: raw["imageUrl"] ?: raw["cover_url"] ?: raw["coverUrl"] ?: raw["images"])?.toString() ?: ""),
            "provider_id" to ext.id,
            "provider_name" to ext.displayName,
            "top_tracks" to topTracks,
            "albums" to albums,
        )
    }

    private fun normalizeTrackMap(
        raw: Map<*, *>,
        ext: LoadedExtension,
        defaultItemType: String = "track",
    ): Map<String, Any?> {
        fun str(vararg keys: String): String {
            for (k in keys) {
                val v = raw[k]
                if (v is String && v.isNotBlank()) return v.trim()
                if (v is Number) return v.toString()
            }
            return ""
        }
        fun num(vararg keys: String): Long {
            for (k in keys) {
                val v = raw[k]
                if (v is Number) return v.toLong()
                if (v is String) v.trim().toDoubleOrNull()?.let { return it.toLong() }
            }
            return 0L
        }
        val rawType = str("item_type", "itemType", "type").lowercase(Locale.ROOT)
        val itemType = when (rawType) {
            "album", "albums" -> "album"
            "artist", "artists" -> "artist"
            "playlist", "playlists" -> "playlist"
            "show", "podcast" -> "show"
            "track", "tracks", "song", "songs" -> "track"
            else -> defaultItemType
        }
        val artistsVal = raw["artists"] ?: raw["artist"]
        val artistStr = when (artistsVal) {
            is String -> artistsVal.trim()
            is List<*> -> artistsVal.mapNotNull { item ->
                when (item) {
                    is String -> item.trim()
                    is Map<*, *> -> item["name"]?.toString()?.trim()
                    else -> null
                }
            }.filter { it.isNotEmpty() }.joinToString(", ")
            is Map<*, *> -> artistsVal["name"]?.toString()?.trim() ?: ""
            else -> ""
        }
        var durationMs = num("duration_ms", "durationMs", "duration")
        if (durationMs in 1..999) {
            durationMs *= 1000L
        }
        val id = str("id", "track_id", "trackId", "spotify_id", "isrc").ifBlank {
            "${ext.id}-${str("name", "title").hashCode()}"
        }
        val title = str("name", "title", "track_name", "trackName").ifBlank { "Unknown" }
        val album = str("album_name", "albumName", "album").ifBlank {
            (raw["album"] as? Map<*, *>)?.get("name")?.toString()?.trim() ?: ""
        }
        val cover = str("cover_url", "coverUrl", "images", "artwork_url", "artworkUrl", "image_url", "imageUrl").ifBlank {
            ((raw["album"] as? Map<*, *>)?.get("cover_url") ?: (raw["album"] as? Map<*, *>)?.get("images"))?.toString()?.trim() ?: ""
        }
        return mapOf(
            "id" to id,
            "item_type" to itemType,
            "name" to title,
            "title" to title,
            "artists" to artistStr,
            "artist" to artistStr,
            "album_name" to album,
            "album" to album,
            "album_artist" to str("album_artist", "albumArtist").ifBlank { artistStr },
            "duration_ms" to durationMs,
            "cover_url" to cover,
            "isrc" to str("isrc"),
            "release_date" to str("release_date", "releaseDate"),
            "track_number" to num("track_number", "trackNumber").toInt(),
            "total_tracks" to num("total_tracks", "totalTracks", "nb_tracks").toInt(),
            "disc_number" to num("disc_number", "discNumber").toInt(),
            "provider_id" to ext.id,
            "provider_name" to ext.displayName,
            "audio_quality" to str("audio_quality", "audioQuality"),
            "external_urls" to str("external_urls", "externalUrls", "url", "external_url"),
            "spotify_id" to str("spotify_id", "spotifyId"),
            "tidal_id" to str("tidal_id", "tidalId"),
            "qobuz_id" to str("qobuz_id", "qobuzId"),
            "deezer_id" to str("deezer_id", "deezerId"),
        )
    }

    /**
     * Downloads [track] through the originating extension (if it provides
     * downloads) or across enabled download provider extensions in priority
     * order, saving the audio file into [musicDirPath] so NocTune's library
     * scanner adds it to the local library.
     */
    fun downloadTrack(rawTrack: Map<String, Any?>, musicDirPath: String?): Map<String, Any?> {
        val track = enrichTrackIsrcIfNeeded(rawTrack)
        val targetBaseDir = if (!musicDirPath.isNullOrBlank()) File(musicDirPath) else defaultMusicDir
        val outDir = File(targetBaseDir, "Extensions").apply { mkdirs() }

        val originId = track["provider_id"]?.toString() ?: ""
        val candidates = synchronized(lock) {
            val enabledDownloaders = extensions.values.filter { it.enabled && it.hasDownloadProvider }.toMutableList()
            val origin = extensions[originId]
            if (origin != null && origin.enabled && origin.hasDownloadProvider) {
                enabledDownloaders.remove(origin)
                enabledDownloaders.add(0, origin)
            }
            enabledDownloaders
        }
        require(candidates.isNotEmpty()) {
            "No download extension is enabled. Enable a download extension in Settings."
        }

        val title = (track["title"] ?: track["name"] ?: "Track").toString().trim()
        val artist = (track["artist"] ?: track["artists"] ?: "").toString().trim()
        val baseFileName = sanitizeFilename(
            if (artist.isNotBlank()) "$artist - $title" else title
        ).ifBlank { "track_${System.currentTimeMillis()}" }

        var lastError = "Track not available from enabled extensions"
        for (ext in candidates) {
            val attempt = runCatching {
                val settings = loadExtensionSettingsMap(ext)
                val quality = settings["quality"]?.toString()
                    ?: ext.qualityOptions.optJSONObject(0)?.optString("id")
                    ?: "LOSSLESS"
                val defaultOutFile = File(outDir, "$baseFileName.flac")

                executeInExtension(ext) { cx, scope, extObj ->
                    val jsTrack = kotlinMapToJsObject(cx, scope, track)
                    val isrc = (track["isrc"] ?: "").toString().trim()
                    var resolvedTrackId = (track["id"] ?: "").toString().trim()
                    var preparedContext: Map<*, *>? = null

                    val checkFn = ScriptableObject.getProperty(extObj, "checkAvailability") as? RhinoFunction
                    if (checkFn != null) {
                        val checkOpts = kotlinMapToJsObject(
                            cx,
                            scope,
                            mapOf(
                                "track" to track,
                                "duration_ms" to (track["duration_ms"] ?: 0L),
                                "deezer_id" to (track["deezer_id"] ?: ""),
                                "tidal_id" to (track["tidal_id"] ?: ""),
                                "qobuz_id" to (track["qobuz_id"] ?: ""),
                                "spotify_id" to (track["spotify_id"] ?: ""),
                                "track_id" to resolvedTrackId,
                                "url" to (track["external_urls"] ?: ""),
                            ),
                        )
                        val availRaw = jsToKotlin(
                            checkFn.call(cx, scope, extObj, arrayOf<Any?>(isrc, title, artist, checkOpts))
                        ) as? Map<*, *>
                        if (availRaw != null && availRaw["available"] == false) {
                            val reason = availRaw["reason"]?.toString()?.ifBlank { "Unavailable on ${ext.displayName}" }
                            throw IllegalStateException(reason ?: "Unavailable")
                        }
                        val availId = (availRaw?.get("track_id") ?: availRaw?.get("trackId"))?.toString()?.trim()
                        if (!availId.isNullOrEmpty()) {
                            resolvedTrackId = availId
                            ScriptableObject.putProperty(jsTrack, "id", availId)
                        }
                        preparedContext = (availRaw?.get("prepared_context") ?: availRaw?.get("preparedContext")) as? Map<*, *>
                    }

                    val downloadFn = ScriptableObject.getProperty(extObj, "download") as? RhinoFunction
                        ?: throw IllegalStateException("${ext.displayName} has no download() function")
                    val progressFn = object : org.mozilla.javascript.BaseFunction() {
                        override fun call(
                            cx: RhinoContext?,
                            scope: Scriptable?,
                            thisObj: Scriptable?,
                            args: Array<out Any?>?,
                        ): Any = Undefined.instance
                    }
                    val optionsMap = mutableMapOf<String, Any?>(
                        "outputDir" to outDir.absolutePath,
                        "output_dir" to outDir.absolutePath,
                        "quality" to quality,
                        "filename" to defaultOutFile.name,
                        "track" to track,
                        "isrc" to isrc,
                        "duration_ms" to (track["duration_ms"] ?: 0L),
                    )
                    if (preparedContext != null) {
                        optionsMap["preparedContext"] = preparedContext
                        optionsMap["prepared_context"] = preparedContext
                    }
                    val jsOptions = kotlinMapToJsObject(cx, scope, optionsMap)
                    jsToKotlin(
                        downloadFn.call(
                            cx,
                            scope,
                            extObj,
                            arrayOf<Any?>(resolvedTrackId, quality, defaultOutFile.absolutePath, progressFn, jsOptions),
                        )
                    )
                }
            }

            val resultObj = attempt.getOrElse { err ->
                lastError = "${ext.displayName}: ${err.message}"
                continue
            }

            val resultMap = when (resultObj) {
                is Map<*, *> -> resultObj
                is String -> mapOf("success" to true, "file_path" to resultObj)
                else -> null
            } ?: continue

            val success = resultMap["success"] as? Boolean ?: (resultMap["file_path"] != null || resultMap["filePath"] != null || resultMap["path"] != null)
            if (!success) {
                lastError = "${ext.displayName}: ${resultMap["error_message"] ?: resultMap["errorMessage"] ?: resultMap["error"] ?: "Download failed"}"
                continue
            }
            val rawPath = (resultMap["file_path"] ?: resultMap["filePath"] ?: resultMap["path"] ?: "").toString()
            val downloadedFile = if (rawPath.isNotBlank() && File(rawPath).isFile) {
                File(rawPath)
            } else {
                File(outDir, "$baseFileName.flac").takeIf { it.isFile }
                    ?: outDir.listFiles()?.maxByOrNull { it.lastModified() }
            }
            if (downloadedFile != null && downloadedFile.isFile && downloadedFile.length() > 0) {
                val finalFile = finalizeDownloadedAudioExtension(downloadedFile, outDir, baseFileName)
                return mapOf(
                    "success" to true,
                    "filePath" to finalFile.absolutePath,
                    "providerId" to ext.id,
                    "providerName" to ext.displayName,
                )
            } else {
                lastError = "${ext.displayName}: Downloaded file was empty or missing"
            }
        }
        throw IllegalStateException(lastError)
    }

    /**
     * Ensures the saved file's extension matches its actual magic bytes (`.flac`,
     * `.mp3`, `.m4a`, `.ogg`, `.wav`) so NocTune's codec sniffer and scanner read
     * it accurately.
     */
    private fun finalizeDownloadedAudioExtension(file: File, outDir: File, baseName: String): File {
        val header = ByteArray(12)
        val read = FileInputStream(file).use { it.read(header) }
        val ext = when {
            read >= 4 && header[0] == 'f'.code.toByte() && header[1] == 'L'.code.toByte() &&
                header[2] == 'a'.code.toByte() && header[3] == 'C'.code.toByte() -> "flac"
            read >= 4 && header[0] == 'R'.code.toByte() && header[1] == 'I'.code.toByte() &&
                header[2] == 'F'.code.toByte() && header[3] == 'F'.code.toByte() -> "wav"
            read >= 4 && header[0] == 'O'.code.toByte() && header[1] == 'g'.code.toByte() &&
                header[2] == 'g'.code.toByte() && header[3] == 'S'.code.toByte() -> "ogg"
            read >= 8 && header[4] == 'f'.code.toByte() && header[5] == 't'.code.toByte() &&
                header[6] == 'y'.code.toByte() && header[7] == 'p'.code.toByte() -> "m4a"
            else -> "mp3"
        }
        if (file.extension.lowercase(Locale.ROOT) == ext && file.parentFile?.canonicalPath == outDir.canonicalPath) {
            return file
        }
        val dest = File(outDir, "$baseName.$ext")
        if (dest.canonicalPath != file.canonicalPath) {
            file.copyTo(dest, overwrite = true)
            file.delete()
        }
        return dest
    }

    /**
     * Fetches synced or plain lyrics from enabled lyrics extensions (falling
     * back to LRCLib if an extension calls `gobackend.getLyricsLRC`).
     */
    fun fetchLyrics(title: String, artist: String, album: String, durationMs: Long): String? {
        if (title.isBlank()) return null
        val active = synchronized(lock) {
            extensions.values.filter { it.enabled && it.hasLyricsProvider }
        }
        for (ext in active) {
            val lrc = runCatching {
                executeInExtension(ext) { cx, scope, extObj ->
                    val fn = (ScriptableObject.getProperty(extObj, "fetchLyrics") as? RhinoFunction)
                        ?: (ScriptableObject.getProperty(extObj, "getLyrics") as? RhinoFunction)
                        ?: return@executeInExtension null
                    val jsTrack = kotlinMapToJsObject(
                        cx,
                        scope,
                        mapOf(
                            "name" to title,
                            "title" to title,
                            "artists" to artist,
                            "artist" to artist,
                            "album_name" to album,
                            "album" to album,
                            "duration_ms" to durationMs,
                        ),
                    )
                    val res = jsToKotlin(
                        fn.call(cx, scope, extObj, arrayOf<Any?>(title, artist, album, durationMs / 1000.0, jsTrack))
                    )
                    formatLyricsResult(res)
                }
            }.getOrNull()
            if (!lrc.isNullOrBlank()) return lrc
        }
        return null
    }

    private fun formatLyricsResult(res: Any?): String? {
        when (res) {
            is String -> if (res.isNotBlank()) return res.trim()
            is Map<*, *> -> {
                val lrcText = (res["lyrics_lrc"] ?: res["lyricsLrc"] ?: res["lrc"] ?: res["lyrics"]) as? String
                if (!lrcText.isNullOrBlank()) return lrcText.trim()
                val lines = res["lines"] as? List<*>
                if (!lines.isNullOrEmpty()) {
                    val sb = StringBuffer()
                    for (item in lines) {
                        val line = item as? Map<*, *> ?: continue
                        val words = (line["words"] ?: line["text"] ?: "").toString()
                        val ms = ((line["startTimeMs"] ?: line["start_time_ms"] ?: line["timeMs"]) as? Number)?.toLong() ?: 0L
                        val min = (ms / 60000).toString().padStart(2, '0')
                        val sec = ((ms % 60000) / 1000).toString().padStart(2, '0')
                        val cs = ((ms % 1000) / 10).toString().padStart(2, '0')
                        sb.append("[$min:$sec.$cs] $words\n")
                    }
                    val built = sb.toString().trim()
                    if (built.isNotEmpty()) return built
                }
                val plain = (res["plainLyrics"] ?: res["plain_lyrics"]) as? String
                if (!plain.isNullOrBlank()) return plain.trim()
            }
        }
        return null
    }

    private fun <T> executeInExtension(
        ext: LoadedExtension,
        block: (cx: RhinoContext, scope: Scriptable, extObj: Scriptable) -> T,
    ): T {
        val cx = RhinoContext.enter()
        try {
            cx.optimizationLevel = -1 // Required on Android (interpreted mode, no JVM bytecode generation)
            cx.languageVersion = RhinoContext.VERSION_ES6
            val scope = cx.initStandardObjects()
            installMornyeHostGlobals(cx, scope, ext)

            val script = ext.compiledScript ?: run {
                val scriptFile = File(ext.dir, "index.js")
                val scriptSource = scriptFile.readText(StandardCharsets.UTF_8)
                cx.compileString(scriptSource, "${ext.id}/index.js", 1, null).also {
                    ext.compiledScript = it
                }
            }
            script.exec(cx, scope)

            val extObj = ScriptableObject.getProperty(scope, "extension") as? Scriptable
                ?: throw IllegalStateException("Extension '${ext.id}' did not call registerExtension()")

            val initFn = ScriptableObject.getProperty(extObj, "initialize") as? RhinoFunction
            if (initFn != null) {
                val settingsObj = kotlinMapToJsObject(cx, scope, loadExtensionSettingsMap(ext))
                runCatching { initFn.call(cx, scope, extObj, arrayOf(settingsObj)) }
            }
            return block(cx, scope, extObj)
        } finally {
            RhinoContext.exit()
        }
    }

    private fun installMornyeHostGlobals(cx: RhinoContext, scope: Scriptable, ext: LoadedExtension) {
        val extDataDir = File(dataDir, ext.id).apply { mkdirs() }
        val storageFile = File(extDataDir, "storage.json")
        val credsFile = File(extDataDir, "credentials.json")
        val settingsMap = loadExtensionSettingsMap(ext)

        fun readJsonStore(file: File): JSONObject {
            if (!file.isFile) return JSONObject()
            return runCatching { JSONObject(file.readText(StandardCharsets.UTF_8)) }.getOrNull() ?: JSONObject()
        }

        val hostBridge = object {
            @Suppress("unused")
            fun storageGet(isCreds: Boolean, key: String): String {
                val store = readJsonStore(if (isCreds) credsFile else storageFile)
                if (store.has(key)) {
                    return JSONObject().put("found", true).put("value", store.opt(key)).toString()
                }
                if (!isCreds && settingsMap.containsKey(key)) {
                    return JSONObject().put("found", true).put("value", settingsMap[key]).toString()
                }
                return JSONObject().put("found", false).toString()
            }

            @Suppress("unused")
            fun storageSet(isCreds: Boolean, key: String, valueJson: String): Boolean {
                val file = if (isCreds) credsFile else storageFile
                val store = readJsonStore(file)
                val parsed = runCatching { JSONObject("{\"v\":$valueJson}").opt("v") }.getOrDefault(valueJson)
                store.put(key, parsed)
                file.writeText(store.toString(), StandardCharsets.UTF_8)
                return true
            }

            @Suppress("unused")
            fun storageRemove(isCreds: Boolean, key: String): Boolean {
                val file = if (isCreds) credsFile else storageFile
                val store = readJsonStore(file)
                store.remove(key)
                file.writeText(store.toString(), StandardCharsets.UTF_8)
                return true
            }

            @Suppress("unused")
            fun httpCall(url: String, method: String, body: String?, headersJson: String): String {
                val headers = mutableMapOf<String, String>()
                runCatching {
                    val obj = JSONObject(headersJson)
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        headers[k] = obj.optString(k)
                    }
                }
                return try {
                    val resp = httpRequestBytes(
                        url = url,
                        method = method,
                        body = body?.toByteArray(StandardCharsets.UTF_8),
                        headers = headers,
                    )
                    val bodyText = String(resp.body, StandardCharsets.UTF_8)
                    val headersObj = JSONObject()
                    for ((k, v) in resp.headers) {
                        headersObj.put(k, v)
                    }
                    JSONObject()
                        .put("ok", resp.status in 200..299)
                        .put("status", resp.status)
                        .put("statusCode", resp.status)
                        .put("statusText", resp.statusText)
                        .put("body", bodyText)
                        .put("bodyBase64", Base64.encodeToString(resp.body, Base64.NO_WRAP))
                        .put("headers", headersObj)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject()
                        .put("ok", false)
                        .put("status", 0)
                        .put("statusCode", 0)
                        .put("statusText", "Network Error")
                        .put("error", e.message ?: e.toString())
                        .put("body", "")
                        .toString()
                }
            }

            @Suppress("unused")
            fun fileDownload(url: String, outputPath: String, headersJson: String): String {
                val headers = mutableMapOf<String, String>()
                runCatching {
                    val obj = JSONObject(headersJson)
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        headers[k] = obj.optString(k)
                    }
                }
                return try {
                    val outFile = resolveExtensionFile(extDataDir, outputPath)
                    outFile.parentFile?.mkdirs()
                    val resp = httpRequestBytes(url, "GET", null, headers)
                    if (resp.status !in 200..299) {
                        return JSONObject()
                            .put("success", false)
                            .put("error", "HTTP ${resp.status}: ${resp.statusText}")
                            .toString()
                    }
                    outFile.writeBytes(resp.body)
                    JSONObject()
                        .put("success", true)
                        .put("file_path", outFile.absolutePath)
                        .put("filePath", outFile.absolutePath)
                        .put("path", outFile.absolutePath)
                        .put("bytes_written", resp.body.size)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject()
                        .put("success", false)
                        .put("error", e.message ?: e.toString())
                        .toString()
                }
            }

            @Suppress("unused")
            fun fileDownloadSegments(segmentsJson: String, outputPath: String, headersJson: String): String {
                val commonHeaders = mutableMapOf<String, String>()
                runCatching {
                    val obj = JSONObject(headersJson)
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        commonHeaders[k] = obj.optString(k)
                    }
                }
                return try {
                    val outFile = resolveExtensionFile(extDataDir, outputPath)
                    outFile.parentFile?.mkdirs()
                    val arr = JSONArray(segmentsJson)
                    FileOutputStream(outFile).use { fos ->
                        for (i in 0 until arr.length()) {
                            val item = arr.get(i)
                            val segUrl: String
                            val segHeaders = commonHeaders.toMutableMap()
                            if (item is JSONObject) {
                                segUrl = item.optString("url")
                                val h = item.optJSONObject("headers")
                                if (h != null) {
                                    val ks = h.keys()
                                    while (ks.hasNext()) {
                                        val k = ks.next()
                                        segHeaders[k] = h.optString(k)
                                    }
                                }
                            } else {
                                segUrl = item.toString()
                            }
                            val resp = httpRequestBytes(segUrl, "GET", null, segHeaders)
                            if (resp.status !in 200..299) {
                                throw IllegalStateException("Segment $i failed with HTTP ${resp.status}")
                            }
                            fos.write(resp.body)
                        }
                    }
                    JSONObject()
                        .put("success", true)
                        .put("file_path", outFile.absolutePath)
                        .put("filePath", outFile.absolutePath)
                        .put("path", outFile.absolutePath)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject()
                        .put("success", false)
                        .put("error", e.message ?: e.toString())
                        .toString()
                }
            }

            @Suppress("unused")
            fun fileOp(op: String, path1: String, path2: String?): String {
                return try {
                    val f1 = resolveExtensionFile(extDataDir, path1)
                    when (op) {
                        "exists" -> JSONObject().put("result", f1.exists()).toString()
                        "delete" -> JSONObject().put("success", f1.deleteRecursively()).toString()
                        "getSize" -> JSONObject().put("success", true).put("size", if (f1.isFile) f1.length() else 0L).toString()
                        "read" -> JSONObject().put("success", true).put("data", f1.readText(StandardCharsets.UTF_8)).toString()
                        "write" -> {
                            f1.parentFile?.mkdirs()
                            f1.writeText(path2 ?: "", StandardCharsets.UTF_8)
                            JSONObject().put("success", true).toString()
                        }
                        "copy" -> {
                            val f2 = resolveExtensionFile(extDataDir, path2 ?: "")
                            f2.parentFile?.mkdirs()
                            f1.copyTo(f2, overwrite = true)
                            JSONObject().put("success", true).toString()
                        }
                        "move" -> {
                            val f2 = resolveExtensionFile(extDataDir, path2 ?: "")
                            f2.parentFile?.mkdirs()
                            f1.copyTo(f2, overwrite = true)
                            f1.delete()
                            JSONObject().put("success", true).toString()
                        }
                        else -> JSONObject().put("success", false).put("error", "Unknown op $op").toString()
                    }
                } catch (e: Throwable) {
                    JSONObject().put("success", false).put("error", e.message ?: e.toString()).toString()
                }
            }

            @Suppress("unused")
            fun base64Encode(input: String): String =
                Base64.encodeToString(input.toByteArray(StandardCharsets.UTF_8), Base64.NO_WRAP)

            @Suppress("unused")
            fun base64Decode(input: String): String =
                runCatching { String(Base64.decode(input, Base64.DEFAULT), StandardCharsets.UTF_8) }.getOrDefault("")

            @Suppress("unused")
            fun hashHex(algo: String, input: String): String {
                val md = MessageDigest.getInstance(algo)
                return md.digest(input.toByteArray(StandardCharsets.UTF_8)).joinToString("") { "%02x".format(it) }
            }

            @Suppress("unused")
            fun hmacHex(algo: String, message: String, key: String, base64Out: Boolean): String {
                val mac = Mac.getInstance(algo)
                mac.init(SecretKeySpec(key.toByteArray(StandardCharsets.UTF_8), algo))
                val out = mac.doFinal(message.toByteArray(StandardCharsets.UTF_8))
                return if (base64Out) {
                    Base64.encodeToString(out, Base64.NO_WRAP)
                } else {
                    out.joinToString("") { "%02x".format(it) }
                }
            }

            @Suppress("unused")
            fun sanitize(name: String): String = sanitizeFilename(name)

            @Suppress("unused")
            fun normalizeMatch(s: String): String {
                val norm = Normalizer.normalize(s.lowercase(Locale.ROOT), Normalizer.Form.NFD)
                return norm.replace(Regex("\\p{M}"), "")
                    .replace(Regex("\\(feat\\..*?\\)|\\[feat\\..*?\\]"), "")
                    .replace(Regex("[^a-z0-9\\s]"), " ")
                    .replace(Regex("\\s+"), " ")
                    .trim()
            }

            @Suppress("unused")
            fun compareStr(a: String, b: String): Double {
                val na = normalizeMatch(a)
                val nb = normalizeMatch(b)
                if (na == nb) return 1.0
                if (na.isEmpty() || nb.isEmpty()) return 0.0
                val maxLen = max(na.length, nb.length)
                val dist = levenshtein(na, nb)
                return max(0.0, 1.0 - dist.toDouble() / maxLen.toDouble())
            }

            @Suppress("unused")
            fun sleepMs(ms: Long): Boolean {
                if (ms > 0) Thread.sleep(min(ms, 30_000L))
                return true
            }

            @Suppress("unused")
            fun transformPatternedBlocks(inPath: String, outPath: String, optionsJson: String): String {
                return try {
                    val inFile = resolveExtensionFile(extDataDir, inPath)
                    val outFile = resolveExtensionFile(extDataDir, outPath)
                    outFile.parentFile?.mkdirs()
                    val opts = JSONObject(optionsJson)
                    val algo = opts.optString("algorithm", "blowfish").lowercase(Locale.ROOT)
                    val keyHex = opts.optString("key", "")
                    val ivHex = opts.optString("iv", "0001020304050607")
                    val segmentSize = opts.optInt("segmentSize", 2048).coerceAtLeast(8)
                    val transformEvery = opts.optInt("transformEvery", 3).coerceAtLeast(1)
                    val transformOffset = opts.optInt("transformOffset", 0).coerceAtLeast(0)

                    val keyBytes = hexToBytes(keyHex)
                    val ivBytes = hexToBytes(ivHex)
                    val cipherAlgo = if (algo.contains("aes")) "AES" else "Blowfish"
                    val cipherTransform = "$cipherAlgo/CBC/NoPadding"
                    val keySpec = SecretKeySpec(keyBytes, cipherAlgo)
                    val ivSpec = IvParameterSpec(ivBytes)

                    FileInputStream(inFile).use { fis ->
                        FileOutputStream(outFile).use { fos ->
                            val buf = ByteArray(segmentSize)
                            var segIndex = 0
                            while (true) {
                                var totalRead = 0
                                while (totalRead < segmentSize) {
                                    val r = fis.read(buf, totalRead, segmentSize - totalRead)
                                    if (r <= 0) break
                                    totalRead += r
                                }
                                if (totalRead <= 0) break
                                val shouldTransform = totalRead == segmentSize &&
                                    segIndex >= transformOffset &&
                                    ((segIndex - transformOffset) % transformEvery == 0)
                                if (shouldTransform) {
                                    val cipher = Cipher.getInstance(cipherTransform)
                                    cipher.init(Cipher.DECRYPT_MODE, keySpec, ivSpec)
                                    val decrypted = cipher.doFinal(buf, 0, totalRead)
                                    fos.write(decrypted)
                                } else {
                                    fos.write(buf, 0, totalRead)
                                }
                                segIndex++
                            }
                        }
                    }
                    JSONObject()
                        .put("success", true)
                        .put("path", outFile.absolutePath)
                        .put("file_path", outFile.absolutePath)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject()
                        .put("success", false)
                        .put("error", e.message ?: e.toString())
                        .toString()
                }
            }

            @Suppress("unused")
            fun signedFetchCall(method: String, path: String, body: String?, headersJson: String): String {
                val signedCfg = ext.manifestJson.optJSONObject("signedSession")
                    ?: ext.manifestJson.optJSONObject("signed_session")
                    ?: return JSONObject().put("ok", false).put("error", "No signedSession in manifest").toString()
                return try {
                    val baseUrl = signedCfg.optString("baseUrl", "https://api.zarz.moe/v2").trimEnd('/')
                    val appVer = signedCfg.optString("appVersion", "${ext.id}@${ext.version}")
                    val platform = signedCfg.optString("platform", "extension")
                    val schemeLabel = signedCfg.optString("schemeLabel", "ZARZ-HMAC-V1")
                    val headerPrefix = signedCfg.optString("headerPrefix", "X-Zarz-")
                    val timeWindow = signedCfg.optLong("timeWindowSeconds", 300L).coerceAtLeast(1L)
                    val endpoints = signedCfg.optJSONObject("endpoints")
                    val bootstrapEp = endpoints?.optString("bootstrap", "/bootstrap") ?: "/bootstrap"

                    val sessionFile = File(extDataDir, "signed_session.json")
                    var sessionObj = if (sessionFile.isFile) {
                        runCatching { JSONObject(sessionFile.readText(StandardCharsets.UTF_8)) }.getOrNull() ?: JSONObject()
                    } else {
                        JSONObject()
                    }
                    var installId = sessionObj.optString("install_id")
                    if (installId.isBlank()) {
                        val rnd = ByteArray(16)
                        SecureRandom().nextBytes(rnd)
                        installId = rnd.joinToString("") { "%02x".format(it) }
                        sessionObj.put("install_id", installId)
                    }
                    var sessionId = sessionObj.optString("session_id")
                    var sessionSecret = sessionObj.optString("session_secret")
                    if (sessionId.isBlank() || sessionSecret.isBlank()) {
                        val bootUrl = "$baseUrl/${bootstrapEp.trimStart('/')}?app_version=${URLEncoder.encode(appVer, "UTF-8")}&install_id=$installId"
                        val bootResp = httpRequestBytes(bootUrl, "GET", null, mapOf("User-Agent" to "NocTune/1.12.0"))
                        if (bootResp.status in 200..299) {
                            val bootJson = JSONObject(String(bootResp.body, StandardCharsets.UTF_8))
                            sessionId = bootJson.optString("session_id")
                            sessionSecret = bootJson.optString("session_secret")
                            if (sessionId.isNotBlank() && sessionSecret.isNotBlank()) {
                                sessionObj.put("session_id", sessionId)
                                sessionObj.put("session_secret", sessionSecret)
                                sessionFile.writeText(sessionObj.toString(), StandardCharsets.UTF_8)
                            }
                        }
                    }
                    if (sessionId.isBlank() || sessionSecret.isBlank()) {
                        return JSONObject().put("ok", false).put("status", 401).put("statusCode", 401)
                            .put("error", "Signed session bootstrap required verification").toString()
                    }

                    val targetUrl = if (path.startsWith("https://")) path else "$baseUrl/${path.trimStart('/')}"
                    val parsedUri = URI(targetUrl)
                    val escapedPath = parsedUri.rawPath.ifBlank { "/" }
                    val bodyBytes = (body ?: "").toByteArray(StandardCharsets.UTF_8)
                    val bodyHash = MessageDigest.getInstance("SHA-256").digest(bodyBytes).joinToString("") { "%02x".format(it) }
                    val nowMillis = System.currentTimeMillis()
                    val sdf = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                        timeZone = java.util.TimeZone.getTimeZone("UTC")
                    }
                    val timestamp = sdf.format(java.util.Date(nowMillis))
                    val nonceBytes = ByteArray(16)
                    SecureRandom().nextBytes(nonceBytes)
                    val nonce = nonceBytes.joinToString("") { "%02x".format(it) }
                    val window = (nowMillis / 1000L) / timeWindow
                    val rolling = hmacSha256Base64Url(sessionSecret, "$window:$sessionId")
                    val signing = listOf(
                        schemeLabel,
                        method.uppercase(Locale.ROOT),
                        escapedPath,
                        "",
                        bodyHash,
                        timestamp,
                        nonce,
                        sessionId,
                        appVer,
                        platform,
                    ).joinToString("\n")
                    val signature = hmacSha256Base64Url(rolling, signing)

                    val reqHeaders = mutableMapOf(
                        "${headerPrefix}Session" to sessionId,
                        "${headerPrefix}Timestamp" to timestamp,
                        "${headerPrefix}Nonce" to nonce,
                        "${headerPrefix}Body-SHA256" to bodyHash,
                        "${headerPrefix}Signature" to signature,
                        "${headerPrefix}App-Version" to appVer,
                        "${headerPrefix}Platform" to platform,
                        "Content-Type" to "application/json",
                        "Accept" to "application/json",
                    )
                    runCatching {
                        val extra = JSONObject(headersJson)
                        val ks = extra.keys()
                        while (ks.hasNext()) {
                            val k = ks.next()
                            reqHeaders[k] = extra.optString(k)
                        }
                    }
                    val resp = httpRequestBytes(
                        url = targetUrl,
                        method = method.uppercase(Locale.ROOT),
                        body = if (body.isNullOrEmpty()) null else bodyBytes,
                        headers = reqHeaders,
                    )
                    val respText = String(resp.body, StandardCharsets.UTF_8)
                    JSONObject()
                        .put("ok", resp.status in 200..299)
                        .put("status", resp.status)
                        .put("statusCode", resp.status)
                        .put("body", respText)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject().put("ok", false).put("status", 0).put("statusCode", 0)
                        .put("error", e.message ?: e.toString()).toString()
                }
            }

            @Suppress("unused")
            fun fetchLrcLib(track: String, artist: String, durationMs: Long): String {
                return try {
                    val qTrack = URLEncoder.encode(track, "UTF-8")
                    val qArtist = URLEncoder.encode(artist, "UTF-8")
                    val url = "https://lrclib.net/api/search?track_name=$qTrack&artist_name=$qArtist"
                    val resp = httpRequestBytes(url, "GET", null, mapOf("User-Agent" to "NocTune/1.12.0"))
                    if (resp.status !in 200..299) return JSONObject().put("error", "HTTP ${resp.status}").toString()
                    val arr = JSONArray(String(resp.body, StandardCharsets.UTF_8))
                    if (arr.length() == 0) return JSONObject().put("error", "No lyrics found").toString()
                    val first = arr.getJSONObject(0)
                    val synced = first.optString("syncedLyrics")
                    val plain = first.optString("plainLyrics")
                    JSONObject()
                        .put("lyrics", synced.ifBlank { plain })
                        .put("sync_type", if (synced.isNotBlank()) "LINE_SYNCED" else "UNSYNCED")
                        .toString()
                } catch (e: Throwable) {
                    JSONObject().put("error", e.message ?: "Failed").toString()
                }
            }
        }

        ScriptableObject.putProperty(scope, "__nocHost", RhinoContext.javaToJS(hostBridge, scope))

        val bootstrapJs = """
            (function(host) {
                globalThis.extension = null;
                globalThis.registerExtension = function(ext) {
                    globalThis.extension = ext;
                };
                globalThis.btoa = function(s) { return String(host.base64Encode(String(s || ""))); };
                globalThis.atob = function(s) { return String(host.base64Decode(String(s || ""))); };
                globalThis.TextEncoder = function() {
                    this.encoding = "utf-8";
                    this.encode = function(str) {
                        var s = unescape(encodeURIComponent(String(str || "")));
                        var arr = new Uint8Array(s.length);
                        for (var i = 0; i < s.length; i++) arr[i] = s.charCodeAt(i);
                        return arr;
                    };
                };
                globalThis.TextDecoder = function() {
                    this.encoding = "utf-8";
                    this.decode = function(bytes) {
                        if (!bytes) return "";
                        if (typeof bytes === "string") return bytes;
                        var s = "";
                        for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i] & 0xff);
                        try { return decodeURIComponent(escape(s)); } catch (_) { return s; }
                    };
                };
                globalThis.URLSearchParams = function(init) {
                    var pairs = [];
                    if (typeof init === "string") {
                        var q = init.replace(/^\?/, "");
                        if (q) {
                            q.split("&").forEach(function(part) {
                                var idx = part.indexOf("=");
                                if (idx >= 0) {
                                    pairs.push([decodeURIComponent(part.slice(0, idx)), decodeURIComponent(part.slice(idx + 1))]);
                                } else if (part) {
                                    pairs.push([decodeURIComponent(part), ""]);
                                }
                            });
                        }
                    } else if (init && typeof init === "object") {
                        Object.keys(init).forEach(function(k) {
                            if (init[k] !== undefined && init[k] !== null) {
                                pairs.push([String(k), String(init[k])]);
                            }
                        });
                    }
                    this.append = function(k, v) { pairs.push([String(k), String(v)]); };
                    this.set = function(k, v) {
                        var key = String(k);
                        pairs = pairs.filter(function(p) { return p[0] !== key; });
                        pairs.push([key, String(v)]);
                    };
                    this.get = function(k) {
                        var key = String(k);
                        for (var i = 0; i < pairs.length; i++) if (pairs[i][0] === key) return pairs[i][1];
                        return null;
                    };
                    this.getAll = function(k) {
                        var key = String(k);
                        return pairs.filter(function(p) { return p[0] === key; }).map(function(p) { return p[1]; });
                    };
                    this.has = function(k) { return this.get(k) !== null; };
                    this.delete = function(k) {
                        var key = String(k);
                        pairs = pairs.filter(function(p) { return p[0] !== key; });
                    };
                    this.toString = function() {
                        return pairs.map(function(p) {
                            return encodeURIComponent(p[0]) + "=" + encodeURIComponent(p[1]);
                        }).join("&");
                    };
                };
                globalThis.URL = function(input, base) {
                    var href = String(input || "");
                    if (base && !/^https?:\/\//i.test(href)) {
                        href = String(base).replace(/\/+$/, "") + "/" + href.replace(/^\/+/, "");
                    }
                    this.href = href;
                    var m = href.match(/^([a-z]+:)\/\/([^\/?#]+)(\/[^?#]*)?(\?[^#]*)?(#.*)?$/i);
                    this.protocol = m ? m[1] : "";
                    this.host = m ? m[2] : "";
                    this.hostname = this.host.split(":")[0];
                    this.pathname = (m && m[3]) ? m[3] : "/";
                    this.search = (m && m[4]) ? m[4] : "";
                    this.hash = (m && m[5]) ? m[5] : "";
                    this.searchParams = new URLSearchParams(this.search);
                    var self = this;
                    this.toString = function() {
                        var qs = self.searchParams.toString();
                        var baseHref = self.href.split("?")[0];
                        return qs ? (baseHref + "?" + qs) : baseHref;
                    };
                };
                globalThis.storage = {
                    get: function(k, fallback) {
                        var res = JSON.parse(String(host.storageGet(false, String(k))));
                        return res.found ? res.value : fallback;
                    },
                    set: function(k, v) {
                        return Boolean(host.storageSet(false, String(k), JSON.stringify(v)));
                    },
                    remove: function(k) {
                        return Boolean(host.storageRemove(false, String(k)));
                    }
                };
                globalThis.credentials = {
                    get: function(k, fallback) {
                        var res = JSON.parse(String(host.storageGet(true, String(k))));
                        return res.found ? res.value : fallback;
                    },
                    store: function(k, v) {
                        var ok = Boolean(host.storageSet(true, String(k), JSON.stringify(v)));
                        return { success: ok };
                    },
                    remove: function(k) {
                        return Boolean(host.storageRemove(true, String(k)));
                    },
                    has: function(k) {
                        var res = JSON.parse(String(host.storageGet(true, String(k))));
                        return res.found === true;
                    }
                };
                function doHttp(url, method, body, headers, isFetch) {
                    var bodyStr = null;
                    if (body !== undefined && body !== null) {
                        bodyStr = (typeof body === "string") ? body : JSON.stringify(body);
                    }
                    var raw = JSON.parse(String(host.httpCall(String(url), String(method || "GET"), bodyStr, JSON.stringify(headers || {}))));
                    raw.text = function() { return raw.body || ""; };
                    raw.json = function() {
                        try { return JSON.parse(raw.body || ""); } catch (_) { return undefined; }
                    };
                    raw.arrayBuffer = function() {
                        var bin = globalThis.atob(raw.bodyBase64 || "");
                        var arr = new Uint8Array(bin.length);
                        for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i) & 0xff;
                        return arr;
                    };
                    return raw;
                }
                globalThis.http = {
                    get: function(url, headers) { return doHttp(url, "GET", null, headers, false); },
                    post: function(url, body, headers) { return doHttp(url, "POST", body, headers, false); },
                    put: function(url, body, headers) { return doHttp(url, "PUT", body, headers, false); },
                    delete: function(url, headers) { return doHttp(url, "DELETE", null, headers, false); },
                    patch: function(url, body, headers) { return doHttp(url, "PATCH", body, headers, false); },
                    request: function(url, opts) {
                        opts = opts || {};
                        return doHttp(url, opts.method || "GET", opts.body, opts.headers, false);
                    },
                    clearCookies: function() { return true; }
                };
                globalThis.fetch = function(url, opts) {
                    opts = opts || {};
                    return doHttp(url, opts.method || "GET", opts.body, opts.headers, true);
                };
                globalThis.file = {
                    download: function(url, path, opts) {
                        var headers = (opts && opts.headers) ? opts.headers : {};
                        return JSON.parse(String(host.fileDownload(String(url), String(path), JSON.stringify(headers))));
                    },
                    downloadSegments: function(segments, path, opts) {
                        var headers = (opts && opts.headers) ? opts.headers : {};
                        return JSON.parse(String(host.fileDownloadSegments(JSON.stringify(segments || []), String(path), JSON.stringify(headers))));
                    },
                    exists: function(path) {
                        return JSON.parse(String(host.fileOp("exists", String(path), null))).result === true;
                    },
                    delete: function(path) {
                        return JSON.parse(String(host.fileOp("delete", String(path), null)));
                    },
                    getSize: function(path) {
                        return JSON.parse(String(host.fileOp("getSize", String(path), null)));
                    },
                    read: function(path) {
                        return JSON.parse(String(host.fileOp("read", String(path), null)));
                    },
                    write: function(path, data) {
                        return JSON.parse(String(host.fileOp("write", String(path), String(data || ""))));
                    },
                    copy: function(src, dst) {
                        return JSON.parse(String(host.fileOp("copy", String(src), String(dst))));
                    },
                    move: function(src, dst) {
                        return JSON.parse(String(host.fileOp("move", String(src), String(dst))));
                    },
                    transformPatternedBlocks: function(inPath, outPath, opts, onProgress) {
                        var res = JSON.parse(String(host.transformPatternedBlocks(String(inPath), String(outPath), JSON.stringify(opts || {}))));
                        if (typeof onProgress === "function") onProgress(100, 100);
                        return res;
                    }
                };
                globalThis.ffmpeg = {
                    getInfo: function(path) {
                        var sz = JSON.parse(String(host.fileOp("getSize", String(path), null))).size || 0;
                        return { success: sz > 0, duration: 200, bitDepth: 16, sampleRate: 44100, codec: "flac" };
                    },
                    convert: function(inPath, outPath, opts) {
                        return JSON.parse(String(host.fileOp("copy", String(inPath), String(outPath))));
                    },
                    execute: function() {
                        return { success: false, error: "raw FFmpeg execution is disabled" };
                    }
                };
                globalThis.session = {
                    status: function() { return { authenticated: true }; },
                    clear: function() { return { success: true }; },
                    completeGrant: function() { return { success: true }; },
                    signedFetch: function(method, path, body, headers) {
                        var bodyStr = (body === undefined || body === null) ? "" : (typeof body === "string" ? body : JSON.stringify(body));
                        return JSON.parse(String(host.signedFetchCall(String(method || "GET"), String(path || "/"), bodyStr, JSON.stringify(headers || {}))));
                    }
                };
                globalThis.utils = {
                    isDownloadCancelled: function() { return false; },
                    isRequestCancelled: function() { return false; },
                    randomUserAgent: function() { return "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36"; },
                    appVersion: function() { return "1.12.0"; },
                    appUserAgent: function() { return "NocTune/1.12.0"; },
                    setDownloadStatus: function() {},
                    getResolutionRemainingMs: function() { return 60000; },
                    base64Encode: function(s) { return String(host.base64Encode(String(s || ""))); },
                    base64Decode: function(s) { return String(host.base64Decode(String(s || ""))); },
                    md5: function(s) { return String(host.hashHex("MD5", String(s || ""))); },
                    sha256: function(s) { return String(host.hashHex("SHA-256", String(s || ""))); },
                    hmacSHA256: function(msg, key) { return String(host.hmacHex("HmacSHA256", String(msg || ""), String(key || ""), false)); },
                    hmacSHA256Base64: function(msg, key) { return String(host.hmacHex("HmacSHA256", String(msg || ""), String(key || ""), true)); },
                    parseJSON: function(s) { try { return JSON.parse(String(s)); } catch (_) { return undefined; } },
                    stringifyJSON: function(v) { try { return JSON.stringify(v); } catch (_) { return ""; } },
                    sleep: function(ms) { return Boolean(host.sleepMs(Number(ms) || 0)); }
                };
                globalThis.gobackend = {
                    sanitizeFilename: function(s) { return String(host.sanitize(String(s || ""))); },
                    buildFilename: function(tpl, meta) {
                        meta = meta || {};
                        var out = String(tpl || "{artist} - {title}");
                        Object.keys(meta).forEach(function(k) {
                            out = out.split("{" + k + "}").join(String(meta[k] || ""));
                        });
                        return String(host.sanitize(out));
                    },
                    getLocalTime: function() {
                        var now = new Date();
                        return { unix: Math.floor(now.getTime() / 1000), iso: now.toISOString() };
                    },
                    getLyricsLRC: function(spotifyId, track, artist, path, duration) {
                        return JSON.parse(String(host.fetchLrcLib(String(track || ""), String(artist || ""), Number(duration) || 0)));
                    },
                    checkISRCExists: function() { return { exists: false }; },
                    addToISRCIndex: function() { return { success: true }; }
                };
                globalThis.matching = {
                    compareStrings: function(a, b) { return Number(host.compareStr(String(a || ""), String(b || ""))); },
                    compareDuration: function(a, b, tol) {
                        var t = (tol === undefined) ? 3000 : Number(tol);
                        return Math.abs(Number(a || 0) - Number(b || 0)) <= t;
                    },
                    normalizeString: function(s) { return String(host.normalizeMatch(String(s || ""))); }
                };
                globalThis.log = {
                    debug: function() {},
                    info: function() {},
                    warn: function() {},
                    error: function() {}
                };
                globalThis.console = globalThis.log;
            })(__nocHost);
        """.trimIndent()
        val bootScript = compiledBootstrapScript ?: cx.compileString(bootstrapJs, "mornye_prelude.js", 1, null).also {
            compiledBootstrapScript = it
        }
        bootScript.exec(cx, scope)
    }

    private fun resolveExtensionFile(extDataDir: File, path: String): File {
        val f = File(path)
        return if (f.isAbsolute) f else File(extDataDir, path)
    }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.trim()
        val out = ByteArray(clean.length / 2)
        for (i in out.indices) {
            out[i] = clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
        return out
    }

    private fun hmacSha256Base64Url(key: String, message: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        val raw = mac.doFinal(message.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(raw, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private data class HttpResponseBytes(
        val status: Int,
        val statusText: String,
        val headers: Map<String, String>,
        val body: ByteArray,
    )

    private fun httpRequestBytes(
        url: String,
        method: String,
        body: ByteArray?,
        headers: Map<String, String>,
    ): HttpResponseBytes {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method.uppercase(Locale.ROOT)
            connectTimeout = 6_000
            readTimeout = 12_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", headers["User-Agent"] ?: headers["user-agent"] ?: "Spotiflac-Extension/1.0")
            for ((k, v) in headers) {
                setRequestProperty(k, v)
            }
            if (body != null && body.isNotEmpty() && requestMethod in setOf("POST", "PUT", "PATCH")) {
                doOutput = true
                outputStream.use { it.write(body) }
            }
        }
        val status = conn.responseCode
        val statusText = conn.responseMessage ?: ""
        val respHeaders = linkedMapOf<String, String>()
        conn.headerFields?.forEach { (k, vals) ->
            if (k != null && !vals.isNullOrEmpty()) {
                respHeaders[k.lowercase(Locale.ROOT)] = vals.joinToString(", ")
            }
        }
        val rawStream = if (status in 200..399) conn.inputStream else (conn.errorStream ?: conn.inputStream)
        val encoding = conn.contentEncoding?.lowercase(Locale.ROOT) ?: ""
        val decodedStream = if (encoding.contains("gzip")) GZIPInputStream(rawStream) else rawStream
        val bytes = decodedStream.use { it.readBytes() }
        return HttpResponseBytes(status, statusText, respHeaders, bytes)
    }

    private fun sanitizeFilename(value: String): String {
        return value
            .replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_")
            .replace(Regex("\\s+"), " ")
            .trim()
            .trimEnd('.')
            .take(120)
    }

    private fun levenshtein(a: String, b: String): Int {
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = dp[0]
            dp[0] = i
            for (j in 1..b.length) {
                val temp = dp[j]
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                dp[j] = min(min(dp[j] + 1, dp[j - 1] + 1), prev + cost)
                prev = temp
            }
        }
        return dp[b.length]
    }

    private fun kotlinMapToJsObject(cx: RhinoContext, scope: Scriptable, map: Map<*, *>): Scriptable {
        val obj = cx.newObject(scope)
        for ((k, v) in map) {
            val key = k?.toString() ?: continue
            val jsVal = when (v) {
                null -> null
                is Map<*, *> -> kotlinMapToJsObject(cx, scope, v)
                is List<*> -> cx.newArray(scope, v.map { item ->
                    if (item is Map<*, *>) kotlinMapToJsObject(cx, scope, item) else item
                }.toTypedArray())
                else -> v
            }
            ScriptableObject.putProperty(obj, key, jsVal)
        }
        return obj
    }

    private fun jsToKotlin(value: Any?): Any? {
        return when (value) {
            null, is Undefined -> null
            is org.mozilla.javascript.Wrapper -> jsToKotlin(value.unwrap())
            is NativeArray -> {
                val len = value.length.toInt()
                (0 until len).map { idx -> jsToKotlin(NativeArray.getProperty(value, idx)) }
            }
            is Scriptable -> {
                val map = linkedMapOf<String, Any?>()
                for (id in ScriptableObject.getPropertyIds(value)) {
                    val key = id.toString()
                    val prop = when (id) {
                        is String -> ScriptableObject.getProperty(value, id)
                        is Int -> ScriptableObject.getProperty(value, id)
                        else -> null
                    }
                    if (prop !is RhinoFunction) {
                        map[key] = jsToKotlin(prop)
                    }
                }
                map
            }
            is CharSequence -> value.toString()
            is Number, is Boolean -> value
            else -> value.toString()
        }
    }

    private fun jsonToKotlin(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> {
                val map = linkedMapOf<String, Any?>()
                val keys = value.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    map[k] = jsonToKotlin(value.opt(k))
                }
                map
            }
            is JSONArray -> (0 until value.length()).map { jsonToKotlin(value.opt(it)) }
            else -> value
        }
    }
}
