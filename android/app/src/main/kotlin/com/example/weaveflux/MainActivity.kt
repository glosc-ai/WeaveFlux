package com.example.weaveflux

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "weaveflux/go_core"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "testConnection" -> {
                    val baseUrl = call.argument<String>("baseUrl").orEmpty()
                    val apiKey = call.argument<String>("apiKey").orEmpty()
                    Thread {
                        val payload = invokeGoJsonMethod("testConnection", baseUrl, apiKey)
                        runOnUiThread { result.success(payload) }
                    }.start()
                }
                "fetchModels" -> {
                    val baseUrl = call.argument<String>("baseUrl").orEmpty()
                    val apiKey = call.argument<String>("apiKey").orEmpty()
                    Thread {
                        val payload = invokeGoJsonMethod("fetchModels", baseUrl, apiKey)
                        runOnUiThread { result.success(payload) }
                    }.start()
                }
                "dispatchVideoTask" -> {
                    val args = listOf(
                        call.argument<String>("baseUrl").orEmpty(),
                        call.argument<String>("apiKey").orEmpty(),
                        call.argument<String>("payload").orEmpty(),
                    )
                    Thread {
                        val payload = invokeGoJsonMethod("dispatchVideoTaskV2", args)
                        runOnUiThread { result.success(payload) }
                    }.start()
                }
                "dispatchImageTask" -> {
                    val args = listOf(
                        call.argument<String>("baseUrl").orEmpty(),
                        call.argument<String>("apiKey").orEmpty(),
                        call.argument<String>("payload").orEmpty(),
                    )
                    Thread {
                        val payload = invokeGoJsonMethod("dispatchImageTask", args)
                        runOnUiThread { result.success(payload) }
                    }.start()
                }
                "queryTask" -> {
                    val args = listOf(
                        call.argument<String>("baseUrl").orEmpty(),
                        call.argument<String>("apiKey").orEmpty(),
                        call.argument<String>("taskId").orEmpty(),
                    )
                    Thread {
                        val payload = invokeGoJsonMethod("queryTask", args)
                        runOnUiThread { result.success(payload) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun invokeGoJsonMethod(methodName: String, baseUrl: String, apiKey: String): Map<String, Any> {
        return invokeGoJsonMethod(methodName, listOf(baseUrl, apiKey))
    }

    private fun invokeGoJsonMethod(methodName: String, args: List<String>): Map<String, Any> {
        return try {
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
            result
        } catch (error: Throwable) {
            mapOf(
                "success" to false,
                "error" to "Go core method $methodName is not available. Rebuild lib/go_core into android/app/libs/weavefluxcore.aar. ${error.message.orEmpty()}",
            )
        }
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
}
