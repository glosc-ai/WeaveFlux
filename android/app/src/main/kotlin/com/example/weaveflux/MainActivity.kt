package com.example.weaveflux

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "weaveflux/go_core"
    private val mediaStoreChannelName = "weaveflux/media_store"
    private lateinit var goCoreChannel: MethodChannel

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
                    runGoBridgeCall(result) {
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
                else -> result.notImplemented()
            }
        }
    }

    private fun exportVideoToGallery(localPath: String, displayName: String) {
        val source = File(localPath)
        require(source.exists() && source.isFile) { "Video file does not exist: $localPath" }

        val safeName = sanitizeVideoName(
            if (displayName.isBlank()) source.name else displayName,
        )
        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, safeName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/WeaveFlux")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.IS_PENDING, 1)
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
                    put(MediaStore.Video.Media.IS_PENDING, 0)
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

    private fun invokeGoJsonMethod(methodName: String, baseUrl: String, apiKey: String): Map<String, Any> {
        return invokeGoJsonMethod(methodName, listOf(baseUrl, apiKey))
    }

    private fun runGoBridgeCall(result: MethodChannel.Result, block: () -> Map<String, Any>) {
        Thread {
            try {
                val payload = block()
                runOnUiThread { result.success(payload) }
            } catch (exception: Throwable) {
                runOnUiThread {
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
                runOnUiThread {
                    goCoreChannel.invokeMethod(
                        "taskStatusChanged",
                        mapOf(
                            "task_id" to taskId,
                            "status" to status,
                            "video_url" to videoUrl,
                            "error" to errStr,
                        ),
                    )
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
