import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_task.dart';

class TaskStore {
  TaskStore._();

  static final TaskStore instance = TaskStore._();

  final ValueNotifier<List<VideoTask>> tasks =
      ValueNotifier<List<VideoTask>>(<VideoTask>[]);

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
