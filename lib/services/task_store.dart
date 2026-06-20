import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_task.dart';
import 'go_core_bridge.dart';
import 'model_catalog.dart';
import 'video_download_service.dart';

class TaskStore {
  TaskStore._();

  static final TaskStore instance = TaskStore._();

  final ValueNotifier<List<VideoTask>> tasks =
      ValueNotifier<List<VideoTask>>(<VideoTask>[]);
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _loaded = false;
  bool _callbackConfigured = false;
  Future<void>? _loading;
  Box<dynamic>? _box;
  final Set<String> _nativePollingTasks = <String>{};
  final Set<String> _downloadingTasks = <String>{};

  Future<void> load() async {
    if (_loaded) return;
    final loading = _loading;
    if (loading != null) {
      await loading;
      return;
    }

    _loading = _load();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load() async {
    _configureNativeCallback();

    final directory = await getApplicationDocumentsDirectory();
    Hive.init(directory.path);
    _box = await Hive.openBox<dynamic>('weaveflux_video_tasks');
    _refreshFromBox();
    _loaded = true;
    await _startNativePollingForProcessingTasksLoaded();
    await _resumePendingDownloadsLoaded();
  }

  Future<void> add(VideoTask task) async {
    await load();
    await _box!.put(task.localId, task.toJson());
    _refreshFromBox();
    if (task.status == VideoTaskStatus.processing) {
      await _startNativePolling(task);
    }
  }

  Future<void> update(VideoTask task) async {
    await load();
    await _box!.put(task.localId, task.toJson());
    _refreshFromBox();
  }

  Future<void> retryPolling(VideoTask task) async {
    await update(
      task.copyWith(
        status: VideoTaskStatus.processing,
        errorMessage: '',
      ),
    );
    await _startNativePolling(task);
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

  Future<void> startNativePollingForProcessingTasks() async {
    await load();
    await _startNativePollingForProcessingTasksLoaded();
  }

  Future<void> _startNativePollingForProcessingTasksLoaded() async {
    final pending = tasks.value
        .where((task) =>
            task.status == VideoTaskStatus.processing &&
            task.remoteTaskId.isNotEmpty &&
            !task.remoteTaskId.startsWith('http'))
        .toList();
    for (final task in pending) {
      await _startNativePolling(task);
    }
  }

  Future<void> resumePendingDownloads() async {
    await load();
    await _resumePendingDownloadsLoaded();
  }

  Future<void> _resumePendingDownloadsLoaded() async {
    final pending = tasks.value
        .where((task) =>
            task.status == VideoTaskStatus.completed &&
            task.resultUrl.isNotEmpty &&
            task.localVideoPath.isEmpty)
        .toList();
    for (final task in pending) {
      await _downloadCompletedVideo(task.remoteTaskId, task.resultUrl);
    }
  }

  void _configureNativeCallback() {
    if (_callbackConfigured) return;
    _callbackConfigured = true;
    GoCoreBridge.configureTaskStatusHandler(_handleNativeStatusUpdate);
  }

  Future<void> _handleNativeStatusUpdate(NativeTaskStatusUpdate update) async {
    if (update.taskId.isEmpty) return;
    await load();
    VideoTask? task;
    for (final candidate in tasks.value) {
      if (candidate.remoteTaskId == update.taskId) {
        task = candidate;
        break;
      }
    }
    if (task == null) return;

    final status = _statusFromRemote(update.status);
    await this.update(
      task.copyWith(
        status: status,
        errorMessage: update.error.isEmpty ? null : update.error,
        resultUrl: update.videoUrl.isEmpty ? null : update.videoUrl,
      ),
    );

    if (status != VideoTaskStatus.processing) {
      _nativePollingTasks.remove(update.taskId);
    }
    if (status == VideoTaskStatus.completed && update.videoUrl.isNotEmpty) {
      await _downloadCompletedVideo(update.taskId, update.videoUrl);
    }
  }

  Future<void> _downloadCompletedVideo(String taskId, String videoUrl) async {
    if (!_downloadingTasks.add(taskId)) return;
    try {
      final localPath = await VideoDownloadService.instance.downloadToSandbox(
        taskId: taskId,
        videoUrl: videoUrl,
      );
      VideoTask? task;
      for (final candidate in tasks.value) {
        if (candidate.remoteTaskId == taskId) {
          task = candidate;
          break;
        }
      }
      if (task == null) return;
      await update(
        task.copyWith(
          status: VideoTaskStatus.completed,
          resultUrl: videoUrl,
          localVideoPath: localPath,
        ),
      );
    } catch (error) {
      VideoTask? task;
      for (final candidate in tasks.value) {
        if (candidate.remoteTaskId == taskId) {
          task = candidate;
          break;
        }
      }
      if (task != null) {
        await update(
          task.copyWith(
            status: VideoTaskStatus.failed,
            errorMessage: '视频下载失败：$error',
          ),
        );
      }
    } finally {
      _downloadingTasks.remove(taskId);
    }
  }

  Future<void> _startNativePolling(VideoTask task) async {
    final taskId = task.remoteTaskId.trim();
    if (taskId.isEmpty ||
        taskId.startsWith('http') ||
        !_nativePollingTasks.add(taskId)) {
      return;
    }

    final baseUrl =
        (await _storage.read(key: ModelCatalog.baseUrlKey))?.trim() ?? '';
    final apiKey =
        (await _storage.read(key: ModelCatalog.apiKeyKey))?.trim() ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      _nativePollingTasks.remove(taskId);
      return;
    }

    try {
      final result = await GoCoreBridge.startPollingTask(
        baseUrl: baseUrl,
        apiKey: apiKey,
        taskId: taskId,
      );
      if (!result.success) {
        _nativePollingTasks.remove(taskId);
        await update(
          task.copyWith(
            status: VideoTaskStatus.failed,
            errorMessage: result.error,
          ),
        );
      }
    } catch (error) {
      _nativePollingTasks.remove(taskId);
      await update(
        task.copyWith(
          status: VideoTaskStatus.failed,
          errorMessage: error.toString(),
        ),
      );
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
