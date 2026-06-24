import 'dart:async';

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
  static const int _maxInlineBase64BytesForUi = 256 * 1024;

  final ValueNotifier<List<VideoTask>> tasks =
      ValueNotifier<List<VideoTask>>(<VideoTask>[]);
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _loaded = false;
  bool _callbackConfigured = false;
  Future<void>? _loading;
  Future<void> _statusUpdateQueue = Future<void>.value();
  Box<dynamic>? _box;
  final Set<String> _nativePollingTasks = <String>{};
  final Set<String> _downloadingTasks = <String>{};
  final Map<String, String> _lastNativeStatusSignature = <String, String>{};

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
  }

  Future<void> add(VideoTask task) async {
    await load();
    await _box!.put(task.localId, task.toJson());
    _refreshFromBox();
    if (task.status == VideoTaskStatus.processing) {
      await _startNativePolling(task);
    } else if (task.status == VideoTaskStatus.completed) {
      await _persistCompletedAsset(task);
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
            task.localVideoPath.isEmpty &&
            (task.resultUrl.isNotEmpty || task.resultBase64.isNotEmpty))
        .toList();
    for (final task in pending) {
      await _persistCompletedAsset(task);
    }
  }

  void _configureNativeCallback() {
    if (_callbackConfigured) return;
    _callbackConfigured = true;
    GoCoreBridge.configureTaskStatusHandler(_handleNativeStatusUpdate);
  }

  Future<void> _handleNativeStatusUpdate(NativeTaskStatusUpdate update) async {
    if (update.taskId.isEmpty) return;
    final signature =
        '${update.status}|${update.videoUrl}|${update.error}'.trim();
    if (_lastNativeStatusSignature[update.taskId] == signature) return;
    _lastNativeStatusSignature[update.taskId] = signature;

    _statusUpdateQueue = _statusUpdateQueue.then((_) {
      return _applyNativeStatusUpdate(update);
    }).catchError((Object error, StackTrace stack) {
      debugPrint('Task status update queue error: $error\nStack: $stack');
    });
    await _statusUpdateQueue;
  }

  Future<void> _applyNativeStatusUpdate(NativeTaskStatusUpdate update) async {
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
    final nextTask = task.copyWith(
      status: status,
      errorMessage: update.error.isEmpty ? null : update.error,
      resultUrl: update.videoUrl.isEmpty ? null : update.videoUrl,
    );
    if (!_sameTaskState(task, nextTask)) {
      await this.update(nextTask);
    }

    if (status != VideoTaskStatus.processing) {
      _nativePollingTasks.remove(update.taskId);
    }
    if (status == VideoTaskStatus.completed && update.videoUrl.isNotEmpty) {
      unawaited(_downloadCompletedVideo(update.taskId, update.videoUrl));
    }
  }

  bool _sameTaskState(VideoTask left, VideoTask right) {
    return left.status == right.status &&
        left.errorMessage == right.errorMessage &&
        left.resultUrl == right.resultUrl &&
        left.resultBase64 == right.resultBase64 &&
        left.localVideoPath == right.localVideoPath;
  }

  Future<void> _persistCompletedAsset(VideoTask task) async {
    if (task.isImage) {
      await _persistCompletedImage(task);
      return;
    }
    if (task.resultUrl.isNotEmpty) {
      await _downloadCompletedVideo(task.remoteTaskId, task.resultUrl);
    }
  }

  Future<void> _persistCompletedImage(VideoTask task) async {
    final taskId = task.remoteTaskId.isNotEmpty ? task.remoteTaskId : task.localId;
    if (!_downloadingTasks.add(taskId)) return;
    try {
      String localPath = '';
      if (task.resultBase64.isNotEmpty) {
        localPath = await VideoDownloadService.instance.saveBase64ToSandbox(
          taskId: taskId,
          base64Data: task.resultBase64,
          isImage: true,
        );
      } else if (task.resultUrl.isNotEmpty) {
        localPath = await VideoDownloadService.instance.downloadToSandbox(
          taskId: taskId,
          videoUrl: task.resultUrl,
          isImage: true,
        );
      }
      if (localPath.isEmpty) return;

      final current = _findTask(task.remoteTaskId, fallbackLocalId: task.localId);
      if (current == null) return;
      await update(current.copyWith(localVideoPath: localPath));
    } catch (error) {
      debugPrint('Image asset persistence failed: $error');
    } finally {
      _downloadingTasks.remove(taskId);
    }
  }

  Future<void> _downloadCompletedVideo(String taskId, String videoUrl) async {
    if (!_downloadingTasks.add(taskId)) return;
    try {
      final localPath = await VideoDownloadService.instance.downloadToSandbox(
        taskId: taskId,
        videoUrl: videoUrl,
      );
      final task = _findTask(taskId);
      if (task == null) return;
      await update(
        task.copyWith(
          status: VideoTaskStatus.completed,
          resultUrl: videoUrl,
          localVideoPath: localPath,
        ),
      );
    } catch (error) {
      final task = _findTask(taskId);
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

  VideoTask? _findTask(String remoteTaskId, {String fallbackLocalId = ''}) {
    for (final candidate in tasks.value) {
      if (remoteTaskId.isNotEmpty && candidate.remoteTaskId == remoteTaskId) {
        return candidate;
      }
      if (fallbackLocalId.isNotEmpty && candidate.localId == fallbackLocalId) {
        return candidate;
      }
    }
    return null;
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
        .map(_stripOversizedInlineAsset)
        .map(VideoTask.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _publishTasks(loadedTasks);
  }

  void _publishTasks(List<VideoTask> nextTasks) {
    final current = tasks.value;
    if (_sameTaskList(current, nextTasks)) return;
    tasks.value = nextTasks;
  }

  bool _sameTaskList(List<VideoTask> left, List<VideoTask> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameTaskState(left[index], right[index]) ||
          left[index].localId != right[index].localId ||
          left[index].remoteTaskId != right[index].remoteTaskId ||
          left[index].prompt != right[index].prompt ||
          left[index].model != right[index].model) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> _stripOversizedInlineAsset(Map<String, Object?> json) {
    final resultBase64 = json['result_b64'] as String? ?? '';
    if (resultBase64.length <= _maxInlineBase64BytesForUi) {
      return json;
    }

    final localPath = json['local_video_path'] as String? ?? '';
    final resultUrl = json['result_url'] as String? ?? '';
    if (localPath.isNotEmpty || resultUrl.isNotEmpty) {
      final copy = Map<String, Object?>.from(json);
      copy['result_b64'] = '';
      return copy;
    }

    final copy = Map<String, Object?>.from(json);
    copy['result_b64'] = '';
    copy['error_message'] =
        'Inline Base64 asset is too large to load in the task list.';
    return copy;
  }
}
