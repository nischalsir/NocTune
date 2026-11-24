package com.nischalpandey.noctune

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.util.Base64
import androidx.core.app.NotificationCompat
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
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.Normalizer
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
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
    private val activeProgressCallback = ThreadLocal<((Int) -> Unit)?>()
    private val activeDownloadTrack = ThreadLocal<Map<String, Any?>?>()
    private val downloadNotificationSeq = java.util.concurrent.atomic.AtomicInteger(4000)

    @Volatile
    private var compiledBootstrapScript: org.mozilla.javascript.Script? = null

    @Volatile
    private var cachedVisitorData: String? = null

    @Volatile
    private var cachedVisitorDataAtMs: Long = 0L

    private val streamProxy by lazy { LocalYtStreamProxy() }

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

    private val latestRegistryVersions = ConcurrentHashMap<String, String>()
    private val latestRegistryUrls = ConcurrentHashMap<String, String>()

    private val bundledAssetMap = linkedMapOf(
        "deezer" to "deezer.sflx",
        "tidal-web" to "tidal-web.sflx",
        "qobuz-web" to "qobuz-web.sflx",
        "jiosaavn" to "jiosaavn.sflx",
        "ytmusic-spotiflac" to "ytmusic-spotiflac.sflx",
        "soundcloud" to "soundcloud.sflx",
        "amazon" to "amzn.sflx",
        "beatport" to "beatport.sflx",
        "spotify-web" to "spotify-web.sflx",
        "apple-music" to "apple-music.sflx",
        "bugs-music" to "bugs-music.sflx",
        "melon-music" to "melon-music.sflx",
        "genie-music" to "genie-music.sflx",
        "jellyfin" to "jellyfin.sflx",
    )

    fun init(musicDirPath: String) {
        if (musicDirPath.isNotBlank()) {
            val dir = File(musicDirPath)
            dir.mkdirs()
            defaultMusicDir = dir
        }
        installBundledAssetExtensions()
        synchronized(lock) {
            reloadInstalledLocked()
        }
    }

    private fun ensureBundledLoaded() {
        val needsReload = synchronized(lock) { extensions.size < bundledAssetMap.size }
        if (needsReload) {
            installBundledAssetExtensions()
            synchronized(lock) {
                if (extensions.size < bundledAssetMap.size) {
                    reloadInstalledLocked()
                }
            }
        }
    }

    private fun compareSemver(a: String, b: String): Int {
        val pa = a.trim().removePrefix("v").removePrefix("V").split('.', '-', '+')
        val pb = b.trim().removePrefix("v").removePrefix("V").split('.', '-', '+')
        val len = max(pa.size, pb.size)
        for (i in 0 until len) {
            val na = pa.getOrNull(i)?.toIntOrNull() ?: 0
            val nb = pb.getOrNull(i)?.toIntOrNull() ?: 0
            if (na != nb) return na.compareTo(nb)
        }
        return 0
    }

    private fun readBundledManifestVersion(assetName: String): String {
        return runCatching {
            context.assets.open("mornye_extensions/$assetName").use { rawIn ->
                ZipInputStream(rawIn).use { zis ->
                    var entry = zis.nextEntry
                    while (entry != null) {
                        val cleanName = entry.name.replace('\\', '/').trimStart('/')
                        if (cleanName == "manifest.json" || cleanName.endsWith("/manifest.json")) {
                            val jsonText = zis.readBytes().toString(StandardCharsets.UTF_8)
                            val ver = JSONObject(jsonText).optString("version").trim()
                            if (ver.isNotEmpty()) return@runCatching ver
                        }
                        zis.closeEntry()
                        entry = zis.nextEntry
                    }
                    ""
                }
            }
        }.getOrDefault("")
    }

    /**
     * Unpacks all 14 Mornye JavaScript `.sflx` extensions bundled in
     * `assets/mornye_extensions/` directly into [installedDir] whenever a
     * bundled extension directory is missing or when a newer version is bundled
     * in an app update, while NEVER overwriting a newer version that the user
     * updated from the Mornye registry.
     */
    private fun installBundledAssetExtensions() {
        runCatching {
            var anyUnpacked = false
            for ((extId, assetName) in bundledAssetMap) {
                val targetDir = File(installedDir, extId)
                val manifestFile = File(targetDir, "manifest.json")
                val indexFile = File(targetDir, "index.js")
                if (manifestFile.isFile && indexFile.isFile) {
                    val installedVer = runCatching {
                        JSONObject(manifestFile.readText(StandardCharsets.UTF_8)).optString("version").trim()
                    }.getOrDefault("")
                    val bundledVer = readBundledManifestVersion(assetName)
                    if (installedVer.isNotEmpty() && (bundledVer.isEmpty() || compareSemver(bundledVer, installedVer) <= 0)) {
                        continue
                    }
                }
                val staging = File(tempDir, "bundle_${System.nanoTime()}_$extId").apply { mkdirs() }
                try {
                    context.assets.open("mornye_extensions/$assetName").use { rawIn ->
                        ZipInputStream(rawIn).use { zis ->
                            var entry = zis.nextEntry
                            while (entry != null) {
                                val cleanName = entry.name.replace('\\', '/').trimStart('/')
                                if (cleanName.isNotEmpty() && !cleanName.contains("..")) {
                                    val outFile = File(staging, cleanName)
                                    if (entry.isDirectory) {
                                        outFile.mkdirs()
                                    } else {
                                        outFile.parentFile?.mkdirs()
                                        FileOutputStream(outFile).use { fos -> zis.copyTo(fos) }
                                    }
                                }
                                zis.closeEntry()
                                entry = zis.nextEntry
                            }
                        }
                    }
                    val rootSource = findExtensionRoot(staging) ?: continue
                    synchronized(lock) {
                        if (targetDir.exists()) targetDir.deleteRecursively()
                        targetDir.mkdirs()
                        rootSource.copyRecursively(targetDir, overwrite = true)
                        if (!statePrefs.contains("enabled_$extId")) {
                            statePrefs.edit().putBoolean("enabled_$extId", extId != "jellyfin").apply()
                        }
                    }
                    anyUnpacked = true
                } catch (_: Throwable) {
                } finally {
                    staging.deleteRecursively()
                }
            }
            if (anyUnpacked && statePrefs.getString("priority_order", null).isNullOrBlank()) {
                statePrefs.edit().putString(
                    "priority_order",
                    bundledAssetMap.keys.joinToString(","),
                ).apply()
            }
        }
    }

    /**
     * Checks `https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/registry-unified.json`
     * for newer extension versions and records each extension's latest version
     * and download URL.
     */
    fun checkExtensionUpdates() {
        ensureBundledLoaded()
        runCatching {
            val registryUrl = "https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/registry-unified.json"
            val resp = httpRequestBytes(
                registryUrl,
                "GET",
                null,
                mapOf("User-Agent" to "NocTune/2.0.0", "Accept" to "application/json"),
            )
            if (resp.status !in 200..299) return
            val obj = JSONObject(String(resp.body, StandardCharsets.UTF_8))
            val arr = obj.optJSONArray("extensions") ?: return
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val runtime = item.optString("runtime", "javascript").lowercase(Locale.ROOT)
                if (runtime == "python") continue
                val id = item.optString("id").ifBlank { item.optString("name") }.trim()
                val ver = item.optString("version").trim()
                val dlUrl = item.optString("download_url").trim()
                if (id.isNotEmpty() && ver.isNotEmpty()) {
                    latestRegistryVersions[id] = ver
                }
                if (id.isNotEmpty() && dlUrl.isNotEmpty()) {
                    latestRegistryUrls[id] = dlUrl
                }
            }
        }
    }

    /**
     * Updates a specific extension ([targetId]) or all extensions from the
     * official Mornye Unified Registry (`registry-unified.json`), preserving
     * each extension's enabled state and user settings.
     */
    fun updateExtensionsFromRegistry(targetId: String? = null) {
        checkExtensionUpdates()
        val idsToUpdate = if (!targetId.isNullOrBlank()) {
            listOf(targetId.trim())
        } else {
            val currentList = synchronized(lock) { extensions.values.toList() }
            val outdated = currentList.filter { ext ->
                val latest = latestRegistryVersions[ext.id]
                !latest.isNullOrBlank() && compareSemver(latest, ext.version) > 0
            }.map { it.id }
            if (outdated.isNotEmpty()) outdated else latestRegistryUrls.keys.toList()
        }
        for (id in idsToUpdate) {
            val dlUrl = latestRegistryUrls[id]
                ?: bundledAssetMap[id]?.let {
                    "https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/extensions/$it"
                }
                ?: continue
            val wasEnabled = synchronized(lock) {
                extensions[id]?.enabled ?: statePrefs.getBoolean("enabled_$id", id != "jellyfin")
            }
            runCatching {
                val pkgBytes = httpRequestBytes(dlUrl, "GET", null, mapOf("User-Agent" to "NocTune/2.0.0")).body
                val tmp = File(tempDir, "upd_${System.nanoTime()}_$id.sflx")
                try {
                    tmp.writeBytes(pkgBytes)
                    val installedId = installPackage(tmp)
                    setEnabled(installedId, wasEnabled)
                } finally {
                    tmp.delete()
                }
            }
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

    fun listExtensions(): List<Map<String, Any?>> {
        ensureBundledLoaded()
        return synchronized(lock) {
        extensions.values.map { ext ->
            val iconFile = listOf("icon.png", "icon.jpg", "icon.jpeg", "icon.webp")
                .map { File(ext.dir, it) }
                .firstOrNull { it.isFile }
            val latestVer = latestRegistryVersions[ext.id] ?: ""
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
            if (qualities.isEmpty() && ext.hasDownloadProvider) {
                qualities.add(
                    mapOf(
                        "id" to "LOSSLESS",
                        "label" to "FLAC Lossless",
                        "description" to "16-bit / 44.1 kHz lossless audio",
                    )
                )
                qualities.add(
                    mapOf(
                        "id" to "HIGH",
                        "label" to "High Quality (320 kbps)",
                        "description" to "AAC / MP3 320 kbps",
                    )
                )
            }
            mapOf(
                "id" to ext.id,
                "name" to ext.name,
                "displayName" to ext.displayName,
                "version" to ext.version,
                "latestVersion" to latestVer,
                "iconPath" to (iconFile?.absolutePath ?: ""),
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
     * Searches across a selected extension ([providerId]), all enabled
     * search/metadata extensions in parallel, or built-in YouTube Music
     * InnerTube (`ytmusic`) when online search is used without search extensions.
     * If the query is a URL, resolves it via [handleUrl] too.
     */
    fun search(
        query: String,
        limit: Int,
        filter: String? = null,
        providerId: String? = null,
    ): List<Map<String, Any?>> {
        ensureBundledLoaded()
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
        val canonicalFilter = when (filter?.trim()?.lowercase(Locale.ROOT)) {
            "track", "tracks", "song", "songs" -> "tracks"
            "album", "albums" -> "albums"
            "artist", "artists" -> "artists"
            else -> "all"
        }

        val requestedProvider = providerId?.trim()?.takeIf { it.isNotEmpty() && it != "all" }
        if (requestedProvider == "ytmusic" || requestedProvider == "ytmusic-spotiflac") {
            if (requestedProvider == "ytmusic-spotiflac") {
                val ytExt = synchronized(lock) { extensions["ytmusic-spotiflac"] }
                if (ytExt != null && !ytExt.enabled) {
                    throw IllegalStateException("${ytExt.displayName} is currently disabled.")
                }
            }
            return searchYtMusicInnerTube(
                query = trimmed,
                limit = limit,
                canonicalFilter = canonicalFilter,
                providerIdLabel = requestedProvider,
            )
        }

        if (requestedProvider != null) {
            val targetExt = synchronized(lock) { extensions[requestedProvider] }
                ?: throw IllegalStateException("Search provider '$requestedProvider' is not installed.")
            if (!targetExt.enabled) {
                throw IllegalStateException("${targetExt.displayName} is currently disabled.")
            }
            if (!targetExt.hasMetadataProvider && !targetExt.hasCustomSearch) {
                throw IllegalStateException("${targetExt.displayName} does not support searching.")
            }
            return try {
                invokeExtensionSearch(targetExt, trimmed, limit, canonicalFilter).take(limit)
            } catch (err: Throwable) {
                targetExt.errorMessage = err.message
                throw IllegalStateException("${targetExt.displayName} search failed: ${err.message}", err)
            }
        }

        val active = synchronized(lock) {
            extensions.values.filter { it.enabled && (it.hasMetadataProvider || it.hasCustomSearch) }
        }

        if (active.isEmpty()) {
            return runCatching { searchYtMusicInnerTube(trimmed, limit, canonicalFilter) }
                .getOrDefault(emptyList())
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
        } else {
            // Run extensions in parallel when "all" is explicitly chosen.
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

        // Interleave results across enabled extensions when searching "all".
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
        val initialResults = list.mapNotNull { item ->
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
        }.toMutableList()

        // Many extensions (e.g. JioSaavn's autocomplete.get or Deezer's mixed search)
        // only return 3-10 songs in "all" mode. When searching an artist or song in "all"
        // mode, supplement with a dedicated tracks query so up to 50 songs are returned.
        val initialTrackCount = initialResults.count { it["item_type"] == "track" }
        if (canonicalFilter == "all" && initialTrackCount < 25) {
            val tracksFilterId = resolveExtensionFilterId(ext, "tracks")
            val targetLimit = max(limit, 50)
            val extraRaw = runCatching {
                executeInExtension(ext) { cx, scope, extObj ->
                    val customFn = ScriptableObject.getProperty(extObj, "customSearch") as? RhinoFunction
                    if (customFn != null && tracksFilterId.isNotEmpty()) {
                        val opts = cx.newObject(scope)
                        ScriptableObject.putProperty(opts, "limit", targetLimit)
                        ScriptableObject.putProperty(opts, "filter", tracksFilterId)
                        return@executeInExtension jsToKotlin(customFn.call(cx, scope, extObj, arrayOf<Any?>(query, opts)))
                    }
                    val searchFn = ScriptableObject.getProperty(extObj, "searchTracks") as? RhinoFunction
                        ?: ScriptableObject.getProperty(extObj, "search") as? RhinoFunction
                        ?: return@executeInExtension null
                    jsToKotlin(searchFn.call(cx, scope, extObj, arrayOf<Any?>(query, targetLimit)))
                }
            }.getOrNull()
            val extraList: List<*> = when (extraRaw) {
                is List<*> -> extraRaw
                is Map<*, *> -> (extraRaw["tracks"] as? List<*>)
                    ?: (extraRaw["items"] as? List<*>)
                    ?: (extraRaw["results"] as? List<*>)
                    ?: emptyList<Any?>()
                else -> emptyList<Any?>()
            }
            val seenTrackIds = initialResults
                .filter { it["item_type"] == "track" }
                .mapNotNull { it["id"]?.toString() }
                .toMutableSet()
            for (item in extraList) {
                val map = item as? Map<*, *> ?: continue
                val normalized = normalizeTrackMap(map, ext, "track")
                if (normalized["item_type"] != "track") continue
                val id = normalized["id"]?.toString() ?: continue
                if (seenTrackIds.add(id)) {
                    initialResults.add(normalized)
                }
            }
        }
        return initialResults
    }

    fun getAlbum(providerId: String, albumId: String): Map<String, Any?> {
        if (providerId == "ytmusic" || providerId == "ytmusic-spotiflac") {
            return getYtMusicAlbumInnerTube(albumId, providerIdLabel = providerId)
        }
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
        if (providerId == "ytmusic" || providerId == "ytmusic-spotiflac") {
            return getYtMusicArtistInnerTube(artistId, providerIdLabel = providerId)
        }
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
        }.toMutableList()
        val albums = albumsRaw.mapNotNull { item ->
            (item as? Map<*, *>)?.let { normalizeTrackMap(it, ext, "album") }
        }
        val artistName = ((raw["name"] ?: raw["title"])?.toString() ?: "").trim()
        if (artistName.isNotEmpty() && topTracks.size < 40) {
            runCatching {
                val moreSongs = invokeExtensionSearch(ext, artistName, 50, "tracks")
                val seenIds = topTracks.mapNotNull { it["id"]?.toString() }.toMutableSet()
                for (song in moreSongs) {
                    val id = song["id"]?.toString() ?: continue
                    if (seenIds.add(id)) {
                        topTracks.add(song)
                    }
                }
            }
        }
        return mapOf(
            "id" to (raw["id"]?.toString() ?: artistId),
            "name" to artistName,
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
            "album_id" to str("album_id", "albumId"),
            "artist_id" to str("artist_id", "artistId"),
            "duration_ms" to durationMs,
            "cover_url" to cover,
            "preview_url" to str("preview_url", "previewUrl"),
            "isrc" to str("isrc"),
            "release_date" to str("release_date", "releaseDate"),
            "track_number" to num("track_number", "trackNumber").toInt(),
            "total_tracks" to num("total_tracks", "totalTracks", "nb_tracks").toInt(),
            "disc_number" to num("disc_number", "discNumber").toInt(),
            "provider_id" to ext.id,
            "provider_name" to ext.displayName,
            "audio_quality" to str("audio_quality", "audioQuality"),
            "external_urls" to str("external_urls", "externalUrls", "url", "external_url"),
            "spotify_id" to str("spotify_id", "spotifyId").ifBlank { id },
            "tidal_id" to str("tidal_id", "tidalId"),
            "qobuz_id" to str("qobuz_id", "qobuzId"),
            "deezer_id" to str("deezer_id", "deezerId"),
        )
    }

    /**
     * Resolves an immediate playable audio URI (`http://127.0.0.1:...` chunked
     * InnerTube stream URL, direct stream URL, or already-downloaded local file)
     * for online playback of [rawTrack] just like LastWave-Native, without
     * requiring download extensions or downloading the track as a fallback.
     */
    fun resolveStream(
        rawTrack: Map<String, Any?>,
        musicDirPath: String?,
    ): Map<String, Any?> {
        val targetBaseDir = if (!musicDirPath.isNullOrBlank()) File(musicDirPath) else defaultMusicDir
        val outDir = File(targetBaseDir, "Extensions").apply { mkdirs() }
        val title = (rawTrack["title"] ?: rawTrack["name"] ?: "Track").toString().trim()
        val artist = (rawTrack["artist"] ?: rawTrack["artists"] ?: "").toString().trim()
        val baseFileName = sanitizeFilename(
            if (artist.isNotBlank()) "$artist - $title" else title
        ).ifBlank { "track_${System.currentTimeMillis()}" }

        // 1. If already downloaded locally, play the local file immediately.
        for (extName in listOf("flac", "m4a", "mp3", "ogg", "wav")) {
            val f = File(outDir, "$baseFileName.$extName")
            if (f.isFile && f.length() > 0) {
                return mapOf(
                    "uri" to f.absolutePath,
                    "isLocal" to true,
                    "proxyPort" to streamProxy.port,
                    "codec" to extName,
                )
            }
        }

        val originId = rawTrack["provider_id"]?.toString()?.trim() ?: ""
        val inputDurationMs = ((rawTrack["duration_ms"] ?: rawTrack["durationMs"]) as? Number)?.toLong() ?: 0L

        // 2. Resolve online stream (JioSaavn or YouTube Music InnerTube) and serve via LocalYtStreamProxy
        // so ExoPlayer always gets seekable 206 Partial Content Range responses and exact duration/format.
        val resolvedStream = runCatching {
            resolveStreamObjectForTrack(rawTrack, allowSaavnDirect = true)
        }.getOrNull()
        if (resolvedStream != null) {
            val tokenKey = extractDirectYouTubeVideoId(rawTrack)
                ?: (rawTrack["id"]?.toString()?.trim()?.takeIf { it.isNotEmpty() } ?: "online")
            val proxyUri = streamProxy.registerStream(tokenKey, resolvedStream, rawTrack)
            val effectiveDurationMs = if (resolvedStream.durationMs > 0L) resolvedStream.durationMs else inputDurationMs
            return mapOf(
                "uri" to proxyUri,
                "isLocal" to false,
                "providerId" to originId.ifBlank { "ytmusic" },
                "proxyPort" to streamProxy.port,
                "codec" to resolvedStream.codec,
                "bitrate" to resolvedStream.bitrate,
                "sampleRate" to resolvedStream.sampleRate,
                "durationMs" to effectiveDurationMs,
            )
        }

        throw IllegalStateException("Could not resolve online audio stream for \"$title\"")
    }

    private fun resolveJioSaavnDirectUrl(rawTrack: Map<String, Any?>): String? {
        val directPreview = (rawTrack["preview_url"] ?: rawTrack["previewUrl"])?.toString()?.trim()
        if (!directPreview.isNullOrEmpty() && (directPreview.startsWith("http://") || directPreview.startsWith("https://"))) {
            return directPreview.replace(Regex("_\\d+\\.mp4(?=[?#]|$)"), "_320.mp4")
        }
        val saavnExt = synchronized(lock) { extensions["jiosaavn"]?.takeIf { it.enabled } } ?: return null
        return runCatching {
            val settings = loadExtensionSettingsMap(saavnExt)
            val quality = resolveValidQualityForExtension(saavnExt, null, settings)
            executeInExtension(saavnExt) { cx, scope, extObj ->
                val getUrlFn = ScriptableObject.getProperty(extObj, "getDownloadUrl") as? RhinoFunction
                    ?: return@executeInExtension null
                val trackId = (rawTrack["id"] ?: "").toString().trim()
                if (trackId.isNotEmpty()) {
                    val jsOpts = kotlinMapToJsObject(
                        cx,
                        scope,
                        mapOf(
                            "quality" to quality,
                            "track" to rawTrack,
                            "preparedContext" to mapOf("track" to rawTrack, "host_track" to rawTrack),
                            "prepared_context" to mapOf("track" to rawTrack, "host_track" to rawTrack),
                        ),
                    )
                    val res = jsToKotlin(getUrlFn.call(cx, scope, extObj, arrayOf<Any?>(trackId, quality, jsOpts)))
                    val url = when (res) {
                        is String -> res.trim().takeIf { it.startsWith("http://") || it.startsWith("https://") }
                        is Map<*, *> -> (res["url"] ?: res["stream_url"] ?: res["streamUrl"])
                            ?.toString()?.trim()?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
                        else -> null
                    }
                    if (!url.isNullOrEmpty()) return@executeInExtension url
                }
                // Fallback when autocomplete.get omitted preview_url: searchSongsService returns full song with preview_url.
                val title = (rawTrack["title"] ?: rawTrack["name"] ?: "").toString().trim()
                val artist = (rawTrack["artist"] ?: rawTrack["artists"] ?: "").toString().trim()
                val searchFn = ScriptableObject.getProperty(extObj, "searchTracks") as? RhinoFunction
                if (searchFn != null && title.isNotEmpty()) {
                    val q = if (artist.isNotEmpty()) "$title $artist" else title
                    val list = jsToKotlin(searchFn.call(cx, scope, extObj, arrayOf<Any?>(q, 5))) as? List<*> ?: emptyList<Any?>()
                    val best = pickBestFallbackTrack(list, title, artist)
                    val bestPreview = (best?.get("preview_url") ?: best?.get("previewUrl"))?.toString()?.trim()
                    if (!bestPreview.isNullOrEmpty() && (bestPreview.startsWith("http://") || bestPreview.startsWith("https://"))) {
                        return@executeInExtension bestPreview.replace(Regex("_\\d+\\.mp4(?=[?#]|$)"), "_320.mp4")
                    }
                }
                null
            }
        }.getOrNull()
    }

    /**
     * Downloads [rawTrack] directly from YouTube Music InnerTube audio streams
     * using chunked 512 KB range requests, embedding metadata, cover art, and
     * `.lrc` lyrics. Used when `ytmusic` is selected or when `ytmusic-spotiflac`
     * JS extraction fails on a video.
     */
    private fun downloadYouTubeTrackNative(
        track: Map<String, Any?>,
        outDir: File,
        baseFileName: String,
        preferredQuality: String?,
        reportProgress: (Int) -> Unit,
    ): File {
        val stream = resolveStreamObjectForTrack(track, allowSaavnDirect = false)
            ?: throw IllegalStateException("Could not resolve YouTube Music audio stream")
        val ext = if (stream.mimeType.contains("webm", ignoreCase = true) || stream.codec == "opus") "ogg" else "m4a"
        val outFile = File(outDir, "$baseFileName.$ext")
        val windowSize = 512L * 1024L
        var written = 0L
        var totalLen = stream.contentLength
        FileOutputStream(outFile).use { fos ->
            while (totalLen < 0L || written < totalLen) {
                val start = written
                val end = if (totalLen > 0L) {
                    min(start + windowSize - 1L, totalLen - 1L)
                } else {
                    start + windowSize - 1L
                }
                val conn = (URL(stream.url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15_000
                    readTimeout = 30_000
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", stream.userAgent)
                    setRequestProperty("Range", "bytes=$start-$end")
                }
                val status = conn.responseCode
                if (status !in 200..299) {
                    conn.disconnect()
                    throw IllegalStateException("YouTube stream HTTP $status")
                }
                if (totalLen <= 0L) {
                    val contentRange = conn.getHeaderField("Content-Range") ?: ""
                    val slashIdx = contentRange.lastIndexOf('/')
                    if (slashIdx >= 0) {
                        totalLen = contentRange.substring(slashIdx + 1).trim().toLongOrNull() ?: -1L
                    }
                    if (totalLen <= 0L && status == 200) {
                        totalLen = conn.contentLengthLong
                    }
                }
                var chunkRead = 0L
                conn.inputStream.use { input ->
                    val buf = ByteArray(32 * 1024)
                    while (true) {
                        val r = input.read(buf)
                        if (r <= 0) break
                        fos.write(buf, 0, r)
                        written += r
                        chunkRead += r
                    }
                }
                conn.disconnect()
                if (totalLen > 0L) {
                    reportProgress(((written * 100L) / totalLen).toInt().coerceIn(0, 100))
                }
                if (status == 200 || chunkRead <= 0L || (totalLen < 0L && chunkRead < (end - start + 1L))) {
                    break
                }
            }
        }
        reportProgress(100)
        return outFile
    }

    /**
     * Downloads [rawTrack] through the user-selected [preferredProviderId] (or
     * originating extension / primary enabled download extension) with
     * [preferredQuality] without falling back across other providers, embeds
     * metadata + cover art + `.lrc` lyrics, and saves the audio file into
     * [musicDirPath].
     */
    fun downloadTrack(
        rawTrack: Map<String, Any?>,
        musicDirPath: String?,
        preferredProviderId: String? = null,
        preferredQuality: String? = null,
    ): Map<String, Any?> {
        ensureBundledLoaded()
        val track = enrichTrackIsrcIfNeeded(rawTrack)
        val targetBaseDir = if (!musicDirPath.isNullOrBlank()) File(musicDirPath) else defaultMusicDir
        val outDir = File(targetBaseDir, "Extensions").apply { mkdirs() }

        val originId = track["provider_id"]?.toString()?.trim() ?: ""
        val chosenId = preferredProviderId?.trim()?.takeIf { it.isNotEmpty() }
        val targetProviderId = chosenId ?: originId.takeIf { it.isNotEmpty() }
            ?: throw IllegalStateException("No download provider specified for track.")
        if (targetProviderId == "ytmusic-spotiflac") {
            val ytExt = synchronized(lock) { extensions["ytmusic-spotiflac"] }
            if (ytExt != null && !ytExt.enabled) {
                throw IllegalStateException("${ytExt.displayName} is currently disabled.")
            }
        }
        val isBuiltInYtDownload = targetProviderId == "ytmusic" || targetProviderId == "ytmusic-spotiflac"
        val ext = if (isBuiltInYtDownload) {
            null
        } else {
            synchronized(lock) {
                val candidate = extensions[targetProviderId]
                    ?: throw IllegalStateException("Download provider '$targetProviderId' is not installed.")
                if (!candidate.enabled) {
                    throw IllegalStateException("${candidate.displayName} is currently disabled.")
                }
                if (!candidate.hasDownloadProvider) {
                    throw IllegalStateException(
                        "${candidate.displayName} only supports search and metadata and cannot download audio directly."
                    )
                }
                candidate
            }
        }

        val providerDisplayName = ext?.displayName ?: "YouTube Music"
        val providerIdLabel = ext?.id ?: targetProviderId
        val title = (track["title"] ?: track["name"] ?: "Track").toString().trim()
        val artist = (track["artist"] ?: track["artists"] ?: "").toString().trim()
        val baseFileName = sanitizeFilename(
            if (artist.isNotBlank()) "$artist - $title" else title
        ).ifBlank { "track_${System.currentTimeMillis()}" }

        val notificationId = downloadNotificationSeq.incrementAndGet()
        ensureDownloadNotificationChannel()

        val subLabel = if (artist.isNotBlank()) "$artist · $providerDisplayName" else providerDisplayName
        postDownloadProgressNotification(
            notificationId = notificationId,
            title = "Downloading $title",
            subtitle = subLabel,
            percent = 0,
            indeterminate = true,
        )
        var lastNotifiedPercent = -1
        var lastNotifiedAtMs = 0L
        val reportProgress: (Int) -> Unit = { pct ->
            val clamped = pct.coerceIn(0, 100)
            val now = System.currentTimeMillis()
            if (clamped != lastNotifiedPercent && (clamped == 100 || clamped - lastNotifiedPercent >= 2 || now - lastNotifiedAtMs >= 250L)) {
                lastNotifiedPercent = clamped
                lastNotifiedAtMs = now
                postDownloadProgressNotification(
                    notificationId = notificationId,
                    title = "Downloading $title",
                    subtitle = "$subLabel · $clamped%",
                    percent = clamped,
                    indeterminate = false,
                )
            }
        }

        if (ext == null) {
            val ytFile = runCatching {
                downloadYouTubeTrackNative(track, outDir, baseFileName, preferredQuality, reportProgress)
            }.getOrElse { err ->
                val errMsg = "YouTube Music: ${err.message}"
                postDownloadFinishedNotification(
                    notificationId = notificationId,
                    title = "Download failed: $title",
                    subtitle = errMsg,
                    success = false,
                )
                throw IllegalStateException(errMsg, err)
            }
            val finalFile = finalizeDownloadedAudioExtension(ytFile, outDir, baseFileName)
            runCatching {
                persistTrackMetadataCoverAndLyrics(finalFile, outDir, baseFileName, track, emptyMap<String, Any?>())
            }
            postDownloadFinishedNotification(
                notificationId = notificationId,
                title = "Downloaded $title",
                subtitle = if (artist.isNotBlank()) "$artist · YouTube Music" else "Saved via YouTube Music",
                success = true,
            )
            return mapOf(
                "success" to true,
                "filePath" to finalFile.absolutePath,
                "providerId" to providerIdLabel,
                "providerName" to "YouTube Music",
            )
        }

        activeProgressCallback.set(reportProgress)
        activeDownloadTrack.set(track)
        val attempt = try {
            runCatching {
                val settings = loadExtensionSettingsMap(ext)
                val requestedQ = preferredQuality?.trim()?.takeIf { it.isNotEmpty() }
                val quality = resolveValidQualityForExtension(ext, requestedQ, settings)
                val defaultOutFile = File(outDir, "$baseFileName.flac")

                executeInExtension(ext) { cx, scope, extObj ->
                    val originalId = (track["id"] ?: "").toString().trim()
                    val isrc = (track["isrc"] ?: "").toString().trim()
                    val isSameProvider = (ext.id == originId || (originId == "ytmusic" && ext.id == "ytmusic-spotiflac")) && originalId.isNotEmpty()

                    var effectiveTrackMap: Map<String, Any?> = track.toMutableMap().apply {
                        if (this["spotify_id"]?.toString().isNullOrBlank() && originalId.isNotEmpty()) {
                            this["spotify_id"] = originalId
                        }
                        if (isSameProvider) {
                            this["provider_id"] = ext.id
                        }
                    }
                    var resolvedTrackId = originalId
                    val hasPreviewUrl = !effectiveTrackMap["preview_url"]?.toString().isNullOrBlank()
                    var preparedContext: Map<*, *>? = if (isSameProvider) {
                        if (ext.id == "jiosaavn" && hasPreviewUrl) {
                            mapOf("track" to effectiveTrackMap, "host_track" to effectiveTrackMap)
                        } else {
                            mapOf("host_track" to effectiveTrackMap)
                        }
                    } else {
                        null
                    }
                    var resolvedOnExt = isSameProvider

                    // If JioSaavn track came from autocomplete.get (no preview_url), hydrate via searchTracks so preview_url is present.
                    if (resolvedOnExt && ext.id == "jiosaavn" && !hasPreviewUrl && title.isNotEmpty()) {
                        val hydrated = runCatching {
                            val searchFn = ScriptableObject.getProperty(extObj, "searchTracks") as? RhinoFunction
                            if (searchFn != null) {
                                val q = if (artist.isNotBlank()) "$title $artist" else title
                                val list = jsToKotlin(searchFn.call(cx, scope, extObj, arrayOf<Any?>(q, 8))) as? List<*> ?: emptyList<Any?>()
                                list.filterIsInstance<Map<*, *>>().firstOrNull {
                                    it["id"]?.toString()?.trim() == resolvedTrackId && !it["preview_url"]?.toString().isNullOrBlank()
                                } ?: pickBestFallbackTrack(list, title, artist)
                            } else null
                        }.getOrNull()
                        if (hydrated != null && !hydrated["preview_url"]?.toString().isNullOrBlank()) {
                            val normHydrated = normalizeTrackMap(hydrated, ext, "track")
                            val hydId = normHydrated["id"]?.toString()?.trim().orEmpty()
                            if (hydId.isNotEmpty()) resolvedTrackId = hydId
                            effectiveTrackMap = normHydrated
                            preparedContext = mapOf("track" to hydrated, "host_track" to normHydrated)
                        }
                    }

                    val matchTitle = title
                        .replace(
                            Regex(
                                "\\s*[(\\[]\\s*(?:official\\s*(?:music\\s*)?(?:video|audio|lyric\\s*video|visualizer)|lyric(?:s|\\s*video)?|audio|hd|4k|hq|visualizer)\\s*[)\\]]",
                                RegexOption.IGNORE_CASE,
                            ),
                            "",
                        )
                        .trim()
                        .ifBlank { title }
                    val matchArtist = artist
                        .replace(Regex("\\s*-\\s*Topic$", RegexOption.IGNORE_CASE), "")
                        .trim()
                        .ifBlank { artist }

                    // Follow Mornye's backend/downloads.rs contract:
                    // Do NOT call checkAvailability when downloading directly from the track's own
                    // provider (direct = true). Only run checkAvailability when matching a track
                    // from Provider A onto a different download Provider B.
                    if (!resolvedOnExt) {
                        val checkFn = ScriptableObject.getProperty(extObj, "checkAvailability") as? RhinoFunction
                        if (checkFn != null) {
                            val checkOpts = kotlinMapToJsObject(
                                cx,
                                scope,
                                mapOf(
                                    "track" to effectiveTrackMap,
                                    "host_track" to effectiveTrackMap,
                                    "duration_ms" to (track["duration_ms"] ?: 0L),
                                    "deezer_id" to (track["deezer_id"] ?: ""),
                                    "tidal_id" to (track["tidal_id"] ?: ""),
                                    "qobuz_id" to (track["qobuz_id"] ?: ""),
                                    "spotify_id" to ((track["spotify_id"]?.toString()?.takeIf { it.isNotBlank() }) ?: originalId),
                                    "track_id" to originalId,
                                    "preferred_track_id" to originalId,
                                    "url" to (track["external_urls"] ?: ""),
                                ),
                            )
                            var availRaw = runCatching {
                                jsToKotlin(
                                    checkFn.call(cx, scope, extObj, arrayOf<Any?>(isrc, matchTitle, matchArtist, checkOpts))
                                ) as? Map<*, *>
                            }.getOrNull()

                            if ((availRaw == null || availRaw["available"] == false) && isrc.isNotEmpty()) {
                                availRaw = runCatching {
                                    jsToKotlin(
                                        checkFn.call(cx, scope, extObj, arrayOf<Any?>("", matchTitle, matchArtist, checkOpts))
                                    ) as? Map<*, *>
                                }.getOrNull()
                            }

                            val availId = (availRaw?.get("track_id")
                                ?: availRaw?.get("trackId")
                                ?: (availRaw?.get("track") as? Map<*, *>)?.get("id"))?.toString()?.trim()
                            val availPrep = (availRaw?.get("prepared_context") ?: availRaw?.get("preparedContext")) as? Map<*, *>
                            if (availRaw != null && availRaw["available"] != false && (!availId.isNullOrEmpty() || availPrep != null)) {
                                if (!availId.isNullOrEmpty()) {
                                    resolvedTrackId = availId
                                }
                                val availTrackMap = (availRaw["track"] as? Map<*, *>)?.let { normalizeTrackMap(it, ext, "track") }
                                if (availTrackMap != null) {
                                    effectiveTrackMap = availTrackMap
                                }
                                resolvedOnExt = true
                                preparedContext = availPrep ?: mapOf("host_track" to effectiveTrackMap)
                                activeDownloadTrack.set(effectiveTrackMap)
                            }
                        }
                    }

                    if (!resolvedOnExt) {
                        val searchQuery = if (matchArtist.isNotBlank()) "$matchTitle $matchArtist" else matchTitle
                        val extFilterId = resolveExtensionFilterId(ext, "tracks")
                        val searchRaw = runCatching {
                            val searchFn = ScriptableObject.getProperty(extObj, "searchTracks") as? RhinoFunction
                                ?: ScriptableObject.getProperty(extObj, "search") as? RhinoFunction
                            if (searchFn != null) {
                                jsToKotlin(searchFn.call(cx, scope, extObj, arrayOf<Any?>(searchQuery, 10)))
                            } else {
                                val customFn = ScriptableObject.getProperty(extObj, "customSearch") as? RhinoFunction
                                if (customFn != null) {
                                    val opts = cx.newObject(scope)
                                    ScriptableObject.putProperty(opts, "limit", 10)
                                    if (extFilterId.isNotEmpty()) {
                                        ScriptableObject.putProperty(opts, "filter", extFilterId)
                                    }
                                    jsToKotlin(customFn.call(cx, scope, extObj, arrayOf<Any?>(searchQuery, opts)))
                                } else {
                                    null
                                }
                            }
                        }.getOrNull()
                        val candidatesList: List<*> = when (searchRaw) {
                            is List<*> -> searchRaw
                            is Map<*, *> -> (searchRaw["tracks"] as? List<*>)
                                ?: (searchRaw["items"] as? List<*>)
                                ?: (searchRaw["results"] as? List<*>)
                                ?: emptyList<Any?>()
                            else -> emptyList<Any?>()
                        }
                        val matchedMap = pickBestFallbackTrack(candidatesList, matchTitle, matchArtist)
                            ?: pickBestFallbackTrack(candidatesList, title, artist)
                            ?: throw IllegalStateException("No matching track found on ${ext.displayName}")
                        val normalizedMatch = normalizeTrackMap(matchedMap, ext, "track")
                        val matchedId = normalizedMatch["id"]?.toString()?.trim() ?: ""
                        if (matchedId.isEmpty()) {
                            throw IllegalStateException("No valid track ID found on ${ext.displayName}")
                        }
                        resolvedTrackId = matchedId
                        effectiveTrackMap = normalizedMatch
                        activeDownloadTrack.set(effectiveTrackMap)
                        val matchedHasPreview = !matchedMap["preview_url"]?.toString().isNullOrBlank()
                        preparedContext = if (ext.id == "jiosaavn" && matchedHasPreview) {
                            mapOf("track" to matchedMap, "host_track" to normalizedMatch)
                        } else {
                            mapOf("host_track" to normalizedMatch)
                        }
                    }

                    val downloadFn = ScriptableObject.getProperty(extObj, "download") as? RhinoFunction
                        ?: throw IllegalStateException("${ext.displayName} has no download() function")
                    val progressFn = object : org.mozilla.javascript.BaseFunction() {
                        override fun call(
                            cx: RhinoContext?,
                            scope: Scriptable?,
                            thisObj: Scriptable?,
                            args: Array<out Any?>?,
                        ): Any {
                            if (!args.isNullOrEmpty()) {
                                val first = (args[0] as? Number)?.toDouble() ?: 0.0
                                val second = if (args.size >= 2) (args[1] as? Number)?.toDouble() else null
                                val pct = when {
                                    second != null && second > 0.0 -> ((first / second) * 100.0).toInt()
                                    first in 0.0..1.0 && first > 0.0 && first < 1.0 -> (first * 100.0).toInt()
                                    else -> first.toInt()
                                }
                                reportProgress(pct)
                            }
                            return Undefined.instance
                        }
                    }
                    val cleanProviderId = resolvedTrackId.substringAfterLast(':').trim()
                    val optionsMap = mutableMapOf<String, Any?>(
                        "outputDir" to outDir.absolutePath,
                        "output_dir" to outDir.absolutePath,
                        "quality" to quality,
                        "allowFallback" to false,
                        "allow_fallback" to false,
                        "qualityFallback" to false,
                        "quality_fallback" to false,
                        "filename" to defaultOutFile.name,
                        "track" to effectiveTrackMap,
                        "host_track" to effectiveTrackMap,
                        "isrc" to isrc,
                        "title" to title,
                        "artist" to artist,
                        "track_name" to title,
                        "artist_name" to artist,
                        "album_name" to (effectiveTrackMap["album_name"] ?: track["album_name"] ?: ""),
                        "duration_ms" to (effectiveTrackMap["duration_ms"] ?: track["duration_ms"] ?: 0L),
                        "track_id" to resolvedTrackId,
                        "preferred_track_id" to resolvedTrackId,
                        "spotify_id" to ((effectiveTrackMap["spotify_id"]?.toString()?.takeIf { it.isNotBlank() }) ?: resolvedTrackId),
                        "deezer_id" to ((effectiveTrackMap["deezer_id"]?.toString()?.takeIf { it.isNotBlank() }) ?: if (ext.id == "deezer") cleanProviderId else ""),
                        "tidal_id" to ((effectiveTrackMap["tidal_id"]?.toString()?.takeIf { it.isNotBlank() }) ?: if (ext.id.startsWith("tidal")) cleanProviderId else ""),
                        "qobuz_id" to ((effectiveTrackMap["qobuz_id"]?.toString()?.takeIf { it.isNotBlank() }) ?: if (ext.id.startsWith("qobuz")) cleanProviderId else ""),
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
        } finally {
            activeProgressCallback.remove()
            activeDownloadTrack.remove()
        }

        val jsMap = attempt.getOrNull() as? Map<*, *>
        val jsStringPath = attempt.getOrNull() as? String
        val jsOk = (jsStringPath != null && File(jsStringPath).isFile) || (
            jsMap != null && (
                (jsMap["success"] as? Boolean == true) ||
                    (jsMap["file_path"] != null && File(jsMap["file_path"].toString()).isFile) ||
                    (jsMap["filePath"] != null && File(jsMap["filePath"].toString()).isFile) ||
                    (jsMap["path"] != null && File(jsMap["path"].toString()).isFile)
            )
        )
        if (!jsOk) {
            val fallbackFile = runCatching {
                downloadFallbackForSelectedExtensionAndQuality(
                    ext = ext,
                    track = track,
                    outDir = outDir,
                    baseFileName = baseFileName,
                    preferredQuality = preferredQuality,
                    reportProgress = reportProgress,
                )
            }.getOrNull()
            if (fallbackFile != null && fallbackFile.isFile && fallbackFile.length() > 0) {
                val finalFile = finalizeDownloadedAudioExtension(fallbackFile, outDir, baseFileName)
                runCatching {
                    persistTrackMetadataCoverAndLyrics(finalFile, outDir, baseFileName, track, jsMap ?: emptyMap<String, Any?>())
                }
                postDownloadFinishedNotification(
                    notificationId = notificationId,
                    title = "Downloaded $title",
                    subtitle = if (artist.isNotBlank()) "$artist · ${ext.displayName}" else "Saved via ${ext.displayName}",
                    success = true,
                )
                return mapOf(
                    "success" to true,
                    "filePath" to finalFile.absolutePath,
                    "providerId" to ext.id,
                    "providerName" to ext.displayName,
                )
            }
        }

        val resultObj = attempt.getOrElse { err ->
            val errMsg = "${ext.displayName}: ${err.message}"
            postDownloadFinishedNotification(
                notificationId = notificationId,
                title = "Download failed: $title",
                subtitle = errMsg,
                success = false,
            )
            throw IllegalStateException(errMsg, err)
        }

        val resultMap = when (resultObj) {
            is Map<*, *> -> resultObj
            is String -> mapOf("success" to true, "file_path" to resultObj)
            else -> null
        } ?: run {
            val errMsg = "${ext.displayName}: Invalid download response"
            postDownloadFinishedNotification(
                notificationId = notificationId,
                title = "Download failed: $title",
                subtitle = errMsg,
                success = false,
            )
            throw IllegalStateException(errMsg)
        }

        val success = resultMap["success"] as? Boolean
            ?: (resultMap["file_path"] != null || resultMap["filePath"] != null || resultMap["path"] != null)
        if (!success) {
            val errMsg = "${ext.displayName}: ${resultMap["error_message"] ?: resultMap["errorMessage"] ?: resultMap["error"] ?: "Download failed"}"
            postDownloadFinishedNotification(
                notificationId = notificationId,
                title = "Download failed: $title",
                subtitle = errMsg,
                success = false,
            )
            throw IllegalStateException(errMsg)
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
            runCatching {
                persistTrackMetadataCoverAndLyrics(finalFile, outDir, baseFileName, track, resultMap)
            }
            postDownloadFinishedNotification(
                notificationId = notificationId,
                title = "Downloaded $title",
                subtitle = if (artist.isNotBlank()) "$artist · ${ext.displayName}" else "Saved via ${ext.displayName}",
                success = true,
            )
            return mapOf(
                "success" to true,
                "filePath" to finalFile.absolutePath,
                "providerId" to ext.id,
                "providerName" to ext.displayName,
            )
        }
        val errMsg = "${ext.displayName}: Downloaded file was empty or missing"
        postDownloadFinishedNotification(
            notificationId = notificationId,
            title = "Download failed: $title",
            subtitle = errMsg,
            success = false,
        )
        throw IllegalStateException(errMsg)
    }

    private fun ensureDownloadNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            runCatching {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
                val channel = NotificationChannel(
                    "noctune_downloads",
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shows progress for extension song and album downloads"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun postDownloadProgressNotification(
        notificationId: Int,
        title: String,
        subtitle: String,
        percent: Int,
        indeterminate: Boolean,
    ) {
        runCatching {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val notification = NotificationCompat.Builder(context, "noctune_downloads")
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setContentText(subtitle)
                .setProgress(100, percent.coerceIn(0, 100), indeterminate)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
            nm.notify(notificationId, notification)
        }
    }

    private fun postDownloadFinishedNotification(
        notificationId: Int,
        title: String,
        subtitle: String,
        success: Boolean,
    ) {
        runCatching {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val notification = NotificationCompat.Builder(context, "noctune_downloads")
                .setSmallIcon(
                    if (success) android.R.drawable.stat_sys_download_done
                    else android.R.drawable.stat_notify_error
                )
                .setContentTitle(title)
                .setContentText(subtitle)
                .setProgress(0, 0, false)
                .setOngoing(false)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
            nm.notify(notificationId, notification)
        }
    }

    private fun resolveValidQualityForExtension(
        ext: LoadedExtension,
        requestedQuality: String?,
        settings: Map<String, Any?>,
    ): String {
        val declaredIds = mutableListOf<String>()
        for (i in 0 until ext.qualityOptions.length()) {
            val id = ext.qualityOptions.optJSONObject(i)?.optString("id")?.trim()
            if (!id.isNullOrEmpty()) declaredIds.add(id)
        }
        if (declaredIds.isEmpty()) {
            return requestedQuality
                ?: settings["quality"]?.toString()?.takeIf { it.isNotBlank() }
                ?: "LOSSLESS"
        }
        if (!requestedQuality.isNullOrBlank()) {
            declaredIds.firstOrNull { it.equals(requestedQuality, ignoreCase = true) }?.let { return it }
        }
        val savedQ = settings["quality"]?.toString()?.trim()
        if (!savedQ.isNullOrEmpty()) {
            declaredIds.firstOrNull { it.equals(savedQ, ignoreCase = true) }?.let { return it }
        }
        return declaredIds.first()
    }

    private fun pickBestFallbackTrack(
        candidatesList: List<*>,
        targetTitle: String,
        targetArtist: String,
    ): Map<*, *>? {
        val normTitle = targetTitle.lowercase(Locale.ROOT).trim()
        val normArtist = targetArtist.lowercase(Locale.ROOT).trim()
        var bestMap: Map<*, *>? = null
        var bestScore = -1.0
        for (item in candidatesList) {
            val map = item as? Map<*, *> ?: continue
            val itemType = (map["item_type"] ?: map["itemType"] ?: map["type"])?.toString()?.lowercase(Locale.ROOT) ?: "track"
            if (itemType in setOf("album", "artist", "playlist", "show")) continue
            val candTitle = (map["name"] ?: map["title"] ?: "").toString().lowercase(Locale.ROOT).trim()
            if (candTitle.isEmpty()) continue
            val candArtist = (map["artists"] ?: map["artist"] ?: "").toString().lowercase(Locale.ROOT).trim()
            var score = 0.0
            if (candTitle == normTitle) score += 70.0
            else if (candTitle.contains(normTitle) || normTitle.contains(candTitle)) score += 50.0
            if (normArtist.isNotEmpty() && candArtist.isNotEmpty()) {
                if (candArtist.contains(normArtist) || normArtist.contains(candArtist)) score += 30.0
            }
            if (score > bestScore) {
                bestScore = score
                bestMap = map
            }
        }
        return bestMap
    }

    private fun persistTrackMetadataCoverAndLyrics(
        audioFile: File,
        outDir: File,
        baseName: String,
        track: Map<String, Any?>,
        resultMap: Map<*, *>,
    ) {
        fun pickStr(vararg keys: String): String {
            for (k in keys) {
                val v1 = resultMap[k]?.toString()?.trim()
                if (!v1.isNullOrEmpty() && v1 != "null") return v1
                val v2 = track[k]?.toString()?.trim()
                if (!v2.isNullOrEmpty() && v2 != "null") return v2
            }
            return ""
        }
        fun pickInt(vararg keys: String): Int {
            for (k in keys) {
                val v1 = resultMap[k]
                if (v1 is Number && v1.toInt() > 0) return v1.toInt()
                if (v1 is String) v1.trim().toIntOrNull()?.takeIf { it > 0 }?.let { return it }
                val v2 = track[k]
                if (v2 is Number && v2.toInt() > 0) return v2.toInt()
                if (v2 is String) v2.trim().toIntOrNull()?.takeIf { it > 0 }?.let { return it }
            }
            return 0
        }

        val finalTitle = pickStr("title", "name").ifBlank { baseName }
        val finalArtist = pickStr("artist", "artists")
        val finalAlbum = pickStr("album", "album_name")
        val finalAlbumArtist = pickStr("album_artist", "albumArtist").ifBlank { finalArtist }
        val finalGenre = pickStr("genre")
        val finalReleaseDate = pickStr("release_date", "releaseDate")
        val finalIsrc = pickStr("isrc")
        val finalCoverUrl = pickStr("cover_url", "coverUrl", "images", "artwork_url")
        val trackNumber = pickInt("track_number", "trackNumber")
        val totalTracks = pickInt("total_tracks", "totalTracks")
        val discNumber = pickInt("disc_number", "discNumber")
        val totalDiscs = pickInt("total_discs", "totalDiscs")
        val sampleRate = pickInt("sample_rate", "sampleRate")
        val bitDepth = pickInt("bit_depth", "bitDepth")
        val durationMs = ((resultMap["duration_ms"] ?: track["duration_ms"]) as? Number)?.toLong() ?: 0L

        // 1. Download cover art image and save <baseName>.cover.jpg
        var coverBytes: ByteArray? = null
        if (finalCoverUrl.startsWith("http://") || finalCoverUrl.startsWith("https://")) {
            runCatching {
                val resp = httpRequestBytes(finalCoverUrl, "GET", null, mapOf("User-Agent" to "NocTune/1.13.0"))
                if (resp.status in 200..299 && resp.body.isNotEmpty()) {
                    coverBytes = resp.body
                    File(outDir, "$baseName.cover.jpg").writeBytes(resp.body)
                }
            }
        }

        // 2. Fetch synced/plain lyrics (from lyrics extensions or LRCLib) and save <baseName>.lrc
        var lyricsText: String? = null
        runCatching {
            lyricsText = fetchLyrics(finalTitle, finalArtist, finalAlbum, durationMs)
            if (!lyricsText.isNullOrBlank()) {
                File(outDir, "$baseName.lrc").writeText(lyricsText!!, StandardCharsets.UTF_8)
            }
        }

        // 3. Save <baseName>.meta.json for NocTune's scanner across all containers (.flac, .m4a, .mp3, .ogg, .wav)
        val metaJson = JSONObject().apply {
            put("title", finalTitle)
            put("artist", finalArtist)
            put("album", finalAlbum)
            put("album_artist", finalAlbumArtist)
            put("genre", finalGenre)
            put("release_date", finalReleaseDate)
            put("isrc", finalIsrc)
            put("cover_url", finalCoverUrl)
            put("track_number", trackNumber)
            put("total_tracks", totalTracks)
            put("disc_number", discNumber)
            put("total_discs", totalDiscs)
            put("duration_ms", durationMs)
            if (sampleRate > 0) put("sample_rate", sampleRate)
            if (bitDepth > 0) put("bit_depth", bitDepth)
        }
        File(outDir, "$baseName.meta.json").writeText(metaJson.toString(), StandardCharsets.UTF_8)

        // 4. Embed Vorbis comments + PICTURE block directly into FLAC files
        if (audioFile.extension.equals("flac", ignoreCase = true)) {
            runCatching {
                embedFlacTagsAndCover(
                    flacFile = audioFile,
                    comments = buildList {
                        add("TITLE=$finalTitle")
                        if (finalArtist.isNotEmpty()) add("ARTIST=$finalArtist")
                        if (finalAlbum.isNotEmpty()) add("ALBUM=$finalAlbum")
                        if (finalAlbumArtist.isNotEmpty()) add("ALBUMARTIST=$finalAlbumArtist")
                        if (finalGenre.isNotEmpty()) add("GENRE=$finalGenre")
                        if (finalReleaseDate.isNotEmpty()) {
                            add("DATE=$finalReleaseDate")
                            if (finalReleaseDate.length >= 4) add("YEAR=${finalReleaseDate.substring(0, 4)}")
                        }
                        if (trackNumber > 0) add("TRACKNUMBER=$trackNumber")
                        if (totalTracks > 0) add("TRACKTOTAL=$totalTracks")
                        if (discNumber > 0) add("DISCNUMBER=$discNumber")
                        if (totalDiscs > 0) add("DISCTOTAL=$totalDiscs")
                        if (finalIsrc.isNotEmpty()) add("ISRC=$finalIsrc")
                        if (!lyricsText.isNullOrBlank()) add("LYRICS=$lyricsText")
                    },
                    coverBytes = coverBytes,
                )
            }
        }
    }

    /**
     * Embeds a `VORBIS_COMMENT` metadata block (type 4) and `PICTURE` metadata
     * block (type 6) directly into a `.flac` file right after its `STREAMINFO`
     * block so standard tag readers and `audio_metadata_reader` read all tags
     * and embedded cover art natively.
     */
    private fun embedFlacTagsAndCover(
        flacFile: File,
        comments: List<String>,
        coverBytes: ByteArray?,
    ) {
        val raw = flacFile.readBytes()
        if (raw.size < 42 || raw[0] != 'f'.code.toByte() || raw[1] != 'L'.code.toByte() ||
            raw[2] != 'a'.code.toByte() || raw[3] != 'C'.code.toByte()
        ) return

        // Parse existing metadata blocks, keeping STREAMINFO (type 0) and SEEKTABLE (type 3),
        // replacing VORBIS_COMMENT (type 4) and PICTURE (type 6).
        val keptBlocks = mutableListOf<Pair<Int, ByteArray>>()
        var pos = 4
        while (pos + 4 <= raw.size) {
            val headerByte = raw[pos].toInt() and 0xFF
            val isLast = (headerByte and 0x80) != 0
            val blockType = headerByte and 0x7F
            val len = ((raw[pos + 1].toInt() and 0xFF) shl 16) or
                ((raw[pos + 2].toInt() and 0xFF) shl 8) or
                (raw[pos + 3].toInt() and 0xFF)
            pos += 4
            if (pos + len > raw.size) return
            if (blockType != 4 && blockType != 6 && blockType != 1) {
                keptBlocks.add(blockType to raw.copyOfRange(pos, pos + len))
            }
            pos += len
            if (isLast) break
        }
        val audioDataStart = pos

        // Build VORBIS_COMMENT block (little-endian lengths)
        val vorbisOut = ByteArrayOutputStream()
        fun writeLe32(out: ByteArrayOutputStream, v: Int) {
            out.write(v and 0xFF)
            out.write((v ushr 8) and 0xFF)
            out.write((v ushr 16) and 0xFF)
            out.write((v ushr 24) and 0xFF)
        }
        val vendorBytes = "NocTune 1.13.0".toByteArray(StandardCharsets.UTF_8)
        writeLe32(vorbisOut, vendorBytes.size)
        vorbisOut.write(vendorBytes)
        writeLe32(vorbisOut, comments.size)
        for (c in comments) {
            val cb = c.toByteArray(StandardCharsets.UTF_8)
            writeLe32(vorbisOut, cb.size)
            vorbisOut.write(cb)
        }
        keptBlocks.add(4 to vorbisOut.toByteArray())

        // Build PICTURE block (big-endian lengths) if coverBytes fits in a 24-bit FLAC block (< 16 MB)
        if (coverBytes != null && coverBytes.isNotEmpty() && coverBytes.size < 8 * 1024 * 1024) {
            val picOut = ByteArrayOutputStream()
            fun writeBe32(out: ByteArrayOutputStream, v: Int) {
                out.write((v ushr 24) and 0xFF)
                out.write((v ushr 16) and 0xFF)
                out.write((v ushr 8) and 0xFF)
                out.write(v and 0xFF)
            }
            val isPng = coverBytes.size >= 4 && coverBytes[0] == 0x89.toByte() && coverBytes[1] == 'P'.code.toByte()
            val mimeBytes = (if (isPng) "image/png" else "image/jpeg").toByteArray(StandardCharsets.US_ASCII)
            writeBe32(picOut, 3) // Picture type 3: Cover (front)
            writeBe32(picOut, mimeBytes.size)
            picOut.write(mimeBytes)
            writeBe32(picOut, 0) // Empty description
            writeBe32(picOut, 0) // Width
            writeBe32(picOut, 0) // Height
            writeBe32(picOut, 24) // Color depth
            writeBe32(picOut, 0) // Indexed colors
            writeBe32(picOut, coverBytes.size)
            picOut.write(coverBytes)
            keptBlocks.add(6 to picOut.toByteArray())
        }

        val tmpFile = File(flacFile.parentFile, "${flacFile.name}.tagging")
        FileOutputStream(tmpFile).use { fos ->
            fos.write(byteArrayOf('f'.code.toByte(), 'L'.code.toByte(), 'a'.code.toByte(), 'C'.code.toByte()))
            for ((index, block) in keptBlocks.withIndex()) {
                val (bType, bData) = block
                val isLast = index == keptBlocks.lastIndex
                val firstByte = (if (isLast) 0x80 else 0x00) or (bType and 0x7F)
                val bLen = bData.size
                fos.write(
                    byteArrayOf(
                        firstByte.toByte(),
                        ((bLen ushr 16) and 0xFF).toByte(),
                        ((bLen ushr 8) and 0xFF).toByte(),
                        (bLen and 0xFF).toByte(),
                    )
                )
                fos.write(bData)
            }
            fos.write(raw, audioDataStart, raw.size - audioDataStart)
        }
        tmpFile.copyTo(flacFile, overwrite = true)
        tmpFile.delete()
    }

    /**
     * Ensures the saved file's extension matches its actual magic bytes (`.flac`,
     * `.mp3`, `.m4a`, `.ogg`, `.wav`) so NocTune's codec sniffer and scanner read
     * it accurately.
     */
    private fun finalizeDownloadedAudioExtension(file: File, outDir: File, baseName: String): File {
        val header = ByteArray(12)
        val read = FileInputStream(file).use { it.read(header) }
        val currentExt = file.extension.lowercase(Locale.ROOT)
        val ext = when {
            read >= 4 && header[0] == 'f'.code.toByte() && header[1] == 'L'.code.toByte() &&
                header[2] == 'a'.code.toByte() && header[3] == 'C'.code.toByte() -> "flac"
            read >= 4 && header[0] == 'R'.code.toByte() && header[1] == 'I'.code.toByte() &&
                header[2] == 'F'.code.toByte() && header[3] == 'F'.code.toByte() -> "wav"
            read >= 4 && header[0] == 'O'.code.toByte() && header[1] == 'g'.code.toByte() &&
                header[2] == 'g'.code.toByte() && header[3] == 'S'.code.toByte() -> "ogg"
            read >= 4 && header[0] == 0x1A.toByte() && header[1] == 0x45.toByte() &&
                header[2] == 0xDF.toByte() && header[3] == 0xA3.toByte() -> "ogg"
            read >= 8 && header[4] == 'f'.code.toByte() && header[5] == 't'.code.toByte() &&
                header[6] == 'y'.code.toByte() && header[7] == 'p'.code.toByte() -> "m4a"
            currentExt in setOf("flac", "m4a", "mp3", "ogg", "wav") -> currentExt
            else -> "mp3"
        }
        if (currentExt == ext && file.parentFile?.canonicalPath == outDir.canonicalPath) {
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
        // Fallback directly to LRCLib so synced lyrics work out-of-the-box just like Mornye.
        return fetchLrcLibDirect(title, artist)
    }

    private fun fetchLrcLibDirect(track: String, artist: String): String? {
        return runCatching {
            val qTrack = URLEncoder.encode(track.trim(), "UTF-8")
            val qArtist = URLEncoder.encode(artist.trim(), "UTF-8")
            val url = "https://lrclib.net/api/search?track_name=$qTrack&artist_name=$qArtist"
            val resp = httpRequestBytes(url, "GET", null, mapOf("User-Agent" to "NocTune/1.13.0"))
            if (resp.status !in 200..299) return null
            val arr = JSONArray(String(resp.body, StandardCharsets.UTF_8))
            if (arr.length() == 0) return null
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val synced = item.optString("syncedLyrics").trim()
                if (synced.isNotEmpty()) return synced
            }
            val first = arr.optJSONObject(0)
            first?.optString("plainLyrics")?.trim()?.takeIf { it.isNotEmpty() }
        }.getOrNull()
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
                        .put("url", resp.finalUrl)
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
                        .put("url", url)
                        .put("error", e.message ?: e.toString())
                        .put("body", "")
                        .toString()
                }
            }

            @Suppress("unused")
            fun fileDownload(
                url: String,
                outputPath: String,
                headersJson: String,
                chunked: Boolean,
                chunkSize: Int,
                jsProgressFn: Any?,
            ): String {
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
                    val progressCb = activeProgressCallback.get()
                    val fnProgress = jsProgressFn as? RhinoFunction
                    val userAgent = headers.entries.firstOrNull { it.key.equals("user-agent", ignoreCase = true) }?.value
                        ?: "Spotiflac-Extension/1.0"

                    fun notifyProgress(written: Long, total: Long) {
                        if (total > 0 && progressCb != null) {
                            progressCb(((written * 100L) / total).toInt().coerceIn(0, 100))
                        }
                        if (fnProgress != null) {
                            runCatching {
                                fnProgress.call(cx, scope, scope, arrayOf<Any?>(written.toDouble(), total.toDouble()))
                            }
                        }
                    }

                    val useChunked = chunked || url.contains("googlevideo.com", ignoreCase = true)
                    var written = 0L

                    if (useChunked) {
                        val windowSize = if (chunkSize > 0) {
                            chunkSize.toLong().coerceIn(128L * 1024L, 2L * 1024L * 1024L)
                        } else {
                            512L * 1024L
                        }
                        var totalLen = -1L
                        FileOutputStream(outFile).use { fos ->
                            while (totalLen < 0L || written < totalLen) {
                                val start = written
                                val end = if (totalLen > 0L) {
                                    min(start + windowSize - 1L, totalLen - 1L)
                                } else {
                                    start + windowSize - 1L
                                }
                                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                                    requestMethod = "GET"
                                    connectTimeout = 15_000
                                    readTimeout = 30_000
                                    instanceFollowRedirects = true
                                    setRequestProperty("User-Agent", userAgent)
                                    for ((k, v) in headers) {
                                        if (!k.equals("range", ignoreCase = true) && !k.equals("user-agent", ignoreCase = true)) {
                                            setRequestProperty(k, v)
                                        }
                                    }
                                    setRequestProperty("Range", "bytes=$start-$end")
                                }
                                val status = conn.responseCode
                                val statusText = conn.responseMessage ?: ""
                                if (status !in 200..299) {
                                    conn.disconnect()
                                    return JSONObject()
                                        .put("success", false)
                                        .put("error", "HTTP $status: $statusText")
                                        .toString()
                                }
                                if (totalLen < 0L) {
                                    val contentRange = conn.getHeaderField("Content-Range") ?: ""
                                    val slashIdx = contentRange.lastIndexOf('/')
                                    if (slashIdx >= 0) {
                                        totalLen = contentRange.substring(slashIdx + 1).trim().toLongOrNull() ?: -1L
                                    }
                                    if (totalLen < 0L && status == 200) {
                                        totalLen = conn.contentLengthLong
                                    }
                                }
                                var chunkRead = 0L
                                conn.inputStream.use { input ->
                                    val buf = ByteArray(32 * 1024)
                                    while (true) {
                                        val r = input.read(buf)
                                        if (r <= 0) break
                                        fos.write(buf, 0, r)
                                        written += r
                                        chunkRead += r
                                    }
                                }
                                conn.disconnect()
                                notifyProgress(written, if (totalLen > 0) totalLen else written)
                                if (status == 200 || chunkRead <= 0L || (totalLen < 0L && chunkRead < (end - start + 1L))) {
                                    break
                                }
                            }
                        }
                    } else {
                        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                            requestMethod = "GET"
                            connectTimeout = 15_000
                            readTimeout = 30_000
                            instanceFollowRedirects = true
                            setRequestProperty("User-Agent", userAgent)
                            for ((k, v) in headers) {
                                if (!k.equals("user-agent", ignoreCase = true)) {
                                    setRequestProperty(k, v)
                                }
                            }
                        }
                        val status = conn.responseCode
                        val statusText = conn.responseMessage ?: ""
                        if (status !in 200..299) {
                            conn.disconnect()
                            return JSONObject()
                                .put("success", false)
                                .put("error", "HTTP $status: $statusText")
                                .toString()
                        }
                        val totalLen = conn.contentLengthLong
                        val rawStream = conn.inputStream
                        val encoding = conn.contentEncoding?.lowercase(Locale.ROOT) ?: ""
                        val decodedStream = if (encoding.contains("gzip")) GZIPInputStream(rawStream) else rawStream
                        var lastProgressReportBytes = 0L
                        decodedStream.use { input ->
                            FileOutputStream(outFile).use { fos ->
                                val buf = ByteArray(32 * 1024)
                                while (true) {
                                    val r = input.read(buf)
                                    if (r <= 0) break
                                    fos.write(buf, 0, r)
                                    written += r
                                    if (written - lastProgressReportBytes >= 64 * 1024 || (totalLen > 0 && written >= totalLen)) {
                                        lastProgressReportBytes = written
                                        notifyProgress(written, totalLen)
                                    }
                                }
                            }
                        }
                        conn.disconnect()
                    }
                    progressCb?.invoke(100)
                    JSONObject()
                        .put("success", true)
                        .put("file_path", outFile.absolutePath)
                        .put("filePath", outFile.absolutePath)
                        .put("path", outFile.absolutePath)
                        .put("bytes_written", written)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject()
                        .put("success", false)
                        .put("error", e.message ?: e.toString())
                        .toString()
                }
            }

            @Suppress("unused")
            fun fileDownloadSegments(
                segmentsJson: String,
                outputPath: String,
                headersJson: String,
                jsProgressFn: Any?,
            ): String {
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
                    val totalSegs = arr.length().coerceAtLeast(1)
                    val progressCb = activeProgressCallback.get()
                    val fnProgress = jsProgressFn as? RhinoFunction
                    var totalBytesWritten = 0L
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
                            totalBytesWritten += resp.body.size
                            val completed = i + 1
                            progressCb?.invoke(((completed * 100) / totalSegs).coerceIn(0, 100))
                            if (fnProgress != null) {
                                runCatching {
                                    fnProgress.call(
                                        cx,
                                        scope,
                                        scope,
                                        arrayOf<Any?>(totalBytesWritten.toDouble(), 0.0, completed, totalSegs),
                                    )
                                }
                            }
                        }
                    }
                    JSONObject()
                        .put("success", true)
                        .put("file_path", outFile.absolutePath)
                        .put("filePath", outFile.absolutePath)
                        .put("path", outFile.absolutePath)
                        .put("bytes_written", totalBytesWritten)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject()
                        .put("success", false)
                        .put("error", e.message ?: e.toString())
                        .toString()
                }
            }

            @Suppress("unused")
            fun resolveUrl(input: String, base: String?): String {
                val raw = input.trim()
                if (base.isNullOrBlank()) return raw
                return runCatching {
                    URL(URL(base.trim()), raw).toString()
                }.getOrElse {
                    runCatching { URI(base.trim()).resolve(raw).toString() }.getOrDefault(raw)
                }
            }

            @Suppress("unused")
            fun getAudioQuality(path: String): String {
                return try {
                    val f = resolveExtensionFile(extDataDir, path)
                    if (!f.isFile || f.length() <= 0L) {
                        return JSONObject().put("success", false).put("error", "File not found").toString()
                    }
                    val size = f.length()
                    var sampleRate = 44100
                    var bitDepth = 16
                    var bitrate = 320000
                    var durationSec = 0.0
                    var totalSamples = 0L
                    var codec = f.extension.lowercase(Locale.ROOT)
                    val header = ByteArray(42)
                    val read = FileInputStream(f).use { it.read(header) }
                    if (read >= 26 && header[0] == 'f'.code.toByte() && header[1] == 'L'.code.toByte() &&
                        header[2] == 'a'.code.toByte() && header[3] == 'C'.code.toByte()
                    ) {
                        codec = "flac"
                        val b18 = header[18].toInt() and 0xFF
                        val b19 = header[19].toInt() and 0xFF
                        val b20 = header[20].toInt() and 0xFF
                        val b21 = header[21].toInt() and 0xFF
                        val sr = (b18 shl 12) or (b19 shl 4) or (b20 ushr 4)
                        val bps = (((b20 and 0x01) shl 4) or (b21 ushr 4)) + 1
                        if (sr in 8000..384000) sampleRate = sr
                        if (bps in 8..32) bitDepth = bps
                        totalSamples = ((b21.toLong() and 0x0FL) shl 32) or
                            (((header[22].toLong() and 0xFFL) shl 24)) or
                            (((header[23].toLong() and 0xFFL) shl 16)) or
                            (((header[24].toLong() and 0xFFL) shl 8)) or
                            (header[25].toLong() and 0xFFL)
                        if (totalSamples > 0 && sampleRate > 0) {
                            durationSec = totalSamples.toDouble() / sampleRate.toDouble()
                        }
                    } else {
                        runCatching {
                            val mmr = android.media.MediaMetadataRetriever()
                            try {
                                mmr.setDataSource(f.absolutePath)
                                val durMs = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                                if (durMs > 0L) durationSec = durMs.toDouble() / 1000.0
                                val br = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
                                if (br > 0) bitrate = br
                                val sr = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull() ?: 0
                                if (sr in 8000..384000) sampleRate = sr
                            } finally {
                                runCatching { mmr.release() }
                            }
                        }
                    }
                    JSONObject()
                        .put("success", true)
                        .put("duration", durationSec)
                        .put("totalSamples", totalSamples)
                        .put("total_samples", totalSamples)
                        .put("bitDepth", bitDepth)
                        .put("bit_depth", bitDepth)
                        .put("sampleRate", sampleRate)
                        .put("sample_rate", sampleRate)
                        .put("bitrate", bitrate)
                        .put("codec", codec)
                        .put("fileSize", size)
                        .put("file_size", size)
                        .toString()
                } catch (e: Throwable) {
                    JSONObject().put("success", false).put("error", e.message ?: e.toString()).toString()
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
                    val ua = "SpotiFLAC-Mobile/$appVer"

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

                    fun tryBootstrap(): Boolean {
                        val bootUrl = "$baseUrl/${bootstrapEp.trimStart('/')}?install_id=$installId&app_version=${URLEncoder.encode(appVer, "UTF-8")}"
                        val bootResp = runCatching {
                            httpRequestBytes(
                                bootUrl,
                                "GET",
                                null,
                                mapOf("User-Agent" to ua, "Accept" to "application/json"),
                            )
                        }.getOrNull() ?: return false
                        if (bootResp.status in 200..299) {
                            val bootJson = runCatching { JSONObject(String(bootResp.body, StandardCharsets.UTF_8)) }.getOrNull() ?: return false
                            val sId = bootJson.optString("session_id")
                            val sSec = bootJson.optString("session_secret")
                            if (sId.isNotBlank() && sSec.isNotBlank()) {
                                sessionId = sId
                                sessionSecret = sSec
                                sessionObj.put("session_id", sessionId)
                                sessionObj.put("session_secret", sessionSecret)
                                sessionObj.put("expires_at", bootJson.optString("expires_at"))
                                sessionFile.writeText(sessionObj.toString(), StandardCharsets.UTF_8)
                                return true
                            }
                        }
                        return false
                    }

                    if (sessionId.isBlank() || sessionSecret.isBlank()) {
                        tryBootstrap()
                    }

                    val targetUrl = if (path.startsWith("https://")) path else "$baseUrl/${path.trimStart('/')}"
                    val parsedUri = URI(targetUrl)
                    val escapedPath = parsedUri.rawPath.ifBlank { "/" }

                    fun tryMirrorFallbackForSignedPath(): String? {
                        if (escapedPath.endsWith("/tickets")) {
                            return JSONObject()
                                .put("ok", true)
                                .put("status", 200)
                                .put("statusCode", 200)
                                .put("body", JSONObject().put("ticket_id", "noctune-local-ticket").toString())
                                .put("headers", JSONObject().put("Content-Type", "application/json"))
                                .toString()
                        }
                        if (escapedPath.endsWith("/dl/tid")) {
                            return resolveTidalMirrorSignedFallback(body)
                        }
                        if (escapedPath.endsWith("/dl/qbz")) {
                            return resolveQobuzMirrorSignedFallback(body)
                        }
                        if (escapedPath.endsWith("/dl/dzr")) {
                            return resolveDeezerMirrorSignedFallback(body)
                        }
                        return null
                    }

                    if (sessionId.isBlank() || sessionSecret.isBlank()) {
                        tryMirrorFallbackForSignedPath()?.let { return it }
                        return JSONObject().put("ok", false).put("status", 428).put("statusCode", 428)
                            .put("needsVerification", true)
                            .put("code", "VERIFY_REQUIRED")
                            .put("error", "Signed session bootstrap required verification").toString()
                    }

                    fun executeSignedHttp(): HttpResponseBytes {
                        val bodyBytes = (body ?: "").toByteArray(StandardCharsets.UTF_8)
                        val bodyHash = MessageDigest.getInstance("SHA-256").digest(bodyBytes).joinToString("") { "%02x".format(it) }
                        val nowMillis = System.currentTimeMillis()
                        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                            timeZone = java.util.TimeZone.getTimeZone("UTC")
                        }
                        val timestamp = sdf.format(java.util.Date(nowMillis))
                        val nonceBytes = ByteArray(12)
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
                            "User-Agent" to ua,
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
                        return httpRequestBytes(
                            url = targetUrl,
                            method = method.uppercase(Locale.ROOT),
                            body = if (body.isNullOrEmpty()) null else bodyBytes,
                            headers = reqHeaders,
                        )
                    }

                    var resp = executeSignedHttp()
                    if (resp.status == 401 && tryBootstrap()) {
                        resp = executeSignedHttp()
                    }
                    if (resp.status !in 200..299) {
                        tryMirrorFallbackForSignedPath()?.let { return it }
                    }

                    val respText = String(resp.body, StandardCharsets.UTF_8)
                    val headersObj = JSONObject()
                    for ((k, v) in resp.headers) {
                        headersObj.put(k, v)
                    }
                    val out = JSONObject()
                        .put("ok", resp.status in 200..299)
                        .put("status", resp.status)
                        .put("statusCode", resp.status)
                        .put("body", respText)
                        .put("headers", headersObj)
                    runCatching {
                        val parsedBody = JSONObject(respText)
                        for (field in listOf("error", "code", "origin", "action", "retryMode", "retry_mode")) {
                            if (parsedBody.has(field)) out.put(field, parsedBody.opt(field))
                        }
                        if (parsedBody.has("retryable")) out.put("retryable", parsedBody.optBoolean("retryable"))
                        if (parsedBody.has("retry_after_seconds")) {
                            out.put("retryAfterSeconds", parsedBody.optLong("retry_after_seconds"))
                        }
                    }
                    out.toString()
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
                    if (base) {
                        href = String(host.resolveUrl(href, String(base)));
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
                        opts = opts || {};
                        var headers = opts.headers ? opts.headers : {};
                        var chunked = Boolean(opts.chunked);
                        var chunkSize = Number(opts.chunkSize || opts.chunk_size || 0) || 0;
                        var progressFn = (typeof opts.onProgress === "function")
                            ? opts.onProgress
                            : ((typeof opts.on_progress === "function") ? opts.on_progress : null);
                        return JSON.parse(String(host.fileDownload(
                            String(url),
                            String(path),
                            JSON.stringify(headers),
                            chunked,
                            chunkSize,
                            progressFn
                        )));
                    },
                    downloadSegments: function(segments, path, opts) {
                        opts = opts || {};
                        var headers = opts.headers ? opts.headers : {};
                        var progressFn = (typeof opts.onProgress === "function")
                            ? opts.onProgress
                            : ((typeof opts.on_progress === "function") ? opts.on_progress : null);
                        return JSON.parse(String(host.fileDownloadSegments(
                            JSON.stringify(segments || []),
                            String(path),
                            JSON.stringify(headers),
                            progressFn
                        )));
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
                        return JSON.parse(String(host.getAudioQuality(String(path || ""))));
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
                    appVersion: function() { return "1.16.0"; },
                    appUserAgent: function() { return "NocTune/1.16.0"; },
                    setDownloadStatus: function() {},
                    getResolutionRemainingMs: function() { return 60000; },
                    base64Encode: function(s) { return String(host.base64Encode(String(s || ""))); },
                    base64Decode: function(s) { return String(host.base64Decode(String(s || ""))); },
                    md5: function(s) { return String(host.hashHex("MD5", String(s || ""))); },
                    sha256: function(s) { return String(host.hashHex("SHA-256", String(s || ""))); },
                    hmacSHA1: function(msg, key) { return String(host.hmacHex("HmacSHA1", String(msg || ""), String(key || ""), false)); },
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
                        return {
                            unix: Math.floor(now.getTime() / 1000),
                            iso: now.toISOString(),
                            year: now.getFullYear(),
                            month: now.getMonth() + 1,
                            day: now.getDate(),
                            hour: now.getHours(),
                            minute: now.getMinutes(),
                            second: now.getSeconds(),
                            timezone: "UTC"
                        };
                    },
                    getAudioQuality: function(path) {
                        return JSON.parse(String(host.getAudioQuality(String(path || ""))));
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
        val finalUrl: String,
    )

    private fun httpRequestBytes(
        url: String,
        method: String,
        body: ByteArray?,
        headers: Map<String, String>,
    ): HttpResponseBytes {
        var currentUrl = url
        var currentMethod = method.uppercase(Locale.ROOT)
        var currentBody = body
        var redirects = 0

        while (true) {
            val userAgent = headers.entries.firstOrNull { it.key.equals("user-agent", ignoreCase = true) }?.value
                ?: "Spotiflac-Extension/1.0"
            val conn = (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = currentMethod
                connectTimeout = 15_000
                readTimeout = 30_000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", userAgent)
                for ((k, v) in headers) {
                    if (!k.equals("user-agent", ignoreCase = true)) {
                        setRequestProperty(k, v)
                    }
                }
                if (currentBody != null && currentBody.isNotEmpty() && currentMethod in setOf("POST", "PUT", "PATCH")) {
                    doOutput = true
                    outputStream.use { it.write(currentBody) }
                }
            }
            val status = conn.responseCode
            val statusText = conn.responseMessage ?: ""
            if (status in listOf(301, 302, 303, 307, 308) && redirects < 5) {
                val loc = conn.getHeaderField("Location")
                if (!loc.isNullOrBlank()) {
                    val resolvedLoc = runCatching { URL(URL(currentUrl), loc).toString() }.getOrDefault(loc)
                    conn.disconnect()
                    currentUrl = resolvedLoc
                    if (status == 303 || ((status == 301 || status == 302) && currentMethod == "POST")) {
                        currentMethod = "GET"
                        currentBody = null
                    }
                    redirects++
                    continue
                }
            }
            val respHeaders = linkedMapOf<String, String>()
            conn.headerFields?.forEach { (k, vals) ->
                if (k != null && !vals.isNullOrEmpty()) {
                    respHeaders[k.lowercase(Locale.ROOT)] = vals.joinToString(", ")
                }
            }
            // Do not call conn.inputStream when status >= 400 and errorStream is null:
            // HttpURLConnection.getInputStream() throws IOException on 4xx/5xx responses,
            // which previously masked 401/403 status codes needed for extension token refresh.
            val rawStream = if (status in 200..399) {
                runCatching { conn.inputStream }.getOrNull()
            } else {
                conn.errorStream
            }
            val encoding = conn.contentEncoding?.lowercase(Locale.ROOT) ?: ""
            val bytes = if (rawStream != null) {
                val decodedStream = if (encoding.contains("gzip")) GZIPInputStream(rawStream) else rawStream
                runCatching { decodedStream.use { it.readBytes() } }.getOrDefault(ByteArray(0))
            } else {
                ByteArray(0)
            }
            val finalUrlStr = conn.url?.toString() ?: currentUrl
            conn.disconnect()
            return HttpResponseBytes(status, statusText, respHeaders, bytes, finalUrlStr)
        }
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

    // =========================================================================
    // LastWave-Native Online Playback & YouTube Music InnerTube Engine
    // =========================================================================

    private data class InnerTubeClientSpec(
        val name: String,
        val version: String,
        val id: Int,
        val apiKey: String,
        val userAgent: String,
        val origin: String = "https://www.youtube.com",
        val referer: String = "https://www.youtube.com/",
        val androidSdkVersion: Int? = null,
        val osName: String? = null,
        val osVersion: String? = null,
        val deviceMake: String? = null,
        val deviceModel: String? = null,
    )

    private data class ResolvedYtStream(
        val url: String,
        val userAgent: String,
        val mimeType: String,
        val contentLength: Long,
        val bitrate: Int,
        val codec: String = "aac",
        val sampleRate: Int = 44100,
        val durationMs: Long = 0L,
    )

    private val ytConsentCookie = "CONSENT=YES+cb.20210328-17-p0.en+FX+100; SOCS=CAISEwgDEgk0ODE3Nzk3MjQaAmVuIAEaBgiA_LyaBg"

    private val ytMusicWebRemixClient = InnerTubeClientSpec(
        name = "WEB_REMIX",
        version = "1.20260707.12.00",
        id = 67,
        apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30",
        userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        origin = "https://music.youtube.com",
        referer = "https://music.youtube.com/",
    )

    // Direct stream InnerTube clients ordered for fast non-ciphered audio extraction,
    // matching LastWave-Native's InnerTubeMusicApiStreamResolver & PLAYER_CLIENTS.
    private val ytStreamClients = listOf(
        InnerTubeClientSpec(
            name = "ANDROID_VR",
            version = "1.60.19",
            id = 28,
            apiKey = "AIzaSyD-p045F_WzU-vA_YgX20SCx4KAo",
            userAgent = "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1) gzip",
            androidSdkVersion = 32,
            osName = "Android",
            osVersion = "12",
            deviceMake = "Oculus",
            deviceModel = "Quest 3",
        ),
        InnerTubeClientSpec(
            name = "VISIONOS",
            version = "0.1",
            id = 101,
            apiKey = "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc",
            userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            osName = "visionOS",
            osVersion = "1.3.21O771",
            deviceMake = "Apple",
            deviceModel = "RealityDevice14,1",
        ),
        InnerTubeClientSpec(
            name = "ANDROID_TESTSUITE",
            version = "1.9",
            id = 30,
            apiKey = "AIzaSyD-p045F_WzU-vA_YgX20SCx4KAo",
            userAgent = "com.google.android.youtube/1.9 (Linux; U; Android 12) gzip",
            androidSdkVersion = 32,
            osName = "Android",
            osVersion = "12",
        ),
        InnerTubeClientSpec(
            name = "TVHTML5",
            version = "7.20260308.08.00",
            id = 7,
            apiKey = "AIzaSyAO_FJ2SlqAz8GlBg1fA54p0wDE7Xk80mU",
            userAgent = "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36",
            referer = "https://www.youtube.com/tv",
        ),
        InnerTubeClientSpec(
            name = "ANDROID_MUSIC",
            version = "7.27.52",
            id = 21,
            apiKey = "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
            userAgent = "com.google.android.apps.youtube.music/7.27.52 (Linux; U; Android 14; en_US; Pixel 8; Build/UD1A.230803.041) gzip",
            androidSdkVersion = 34,
            osName = "Android",
            osVersion = "14",
            deviceMake = "Google",
            deviceModel = "Pixel 8",
        ),
        InnerTubeClientSpec(
            name = "IOS",
            version = "20.03.02",
            id = 5,
            apiKey = "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc",
            userAgent = "com.google.ios.youtube/20.03.02 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
            osName = "iPhone",
            osVersion = "18.2",
            deviceMake = "Apple",
            deviceModel = "iPhone16,2",
        ),
    )

    private val ytApiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    private fun getOrFetchVisitorData(): String? {
        val now = System.currentTimeMillis()
        val cached = cachedVisitorData
        if (!cached.isNullOrBlank() && now - cachedVisitorDataAtMs < 30 * 60 * 1000L) {
            return cached
        }
        return runCatching {
            val bodyJson = JSONObject().apply {
                put(
                    "context",
                    JSONObject().put(
                        "client",
                        JSONObject()
                            .put("clientName", ytMusicWebRemixClient.name)
                            .put("clientVersion", ytMusicWebRemixClient.version)
                            .put("hl", "en")
                            .put("gl", "US"),
                    ),
                )
            }
            val resp = runCatching {
                httpRequestBytes(
                    url = "https://music.youtube.com/youtubei/v1/visitor_id?key=$ytApiKey&prettyPrint=false",
                    method = "POST",
                    body = bodyJson.toString().toByteArray(StandardCharsets.UTF_8),
                    headers = mapOf(
                        "User-Agent" to ytMusicWebRemixClient.userAgent,
                        "Content-Type" to "application/json",
                        "Origin" to "https://music.youtube.com",
                        "X-Origin" to "https://music.youtube.com",
                        "Referer" to "https://music.youtube.com/",
                        "Cookie" to ytConsentCookie,
                    ),
                )
            }.getOrNull()
            val visitor = if (resp != null && resp.status in 200..299) {
                JSONObject(String(resp.body, StandardCharsets.UTF_8))
                    .optJSONObject("responseContext")
                    ?.optString("visitorData")
                    ?.takeIf { it.isNotBlank() }
            } else {
                null
            } ?: runCatching {
                val swResp = httpRequestBytes(
                    url = "https://music.youtube.com/sw.js_data",
                    method = "GET",
                    body = null,
                    headers = mapOf(
                        "User-Agent" to ytMusicWebRemixClient.userAgent,
                        "Cookie" to ytConsentCookie,
                    ),
                )
                val text = String(swResp.body, StandardCharsets.UTF_8)
                Regex("Cg[a-zA-Z0-9%_-]{20,}").find(text)?.value
            }.getOrNull() ?: runCatching {
                val homeResp = httpRequestBytes(
                    url = "https://music.youtube.com/",
                    method = "GET",
                    body = null,
                    headers = mapOf(
                        "User-Agent" to ytMusicWebRemixClient.userAgent,
                        "Cookie" to ytConsentCookie,
                    ),
                )
                val html = String(homeResp.body, StandardCharsets.UTF_8)
                Regex("\"VISITOR_DATA\"\\s*:\\s*\"([^\"]+)\"").find(html)?.groupValues?.getOrNull(1)
            }.getOrNull()
            if (!visitor.isNullOrBlank()) {
                cachedVisitorData = visitor
                cachedVisitorDataAtMs = now
            }
            visitor
        }.getOrNull()
    }

    /**
     * Resolves an online playable URI for [rawTrack] using LastWave-Native's
     * YouTube Music InnerTube track matching + `/youtubei/v1/player` audio
     * extraction + local chunked Range proxy (`LocalYtStreamProxy`).
     */
    private fun resolveLastWaveInnerTubeStream(rawTrack: Map<String, Any?>): String? {
        val stream = resolveStreamObjectForTrack(rawTrack, allowSaavnDirect = false) ?: return null
        val videoId = extractDirectYouTubeVideoId(rawTrack) ?: "yt"
        return streamProxy.registerStream(videoId, stream, rawTrack)
    }

    private fun resolveStreamObjectForTrack(
        rawTrack: Map<String, Any?>,
        allowSaavnDirect: Boolean = true,
    ): ResolvedYtStream? {
        val originId = (rawTrack["provider_id"] ?: "").toString().trim().lowercase(Locale.ROOT)
        val inputDurationMs = ((rawTrack["duration_ms"] ?: rawTrack["durationMs"]) as? Number)?.toLong() ?: 0L
        if (allowSaavnDirect && originId == "jiosaavn") {
            val directUrl = resolveJioSaavnDirectUrl(rawTrack)
            if (!directUrl.isNullOrEmpty()) {
                val len = probeStreamUrl(directUrl, "Mozilla/5.0") ?: -1L
                val estDurationMs = if (inputDurationMs > 0L) {
                    inputDurationMs
                } else if (len > 0L) {
                    (len * 8L * 1000L) / 320_000L
                } else {
                    0L
                }
                return ResolvedYtStream(
                    url = directUrl,
                    userAgent = "Mozilla/5.0",
                    mimeType = "audio/mp4",
                    contentLength = len,
                    bitrate = 320_000,
                    codec = "aac",
                    sampleRate = 44100,
                    durationMs = estDurationMs,
                )
            }
        }
        val title = (rawTrack["title"] ?: rawTrack["name"] ?: "").toString().trim()
        val artist = (rawTrack["artist"] ?: rawTrack["artists"] ?: "").toString().trim()
        val durationMs = ((rawTrack["duration_ms"] ?: rawTrack["durationMs"]) as? Number)?.toLong() ?: 0L

        var videoId = extractDirectYouTubeVideoId(rawTrack)
        if (videoId == null && title.isNotEmpty()) {
            videoId = findBestYouTubeMusicVideoId(title, artist, durationMs)
        }
        if (videoId.isNullOrBlank()) return null

        return resolveYouTubeAudioStreamForVideoId(videoId)
    }

    private fun extractDirectYouTubeVideoId(rawTrack: Map<String, Any?>): String? {
        val videoIdRegex = Regex("^[a-zA-Z0-9_-]{11}$")
        val providerId = (rawTrack["provider_id"] ?: "").toString().trim().lowercase(Locale.ROOT)
        val rawId = (rawTrack["id"] ?: "").toString().trim().substringAfterLast(':')
        if ((providerId == "ytmusic" || providerId == "ytmusic-spotiflac") && videoIdRegex.matches(rawId)) {
            return rawId
        }
        val extUrl = (rawTrack["external_urls"] ?: "").toString().trim()
        if (extUrl.contains("youtube.com") || extUrl.contains("youtu.be")) {
            Regex("[?&]v=([a-zA-Z0-9_-]{11})").find(extUrl)?.groupValues?.getOrNull(1)?.let { return it }
            Regex("youtu\\.be/([a-zA-Z0-9_-]{11})").find(extUrl)?.groupValues?.getOrNull(1)?.let { return it }
        }
        return null
    }

    private fun findBestYouTubeMusicVideoId(
        targetTitle: String,
        targetArtist: String,
        targetDurationMs: Long,
    ): String? {
        val query = if (targetArtist.isNotBlank()) "$targetTitle $targetArtist" else targetTitle
        // 1. Search with Songs filter params (EgWKAQIIAWoKEAkQBRAKEAMQBA==)
        val filteredSongs = searchYtMusicSongsOnly(query, params = "EgWKAQIIAWoKEAkQBRAKEAMQBA==", limit = 12)
        pickBestLastWaveMatch(filteredSongs, targetTitle, targetArtist, targetDurationMs)?.let { return it }

        // 2. Fallback to unfiltered search
        val unfilteredSongs = searchYtMusicSongsOnly(query, params = null, limit = 12)
        return pickBestLastWaveMatch(unfilteredSongs, targetTitle, targetArtist, targetDurationMs)
    }

    private fun pickBestLastWaveMatch(
        candidates: List<Map<String, Any?>>,
        targetTitle: String,
        targetArtist: String,
        targetDurationMs: Long,
    ): String? {
        if (candidates.isEmpty()) return null
        val reqTitleLower = targetTitle.lowercase(Locale.ROOT)
        val penaltyKeywords = listOf(
            "live",
            "karaoke",
            "instrumental",
            "sped up",
            "slowed",
            "nightcore",
            "8d audio",
            "reverb",
            "cover",
        )
        var bestVideoId: String? = null
        var bestScore = Double.NEGATIVE_INFINITY

        for ((index, cand) in candidates.withIndex()) {
            val vid = cand["id"]?.toString()?.trim() ?: continue
            if (vid.length != 11) continue
            val candTitle = (cand["title"] ?: cand["name"] ?: "").toString().trim()
            val candArtist = (cand["artist"] ?: cand["artists"] ?: "").toString().trim()
            val candDurationMs = (cand["duration_ms"] as? Number)?.toLong() ?: 0L

            val titleSim = stringSimilarity(targetTitle, candTitle)
            val artistSim = if (targetArtist.isNotBlank() && candArtist.isNotBlank()) {
                stringSimilarity(targetArtist, candArtist)
            } else {
                0.5
            }
            var score = titleSim * 65.0 + artistSim * 35.0 - (index * 1.2)

            val candLower = "$candTitle $candArtist".lowercase(Locale.ROOT)
            for (kw in penaltyKeywords) {
                if (candLower.contains(kw) && !reqTitleLower.contains(kw)) {
                    score -= 28.0
                }
            }
            if (targetDurationMs > 0L && candDurationMs > 0L) {
                val diffSec = abs(targetDurationMs - candDurationMs) / 1000.0
                when {
                    diffSec <= 3.0 -> score += 15.0
                    diffSec <= 8.0 -> score += 8.0
                    diffSec > 25.0 -> score -= 25.0
                }
            }
            if (score > bestScore) {
                bestScore = score
                bestVideoId = vid
            }
        }
        return bestVideoId
    }

    private fun stringSimilarity(a: String, b: String): Double {
        val na = Normalizer.normalize(a.lowercase(Locale.ROOT), Normalizer.Form.NFD)
            .replace(Regex("\\p{M}"), "")
            .replace(Regex("\\(feat\\..*?\\)|\\[feat\\..*?\\]"), "")
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        val nb = Normalizer.normalize(b.lowercase(Locale.ROOT), Normalizer.Form.NFD)
            .replace(Regex("\\p{M}"), "")
            .replace(Regex("\\(feat\\..*?\\)|\\[feat\\..*?\\]"), "")
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (na == nb) return 1.0
        if (na.isEmpty() || nb.isEmpty()) return 0.0
        if (na.contains(nb) || nb.contains(na)) return 0.88
        val maxLen = max(na.length, nb.length)
        val dist = levenshtein(na, nb)
        return max(0.0, 1.0 - dist.toDouble() / maxLen.toDouble())
    }

    private fun resolveYouTubeAudioStreamForVideoId(videoId: String): ResolvedYtStream? {
        val visitorData = getOrFetchVisitorData()
        for (client in ytStreamClients) {
            val resolved = runCatching {
                requestPlayerStreamWithClient(videoId, client, visitorData)
            }.getOrNull()
            if (resolved != null) return resolved
        }
        return null
    }

    private fun requestPlayerStreamWithClient(
        videoId: String,
        client: InnerTubeClientSpec,
        visitorData: String?,
    ): ResolvedYtStream? {
        val clientObj = JSONObject()
            .put("clientName", client.name)
            .put("clientVersion", client.version)
            .put("hl", "en")
            .put("gl", "US")
            .put("userAgent", client.userAgent)
        if (client.androidSdkVersion != null) clientObj.put("androidSdkVersion", client.androidSdkVersion)
        if (client.osName != null) clientObj.put("osName", client.osName)
        if (client.osVersion != null) clientObj.put("osVersion", client.osVersion)
        if (client.deviceMake != null) clientObj.put("deviceMake", client.deviceMake)
        if (client.deviceModel != null) clientObj.put("deviceModel", client.deviceModel)
        if (!visitorData.isNullOrBlank()) clientObj.put("visitorData", visitorData)

        val payload = JSONObject()
            .put("context", JSONObject().put("client", clientObj))
            .put("videoId", videoId)
            .put("contentCheckOk", true)
            .put("racyCheckOk", true)

        val headers = mutableMapOf(
            "User-Agent" to client.userAgent,
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "Origin" to client.origin,
            "X-Origin" to client.origin,
            "Referer" to client.referer,
            "X-Goog-Api-Format-Version" to "1",
            "X-YouTube-Client-Name" to client.id.toString(),
            "X-YouTube-Client-Version" to client.version,
            "Cookie" to ytConsentCookie,
        )
        if (!visitorData.isNullOrBlank()) {
            headers["X-Goog-Visitor-Id"] = visitorData
        }

        val resp = httpRequestBytes(
            url = "https://www.youtube.com/youtubei/v1/player?key=${client.apiKey}&prettyPrint=false",
            method = "POST",
            body = payload.toString().toByteArray(StandardCharsets.UTF_8),
            headers = headers,
        )
        if (resp.status !in 200..299) return null
        val root = JSONObject(String(resp.body, StandardCharsets.UTF_8))
        val respVisitor = root.optJSONObject("responseContext")?.optString("visitorData")?.trim()
        if (!respVisitor.isNullOrEmpty() && cachedVisitorData.isNullOrBlank()) {
            cachedVisitorData = respVisitor
            cachedVisitorDataAtMs = System.currentTimeMillis()
        }
        val playability = root.optJSONObject("playabilityStatus")?.optString("status") ?: ""
        if (playability.isNotEmpty() && playability != "OK") return null

        val streamingData = root.optJSONObject("streamingData") ?: return null
        val videoDurationMs = (root.optJSONObject("videoDetails")?.optString("lengthSeconds")?.toLongOrNull() ?: 0L) * 1000L
        val candidates = mutableListOf<ResolvedYtStream>()

        fun collectFormats(arr: JSONArray?) {
            if (arr == null) return
            for (i in 0 until arr.length()) {
                val fmt = arr.optJSONObject(i) ?: continue
                val url = fmt.optString("url").trim()
                if (!url.startsWith("https://") && !url.startsWith("http://")) continue
                val mimeRaw = fmt.optString("mimeType").trim()
                if (!mimeRaw.startsWith("audio/", ignoreCase = true)) continue
                val cleanMime = mimeRaw.substringBefore(';').trim().ifBlank { "audio/mp4" }
                val bitrate = fmt.optInt("averageBitrate", fmt.optInt("bitrate", 128000))
                val contentLen = fmt.optString("contentLength").toLongOrNull() ?: fmt.optLong("contentLength", -1L)
                val sampleRate = fmt.optString("audioSampleRate").toIntOrNull()
                    ?: fmt.optInt("audioSampleRate", 44100).takeIf { it > 0 }
                    ?: 44100
                val fmtDurationMs = fmt.optString("approxDurationMs").toLongOrNull()
                    ?: fmt.optLong("approxDurationMs", 0L).takeIf { it > 0L }
                    ?: videoDurationMs
                val codec = when {
                    mimeRaw.contains("opus", ignoreCase = true) || cleanMime.contains("webm", ignoreCase = true) -> "opus"
                    mimeRaw.contains("flac", ignoreCase = true) -> "flac"
                    mimeRaw.contains("mpeg", ignoreCase = true) || mimeRaw.contains("mp3", ignoreCase = true) -> "mp3"
                    else -> "aac"
                }
                candidates.add(
                    ResolvedYtStream(
                        url = url,
                        userAgent = client.userAgent,
                        mimeType = cleanMime,
                        contentLength = contentLen,
                        bitrate = bitrate,
                        codec = codec,
                        sampleRate = sampleRate,
                        durationMs = fmtDurationMs,
                    )
                )
            }
        }

        collectFormats(streamingData.optJSONArray("adaptiveFormats"))
        collectFormats(streamingData.optJSONArray("formats"))
        if (candidates.isEmpty()) return null

        // Sort preferring audio/mp4 (M4A AAC) first for universal ExoPlayer seeking, then highest bitrate.
        val sorted = candidates.sortedWith(
            compareByDescending<ResolvedYtStream> { it.mimeType.contains("mp4", ignoreCase = true) }
                .thenByDescending { it.bitrate }
        )

        for (candidate in sorted.take(3)) {
            val probedLen = probeStreamUrl(candidate.url, candidate.userAgent, candidate.contentLength)
            if (probedLen != null) {
                return if (candidate.contentLength > 2L) {
                    candidate
                } else {
                    candidate.copy(contentLength = probedLen)
                }
            }
        }
        return null
    }

    private fun probeStreamUrl(url: String, userAgent: String, expectedContentLength: Long = -1L): Long? {
        return runCatching {
            // Probe past the 1 MiB auth boundary when the file is >1 MiB (matching LastWave-Native's
            // YouTubeStreamExtractor.playbackProbeRequest) so unattested URLs that 403 at ~60s are rejected.
            val probeStart = if (expectedContentLength > 1_064_960L) 1_048_576L else 0L
            val probeEnd = probeStart + 1L
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5_000
                readTimeout = 5_000
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", userAgent)
                setRequestProperty("Range", "bytes=$probeStart-$probeEnd")
            }
            val code = conn.responseCode
            if (code != 200 && code != 206) {
                conn.disconnect()
                return@runCatching null
            }
            val contentRange = conn.getHeaderField("Content-Range")
                ?: conn.getHeaderField("content-range")
                ?: ""
            val totalFromRange = contentRange.substringAfterLast('/', "").trim().toLongOrNull()?.takeIf { it > 2L }
            val totalLen = if (code == 206) {
                totalFromRange ?: -1L
            } else {
                totalFromRange ?: conn.contentLengthLong.takeIf { it > 2L } ?: -1L
            }
            runCatching { conn.inputStream.close() }
            conn.disconnect()
            totalLen
        }.getOrNull()
    }

    private fun searchYtMusicInnerTube(
        query: String,
        limit: Int,
        canonicalFilter: String,
        providerIdLabel: String = "ytmusic",
    ): List<Map<String, Any?>> {
        return when (canonicalFilter) {
            "tracks" -> searchYtMusicSongsOnly(
                query = query,
                params = "EgWKAQIIAWoKEAkQBRAKEAMQBA==",
                limit = limit,
                providerIdLabel = providerIdLabel,
            )
            "albums" -> searchYtMusicFiltered(
                query = query,
                params = "EgWKAQIYAWoKEAkQBRAKEAMQBA==",
                itemType = "album",
                limit = limit,
                providerIdLabel = providerIdLabel,
            )
            "artists" -> searchYtMusicFiltered(
                query = query,
                params = "EgWKAQIgAWoKEAkQBRAKEAMQBA==",
                itemType = "artist",
                limit = limit,
                providerIdLabel = providerIdLabel,
            )
            else -> {
                val songsTask = searchPool.submit<List<Map<String, Any?>>> {
                    runCatching {
                        searchYtMusicSongsOnly(
                            query = query,
                            params = "EgWKAQIIAWoKEAkQBRAKEAMQBA==",
                            limit = max(limit, 30),
                            providerIdLabel = providerIdLabel,
                        )
                    }.getOrDefault(emptyList())
                }
                val albumsTask = searchPool.submit<List<Map<String, Any?>>> {
                    runCatching {
                        searchYtMusicFiltered(
                            query = query,
                            params = "EgWKAQIYAWoKEAkQBRAKEAMQBA==",
                            itemType = "album",
                            limit = 8,
                            providerIdLabel = providerIdLabel,
                        )
                    }.getOrDefault(emptyList())
                }
                val artistsTask = searchPool.submit<List<Map<String, Any?>>> {
                    runCatching {
                        searchYtMusicFiltered(
                            query = query,
                            params = "EgWKAQIgAWoKEAkQBRAKEAMQBA==",
                            itemType = "artist",
                            limit = 6,
                            providerIdLabel = providerIdLabel,
                        )
                    }.getOrDefault(emptyList())
                }
                val out = mutableListOf<Map<String, Any?>>()
                out.addAll(runCatching { artistsTask.get(5000L, java.util.concurrent.TimeUnit.MILLISECONDS) }.getOrDefault(emptyList()))
                out.addAll(runCatching { albumsTask.get(5000L, java.util.concurrent.TimeUnit.MILLISECONDS) }.getOrDefault(emptyList()))
                out.addAll(runCatching { songsTask.get(5000L, java.util.concurrent.TimeUnit.MILLISECONDS) }.getOrDefault(emptyList()))
                out
            }
        }
    }

    private fun postYtMusicWebRemix(endpoint: String, bodyFiller: JSONObject.() -> Unit): JSONObject? {
        val visitorData = cachedVisitorData
        val clientObj = JSONObject()
            .put("clientName", ytMusicWebRemixClient.name)
            .put("clientVersion", ytMusicWebRemixClient.version)
            .put("hl", "en")
            .put("gl", "US")
        if (!visitorData.isNullOrBlank()) {
            clientObj.put("visitorData", visitorData)
        }
        val payload = JSONObject().apply {
            put("context", JSONObject().put("client", clientObj))
            bodyFiller()
        }
        val headers = mutableMapOf(
            "User-Agent" to ytMusicWebRemixClient.userAgent,
            "Content-Type" to "application/json",
            "Origin" to "https://music.youtube.com",
            "X-Origin" to "https://music.youtube.com",
            "Referer" to "https://music.youtube.com/",
            "X-Goog-Api-Format-Version" to "1",
            "X-YouTube-Client-Name" to ytMusicWebRemixClient.id.toString(),
            "X-YouTube-Client-Version" to ytMusicWebRemixClient.version,
            "Cookie" to ytConsentCookie,
        )
        if (!visitorData.isNullOrBlank()) {
            headers["X-Goog-Visitor-Id"] = visitorData
        }
        val resp = httpRequestBytes(
            url = "https://music.youtube.com/youtubei/v1/$endpoint?key=$ytApiKey&prettyPrint=false",
            method = "POST",
            body = payload.toString().toByteArray(StandardCharsets.UTF_8),
            headers = headers,
        )
        if (resp.status !in 200..299) return null
        return runCatching {
            JSONObject(String(resp.body, StandardCharsets.UTF_8)).also { parsed ->
                val respVisitor = parsed.optJSONObject("responseContext")?.optString("visitorData")?.trim()
                if (!respVisitor.isNullOrEmpty() && cachedVisitorData.isNullOrBlank()) {
                    cachedVisitorData = respVisitor
                    cachedVisitorDataAtMs = System.currentTimeMillis()
                }
            }
        }.getOrNull()
    }

    private fun extractDirectWatchVideoId(renderer: JSONObject): String? {
        val vidRegex = Regex("^[a-zA-Z0-9_-]{11}$")
        fun validId(s: String?): String? = s?.trim()?.takeIf { vidRegex.matches(it) }

        validId(renderer.optJSONObject("playlistItemData")?.optString("videoId"))?.let { return it }
        validId(renderer.optJSONObject("navigationEndpoint")?.optJSONObject("watchEndpoint")?.optString("videoId"))?.let { return it }
        val overlay = renderer.optJSONObject("overlay") ?: renderer.optJSONObject("thumbnailOverlay")
        validId(
            overlay?.optJSONObject("musicItemThumbnailOverlayRenderer")
                ?.optJSONObject("content")
                ?.optJSONObject("musicPlayButtonRenderer")
                ?.optJSONObject("playNavigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
        )?.let { return it }
        validId(renderer.optJSONObject("onTap")?.optJSONObject("watchEndpoint")?.optString("videoId"))?.let { return it }
        validId(
            renderer.optJSONArray("flexColumns")
                ?.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optJSONObject("navigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
        )?.let { return it }
        validId(renderer.optJSONObject("doubleTapCommand")?.optJSONObject("watchEndpoint")?.optString("videoId"))?.let { return it }
        return validId(findStringByKey(renderer, "videoId"))
    }

    private fun isLikelyYtArtistDetail(text: String): Boolean {
        val t = text.trim()
        if (t.isEmpty() || t in setOf("•", "·", "&", ",", "|")) return false
        val lower = t.lowercase(Locale.ROOT)
        if (lower in setOf("song", "video", "album", "single", "ep", "playlist", "artist", "podcast", "episode", "explicit")) {
            return false
        }
        if (t.matches(Regex("^(\\d+:)?\\d{1,2}:\\d{2}$"))) return false
        if (lower.endsWith(" views") || lower.endsWith(" plays") || lower.endsWith(" subscribers") || lower.endsWith(" likes")) {
            return false
        }
        return true
    }

    private fun parseYtMusicSongsFromRoot(
        root: JSONObject,
        limit: Int,
        providerIdLabel: String,
    ): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seenIds = mutableSetOf<String>()

        fun addSong(
            videoId: String,
            title: String,
            artistStr: String,
            album: String,
            durationMs: Long,
            coverUrl: String,
        ) {
            if (videoId.length != 11 || title.isBlank() || !seenIds.add(videoId)) return
            results.add(
                mapOf(
                    "id" to videoId,
                    "spotify_id" to videoId,
                    "item_type" to "track",
                    "name" to title,
                    "title" to title,
                    "artists" to artistStr,
                    "artist" to artistStr,
                    "album_name" to album,
                    "album" to album,
                    "album_artist" to artistStr,
                    "duration_ms" to durationMs,
                    "cover_url" to coverUrl,
                    "isrc" to "",
                    "provider_id" to providerIdLabel,
                    "provider_name" to "YouTube Music",
                    "external_urls" to "https://music.youtube.com/watch?v=$videoId",
                )
            )
        }

        // 1. Parse top-result musicCardShelfRenderer (LastWave-Native InnerTubeMusicApiParsers.parseCardShelfSong)
        val cardRenderers = mutableListOf<JSONObject>()
        collectObjectsByKey(root, "musicCardShelfRenderer", cardRenderers)
        for (card in cardRenderers) {
            val videoId = extractDirectWatchVideoId(card) ?: continue
            val titleRuns = card.optJSONObject("title")?.optJSONArray("runs")
            val title = buildString {
                if (titleRuns != null) {
                    for (i in 0 until titleRuns.length()) {
                        append(titleRuns.optJSONObject(i)?.optString("text").orEmpty())
                    }
                }
            }.trim().ifBlank { card.optJSONObject("title")?.optString("simpleText")?.trim().orEmpty() }
            if (title.isEmpty()) continue
            val subRuns = card.optJSONObject("subtitle")?.optJSONArray("runs")
            val artists = mutableListOf<String>()
            var album = ""
            var durationMs = 0L
            if (subRuns != null) {
                for (i in 0 until subRuns.length()) {
                    val run = subRuns.optJSONObject(i) ?: continue
                    val text = run.optString("text").trim()
                    if (text.isEmpty() || text == "•" || text == "·" || text == "&" || text == ",") continue
                    if (text.matches(Regex("^(\\d+:)?\\d{1,2}:\\d{2}$"))) {
                        durationMs = parseColonDurationMs(text)
                        continue
                    }
                    val browseId = findStringByKey(run, "browseId") ?: ""
                    val pageType = findStringByKey(run, "pageType") ?: ""
                    when {
                        browseId.startsWith("MPRE") || pageType.contains("ALBUM") -> album = text
                        browseId.startsWith("UC") || pageType.contains("ARTIST") -> artists.add(text)
                        artists.isEmpty() && isLikelyYtArtistDetail(text) -> artists.add(text)
                    }
                }
            }
            addSong(
                videoId = videoId,
                title = title,
                artistStr = artists.joinToString(", ").ifBlank { "YouTube Music" },
                album = album,
                durationMs = durationMs,
                coverUrl = extractBestThumbnail(card),
            )
        }

        // 2. Parse musicResponsiveListItemRenderer rows (LastWave-Native InnerTubeMusicApiParsers.parseSong)
        val renderers = mutableListOf<JSONObject>()
        collectMusicResponsiveRenderers(root, renderers)
        for (item in renderers) {
            val videoId = extractDirectWatchVideoId(item) ?: continue
            val flexCols = item.optJSONArray("flexColumns") ?: continue
            val col0Text = flexCols.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
            val titleRuns = col0Text?.optJSONArray("runs")
            val title = buildString {
                if (titleRuns != null) {
                    for (i in 0 until titleRuns.length()) {
                        append(titleRuns.optJSONObject(i)?.optString("text").orEmpty())
                    }
                }
            }.trim().ifBlank { col0Text?.optString("simpleText")?.trim().orEmpty() }
            if (title.isEmpty()) continue

            val detailRuns = mutableListOf<JSONObject>()
            for (colIdx in 1 until flexCols.length()) {
                val runs = flexCols.optJSONObject(colIdx)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
                if (runs != null) {
                    for (rIdx in 0 until runs.length()) {
                        runs.optJSONObject(rIdx)?.let { detailRuns.add(it) }
                    }
                }
            }
            val fixedCols = item.optJSONArray("fixedColumns")
            if (fixedCols != null) {
                for (colIdx in 0 until fixedCols.length()) {
                    val runs = fixedCols.optJSONObject(colIdx)
                        ?.optJSONObject("musicResponsiveListItemFixedColumnRenderer")
                        ?.optJSONObject("text")
                        ?.optJSONArray("runs")
                    if (runs != null) {
                        for (rIdx in 0 until runs.length()) {
                            runs.optJSONObject(rIdx)?.let { detailRuns.add(it) }
                        }
                    }
                }
            }

            val artists = mutableListOf<String>()
            var fallbackArtist = ""
            var album = ""
            var durationMs = 0L

            for (run in detailRuns) {
                val text = run.optString("text").trim()
                if (text.isEmpty() || text == "•" || text == "·" || text == "&" || text == ",") continue
                if (text.matches(Regex("^(\\d+:)?\\d{1,2}:\\d{2}$"))) {
                    if (durationMs == 0L) durationMs = parseColonDurationMs(text)
                    continue
                }
                val pageType = findStringByKey(run, "pageType") ?: ""
                val browseId = findStringByKey(run, "browseId") ?: ""
                when {
                    pageType.contains("ALBUM") || browseId.startsWith("MPRE") -> if (album.isEmpty()) album = text
                    pageType.contains("ARTIST") || browseId.startsWith("UC") -> if (text !in artists) artists.add(text)
                    fallbackArtist.isEmpty() && isLikelyYtArtistDetail(text) -> fallbackArtist = text
                }
            }

            val artistStr = if (artists.isNotEmpty()) artists.joinToString(", ") else fallbackArtist
            val coverUrl = extractBestThumbnail(item)
            addSong(
                videoId = videoId,
                title = title,
                artistStr = artistStr,
                album = album,
                durationMs = durationMs,
                coverUrl = coverUrl,
            )
            if (results.size >= limit * 2) break
        }

        // 3. Parse standard YouTube videoRenderer / compactVideoRenderer if present
        if (results.isEmpty()) {
            val videoRenderers = mutableListOf<JSONObject>()
            collectObjectsByKey(root, "videoRenderer", videoRenderers)
            collectObjectsByKey(root, "compactVideoRenderer", videoRenderers)
            for (vr in videoRenderers) {
                val videoId = vr.optString("videoId").trim().takeIf { it.length == 11 } ?: continue
                val titleRuns = vr.optJSONObject("title")?.optJSONArray("runs")
                val title = buildString {
                    if (titleRuns != null) {
                        for (i in 0 until titleRuns.length()) {
                            append(titleRuns.optJSONObject(i)?.optString("text").orEmpty())
                        }
                    }
                }.trim().ifBlank { vr.optJSONObject("title")?.optString("simpleText")?.trim().orEmpty() }
                if (title.isEmpty()) continue
                val artist = vr.optJSONObject("ownerText")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim()
                    ?: vr.optJSONObject("shortBylineText")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim()
                    ?: ""
                val lenText = vr.optJSONObject("lengthText")?.optString("simpleText")?.trim().orEmpty()
                val durationMs = if (lenText.isNotEmpty()) parseColonDurationMs(lenText) else 0L
                val coverUrl = extractBestThumbnail(vr)
                addSong(
                    videoId = videoId,
                    title = title,
                    artistStr = artist,
                    album = "",
                    durationMs = durationMs,
                    coverUrl = coverUrl,
                )
                if (results.size >= limit) break
            }
        }

        // Sort preferring official YouTube Music square album artwork (googleusercontent.com / ggpht.com)
        // and items with album metadata, matching LastWave-Native InnerTubeMusicApi.searchSongs (lines 1384-1392).
        return results
            .sortedWith(
                compareByDescending<Map<String, Any?>> { item ->
                    val cover = item["cover_url"]?.toString().orEmpty()
                    val isYtMusicThumb = (cover.contains("googleusercontent.com") || cover.contains("ggpht.com")) &&
                        !cover.contains("ytimg.com")
                    val hasAlbum = !item["album"]?.toString().isNullOrBlank()
                    (if (isYtMusicThumb) 2 else 0) + (if (hasAlbum) 1 else 0)
                }
            )
            .take(limit)
    }

    private fun searchYtMusicSongsOnly(
        query: String,
        params: String?,
        limit: Int,
        providerIdLabel: String = "ytmusic",
    ): List<Map<String, Any?>> {
        fun runWebRemixSearch(searchParams: String?): List<Map<String, Any?>> {
            val root = postYtMusicWebRemix("search") {
                put("query", query)
                if (!searchParams.isNullOrBlank()) put("params", searchParams)
            } ?: return emptyList()
            return parseYtMusicSongsFromRoot(root, limit, providerIdLabel)
        }

        var results = runWebRemixSearch(params)
        if (results.isEmpty() && !params.isNullOrBlank()) {
            results = runWebRemixSearch(null)
        }
        if (results.isEmpty()) {
            cachedVisitorData = null
            getOrFetchVisitorData()
            results = runWebRemixSearch(params)
            if (results.isEmpty() && !params.isNullOrBlank()) {
                results = runWebRemixSearch(null)
            }
        }
        if (results.isEmpty()) {
            // Fallback to standard YouTube WEB search endpoint (matching LastWave-Native InnerTubeMusicApi.kt:1360-1378)
            results = runCatching {
                val payload = JSONObject()
                    .put(
                        "context",
                        JSONObject().put(
                            "client",
                            JSONObject()
                                .put("clientName", "WEB")
                                .put("clientVersion", "2.20261011.05.00")
                                .put("hl", "en")
                                .put("gl", "US"),
                        ),
                    )
                    .put("query", query)
                val resp = httpRequestBytes(
                    url = "https://www.youtube.com/youtubei/v1/search?key=AIzaSyAO_FJ2SlqAz8GlBg1fA54p0wDE7Xk80mU&prettyPrint=false",
                    method = "POST",
                    body = payload.toString().toByteArray(StandardCharsets.UTF_8),
                    headers = mapOf(
                        "User-Agent" to ytMusicWebRemixClient.userAgent,
                        "Content-Type" to "application/json",
                        "Origin" to "https://www.youtube.com",
                        "Referer" to "https://www.youtube.com/",
                    ),
                )
                if (resp.status in 200..299) {
                    val root = JSONObject(String(resp.body, StandardCharsets.UTF_8))
                    parseYtMusicSongsFromRoot(root, limit, providerIdLabel)
                } else {
                    emptyList()
                }
            }.getOrDefault(emptyList())
        }
        return results
    }

    private fun searchYtMusicFiltered(
        query: String,
        params: String,
        itemType: String,
        limit: Int,
        providerIdLabel: String = "ytmusic",
    ): List<Map<String, Any?>> {
        val root = postYtMusicWebRemix("search") {
            put("query", query)
            put("params", params)
        } ?: return emptyList()

        val renderers = mutableListOf<JSONObject>()
        collectMusicResponsiveRenderers(root, renderers)
        val results = mutableListOf<Map<String, Any?>>()
        val seenIds = mutableSetOf<String>()

        for (item in renderers) {
            val browseId = item.optJSONObject("navigationEndpoint")
                ?.optJSONObject("browseEndpoint")
                ?.optString("browseId")
                ?.takeIf { it.isNotBlank() }
                ?: findStringByKey(item, "browseId")?.takeIf { it.isNotBlank() }
                ?: continue
            if (itemType == "artist" && !browseId.startsWith("UC")) continue
            if (itemType == "album" && !browseId.startsWith("MPRE") && !browseId.startsWith("OLAK") && !browseId.startsWith("VL")) continue
            if (!seenIds.add(browseId)) continue

            val flexCols = item.optJSONArray("flexColumns") ?: continue
            val titleRuns = flexCols.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
            val title = buildString {
                if (titleRuns != null) {
                    for (i in 0 until titleRuns.length()) {
                        append(titleRuns.optJSONObject(i)?.optString("text").orEmpty())
                    }
                }
            }.trim()
            if (title.isEmpty()) continue

            val subRuns = flexCols.optJSONObject(1)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
            val subParts = mutableListOf<String>()
            var explicitArtist = ""
            if (subRuns != null) {
                for (i in 0 until subRuns.length()) {
                    val run = subRuns.optJSONObject(i) ?: continue
                    val t = run.optString("text").trim()
                    val bId = findStringByKey(run, "browseId") ?: ""
                    if (bId.startsWith("UC") && explicitArtist.isEmpty()) {
                        explicitArtist = t
                    }
                    if (t.isNotEmpty() && t != "•" && t != "·" && !t.equals("Album", ignoreCase = true) && !t.equals("Artist", ignoreCase = true) && !t.equals("Single", ignoreCase = true) && !t.equals("EP", ignoreCase = true)) {
                        subParts.add(t)
                    }
                }
            }
            val artistStr = if (itemType == "album") {
                explicitArtist.ifBlank { subParts.firstOrNull().orEmpty() }
            } else {
                title
            }
            val coverUrl = extractBestThumbnail(item)

            results.add(
                mapOf(
                    "id" to browseId,
                    "item_type" to itemType,
                    "name" to title,
                    "title" to title,
                    "artists" to artistStr,
                    "artist" to artistStr,
                    "album_name" to if (itemType == "album") title else "",
                    "album" to if (itemType == "album") title else "",
                    "duration_ms" to 0L,
                    "cover_url" to coverUrl,
                    "provider_id" to providerIdLabel,
                    "provider_name" to "YouTube Music",
                )
            )
            if (results.size >= limit) break
        }
        return results
    }

    private fun getYtMusicAlbumInnerTube(
        browseId: String,
        providerIdLabel: String = "ytmusic",
    ): Map<String, Any?> {
        val root = postYtMusicWebRemix("browse") {
            put("browseId", browseId)
        } ?: return emptyMap()

        val albumTitle = findHeaderTitle(root).ifBlank { "Album" }
        val albumCover = extractBestThumbnail(root)
        val renderers = mutableListOf<JSONObject>()
        collectMusicResponsiveRenderers(root, renderers)

        var albumArtist = ""
        val tracks = mutableListOf<Map<String, Any?>>()
        for ((idx, item) in renderers.withIndex()) {
            val videoId = extractDirectWatchVideoId(item) ?: continue
            val flexCols = item.optJSONArray("flexColumns") ?: continue
            val title = flexCols.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optString("text")
                ?.trim()
                .orEmpty()
            if (title.isEmpty()) continue
            val artist = flexCols.optJSONObject(1)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optString("text")
                ?.trim()
                .orEmpty()
            if (albumArtist.isEmpty() && artist.isNotEmpty()) albumArtist = artist

            var durationMs = 0L
            val fixedCols = item.optJSONArray("fixedColumns")
            val durText = fixedCols?.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFixedColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optString("text")
                ?.trim()
                .orEmpty()
            if (durText.isNotEmpty()) durationMs = parseColonDurationMs(durText)

            tracks.add(
                mapOf(
                    "id" to videoId,
                    "spotify_id" to videoId,
                    "item_type" to "track",
                    "name" to title,
                    "title" to title,
                    "artists" to artist.ifBlank { albumArtist },
                    "artist" to artist.ifBlank { albumArtist },
                    "album_name" to albumTitle,
                    "album" to albumTitle,
                    "duration_ms" to durationMs,
                    "track_number" to (idx + 1),
                    "cover_url" to extractBestThumbnail(item).ifBlank { albumCover },
                    "provider_id" to providerIdLabel,
                    "provider_name" to "YouTube Music",
                )
            )
        }
        return mapOf(
            "id" to browseId,
            "name" to albumTitle,
            "artist" to albumArtist,
            "cover_url" to albumCover,
            "release_date" to "",
            "provider_id" to providerIdLabel,
            "provider_name" to "YouTube Music",
            "tracks" to tracks,
        )
    }

    private fun getYtMusicArtistInnerTube(
        browseId: String,
        providerIdLabel: String = "ytmusic",
    ): Map<String, Any?> {
        val root = postYtMusicWebRemix("browse") {
            put("browseId", browseId)
        }
        val artistName = (root?.let { findHeaderTitle(it) }.orEmpty()).ifBlank { "Artist" }
        val coverUrl = root?.let { extractBestThumbnail(it) }.orEmpty()
        val topTracks = if (artistName.isNotBlank()) {
            searchYtMusicSongsOnly(
                query = artistName,
                params = "EgWKAQIIAWoKEAkQBRAKEAMQBA==",
                limit = 50,
                providerIdLabel = providerIdLabel,
            )
        } else {
            emptyList()
        }
        val albums = if (artistName.isNotBlank()) {
            searchYtMusicFiltered(
                query = artistName,
                params = "EgWKAQIYAWoKEAkQBRAKEAMQBA==",
                itemType = "album",
                limit = 15,
                providerIdLabel = providerIdLabel,
            )
        } else {
            emptyList()
        }
        return mapOf(
            "id" to browseId,
            "name" to artistName,
            "cover_url" to coverUrl,
            "provider_id" to providerIdLabel,
            "provider_name" to "YouTube Music",
            "top_tracks" to topTracks,
            "albums" to albums,
        )
    }

    private val tidalLosslessMirrors = listOf(
        "https://triton.squid.wtf",
        "https://tidal.kinoplus.online",
        "https://tidal-api.binimum.org",
        "https://hifi-one.spotisaver.net",
        "https://hifi-two.spotisaver.net",
        "https://hund.qqdl.site",
        "https://katze.qqdl.site",
        "https://maus.qqdl.site",
        "https://vogel.qqdl.site",
        "https://wolf.qqdl.site",
    )

    /**
     * Resolves a Tidal `/dl/tid` request against public `hifi-api` compatible
     * mirrors when `api.zarz.moe/v2` requires interactive Turnstile verification
     * or returns a server error.
     */
    private fun resolveTidalMirrorSignedFallback(bodyJson: String?): String? {
        if (bodyJson.isNullOrBlank()) return null
        val reqObj = runCatching { JSONObject(bodyJson) }.getOrNull() ?: return null
        val trackId = reqObj.optString("id").trim()
        val requestedQuality = reqObj.optString("quality", "LOSSLESS").trim().ifBlank { "LOSSLESS" }
        if (trackId.isEmpty() || reqObj.optString("endpoint") == "manifests") return null

        val qualitiesToTry = buildList {
            if (requestedQuality == "DOLBY_ATMOS") {
                add("HI_RES_LOSSLESS")
                add("LOSSLESS")
            } else if (requestedQuality == "HI_RES_LOSSLESS") {
                add("LOSSLESS")
                add("HI_RES_LOSSLESS")
            } else {
                add(requestedQuality)
                if (requestedQuality != "LOSSLESS") add("LOSSLESS")
            }
        }.distinct()

        var fallbackDashResponse: String? = null
        for (q in qualitiesToTry) {
            for (base in tidalLosslessMirrors) {
                val url = "$base/track/?id=${URLEncoder.encode(trackId, "UTF-8")}&quality=${URLEncoder.encode(q, "UTF-8")}"
                val resp = runCatching {
                    httpRequestBytes(
                        url,
                        "GET",
                        null,
                        mapOf("User-Agent" to "Mozilla/5.0", "Accept" to "application/json"),
                    )
                }.getOrNull() ?: continue
                if (resp.status !in 200..299) continue
                val text = String(resp.body, StandardCharsets.UTF_8).trim()
                if (text.startsWith("{")) {
                    val obj = runCatching { JSONObject(text) }.getOrNull() ?: continue
                    val data = obj.optJSONObject("data") ?: continue
                    val manifest = data.optString("manifest")
                    if (manifest.isNotBlank()) {
                        val mime = data.optString("manifestMimeType")
                        val wrappedResp = JSONObject()
                            .put("ok", true)
                            .put("status", 200)
                            .put("statusCode", 200)
                            .put("body", text)
                            .put("headers", JSONObject().put("Content-Type", "application/json"))
                            .toString()
                        if (mime.contains("bts", ignoreCase = true)) {
                            return wrappedResp
                        } else if (fallbackDashResponse == null) {
                            fallbackDashResponse = wrappedResp
                        }
                    }
                } else if (text.startsWith("[")) {
                    val arr = runCatching { JSONArray(text) }.getOrNull() ?: continue
                    for (i in 0 until arr.length()) {
                        val item = arr.optJSONObject(i) ?: continue
                        val directUrl = item.optString("OriginalTrackUrl").trim()
                        if (directUrl.startsWith("http://") || directUrl.startsWith("https://")) {
                            val bts = JSONObject()
                                .put("mimeType", "audio/flac")
                                .put("codecs", "flac")
                                .put("urls", JSONArray().put(directUrl))
                                .toString()
                            val b64 = Base64.encodeToString(bts.toByteArray(StandardCharsets.UTF_8), Base64.NO_WRAP)
                            val wrapped = JSONObject().put(
                                "data",
                                JSONObject()
                                    .put("assetPresentation", "FULL")
                                    .put("audioMode", "STEREO")
                                    .put("audioQuality", if (q == "HI_RES_LOSSLESS") "LOSSLESS" else q)
                                    .put("bitDepth", 16)
                                    .put("sampleRate", 44100)
                                    .put("manifestMimeType", "application/vnd.tidal.bts")
                                    .put("manifest", b64),
                            )
                            return JSONObject()
                                .put("ok", true)
                                .put("status", 200)
                                .put("statusCode", 200)
                                .put("body", wrapped.toString())
                                .put("headers", JSONObject().put("Content-Type", "application/json"))
                                .toString()
                        }
                    }
                }
            }
        }
        return fallbackDashResponse
    }

    /**
     * Resolves a Qobuz `/dl/qbz` request against public Qobuz lossless mirrors
     * when `api.zarz.moe/v2` requires interactive Turnstile verification or
     * returns an error.
     */
    private fun resolveQobuzMirrorSignedFallback(bodyJson: String?): String? {
        if (bodyJson.isNullOrBlank()) return null
        val reqObj = runCatching { JSONObject(bodyJson) }.getOrNull() ?: return null
        val trackId = reqObj.optString("id").trim()
        if (trackId.isEmpty()) return null
        val qStr = reqObj.optString("quality", "hi-res-max").lowercase(Locale.ROOT)
        val primaryFormatId = when {
            qStr.contains("max") -> "27"
            qStr.contains("hi-res") -> "7"
            else -> "6"
        }
        val formatIds = listOf(primaryFormatId, "7", "6").distinct()
        for (formatId in formatIds) {
            val endpoints = listOf(
                "https://eu.qobuz.squid.wtf/api/download-music?track_id=${URLEncoder.encode(trackId, "UTF-8")}&quality=$formatId",
                "https://us.qobuz.squid.wtf/api/download-music?track_id=${URLEncoder.encode(trackId, "UTF-8")}&quality=$formatId",
                "https://dab.yeet.su/api/stream?trackId=${URLEncoder.encode(trackId, "UTF-8")}&quality=$formatId",
            )
            for (url in endpoints) {
                val resp = runCatching {
                    httpRequestBytes(
                        url,
                        "GET",
                        null,
                        mapOf("User-Agent" to "Mozilla/5.0", "Accept" to "application/json"),
                    )
                }.getOrNull() ?: continue
                if (resp.status !in 200..299) continue
                val text = String(resp.body, StandardCharsets.UTF_8).trim()
                val obj = runCatching { JSONObject(text) }.getOrNull() ?: continue
                val nested = obj.optJSONObject("data")
                val dlUrl = listOf(
                    obj.optString("url"),
                    obj.optString("download_url"),
                    obj.optString("link"),
                    nested?.optString("url") ?: "",
                    nested?.optString("download_url") ?: "",
                    nested?.optString("link") ?: "",
                ).firstOrNull { it.startsWith("http://") || it.startsWith("https://") }
                if (!dlUrl.isNullOrEmpty()) {
                    return JSONObject()
                        .put("ok", true)
                        .put("status", 200)
                        .put("statusCode", 200)
                        .put("body", text)
                        .put("headers", JSONObject().put("Content-Type", "application/json"))
                        .toString()
                }
            }
        }
        val activeTrack = activeDownloadTrack.get()
        if (activeTrack != null) {
            val isrc = (activeTrack["isrc"] ?: "").toString().trim()
            val title = (activeTrack["title"] ?: activeTrack["name"] ?: "").toString().trim()
            val artist = (activeTrack["artist"] ?: activeTrack["artists"] ?: "").toString().trim()
            val flacUrl = resolveLosslessFlacUrlFromPublicMirrors(isrc, title, artist)
            if (!flacUrl.isNullOrEmpty()) {
                val payload = JSONObject()
                    .put("url", flacUrl)
                    .put("format_id", 6)
                    .put("mime_type", "audio/flac")
                    .put("sampling_rate", 44.1)
                    .put("bit_depth", 16)
                return JSONObject()
                    .put("ok", true)
                    .put("status", 200)
                    .put("statusCode", 200)
                    .put("body", payload.toString())
                    .put("headers", JSONObject().put("Content-Type", "application/json"))
                    .toString()
            }
        }
        return null
    }

    /**
     * Resolves a Deezer `/dl/dzr` signed request against public lossless FLAC
     * mirrors when `api.zarz.moe/v2` returns 428 `VERIFY_REQUIRED`.
     */
    private fun resolveDeezerMirrorSignedFallback(bodyJson: String?): String? {
        if (bodyJson.isNullOrBlank()) return null
        val reqObj = runCatching { JSONObject(bodyJson) }.getOrNull() ?: return null
        val dzrId = reqObj.optString("id").trim().substringAfterLast(':')
        val activeTrack = activeDownloadTrack.get()
        var isrc = (activeTrack?.get("isrc") ?: "").toString().trim()
        var title = (activeTrack?.get("title") ?: activeTrack?.get("name") ?: "").toString().trim()
        var artist = (activeTrack?.get("artist") ?: activeTrack?.get("artists") ?: "").toString().trim()

        if (dzrId.isNotEmpty() && (isrc.isEmpty() || title.isEmpty())) {
            runCatching {
                val resp = httpRequestBytes(
                    "https://api.deezer.com/track/${URLEncoder.encode(dzrId, "UTF-8")}",
                    "GET",
                    null,
                    mapOf("User-Agent" to "Mozilla/5.0", "Accept" to "application/json"),
                )
                if (resp.status in 200..299) {
                    val obj = JSONObject(String(resp.body, StandardCharsets.UTF_8))
                    if (isrc.isEmpty()) isrc = obj.optString("isrc").trim()
                    if (title.isEmpty()) title = obj.optString("title").trim()
                    if (artist.isEmpty()) artist = obj.optJSONObject("artist")?.optString("name")?.trim().orEmpty()
                }
            }
        }

        val flacUrl = resolveLosslessFlacUrlFromPublicMirrors(isrc, title, artist) ?: return null
        val descriptor = JSONObject()
            .put("success", true)
            .put("direct_downloadable", true)
            .put("direct_download_url", flacUrl)
            .put("download_url", flacUrl)
            .put("requires_client_decryption", false)
            .put("deezer_encrypted", false)
            .put("deezer_source_format", "FLAC")
            .put("title", title)
            .put("artist", artist)
        return JSONObject()
            .put("ok", true)
            .put("status", 200)
            .put("statusCode", 200)
            .put("body", descriptor.toString())
            .put("headers", JSONObject().put("Content-Type", "application/json"))
            .toString()
    }

    /**
     * Searches public lossless `hifi-api` / Qobuz mirrors by [isrc] or
     * `[title] [artist]` and extracts a direct `.flac` download URL.
     */
    private fun resolveLosslessFlacUrlFromPublicMirrors(
        isrc: String,
        title: String,
        artist: String,
    ): String? {
        val cleanTitle = title.trim()
        val cleanArtist = artist.substringBefore(',').trim()
        val query = if (cleanArtist.isNotEmpty()) "$cleanTitle $cleanArtist" else cleanTitle
        if (query.isEmpty() && isrc.isEmpty()) return null

        var tidalTrackId: String? = null
        val tidalExt = synchronized(lock) { extensions["tidal-web"] }
        if (tidalExt != null) {
            tidalTrackId = runCatching {
                executeInExtension(tidalExt) { cx, scope, extObj ->
                    val checkFn = ScriptableObject.getProperty(extObj, "checkAvailability") as? RhinoFunction
                    if (checkFn != null) {
                        val raw = jsToKotlin(
                            checkFn.call(cx, scope, extObj, arrayOf<Any?>(isrc, cleanTitle, cleanArtist, cx.newObject(scope)))
                        ) as? Map<*, *>
                        val id = (raw?.get("track_id") ?: raw?.get("trackId"))?.toString()?.trim()?.substringAfterLast(':')
                        if (!id.isNullOrEmpty() && raw?.get("available") != false) return@executeInExtension id
                    }
                    null
                }
            }.getOrNull()
        }

        if (tidalTrackId.isNullOrEmpty() && query.isNotEmpty()) {
            for (base in tidalLosslessMirrors.take(4)) {
                val searchUrl = "$base/search/?s=${URLEncoder.encode(query, "UTF-8")}"
                val resp = runCatching {
                    httpRequestBytes(searchUrl, "GET", null, mapOf("User-Agent" to "Mozilla/5.0", "Accept" to "application/json"))
                }.getOrNull() ?: continue
                if (resp.status !in 200..299) continue
                val text = String(resp.body, StandardCharsets.UTF_8).trim()
                val items = runCatching {
                    val root = JSONObject(text)
                    root.optJSONObject("data")?.optJSONArray("items")
                        ?: root.optJSONObject("tracks")?.optJSONArray("items")
                        ?: root.optJSONArray("items")
                }.getOrNull() ?: continue
                if (items.length() > 0) {
                    val firstId = items.optJSONObject(0)?.optString("id")?.trim()
                    if (!firstId.isNullOrEmpty()) {
                        tidalTrackId = firstId
                        break
                    }
                }
            }
        }

        if (!tidalTrackId.isNullOrEmpty()) {
            for (base in tidalLosslessMirrors) {
                val url = "$base/track/?id=${URLEncoder.encode(tidalTrackId, "UTF-8")}&quality=LOSSLESS"
                val resp = runCatching {
                    httpRequestBytes(url, "GET", null, mapOf("User-Agent" to "Mozilla/5.0", "Accept" to "application/json"))
                }.getOrNull() ?: continue
                if (resp.status !in 200..299) continue
                val text = String(resp.body, StandardCharsets.UTF_8).trim()
                if (text.startsWith("[")) {
                    val arr = runCatching { JSONArray(text) }.getOrNull() ?: continue
                    for (i in 0 until arr.length()) {
                        val direct = arr.optJSONObject(i)?.optString("OriginalTrackUrl")?.trim().orEmpty()
                        if (direct.startsWith("http://") || direct.startsWith("https://")) return direct
                    }
                } else if (text.startsWith("{")) {
                    val obj = runCatching { JSONObject(text) }.getOrNull() ?: continue
                    val data = obj.optJSONObject("data") ?: continue
                    val mime = data.optString("manifestMimeType")
                    val b64 = data.optString("manifest")
                    if (mime.contains("bts", ignoreCase = true) && b64.isNotBlank()) {
                        val decoded = runCatching { String(Base64.decode(b64, Base64.DEFAULT), StandardCharsets.UTF_8) }.getOrNull()
                        val btsObj = decoded?.let { runCatching { JSONObject(it) }.getOrNull() }
                        val firstUrl = btsObj?.optJSONArray("urls")?.optString(0)?.trim().orEmpty()
                        if (firstUrl.startsWith("http://") || firstUrl.startsWith("https://")) return firstUrl
                    }
                }
            }
        }
        return null
    }

    /**
     * Completes a download using ONLY the selected provider's own direct
     * endpoints when [ext]'s primary JS download handler fails, never switching
     * or falling back to a different provider.
     */
    private fun downloadFallbackForSelectedExtensionAndQuality(
        ext: LoadedExtension,
        track: Map<String, Any?>,
        outDir: File,
        baseFileName: String,
        preferredQuality: String?,
        reportProgress: (Int) -> Unit,
    ): File? {
        val isrc = (track["isrc"] ?: "").toString().trim()
        val title = (track["title"] ?: track["name"] ?: "").toString().trim()
        val artist = (track["artist"] ?: track["artists"] ?: "").toString().trim()
        val qLower = (preferredQuality ?: "").trim().lowercase(Locale.ROOT)
        val wantsLossless = qLower.contains("flac") ||
            qLower.contains("lossless") ||
            qLower.contains("hi_res") ||
            qLower.contains("hi-res") ||
            (!qLower.contains("high") && !qLower.contains("low") && !qLower.contains("aac") && !qLower.contains("opus"))

        return when (ext.id) {
            "tidal-web" -> {
                if (!wantsLossless) return null
                val flacUrl = resolveLosslessFlacUrlFromPublicMirrors(isrc, title, artist)
                if (!flacUrl.isNullOrEmpty()) {
                    val outFile = File(outDir, "$baseFileName.flac")
                    val dlOk = runCatching {
                        downloadDirectHttpToFile(flacUrl, outFile, reportProgress)
                    }.getOrDefault(false)
                    if (dlOk && outFile.isFile && outFile.length() > 0) outFile else null
                } else {
                    null
                }
            }
            "jiosaavn" -> {
                val saavnUrl = runCatching { resolveJioSaavnDirectUrl(track) }.getOrNull()
                if (!saavnUrl.isNullOrEmpty()) {
                    val outFile = File(outDir, "$baseFileName.m4a")
                    val dlOk = runCatching {
                        downloadDirectHttpToFile(saavnUrl, outFile, reportProgress)
                    }.getOrDefault(false)
                    if (dlOk && outFile.isFile && outFile.length() > 0) outFile else null
                } else {
                    null
                }
            }
            "ytmusic-spotiflac" -> {
                runCatching {
                    downloadYouTubeTrackNative(track, outDir, baseFileName, preferredQuality, reportProgress)
                }.getOrNull()
            }
            else -> null
        }
    }

    private fun downloadDirectHttpToFile(
        url: String,
        outFile: File,
        reportProgress: (Int) -> Unit,
    ): Boolean {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Mozilla/5.0")
        }
        return try {
            val status = conn.responseCode
            if (status !in 200..299) return false
            val totalLen = conn.contentLengthLong
            var written = 0L
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { fos ->
                conn.inputStream.use { input ->
                    val buf = ByteArray(32 * 1024)
                    while (true) {
                        val r = input.read(buf)
                        if (r <= 0) break
                        fos.write(buf, 0, r)
                        written += r
                        if (totalLen > 0L) {
                            reportProgress(((written * 100L) / totalLen).toInt().coerceIn(0, 100))
                        }
                    }
                }
            }
            reportProgress(100)
            written > 0L
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Builds the LastWave-Native Home Discovery Feed (`FeedRepository.kt` &
     * `LocalTasteSuggestionEngine.kt`) with:
     * 1. `forYou` ("Quick picks"): Personalized recommendations combining
     *    YouTube Music `/youtubei/v1/next` watch-next radio for top seed tracks,
     *    seed artist tracks, and `FEmusic_home` picks, filtered for junk/edits
     *    and diversified (`maxPerArtist = 2`).
     * 2. `becauseYouListenTo` ("Because you listen to <Artist>"): Dedicated
     *    watch-next radio shelf expanded from the top affinity artist/track.
     * 3. `freshFinds` ("Fresh finds"): Unseen discovery tracks diversified with
     *    strict `maxPerArtist = 1`.
     * 4. `trending` ("Trending charts"): Live chart & home feed tracks from the
     *    selected provider (`getHomeFeed()`) and YouTube Music `FEmusic_charts`
     *    / `FEmusic_home`.
     * 5. `chips`: Dynamic mood & activity chips (*Relax*, *Energize*, *Workout*,
     *    *Focus*, *Commute*, etc.) parsed from `FEmusic_home`.
     */
    fun getHomeFeed(
        seedArtists: List<String>,
        seedTracks: List<String>,
        preferredProviderId: String? = null,
        chipParams: String? = null,
    ): Map<String, Any?> {
        ensureBundledLoaded()
        val defaultArtists = listOf(
            "The Weeknd",
            "Arijit Singh",
            "Coldplay",
            "Billie Eilish",
            "Drake",
            "A.R. Rahman",
        )
        val cleanArtists = seedArtists.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        val cleanTracks = seedTracks.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        val seeds = buildList {
            addAll(cleanTracks.take(3))
            addAll(cleanArtists.take(4))
            if (isEmpty()) {
                addAll(defaultArtists.shuffled().take(4))
            }
        }.distinct().take(5)

        val becauseSeedArtist = cleanArtists.firstOrNull() ?: defaultArtists.first()

        val activeExt = synchronized(lock) {
            val pref = preferredProviderId?.trim()?.takeIf { it.isNotEmpty() && it != "all" && it != "ytmusic" }
            if (pref != null) {
                extensions[pref]?.takeIf { it.enabled && (it.hasMetadataProvider || it.hasCustomSearch) }
            } else {
                null
            }
        }
        val providerToSearch = if (preferredProviderId == "ytmusic" || activeExt == null) "ytmusic" else activeExt.id

        // 1. Browse FEmusic_home (with optional mood/activity chipParams) for native shelves & mood chips
        val homePageFuture = searchPool.submit<Pair<List<Map<String, Any?>>, List<Map<String, String>>>> {
            runCatching {
                browseYtMusicHomeSongsAndChips(chipParams = chipParams, limit = 28)
            }.getOrDefault(emptyList<Map<String, Any?>>() to emptyList())
        }

        // 2. Search seed queries on the selected provider
        val seedFutures = seeds.map { seedQuery ->
            searchPool.submit<List<Map<String, Any?>>> {
                runCatching {
                    search(seedQuery, 10, "tracks", providerToSearch)
                        .filter { (it["item_type"]?.toString() ?: "track") == "track" }
                }.getOrDefault(emptyList())
            }
        }

        // 3. Trending / Extension Home Feed + FEmusic_charts
        val trendingFuture = searchPool.submit<List<Map<String, Any?>>> {
            runCatching {
                fetchTrendingHomeTracks(activeExt, chipParams)
            }.getOrDefault(emptyList())
        }

        val seedBatches = seedFutures.map { fut ->
            runCatching { fut.get(4500L, java.util.concurrent.TimeUnit.MILLISECONDS) }.getOrDefault(emptyList())
        }

        // 4. LastWave-Native RelatedGraphRepository: expand top seed videoIds via /youtubei/v1/next radio
        val seedVideoIds = buildList {
            for (batch in seedBatches) {
                val firstYt = batch.firstOrNull { (it["id"]?.toString()?.length == 11) }
                val vid = firstYt?.get("id")?.toString()?.trim()
                if (!vid.isNullOrEmpty() && vid !in this) {
                    add(vid)
                }
                if (size >= 2) break
            }
        }
        val radioFutures = seedVideoIds.map { vid ->
            searchPool.submit<List<Map<String, Any?>>> {
                runCatching { fetchRelatedSongsInnerTube(vid, limit = 18) }.getOrDefault(emptyList())
            }
        }
        val radioBatches = radioFutures.map { fut ->
            runCatching { fut.get(4000L, java.util.concurrent.TimeUnit.MILLISECONDS) }.getOrDefault(emptyList())
        }

        val (homeSongs, homeChips) = runCatching {
            homePageFuture.get(4500L, java.util.concurrent.TimeUnit.MILLISECONDS)
        }.getOrDefault(emptyList<Map<String, Any?>>() to emptyList())

        val seenKeys = mutableSetOf<String>()

        fun trackKey(item: Map<String, Any?>): String {
            val t = (item["title"] ?: item["name"] ?: "").toString().trim().lowercase(Locale.ROOT)
                .replace(Regex("\\(official.*?\\)|\\[official.*?\\]|\\(lyric.*?\\)|\\[lyric.*?\\]"), "")
                .trim()
            val a = (item["artist"] ?: item["artists"] ?: "").toString().trim().lowercase(Locale.ROOT)
                .substringBefore(',').trim()
            return "$t:$a"
        }

        fun isJunkRecommendation(item: Map<String, Any?>): Boolean {
            val title = (item["title"] ?: item["name"] ?: "").toString().trim().lowercase(Locale.ROOT)
            if (title.isEmpty()) return true
            val junkMarkers = listOf("karaoke", "ringtone", "8d audio", "nightcore", "1 hour", "full album", "sound effect")
            return junkMarkers.any { title.contains(it) }
        }

        // If a mood chip is active, prioritize the mood chip's FEmusic_home songs in Quick picks!
        val quickPickBatches = buildList {
            if (!chipParams.isNullOrBlank() && homeSongs.isNotEmpty()) {
                add(homeSongs)
            }
            addAll(radioBatches)
            addAll(seedBatches)
            if (chipParams.isNullOrBlank() && homeSongs.isNotEmpty()) {
                add(homeSongs)
            }
        }

        val forYou = mutableListOf<Map<String, Any?>>()
        val forYouArtistCounts = mutableMapOf<String, Int>()
        val maxQuickLen = quickPickBatches.maxOfOrNull { it.size } ?: 0
        for (idx in 0 until maxQuickLen) {
            for (batch in quickPickBatches) {
                if (idx >= batch.size) continue
                val item = batch[idx]
                if (isJunkRecommendation(item)) continue
                val key = trackKey(item)
                if (key in seenKeys) continue
                val normArtist = (item["artist"] ?: item["artists"] ?: "").toString().trim().lowercase(Locale.ROOT).substringBefore(',').trim()
                val count = forYouArtistCounts[normArtist] ?: 0
                if (normArtist.isNotEmpty() && count >= 2) continue
                seenKeys.add(key)
                if (normArtist.isNotEmpty()) forYouArtistCounts[normArtist] = count + 1
                forYou.add(item)
                if (forYou.size >= 18) break
            }
            if (forYou.size >= 18) break
        }

        // Build "Because you listen to <becauseSeedArtist>" shelf (LastWave-Native style)
        val becauseYouListenTo = mutableListOf<Map<String, Any?>>()
        val becauseArtistCounts = mutableMapOf<String, Int>()
        val becauseCandidates = buildList {
            if (radioBatches.isNotEmpty()) addAll(radioBatches.first())
            if (seedBatches.isNotEmpty()) addAll(seedBatches.flatten())
        }
        for (item in becauseCandidates) {
            if (isJunkRecommendation(item)) continue
            val key = trackKey(item)
            if (key in seenKeys) continue
            val normArtist = (item["artist"] ?: item["artists"] ?: "").toString().trim().lowercase(Locale.ROOT).substringBefore(',').trim()
            val count = becauseArtistCounts[normArtist] ?: 0
            if (normArtist.isNotEmpty() && count >= 2) continue
            seenKeys.add(key)
            if (normArtist.isNotEmpty()) becauseArtistCounts[normArtist] = count + 1
            becauseYouListenTo.add(item)
            if (becauseYouListenTo.size >= 16) break
        }

        // Build "Fresh finds" shelf (strict maxPerArtist = 1 diversity, unseen artists/tracks)
        val freshFinds = mutableListOf<Map<String, Any?>>()
        val freshArtistsSeen = mutableSetOf<String>()
        val freshCandidates = buildList {
            if (radioBatches.size > 1) addAll(radioBatches.drop(1).flatten())
            addAll(homeSongs)
            addAll(seedBatches.flatten())
        }
        for (item in freshCandidates) {
            if (isJunkRecommendation(item)) continue
            val key = trackKey(item)
            if (key in seenKeys) continue
            val normArtist = (item["artist"] ?: item["artists"] ?: "").toString().trim().lowercase(Locale.ROOT).substringBefore(',').trim()
            if (normArtist.isNotEmpty() && !freshArtistsSeen.add(normArtist)) continue
            seenKeys.add(key)
            freshFinds.add(item)
            if (freshFinds.size >= 16) break
        }

        // Build "Trending charts" shelf
        val rawTrending = runCatching {
            trendingFuture.get(4500L, java.util.concurrent.TimeUnit.MILLISECONDS)
        }.getOrDefault(emptyList())
        val trending = mutableListOf<Map<String, Any?>>()
        val trendingArtistCounts = mutableMapOf<String, Int>()
        for (item in (rawTrending + homeSongs)) {
            if ((item["item_type"]?.toString() ?: "track") != "track") continue
            if (isJunkRecommendation(item)) continue
            val key = trackKey(item)
            if (!seenKeys.add(key)) continue
            val normArtist = (item["artist"] ?: item["artists"] ?: "").toString().trim().lowercase(Locale.ROOT).substringBefore(',').trim()
            val count = trendingArtistCounts[normArtist] ?: 0
            if (normArtist.isNotEmpty() && count >= 2) continue
            if (normArtist.isNotEmpty()) trendingArtistCounts[normArtist] = count + 1
            trending.add(item)
            if (trending.size >= 18) break
        }

        return mapOf(
            "forYou" to forYou,
            "becauseYouListenTo" to becauseYouListenTo,
            "becauseArtist" to becauseSeedArtist,
            "freshFinds" to freshFinds,
            "trending" to trending,
            "chips" to homeChips,
            "providerName" to (activeExt?.displayName ?: "YouTube Music"),
        )
    }

    /**
     * Fetches YouTube Music's `/youtubei/v1/next` watch-next radio tracks for a
     * seed [videoId] (`playlistId = RDAMVM<videoId>`), matching LastWave-Native's
     * `InnerTubeMusicApi.fetchRelatedSongs`.
     */
    private fun fetchRelatedSongsInnerTube(videoId: String, limit: Int = 18): List<Map<String, Any?>> {
        if (videoId.length != 11) return emptyList()
        val root = postYtMusicWebRemix("next") {
            put("videoId", videoId)
            put("playlistId", "RDAMVM$videoId")
            put("params", "wAEB")
            put("isAudioOnly", true)
        } ?: return emptyList()

        val panelRenderers = mutableListOf<JSONObject>()
        collectPlaylistPanelVideoRenderers(root, panelRenderers)
        val results = mutableListOf<Map<String, Any?>>()
        val seenIds = mutableSetOf(videoId)

        for (renderer in panelRenderers) {
            if (renderer.optJSONObject("unplayableText") != null) continue
            val vid = renderer.optString("videoId").trim().takeIf { it.length == 11 }
                ?: renderer.optJSONObject("navigationEndpoint")?.optJSONObject("watchEndpoint")?.optString("videoId")?.trim()?.takeIf { it.length == 11 }
                ?: continue
            if (!seenIds.add(vid)) continue
            val title = renderer.optJSONObject("title")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim()
                ?: renderer.optJSONObject("title")?.optString("simpleText")?.trim()
                ?: continue
            if (title.isEmpty()) continue

            val bylineRuns = (renderer.optJSONObject("longBylineText") ?: renderer.optJSONObject("shortBylineText"))
                ?.optJSONArray("runs")
            val artists = mutableListOf<String>()
            var album = ""
            if (bylineRuns != null) {
                for (i in 0 until bylineRuns.length()) {
                    val run = bylineRuns.optJSONObject(i) ?: continue
                    val t = run.optString("text").trim()
                    if (t.isEmpty() || t == "•" || t == "·" || t == "&" || t == ",") continue
                    val browseId = findStringByKey(run, "browseId") ?: ""
                    when {
                        browseId.startsWith("MPRE") -> album = t
                        browseId.startsWith("UC") -> artists.add(t)
                        artists.isEmpty() && !t.contains("views", ignoreCase = true) && !t.contains("likes", ignoreCase = true) -> {
                            artists.add(t)
                        }
                    }
                }
            }
            val durText = renderer.optJSONObject("lengthText")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim()
                ?: renderer.optJSONObject("lengthText")?.optString("simpleText")?.trim()
                ?: ""
            val durationMs = if (durText.isNotEmpty()) parseColonDurationMs(durText) else 0L
            val artistStr = artists.joinToString(", ")

            results.add(
                mapOf(
                    "id" to vid,
                    "spotify_id" to vid,
                    "item_type" to "track",
                    "name" to title,
                    "title" to title,
                    "artists" to artistStr,
                    "artist" to artistStr,
                    "album_name" to album,
                    "album" to album,
                    "album_artist" to artistStr,
                    "duration_ms" to durationMs,
                    "cover_url" to extractBestThumbnail(renderer),
                    "provider_id" to "ytmusic",
                    "provider_name" to "YouTube Music",
                    "external_urls" to "https://music.youtube.com/watch?v=$vid",
                )
            )
            if (results.size >= limit) break
        }
        return results
    }

    private fun collectPlaylistPanelVideoRenderers(node: Any?, out: MutableList<JSONObject>) {
        when (node) {
            is JSONObject -> {
                node.optJSONObject("playlistPanelVideoRenderer")?.let { out.add(it) }
                val keys = node.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    if (k != "playlistPanelVideoRenderer") {
                        collectPlaylistPanelVideoRenderers(node.opt(k), out)
                    }
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    collectPlaylistPanelVideoRenderers(node.opt(i), out)
                }
            }
        }
    }

    private fun fetchTrendingHomeTracks(
        activeExt: LoadedExtension?,
        chipParams: String? = null,
    ): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        if (activeExt != null) {
            val extFeedTracks = runCatching {
                executeInExtension(activeExt) { cx, scope, extObj ->
                    val fn = (ScriptableObject.getProperty(extObj, "getHomeFeed") as? RhinoFunction)
                        ?: (ScriptableObject.getProperty(scope, "getHomeFeed") as? RhinoFunction)
                        ?: return@executeInExtension emptyList<Map<String, Any?>>()
                    val raw = jsToKotlin(fn.call(cx, scope, extObj, emptyArray()))
                    val sections = when (raw) {
                        is Map<*, *> -> (raw["sections"] as? List<*>) ?: (raw["items"] as? List<*>) ?: emptyList<Any?>()
                        is List<*> -> raw
                        else -> emptyList<Any?>()
                    }
                    val collected = mutableListOf<Map<String, Any?>>()
                    for (sec in sections) {
                        val secMap = sec as? Map<*, *> ?: continue
                        val items = (secMap["items"] as? List<*>) ?: (secMap["tracks"] as? List<*>) ?: continue
                        for (it in items) {
                            val itemMap = it as? Map<*, *> ?: continue
                            val norm = normalizeTrackMap(itemMap, activeExt, "track")
                            if (norm["item_type"] == "track" && !norm["title"]?.toString().isNullOrBlank()) {
                                collected.add(norm)
                            }
                        }
                    }
                    collected
                }
            }.getOrDefault(emptyList())
            out.addAll(extFeedTracks)
        }
        if (out.size < 14) {
            out.addAll(browseYtMusicChartsSongs(limit = 18))
        }
        if (out.size < 14) {
            out.addAll(searchYtMusicSongsOnly("Top Global Trending Hits", params = "EgWKAQIIAWoKEAkQBRAKEAMQBA==", limit = 16))
        }
        return out
    }

    private fun browseYtMusicChartsSongs(limit: Int): List<Map<String, Any?>> {
        val root = postYtMusicWebRemix("browse") {
            put("browseId", "FEmusic_charts")
        } ?: return emptyList()
        return parseSongsFromYtBrowseRoot(root, limit)
    }

    private fun browseYtMusicHomeSongsAndChips(
        chipParams: String? = null,
        limit: Int = 24,
    ): Pair<List<Map<String, Any?>>, List<Map<String, String>>> {
        val root = postYtMusicWebRemix("browse") {
            put("browseId", "FEmusic_home")
            if (!chipParams.isNullOrBlank()) {
                put("params", chipParams)
            }
        } ?: return emptyList<Map<String, Any?>>() to emptyList()

        val chips = parseYtMusicHomeChips(root)
        val songs = parseSongsFromYtBrowseRoot(root, limit)
        return songs to chips
    }

    private fun parseYtMusicHomeChips(root: JSONObject): List<Map<String, String>> {
        val chipRenderers = mutableListOf<JSONObject>()
        collectObjectsByKey(root, "chipCloudChipRenderer", chipRenderers)
        val out = mutableListOf<Map<String, String>>()
        val seenTitles = mutableSetOf<String>()
        for (renderer in chipRenderers) {
            val title = renderer.optJSONObject("text")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim()
                ?: renderer.optJSONObject("text")?.optString("simpleText")?.trim()
                ?: continue
            if (title.isEmpty() || !seenTitles.add(title.lowercase(Locale.ROOT))) continue
            val endpoint = renderer.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint") ?: continue
            val params = endpoint.optString("params").trim()
            if (params.isEmpty()) continue
            val browseId = endpoint.optString("browseId").trim().ifBlank { "FEmusic_home" }
            out.add(
                mapOf(
                    "title" to title,
                    "params" to params,
                    "browseId" to browseId,
                )
            )
        }
        return out
    }

    private fun collectObjectsByKey(node: Any?, targetKey: String, out: MutableList<JSONObject>) {
        when (node) {
            is JSONObject -> {
                node.optJSONObject(targetKey)?.let { out.add(it) }
                val keys = node.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    if (k != targetKey) {
                        collectObjectsByKey(node.opt(k), targetKey, out)
                    }
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    collectObjectsByKey(node.opt(i), targetKey, out)
                }
            }
        }
    }

    private fun parseSongsFromYtBrowseRoot(root: JSONObject, limit: Int): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seenIds = mutableSetOf<String>()

        val responsiveRenderers = mutableListOf<JSONObject>()
        collectMusicResponsiveRenderers(root, responsiveRenderers)
        for (item in responsiveRenderers) {
            val videoId = item.optJSONObject("playlistItemData")?.optString("videoId")?.takeIf { it.isNotBlank() }
                ?: findStringByKey(item, "videoId")?.takeIf { it.length == 11 }
                ?: continue
            if (!seenIds.add(videoId)) continue
            val flexCols = item.optJSONArray("flexColumns") ?: continue
            val title = flexCols.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optString("text")
                ?.trim()
                .orEmpty()
            if (title.isEmpty()) continue
            val subRuns = flexCols.optJSONObject(1)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
            val artists = mutableListOf<String>()
            if (subRuns != null) {
                for (i in 0 until subRuns.length()) {
                    val t = subRuns.optJSONObject(i)?.optString("text")?.trim().orEmpty()
                    if (t.isNotEmpty() && t != "•" && t != "·" && t != "&" && t != "," && !t.equals("Song", ignoreCase = true) && !t.equals("Video", ignoreCase = true)) {
                        artists.add(t)
                        break
                    }
                }
            }
            val artistStr = artists.joinToString(", ")
            results.add(
                mapOf(
                    "id" to videoId,
                    "spotify_id" to videoId,
                    "item_type" to "track",
                    "name" to title,
                    "title" to title,
                    "artists" to artistStr,
                    "artist" to artistStr,
                    "album_name" to "",
                    "album" to "",
                    "duration_ms" to 0L,
                    "cover_url" to extractBestThumbnail(item),
                    "provider_id" to "ytmusic",
                    "provider_name" to "YouTube Music",
                    "external_urls" to "https://music.youtube.com/watch?v=$videoId",
                )
            )
            if (results.size >= limit) return results
        }

        val twoRowRenderers = mutableListOf<JSONObject>()
        collectMusicTwoRowRenderers(root, twoRowRenderers)
        for (item in twoRowRenderers) {
            val videoId = item.optJSONObject("navigationEndpoint")?.optJSONObject("watchEndpoint")?.optString("videoId")?.takeIf { it.length == 11 }
                ?: findStringByKey(item, "videoId")?.takeIf { it.length == 11 }
                ?: continue
            if (!seenIds.add(videoId)) continue
            val title = item.optJSONObject("title")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim().orEmpty()
            if (title.isEmpty()) continue
            val subRuns = item.optJSONObject("subtitle")?.optJSONArray("runs")
            val artists = mutableListOf<String>()
            if (subRuns != null) {
                for (i in 0 until subRuns.length()) {
                    val t = subRuns.optJSONObject(i)?.optString("text")?.trim().orEmpty()
                    if (t.isNotEmpty() && t != "•" && t != "·" && t != "&" && t != "," && !t.equals("Song", ignoreCase = true) && !t.equals("Video", ignoreCase = true)) {
                        artists.add(t)
                        break
                    }
                }
            }
            val artistStr = artists.joinToString(", ")
            results.add(
                mapOf(
                    "id" to videoId,
                    "spotify_id" to videoId,
                    "item_type" to "track",
                    "name" to title,
                    "title" to title,
                    "artists" to artistStr,
                    "artist" to artistStr,
                    "album_name" to "",
                    "album" to "",
                    "duration_ms" to 0L,
                    "cover_url" to extractBestThumbnail(item),
                    "provider_id" to "ytmusic",
                    "provider_name" to "YouTube Music",
                    "external_urls" to "https://music.youtube.com/watch?v=$videoId",
                )
            )
            if (results.size >= limit) return results
        }
        return results
    }

    private fun collectMusicTwoRowRenderers(node: Any?, out: MutableList<JSONObject>) {
        when (node) {
            is JSONObject -> {
                val renderer = node.optJSONObject("musicTwoRowItemRenderer")
                if (renderer != null) {
                    out.add(renderer)
                }
                val keys = node.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    if (k != "musicTwoRowItemRenderer") {
                        collectMusicTwoRowRenderers(node.opt(k), out)
                    }
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    collectMusicTwoRowRenderers(node.opt(i), out)
                }
            }
        }
    }

    private fun collectMusicResponsiveRenderers(node: Any?, out: MutableList<JSONObject>) {
        when (node) {
            is JSONObject -> {
                val renderer = node.optJSONObject("musicResponsiveListItemRenderer")
                if (renderer != null) {
                    out.add(renderer)
                }
                val keys = node.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    if (k != "musicResponsiveListItemRenderer") {
                        collectMusicResponsiveRenderers(node.opt(k), out)
                    }
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    collectMusicResponsiveRenderers(node.opt(i), out)
                }
            }
        }
    }

    private fun findStringByKey(node: Any?, targetKey: String): String? {
        when (node) {
            is JSONObject -> {
                if (node.has(targetKey)) {
                    val v = node.optString(targetKey)
                    if (v.isNotBlank()) return v
                }
                val keys = node.keys()
                while (keys.hasNext()) {
                    val found = findStringByKey(node.opt(keys.next()), targetKey)
                    if (!found.isNullOrBlank()) return found
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    val found = findStringByKey(node.opt(i), targetKey)
                    if (!found.isNullOrBlank()) return found
                }
            }
        }
        return null
    }

    private fun findHeaderTitle(root: JSONObject): String {
        for (headerKey in listOf("musicImmersiveHeaderRenderer", "musicResponsiveHeaderRenderer", "musicVisualHeaderRenderer", "musicDetailHeaderRenderer")) {
            val header = findObjectByKey(root, headerKey) ?: continue
            val text = header.optJSONObject("title")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")?.trim()
            if (!text.isNullOrBlank()) return text
        }
        return ""
    }

    private fun findObjectByKey(node: Any?, targetKey: String): JSONObject? {
        when (node) {
            is JSONObject -> {
                node.optJSONObject(targetKey)?.let { return it }
                val keys = node.keys()
                while (keys.hasNext()) {
                    findObjectByKey(node.opt(keys.next()), targetKey)?.let { return it }
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    findObjectByKey(node.opt(i), targetKey)?.let { return it }
                }
            }
        }
        return null
    }

    private fun extractBestThumbnail(node: JSONObject): String {
        val thumbs = findObjectByKey(node, "musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?.optJSONArray("thumbnails")
            ?: node.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
            ?: return ""
        if (thumbs.length() == 0) return ""
        var rawUrl = thumbs.optJSONObject(thumbs.length() - 1)?.optString("url")?.trim().orEmpty()
        if (rawUrl.startsWith("//")) {
            rawUrl = "https:$rawUrl"
        }
        if ((rawUrl.contains("googleusercontent.com") || rawUrl.contains("ggpht.com")) && rawUrl.contains("=w")) {
            return rawUrl.replace(Regex("=w\\d+-h\\d+[^&]*"), "=w544-h544-l90-rj")
        }
        return rawUrl
    }

    private fun parseColonDurationMs(text: String): Long {
        val parts = text.trim().split(":").mapNotNull { it.toLongOrNull() }
        val seconds = when (parts.size) {
            2 -> parts[0] * 60L + parts[1]
            3 -> parts[0] * 3600L + parts[1] * 60L + parts[2]
            else -> 0L
        }
        return seconds * 1000L
    }

    /**
     * Local loopback HTTP proxy (`127.0.0.1:<port>`) modelled on LastWave-Native's
     * `ChunkedRangeDataSource` and `HybridMediaServer`.
     *
     * Accepts standard HTTP / Range requests from Flutter's `just_audio` (ExoPlayer)
     * and fetches upstream `googlevideo.com` audio streams in bounded 512 KB
     * `Range: bytes=start-end` chunks using the minting InnerTube client's exact
     * `User-Agent`, preventing YouTube's HTTP 403 and open-range throttling.
     */
    private inner class LocalYtStreamProxy {
        private val streams = ConcurrentHashMap<String, ResolvedYtStream>()
        private val lazyStreams = ConcurrentHashMap<String, Pair<Long, ResolvedYtStream>>()
        private val lazyLocks = ConcurrentHashMap<String, Any>()
        private val serverSocket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        val port: Int = serverSocket.localPort

        init {
            Thread({
                while (!serverSocket.isClosed) {
                    val client = runCatching { serverSocket.accept() }.getOrNull() ?: break
                    searchPool.execute {
                        // The player hangs up mid-stream whenever it skips,
                        // seeks or stops: that ends this stream, never the app.
                        try {
                            handleClient(client)
                        } catch (_: Exception) {
                            runCatching { client.close() }
                        }
                    }
                }
            }, "noctune-yt-stream-proxy").apply {
                isDaemon = true
                start()
            }
        }

        private fun buildLazyCacheKey(rawTrack: Map<String, Any?>): String {
            val providerId = (rawTrack["provider_id"] ?: "").toString().trim().lowercase(Locale.ROOT)
            val id = (rawTrack["id"] ?: "").toString().trim()
            val title = (rawTrack["title"] ?: rawTrack["name"] ?: "").toString().trim().lowercase(Locale.ROOT)
            val artist = (rawTrack["artist"] ?: rawTrack["artists"] ?: "").toString().trim().lowercase(Locale.ROOT)
            return "$providerId:$id:$title:$artist"
        }

        fun registerStream(
            videoId: String,
            stream: ResolvedYtStream,
            rawTrack: Map<String, Any?>? = null,
        ): String {
            val token = "${videoId}_${System.currentTimeMillis()}"
            streams[token] = stream
            if (rawTrack != null) {
                lazyStreams[buildLazyCacheKey(rawTrack)] = System.currentTimeMillis() to stream
            }
            return "http://127.0.0.1:$port/ytstream/$token"
        }

        private fun resolveLazyEntry(path: String): ResolvedYtStream? {
            val query = path.substringAfter('?', "")
            if (query.isEmpty()) return null
            val params = mutableMapOf<String, String>()
            for (part in query.split("&")) {
                if (part.isEmpty()) continue
                val eq = part.indexOf('=')
                if (eq > 0) {
                    val k = runCatching { URLDecoder.decode(part.substring(0, eq), "UTF-8") }.getOrDefault("")
                    val v = runCatching { URLDecoder.decode(part.substring(eq + 1), "UTF-8") }.getOrDefault("")
                    if (k.isNotEmpty()) params[k] = v
                }
            }
            val trackMap = mapOf<String, Any?>(
                "id" to (params["id"] ?: ""),
                "provider_id" to (params["provider_id"] ?: ""),
                "title" to (params["title"] ?: ""),
                "name" to (params["title"] ?: ""),
                "artist" to (params["artist"] ?: ""),
                "artists" to (params["artist"] ?: ""),
                "duration_ms" to (params["duration_ms"]?.toLongOrNull() ?: 0L),
            )
            val cacheKey = buildLazyCacheKey(trackMap)
            val lockObj = lazyLocks.computeIfAbsent(cacheKey) { Any() }
            return synchronized(lockObj) {
                val now = System.currentTimeMillis()
                val cached = lazyStreams[cacheKey]
                if (cached != null && now - cached.first < 20 * 60 * 1000L) {
                    cached.second
                } else {
                    runCatching { resolveStreamObjectForTrack(trackMap) }.getOrNull()?.also { resolved ->
                        lazyStreams[cacheKey] = now to resolved
                    }
                }
            }
        }

        private fun handleClient(socket: Socket) {
            socket.use { sock ->
                sock.soTimeout = 30_000
                val input = sock.getInputStream().bufferedReader(StandardCharsets.US_ASCII)
                val requestLine = input.readLine() ?: return
                val parts = requestLine.split(" ")
                if (parts.size < 2) return
                val method = parts[0].uppercase(Locale.ROOT)
                val path = parts[1]

                var rangeHeader: String? = null
                while (true) {
                    val line = input.readLine()
                    if (line.isNullOrEmpty()) break
                    if (line.startsWith("Range:", ignoreCase = true)) {
                        rangeHeader = line.substringAfter(':').trim()
                    }
                }

                val entry = if (path.startsWith("/ytlazy")) {
                    resolveLazyEntry(path)
                } else {
                    val token = path.substringAfter("/ytstream/", "").substringBefore('?').trim()
                    streams[token]
                }
                val out = sock.getOutputStream()
                if (entry == null) {
                    out.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
                    out.flush()
                    return
                }

                var reqStart = 0L
                var reqEnd = if (entry.contentLength > 0L) entry.contentLength - 1L else -1L
                val isPartial = !rangeHeader.isNullOrBlank() && rangeHeader.startsWith("bytes=", ignoreCase = true)
                if (isPartial) {
                    val spec = rangeHeader!!.substringAfter("bytes=", "").trim()
                    val dash = spec.indexOf('-')
                    if (dash >= 0) {
                        reqStart = spec.substring(0, dash).trim().toLongOrNull() ?: 0L
                        val endPart = spec.substring(dash + 1).trim()
                        if (endPart.isNotEmpty()) {
                            reqEnd = endPart.toLongOrNull() ?: reqEnd
                        }
                    }
                }

                var totalSize = entry.contentLength
                val chunkWindow = 512L * 1024L

                // If totalSize is unknown, do a quick initial chunk fetch to learn Content-Range total size.
                if (totalSize <= 0L) {
                    val probeLen = probeStreamUrl(entry.url, entry.userAgent) ?: -1L
                    if (probeLen > 0L) {
                        totalSize = probeLen
                        if (reqEnd < 0L || reqEnd >= totalSize) reqEnd = totalSize - 1L
                    }
                } else if (reqEnd < 0L || reqEnd >= totalSize) {
                    reqEnd = totalSize - 1L
                }

                val statusLine = if (isPartial) "HTTP/1.1 206 Partial Content" else "HTTP/1.1 200 OK"
                val headersSb = StringBuilder()
                headersSb.append("$statusLine\r\n")
                headersSb.append("Content-Type: ${entry.mimeType}\r\n")
                headersSb.append("Accept-Ranges: bytes\r\n")
                if (totalSize > 0L && reqEnd >= reqStart) {
                    val contentLen = reqEnd - reqStart + 1L
                    headersSb.append("Content-Length: $contentLen\r\n")
                    if (isPartial) {
                        headersSb.append("Content-Range: bytes $reqStart-$reqEnd/$totalSize\r\n")
                    }
                }
                headersSb.append("Connection: close\r\n\r\n")
                out.write(headersSb.toString().toByteArray(StandardCharsets.US_ASCII))
                out.flush()

                if (method == "HEAD") return

                var cursor = reqStart
                val buf = ByteArray(32 * 1024)
                while (reqEnd < 0L || cursor <= reqEnd) {
                    val chunkEnd = if (reqEnd >= 0L) {
                        min(cursor + chunkWindow - 1L, reqEnd)
                    } else {
                        cursor + chunkWindow - 1L
                    }
                    val conn = (URL(entry.url).openConnection() as HttpURLConnection).apply {
                        requestMethod = "GET"
                        connectTimeout = 10_000
                        readTimeout = 15_000
                        instanceFollowRedirects = true
                        setRequestProperty("User-Agent", entry.userAgent)
                        setRequestProperty("Range", "bytes=$cursor-$chunkEnd")
                    }
                    val code = conn.responseCode
                    if (code !in 200..299) {
                        conn.disconnect()
                        break
                    }
                    var chunkBytesRead = 0L
                    try {
                        conn.inputStream.use { upstream ->
                            while (true) {
                                val r = upstream.read(buf)
                                if (r <= 0) break
                                out.write(buf, 0, r)
                                cursor += r
                                chunkBytesRead += r
                            }
                        }
                    } finally {
                        conn.disconnect()
                    }
                    out.flush()
                    if (chunkBytesRead <= 0L || (reqEnd < 0L && chunkBytesRead < (chunkEnd - (cursor - chunkBytesRead) + 1L))) {
                        break
                    }
                }
            }
        }
    }
}
