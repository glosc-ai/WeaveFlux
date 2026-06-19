enum VideoTaskStatus { processing, failed, completed }

enum VideoTaskMode { textToVideo, imageToVideo }

class VideoTask {
  const VideoTask({
    required this.localId,
    required this.remoteTaskId,
    required this.status,
    required this.mode,
    required this.prompt,
    required this.model,
    required this.aspectRatio,
    required this.size,
    required this.motionScale,
    required this.createdAt,
    this.imagePath = '',
    this.errorMessage = '',
    this.localVideoPath = '',
  });

  factory VideoTask.fromJson(Map<String, Object?> json) {
    return VideoTask(
      localId: json['local_id'] as String? ?? '',
      remoteTaskId: json['remote_task_id'] as String? ?? '',
      status: _statusFromName(json['status'] as String?),
      mode: _modeFromName(json['mode'] as String?),
      prompt: json['prompt'] as String? ?? '',
      model: json['model'] as String? ?? '',
      aspectRatio: json['aspect_ratio'] as String? ?? '',
      size: json['size'] as String? ?? '',
      motionScale: (json['motion_scale'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['created_at'] as int? ?? 0,
      ),
      imagePath: json['image_path'] as String? ?? '',
      errorMessage: json['error_message'] as String? ?? '',
      localVideoPath: json['local_video_path'] as String? ?? '',
    );
  }

  final String localId;
  final String remoteTaskId;
  final VideoTaskStatus status;
  final VideoTaskMode mode;
  final String prompt;
  final String model;
  final String aspectRatio;
  final String size;
  final double motionScale;
  final DateTime createdAt;
  final String imagePath;
  final String errorMessage;
  final String localVideoPath;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'local_id': localId,
      'remote_task_id': remoteTaskId,
      'status': status.name,
      'mode': mode.name,
      'prompt': prompt,
      'model': model,
      'aspect_ratio': aspectRatio,
      'size': size,
      'motion_scale': motionScale,
      'created_at': createdAt.millisecondsSinceEpoch,
      'image_path': imagePath,
      'error_message': errorMessage,
      'local_video_path': localVideoPath,
    };
  }

  static VideoTaskStatus _statusFromName(String? name) {
    return VideoTaskStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => VideoTaskStatus.processing,
    );
  }

  static VideoTaskMode _modeFromName(String? name) {
    return VideoTaskMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => VideoTaskMode.textToVideo,
    );
  }
}
