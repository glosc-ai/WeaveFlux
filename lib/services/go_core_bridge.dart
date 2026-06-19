import 'package:flutter/services.dart';

class GoCoreBridge {
  GoCoreBridge._();

  static const MethodChannel _channel = MethodChannel('weaveflux/go_core');

  static Future<ConnectionTestResult> testConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'testConnection',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      },
    );

    return ConnectionTestResult(
      success: raw?['success'] == true,
      error: raw?['error'] as String? ?? 'Unknown connection result',
    );
  }

  static Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'fetchModels',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      },
    );

    final rawModels = raw?['models'];
    final models = rawModels is List
        ? rawModels
            .whereType<String>()
            .where((model) => model.isNotEmpty)
            .toList()
        : <String>[];

    return ModelFetchResult(
      success: raw?['success'] == true,
      models: models,
      error: raw?['error'] as String? ?? 'Unknown models result',
      debug: raw?['debug'] as String? ?? '',
    );
  }

  static Future<DispatchVideoTaskResult> dispatchVideoTask({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String size,
    required double motionScale,
    required String imageBase64,
  }) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'dispatchVideoTask',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'prompt': prompt,
        'size': size,
        'motionScale': motionScale.toStringAsFixed(3),
        'imageBase64': imageBase64,
      },
    );

    return DispatchVideoTaskResult(
      taskId: raw?['task_id'] as String? ?? '',
      error: raw?['error'] as String? ?? 'Unknown dispatch result',
    );
  }
}

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.success,
    required this.error,
  });

  final bool success;
  final String error;
}

class ModelFetchResult {
  const ModelFetchResult({
    required this.success,
    required this.models,
    required this.error,
    required this.debug,
  });

  final bool success;
  final List<String> models;
  final String error;
  final String debug;
}

class DispatchVideoTaskResult {
  const DispatchVideoTaskResult({
    required this.taskId,
    required this.error,
  });

  final String taskId;
  final String error;

  bool get success => taskId.isNotEmpty && error.isEmpty;
}
