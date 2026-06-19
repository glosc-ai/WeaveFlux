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
                        call.argument<String>("model").orEmpty(),
                        call.argument<String>("prompt").orEmpty(),
                        call.argument<String>("size").orEmpty(),
                        call.argument<String>("motionScale").orEmpty(),
                        call.argument<String>("imageBase64").orEmpty(),
                    )
                    Thread {
                        val payload = invokeGoJsonMethod("dispatchVideoTask", args)
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
            )
            val models = payload.optJSONArray("models")
            if (models != null) {
                result["models"] = List(models.length()) { index -> models.optString(index) }
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
