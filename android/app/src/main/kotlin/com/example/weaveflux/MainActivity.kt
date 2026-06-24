package com.example.weaveflux

import android.content.ContentValues
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import androidx.core.content.FileProvider
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "weaveflux/go_core"
    private val mediaStoreChannelName = "weaveflux/media_store"
    private val updateChannelName = "weaveflux/update"
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var goCoreChannel: MethodChannel
    private lateinit var updateChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        goCoreChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        goCoreChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "testConnection" -> {
                    val baseUrl = call.argument<String>("baseUrl").orEmpty()
                    val apiKey = call.argument<String>("apiKey").orEmpty()
                    runGoBridgeCall(result) {
                        invokeGoJsonMethod("testConnection", baseUrl, apiKey)
                    }
                }
                "fetchModels" -> {
                    val baseUrl = call.argument<String>("baseUrl").orEmpty()
                    val apiKey = call.argument<String>("apiKey").orEmpty()
                    runGoBridgeCall(result) {
                        invokeGoJsonMethod("fetchModels", baseUrl, apiKey)
                    }
                }
                "dispatchVideoTask" -> {
                    val args = listOf(
                        call.argument<String>("baseUrl").orEmpty(),
                        call.argument<String>("apiKey").orEmpty(),
                        call.argument<String>("payload").orEmpty(),
                    )
                    runGoBridgeCall(result) {
                        invokeGoJsonMethod("dispatchVideoTaskV2", args)
                    }
                }
                "dispatchImageTask" -> {
                    val args = listOf(
                        call.argument<String>("baseUrl").orEmpty(),
                        call.argument<String>("apiKey").orEmpty(),
                        call.argument<String>("payload").orEmpty(),
                    )
                    runGoBridgeCall(
                        result,
                        timeoutMs = 25_000L,
                        timeoutPayload = mapOf(
                            "success" to false,
                            "error" to "Go core request timed out after 25 seconds",
                            "debug" to "",
                            "task_id" to "",
                            "status" to "",
                            "result_url" to "",
                            "result_b64" to "",
                        ),
                    ) {
                        invokeGoJsonMethod("dispatchImageTask", args)
                    }
                }
                "queryTask" -> {
                    val args = listOf(
                        call.argument<String>("baseUrl").orEmpty(),
                        call.argument<String>("apiKey").orEmpty(),
                        call.argument<String>("taskId").orEmpty(),
                    )
                    runGoBridgeCall(result) {
                        invokeGoJsonMethod("queryTask", args)
                    }
                }
                "startPollingTask" -> {
                    val baseUrl = call.argument<String>("baseUrl").orEmpty()
                    val apiKey = call.argument<String>("apiKey").orEmpty()
                    val taskId = call.argument<String>("taskId").orEmpty()
                    runGoBridgeCall(result) {
                        startGoPollingTask(baseUrl, apiKey, taskId)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaStoreChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportVideoToGallery" -> {
                    val localPath = call.argument<String>("localPath").orEmpty()
                    val displayName = call.argument<String>("displayName").orEmpty()
                    Thread {
                        try {
                            exportVideoToGallery(localPath, displayName)
                            runOnUiThread { result.success(null) }
                        } catch (error: Throwable) {
                            runOnUiThread {
                                result.error(
                                    "EXPORT_FAILED",
                                    error.message ?: "Failed to export video",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                "exportImageToGallery" -> {
                    val localPath = call.argument<String>("localPath").orEmpty()
                    val displayName = call.argument<String>("displayName").orEmpty()
                    Thread {
                        try {
                            exportImageToGallery(localPath, displayName)
                            runOnUiThread { result.success(null) }
                        } catch (error: Throwable) {
                            runOnUiThread {
                                result.error(
                                    "EXPORT_FAILED",
                                    error.message ?: "Failed to export image",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateChannelName,
        )
        updateChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadApk" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val displayName = call.argument<String>("displayName").orEmpty()
                    Thread {
                        try {
                            val path = downloadApkWithSystemManager(url, displayName)
                            mainHandler.post { result.success(path) }
                        } catch (error: Throwable) {
                            mainHandler.post {
                                result.error(
                                    "DOWNLOAD_FAILED",
                                    error.message ?: "Failed to download APK",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath").orEmpty()
                    Thread {
                        try {
                            val apk = validateApkFile(apkPath)
                            mainHandler.post {
                                try {
                                    openApkInstaller(apk)
                                    result.success(null)
                                } catch (error: Throwable) {
                                    result.error(
                                        "INSTALL_FAILED",
                                        error.message ?: "Failed to open APK installer",
                                        null,
                                    )
                                }
                            }
                        } catch (error: Throwable) {
                            mainHandler.post {
                                result.error(
                                    "INSTALL_FAILED",
                                    error.message ?: "Failed to prepare APK installer",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun downloadApkWithSystemManager(url: String, displayName: String): String {
        require(url.isNotBlank()) { "APK download URL is empty" }
        val safeName = sanitizeApkName(displayName)
        val existing = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?.resolve(safeName)
        if (existing != null && existing.exists()) {
            existing.delete()
        }

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle("WeaveFlux update")
            setDescription(safeName)
            setMimeType("application/vnd.android.package-archive")
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            setDestinationInExternalFilesDir(
                this@MainActivity,
                Environment.DIRECTORY_DOWNLOADS,
                safeName,
            )
        }
        val downloadId = manager.enqueue(request)
        val query = DownloadManager.Query().setFilterById(downloadId)
        var lastProgress = -1
        val startedAt = System.currentTimeMillis()

        while (true) {
            manager.query(query)?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    throw IllegalStateException("Download disappeared")
                }
                val status = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS),
                )
                val downloaded = cursor.getLong(
                    cursor.getColumnIndexOrThrow(
                        DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
                    ),
                )
                val total = cursor.getLong(
                    cursor.getColumnIndexOrThrow(
                        DownloadManager.COLUMN_TOTAL_SIZE_BYTES,
                    ),
                )
                if (total > 0) {
                    val percent = ((downloaded * 100) / total).toInt()
                    if (percent != lastProgress) {
                        lastProgress = percent
                        postUpdateDownloadProgress(percent / 100.0)
                    }
                }

                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        postUpdateDownloadProgress(1.0)
                        val localUri = cursor.getString(
                            cursor.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_LOCAL_URI,
                            ),
                        )
                        val path = Uri.parse(localUri).path
                            ?: throw IllegalStateException("Download path is empty")
                        return path
                    }
                    DownloadManager.STATUS_FAILED -> {
                        val reason = cursor.getInt(
                            cursor.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_REASON,
                            ),
                        )
                        throw IllegalStateException("Download failed, reason=$reason")
                    }
                }
            } ?: throw IllegalStateException("Unable to query download status")

            if (System.currentTimeMillis() - startedAt > 10 * 60 * 1000L) {
                manager.remove(downloadId)
                throw IllegalStateException("Download timed out after 10 minutes")
            }
            Thread.sleep(1000L)
        }
    }

    private fun postUpdateDownloadProgress(progress: Double) {
        mainHandler.post {
            try {
                updateChannel.invokeMethod(
                    "updateDownloadProgress",
                    mapOf("progress" to progress),
                )
            } catch (error: Throwable) {
                android.util.Log.e("WeaveFlux", "Failed to deliver update progress", error)
            }
        }
    }

    private fun sanitizeApkName(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
        val withFallback = if (cleaned.isBlank()) "weaveflux_update.apk" else cleaned
        return if (withFallback.lowercase().endsWith(".apk")) {
            withFallback
        } else {
            "$withFallback.apk"
        }
    }

    private fun validateApkFile(apkPath: String): File {
        val apk = File(apkPath)
        require(apk.exists() && apk.isFile) { "APK file does not exist: $apkPath" }
        require(apk.extension.equals("apk", ignoreCase = true)) {
            "Invalid APK file: $apkPath"
        }
        return apk
    }

    private fun openApkInstaller(apk: File) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
            throw IllegalStateException(
                "Please allow WeaveFlux to install unknown apps, then retry",
            )
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun exportVideoToGallery(localPath: String, displayName: String) {
        val source = File(localPath)
        require(source.exists() && source.isFile) { "Video file does not exist: $localPath" }

        val safeName = sanitizeVideoName(
            if (displayName.isBlank()) source.name else displayName,
        )
        copyAssetToMediaStore(
            source = source,
            displayName = safeName,
            mimeType = "video/mp4",
            relativePath = "Movies/WeaveFlux",
            collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            pendingColumn = MediaStore.Video.Media.IS_PENDING,
        )
    }

    private fun exportImageToGallery(localPath: String, displayName: String) {
        val source = File(localPath)
        require(source.exists() && source.isFile) { "Image file does not exist: $localPath" }

        val safeName = sanitizeImageName(
            if (displayName.isBlank()) source.name else displayName,
        )
        copyAssetToMediaStore(
            source = source,
            displayName = safeName,
            mimeType = imageMimeType(safeName),
            relativePath = "Pictures/WeaveFlux",
            collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            pendingColumn = MediaStore.Images.Media.IS_PENDING,
        )
    }

    private fun copyAssetToMediaStore(
        source: File,
        displayName: String,
        mimeType: String,
        relativePath: String,
        collection: android.net.Uri,
        pendingColumn: String,
    ) {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(pendingColumn, 1)
            }
        }

        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Failed to create MediaStore item")
        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Failed to open MediaStore output stream")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val completed = ContentValues().apply {
                    put(pendingColumn, 0)
                }
                resolver.update(uri, completed, null, null)
            }
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun sanitizeVideoName(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
        val withFallback = if (cleaned.isBlank()) "weaveflux_video.mp4" else cleaned
        return if (withFallback.lowercase().endsWith(".mp4")) withFallback else "$withFallback.mp4"
    }

    private fun sanitizeImageName(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
        val withFallback = if (cleaned.isBlank()) "weaveflux_image.png" else cleaned
        val lower = withFallback.lowercase()
        return if (lower.endsWith(".png") || lower.endsWith(".jpg") ||
            lower.endsWith(".jpeg") || lower.endsWith(".webp")
        ) {
            withFallback
        } else {
            "$withFallback.png"
        }
    }

    private fun imageMimeType(name: String): String {
        val lower = name.lowercase()
        return when {
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".webp") -> "image/webp"
            else -> "image/png"
        }
    }

    private fun invokeGoJsonMethod(methodName: String, baseUrl: String, apiKey: String): Map<String, Any> {
        return invokeGoJsonMethod(methodName, listOf(baseUrl, apiKey))
    }

    private fun runGoBridgeCall(
        result: MethodChannel.Result,
        timeoutMs: Long = 0L,
        timeoutPayload: Map<String, Any>? = null,
        block: () -> Map<String, Any>,
    ) {
        val completed = AtomicBoolean(false)
        if (timeoutMs > 0L) {
            Thread {
                try {
                    Thread.sleep(timeoutMs)
                } catch (_: InterruptedException) {
                    return@Thread
                }
                if (completed.compareAndSet(false, true)) {
                    if (timeoutPayload != null) {
                        result.success(timeoutPayload)
                    } else {
                        result.error(
                            "GO_TIMEOUT",
                            "Go core request timed out after ${timeoutMs / 1000} seconds",
                            null,
                        )
                    }
                }
            }.start()
        }

        Thread {
            try {
                val payload = block()
                if (completed.compareAndSet(false, true)) {
                    result.success(payload)
                }
            } catch (exception: Throwable) {
                if (completed.compareAndSet(false, true)) {
                    result.error(
                        "GO_ERROR",
                        exception.message ?: exception.toString(),
                        null,
                    )
                }
            }
        }.start()
    }

    private fun invokeGoJsonMethod(methodName: String, args: List<String>): Map<String, Any> {
        val bridgeClass = findGoBridgeClass()
        val parameterTypes = Array(args.size) { String::class.java }
        val method = bridgeClass.getMethod(methodName, *parameterTypes)
        val json = method.invoke(null, *args.toTypedArray()) as String
        val payload = JSONObject(json)
        val result = mutableMapOf<String, Any>(
            "success" to payload.optBoolean("success", false),
            "error" to payload.optString("error", ""),
            "debug" to payload.optString("debug", ""),
            "task_id" to payload.optString("task_id", ""),
            "status" to payload.optString("status", ""),
            "result_url" to payload.optString("result_url", ""),
            "result_b64" to payload.optString("result_b64", ""),
        )
        val models = payload.optJSONArray("models")
        if (models != null) {
            result["models"] = List(models.length()) { index -> models.optString(index) }
        }
        val videoModels = payload.optJSONArray("video_models")
        if (videoModels != null) {
            result["video_models"] = List(videoModels.length()) { index -> videoModels.optString(index) }
        }
        val imageModels = payload.optJSONArray("image_models")
        if (imageModels != null) {
            result["image_models"] = List(imageModels.length()) { index -> imageModels.optString(index) }
        }
        return result
    }

    private fun startGoPollingTask(baseUrl: String, apiKey: String, taskId: String): Map<String, Any> {
        val bridgeClass = findGoBridgeClass()
        val listenerClass = findGoListenerClass()
        val listener = java.lang.reflect.Proxy.newProxyInstance(
            listenerClass.classLoader,
            arrayOf(listenerClass),
        ) { _, method, args ->
            if (method.name == "onStatusChanged") {
                val status = args?.getOrNull(0) as? String ?: ""
                val videoUrl = args?.getOrNull(1) as? String ?: ""
                val errStr = args?.getOrNull(2) as? String ?: ""
                mainHandler.post {
                    try {
                        goCoreChannel.invokeMethod(
                            "taskStatusChanged",
                            mapOf(
                                "task_id" to taskId,
                                "status" to status,
                                "video_url" to videoUrl,
                                "error" to errStr,
                            ),
                        )
                    } catch (exception: Throwable) {
                        android.util.Log.e(
                            "WeaveFlux",
                            "Failed to deliver task status callback",
                            exception,
                        )
                    }
                }
            }
            null
        }
        val method = bridgeClass.getMethod(
            "startPollingTask",
            String::class.java,
            String::class.java,
            String::class.java,
            listenerClass,
        )
        method.invoke(null, baseUrl, apiKey, taskId, listener)
        return mapOf("success" to true, "error" to "")
    }

    private fun findGoBridgeClass(): Class<*> {
        val candidates = listOf(
            "weavefluxcore.Weavefluxcore",
            "go.weavefluxcore.Weavefluxcore",
        )

        for (name in candidates) {
            try {
                return Class.forName(name)
            } catch (_: ClassNotFoundException) {
                // 兼容不同 gomobile 绑定包名前缀。
            }
        }
        throw ClassNotFoundException("weavefluxcore.Weavefluxcore")
    }

    private fun findGoListenerClass(): Class<*> {
        val candidates = listOf(
            "weavefluxcore.GoStatusListener",
            "go.weavefluxcore.GoStatusListener",
        )

        for (name in candidates) {
            try {
                return Class.forName(name)
            } catch (_: ClassNotFoundException) {
                // 兼容不同 gomobile 绑定包名前缀。
            }
        }
        throw ClassNotFoundException("weavefluxcore.GoStatusListener")
    }
}
