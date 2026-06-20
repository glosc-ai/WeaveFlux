import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_task.dart';
import 'go_core_bridge.dart';
import 'model_catalog.dart';

class TaskStore {
  TaskStore._();

  static final TaskStore instance = TaskStore._();

  final ValueNotifier<List<VideoTask>> tasks =
      ValueNotifier<List<VideoTask>>(<VideoTask>[]);
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _loaded = false;
  Box<dynamic>? _box;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final directory = await getApplicationDocumentsDirectory();
    Hive.init(directory.path);
    _box = await Hive.openBox<dynamic>('weaveflux_video_tasks');
    _refreshFromBox();
  }

  Future<void> add(VideoTask task) async {
    await load();
    await _box!.put(task.localId, task.toJson());
    _refreshFromBox();
  }

  Future<void> update(VideoTask task) async {
    await load();
    await _box!.put(task.localId, task.toJson());
    _refreshFromBox();
  }

  Future<void> pollProcessingTasks() async {
    await load();
    final baseUrl =
        (await _storage.read(key: ModelCatalog.baseUrlKey))?.trim() ?? '';
    final apiKey =
        (await _storage.read(key: ModelCatalog.apiKeyKey))?.trim() ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) return;

    final pending = tasks.value
        .where((task) =>
            task.status == VideoTaskStatus.processing &&
            task.remoteTaskId.isNotEmpty &&
            !task.remoteTaskId.startsWith('http'))
        .toList();
    for (final task in pending) {
      try {
        final result = await GoCoreBridge.queryTask(
          baseUrl: baseUrl,
          apiKey: apiKey,
          taskId: task.remoteTaskId,
        );
        if (!result.success) continue;
        final status = _statusFromRemote(result.status);
        await update(
          task.copyWith(
            status: status,
            resultUrl: result.resultUrl.isEmpty ? null : result.resultUrl,
            resultBase64:
                result.resultBase64.isEmpty ? null : result.resultBase64,
          ),
        );
      } catch (_) {
        // 网络抖动不应打断本地队列；下次轮询继续。
      }
    }
  }

  VideoTaskStatus _statusFromRemote(String status) {
    return switch (status.trim().toLowerCase()) {
      'completed' || 'succeeded' || 'success' || 'finished' =>
        VideoTaskStatus.completed,
      'failed' || 'error' || 'cancelled' || 'canceled' =>
        VideoTaskStatus.failed,
      _ => VideoTaskStatus.processing,
    };
  }

  void _refreshFromBox() {
    final box = _box;
    if (box == null) {
      tasks.value = <VideoTask>[];
      return;
    }

    final loadedTasks = box.values
        .whereType<Map>()
        .map(
          (value) => value.map(
            (key, item) => MapEntry(key.toString(), item as Object?),
          ),
        )
        .map(VideoTask.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    tasks.value = loadedTasks;
  }
}
