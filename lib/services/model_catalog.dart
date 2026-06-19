import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'go_core_bridge.dart';

class ModelCatalog {
  ModelCatalog._();

  static final ModelCatalog instance = ModelCatalog._();

  static const baseUrlKey = 'wf_base_url';
  static const apiKeyKey = 'wf_api_key';
  static const legacyModelKey = 'wf_selected_model';
  static const selectedVideoModelKey = 'wf_selected_video_model';
  static const selectedImageModelKey = 'wf_selected_image_model';
  static const modelsKey = 'wf_available_models';
  static const videoModelsKey = 'wf_available_video_models';
  static const imageModelsKey = 'wf_available_image_models';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final ValueNotifier<List<String>> models =
      ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<List<String>> videoModels =
      ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<List<String>> imageModels =
      ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<String?> selectedVideoModel =
      ValueNotifier<String?>(null);
  final ValueNotifier<String?> selectedImageModel =
      ValueNotifier<String?>(null);

  bool _loaded = false;
  bool _refreshing = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final storedModels = await _storage.read(key: modelsKey);
    final storedVideoModels = await _storage.read(key: videoModelsKey);
    final storedImageModels = await _storage.read(key: imageModelsKey);
    final legacyModel = await _storage.read(key: legacyModelKey);
    final videoModel = await _storage.read(key: selectedVideoModelKey);
    final imageModel = await _storage.read(key: selectedImageModelKey);

    final parsedModels = _parseModels(storedModels);
    final parsedVideoModels = _parseModels(storedVideoModels);
    final parsedImageModels = _parseModels(storedImageModels);
    if (legacyModel != null && legacyModel.isNotEmpty) {
      parsedModels.add(legacyModel);
      parsedVideoModels.add(legacyModel);
    }
    models.value = _dedupe(parsedModels);
    videoModels.value = _dedupe(parsedVideoModels);
    imageModels.value = _dedupe(parsedImageModels);
    selectedVideoModel.value = _firstNonEmpty(videoModel, legacyModel);
    selectedImageModel.value = imageModel;
  }

  Future<void> refreshFromSavedCredentials() async {
    await load();
    final baseUrl = (await _storage.read(key: baseUrlKey))?.trim() ?? '';
    final apiKey = (await _storage.read(key: apiKeyKey))?.trim() ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) return;
    await refresh(baseUrl: baseUrl, apiKey: apiKey);
  }

  Future<ModelFetchResult> refresh({
    required String baseUrl,
    required String apiKey,
  }) async {
    await load();
    if (_refreshing) {
      return ModelFetchResult(
        success: true,
        models: models.value,
        videoModels: videoModels.value,
        imageModels: imageModels.value,
        error: '',
        debug: 'refresh already running',
      );
    }

    _refreshing = true;
    try {
      final result = await GoCoreBridge.fetchModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      if (!result.success) return result;

      await setModels(
        allModels: result.models,
        videoModels: result.videoModels,
        imageModels: result.imageModels,
      );
      return result;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> setModels({
    required List<String> allModels,
    required List<String> videoModels,
    required List<String> imageModels,
  }) async {
    final normalizedVideo = _dedupe(videoModels);
    final normalizedImage = _dedupe(imageModels);
    final normalized = _dedupe([
      ...allModels,
      ...normalizedVideo,
      ...normalizedImage,
    ]);
    models.value = normalized;
    this.videoModels.value = normalizedVideo;
    this.imageModels.value = normalizedImage;
    await _storage.write(key: modelsKey, value: jsonEncode(normalized));
    await _storage.write(
      key: videoModelsKey,
      value: jsonEncode(normalizedVideo),
    );
    await _storage.write(
      key: imageModelsKey,
      value: jsonEncode(normalizedImage),
    );

    final currentVideo = selectedVideoModel.value;
    if ((currentVideo == null || !normalizedVideo.contains(currentVideo)) &&
        normalizedVideo.isNotEmpty) {
      await setSelectedVideoModel(normalizedVideo.first);
    }

    final currentImage = selectedImageModel.value;
    if ((currentImage == null || !normalizedImage.contains(currentImage)) &&
        normalizedImage.isNotEmpty) {
      await setSelectedImageModel(normalizedImage.first);
    }
  }

  Future<void> setSelectedVideoModel(String model) async {
    selectedVideoModel.value = model;
    await _storage.write(key: selectedVideoModelKey, value: model);
    await _storage.write(key: legacyModelKey, value: model);
  }

  Future<void> setSelectedImageModel(String model) async {
    selectedImageModel.value = model;
    await _storage.write(key: selectedImageModelKey, value: model);
  }

  List<String> _parseModels(String? value) {
    if (value == null || value.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      return <String>[];
    }
    return <String>[];
  }

  List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final model = value.trim();
      if (model.isEmpty || seen.contains(model)) continue;
      seen.add(model);
      result.add(model);
    }
    return result;
  }

  String? _firstNonEmpty(String? first, String? second) {
    if (first != null && first.isNotEmpty) return first;
    if (second != null && second.isNotEmpty) return second;
    return null;
  }
}
