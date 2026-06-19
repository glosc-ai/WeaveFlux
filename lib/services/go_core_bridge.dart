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
    required this.error,
  });

  final String taskId;
  final String error;

  bool get success => taskId.isNotEmpty && error.isEmpty;
}
