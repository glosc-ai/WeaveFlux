import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GoCoreBridge {
  GoCoreBridge._();

  static const MethodChannel _channel = MethodChannel('weaveflux/go_core');
  static Future<void> Function(NativeTaskStatusUpdate update)?
      _taskStatusHandler;
  static bool _methodHandlerConfigured = false;

  static Future<Map<String, Object?>?> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
    } catch (e, stack) {
      debugPrint('❌ [MethodChannel Error]: $e \n Stack: $stack');
      rethrow;
    }
  }

  static void configureTaskStatusHandler(
    Future<void> Function(NativeTaskStatusUpdate update) handler,
  ) {
    _taskStatusHandler = handler;
    if (_methodHandlerConfigured) return;
    _methodHandlerConfigured = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'taskStatusChanged') return null;
      final raw = call.arguments;
      if (raw is! Map) return null;
      final handler = _taskStatusHandler;
      if (handler == null) return null;
      await handler(
        NativeTaskStatusUpdate(
          taskId: raw['task_id'] as String? ?? '',
          status: raw['status'] as String? ?? '',
          videoUrl: raw['video_url'] as String? ?? '',
          error: raw['error'] as String? ?? '',
        ),
      );
      return null;
    });
  }

  static Future<ConnectionTestResult> testConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    final raw = await _invokeMap(
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
    final raw = await _invokeMap(
      'fetchModels',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      },
    );

    final models = _readStringList(raw?['models']);
    final videoModels = _readStringList(raw?['video_models']);
    final imageModels = _readStringList(raw?['image_models']);
    final fallbackImageModels = imageModels.isEmpty
        ? models.where(_looksLikeImageModel).toList()
        : imageModels;

    return ModelFetchResult(
      success: raw?['success'] == true,
      models: models,
      videoModels: videoModels.isEmpty ? models : videoModels,
      imageModels: fallbackImageModels,
      error: raw?['error'] as String? ?? 'Unknown models result',
      debug: raw?['debug'] as String? ?? '',
    );
  }

  static List<String> _readStringList(Object? raw) {
    return raw is List
        ? raw.whereType<String>().where((model) => model.isNotEmpty).toList()
        : <String>[];
  }

  static bool _looksLikeImageModel(String model) {
    final value = model.toLowerCase();
    const keywords = [
      'image',
      'img',
      't2i',
      'i2i',
      'flux',
      'sdxl',
      'stable-diffusion',
      'dall-e',
      'imagen',
      'midjourney',
      'gpt-image',
      'seedream',
    ];
    return keywords.any(value.contains);
  }

  static Future<DispatchVideoTaskResult> dispatchVideoTask({
    required String baseUrl,
    required String apiKey,
    required Map<String, Object?> payload,
  }) async {
    final raw = await _invokeMap(
      'dispatchVideoTask',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'payload': jsonEncode(payload),
      },
    );

    return DispatchVideoTaskResult(
      taskId: raw?['task_id'] as String? ?? '',
      status: raw?['status'] as String? ?? '',
      resultUrl: raw?['result_url'] as String? ?? '',
      resultBase64: raw?['result_b64'] as String? ?? '',
      error: raw?['error'] as String? ?? 'Unknown dispatch result',
    );
  }

  static Future<DispatchVideoTaskResult> dispatchImageTask({
    required String baseUrl,
    required String apiKey,
    required Map<String, Object?> payload,
  }) async {
    final raw = await _invokeMap(
      'dispatchImageTask',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'payload': jsonEncode(payload),
      },
    );

    return DispatchVideoTaskResult(
      taskId: raw?['task_id'] as String? ?? '',
      status: raw?['status'] as String? ?? '',
      resultUrl: raw?['result_url'] as String? ?? '',
      resultBase64: raw?['result_b64'] as String? ?? '',
      error: raw?['error'] as String? ?? 'Unknown image dispatch result',
    );
  }

  static Future<TaskStatusResult> queryTask({
    required String baseUrl,
    required String apiKey,
    required String taskId,
  }) async {
    final raw = await _invokeMap(
      'queryTask',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'taskId': taskId,
      },
    );

    return TaskStatusResult(
      success: raw?['success'] == true,
      status: raw?['status'] as String? ?? '',
      resultUrl: raw?['result_url'] as String? ?? '',
      resultBase64: raw?['result_b64'] as String? ?? '',
      error: raw?['error'] as String? ?? 'Unknown task status result',
    );
  }

  static Future<ConnectionTestResult> startPollingTask({
    required String baseUrl,
    required String apiKey,
    required String taskId,
  }) async {
    final raw = await _invokeMap(
      'startPollingTask',
      <String, Object?>{
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'taskId': taskId,
      },
    );

    return ConnectionTestResult(
      success: raw?['success'] == true,
      error: raw?['error'] as String? ?? 'Unknown polling start result',
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
    required this.videoModels,
    required this.imageModels,
    required this.error,
    required this.debug,
  });

  final bool success;
  final List<String> models;
  final List<String> videoModels;
  final List<String> imageModels;
  final String error;
  final String debug;
}

class DispatchVideoTaskResult {
  const DispatchVideoTaskResult({
    required this.taskId,
    required this.status,
    required this.resultUrl,
    required this.resultBase64,
    required this.error,
  });

  final String taskId;
  final String status;
  final String resultUrl;
  final String resultBase64;
  final String error;

  bool get success => taskId.isNotEmpty && error.isEmpty;
}

class TaskStatusResult {
  const TaskStatusResult({
    required this.success,
    required this.status,
    required this.resultUrl,
    required this.resultBase64,
    required this.error,
  });

  final bool success;
  final String status;
  final String resultUrl;
  final String resultBase64;
  final String error;
}

class NativeTaskStatusUpdate {
  const NativeTaskStatusUpdate({
    required this.taskId,
    required this.status,
    required this.videoUrl,
    required this.error,
  });

  final String taskId;
  final String status;
  final String videoUrl;
  final String error;
}
