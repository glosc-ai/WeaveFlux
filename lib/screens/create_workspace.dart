import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/video_task.dart';
import '../services/go_core_bridge.dart';
import '../services/model_catalog.dart';
import '../services/task_store.dart';
import '../theme/app_theme.dart';

enum CreationTarget { video, image }

enum VideoCreationMode { promptOnly, firstFrame, firstLastFrame, extendClip }

enum LocalAssetSlot { firstFrame, lastFrame, clip, audio }

class CreateWorkspace extends StatefulWidget {
  const CreateWorkspace({this.onOpenSettings, this.onOpenTasks, super.key});

  static const routeName = '/';

  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenTasks;

  @override
  State<CreateWorkspace> createState() => _CreateWorkspaceState();
}

class _CreateWorkspaceState extends State<CreateWorkspace> {
  static const _baseUrlKey = ModelCatalog.baseUrlKey;
  static const _apiKeyKey = ModelCatalog.apiKeyKey;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _imagePicker = ImagePicker();
  final _promptController = TextEditingController();
  final _negativePromptController = TextEditingController();
  final _modelController = TextEditingController(text: 't2v-default-model');
  final _imageModelController =
      TextEditingController(text: 'image-default-model');
  final _firstFrameUrlController = TextEditingController();
  final _lastFrameUrlController = TextEditingController();
  final _clipUrlController = TextEditingController();
  final _audioUrlController = TextEditingController();
  final _seedController = TextEditingController();
  final _templateController = TextEditingController();

  CreationTarget _target = CreationTarget.video;
  VideoCreationMode _videoMode = VideoCreationMode.promptOnly;
  bool _advancedOpen = true;
  String _size = '1024x576';
  String _imageSize = '1024x1024';
  String _imageQuality = 'standard';
  int _imageCount = 1;
  double _duration = 5;
  double _motion = 0.5;
  bool _promptExtension = true;
  bool _watermark = false;
  bool _sheetOpen = false;
  bool _submitting = false;

  XFile? _firstFrameFile;
  XFile? _lastFrameFile;
  XFile? _clipFile;
  PlatformFile? _audioFile;
  XFile? _imageReferenceFile;

  List<String> _videoModels = <String>[];
  List<String> _imageModels = <String>[];
  String? _selectedVideoModel;
  String? _selectedImageModel;

  @override
  void initState() {
    super.initState();
    ModelCatalog.instance.videoModels.addListener(_syncModelsFromCatalog);
    ModelCatalog.instance.imageModels.addListener(_syncModelsFromCatalog);
    ModelCatalog.instance.selectedVideoModel
        .addListener(_syncModelsFromCatalog);
    ModelCatalog.instance.selectedImageModel
        .addListener(_syncModelsFromCatalog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadDefaultModel();
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _modelController.dispose();
    _imageModelController.dispose();
    _firstFrameUrlController.dispose();
    _lastFrameUrlController.dispose();
    _clipUrlController.dispose();
    _audioUrlController.dispose();
    _seedController.dispose();
    _templateController.dispose();
    ModelCatalog.instance.videoModels.removeListener(_syncModelsFromCatalog);
    ModelCatalog.instance.imageModels.removeListener(_syncModelsFromCatalog);
    ModelCatalog.instance.selectedVideoModel
        .removeListener(_syncModelsFromCatalog);
    ModelCatalog.instance.selectedImageModel
        .removeListener(_syncModelsFromCatalog);
    super.dispose();
  }

  Future<void> _loadDefaultModel() async {
    await ModelCatalog.instance.load();
    if (!mounted) return;
    _syncModelsFromCatalog();
  }

  void _syncModelsFromCatalog() {
    if (!mounted) return;
    final videoModels = _dedupeModels(ModelCatalog.instance.videoModels.value);
    final imageModels = _dedupeModels(ModelCatalog.instance.imageModels.value);
    final videoModel = ModelCatalog.instance.selectedVideoModel.value;
    final imageModel = ModelCatalog.instance.selectedImageModel.value;
    setState(() {
      _videoModels = videoModels;
      _imageModels = imageModels;
      _selectedVideoModel = videoModels.contains(videoModel)
          ? videoModel
          : videoModels.isEmpty
              ? null
              : videoModels.first;
      _selectedImageModel = imageModels.contains(imageModel)
          ? imageModel
          : imageModels.isEmpty
              ? null
              : imageModels.first;
      if (_selectedVideoModel != null) {
        _modelController.text = _selectedVideoModel!;
      }
      if (_selectedImageModel != null) {
        _imageModelController.text = _selectedImageModel!;
      }
    });
  }

  List<String> _dedupeModels(List<String> models) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in models) {
      final model = raw.trim();
      if (model.isEmpty || !seen.add(model)) continue;
      result.add(model);
    }
    return result;
  }

  Future<void> _pickImage(LocalAssetSlot slot) async {
    if (slot == LocalAssetSlot.clip) {
      final video = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (video == null || !mounted) return;
      setState(() => _clipFile = video);
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    setState(() {
      switch (slot) {
        case LocalAssetSlot.firstFrame:
          _firstFrameFile = image;
        case LocalAssetSlot.lastFrame:
          _lastFrameFile = image;
        case LocalAssetSlot.clip:
          break;
        case LocalAssetSlot.audio:
          break;
      }
    });
  }

  Future<void> _pickImageReference() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    setState(() => _imageReferenceFile = image);
  }

  Future<void> _selectVideoModel(String? model) async {
    if (model == null) return;
    setState(() {
      _selectedVideoModel = model;
      _modelController.text = model;
    });
    await ModelCatalog.instance.setSelectedVideoModel(model);
  }

  Future<void> _selectImageModel(String? model) async {
    if (model == null) return;
    setState(() {
      _selectedImageModel = model;
      _imageModelController.text = model;
    });
    await ModelCatalog.instance.setSelectedImageModel(model);
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _audioFile = result.files.single);
  }

  Future<void> _startCreation() async {
    if (_target == CreationTarget.image) {
      await _startImageCreation();
      return;
    }
    if (_target == CreationTarget.image) {
      _showMessage('图片生成入口已接入，请直接提交到任务队列。');
      return;
    }
    await _startVideoCreation();
  }

  Future<void> _startImageCreation() async {
    if (_submitting) return;

    final baseUrl = (await _storage.read(key: _baseUrlKey))?.trim() ?? '';
    final apiKey = (await _storage.read(key: _apiKeyKey))?.trim() ?? '';
    final model = _imageModelController.text.trim();
    final prompt = _promptController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      setState(() => _sheetOpen = true);
      return;
    }
    if (prompt.isEmpty) {
      _showMessage('请输入图片提示词');
      return;
    }
    if (model.isEmpty) {
      _showMessage('请选择或输入图片模型');
      return;
    }

    setState(() => _submitting = true);

    try {
      final referenceBase64 = _imageReferenceFile == null
          ? ''
          : base64Encode(await File(_imageReferenceFile!.path).readAsBytes());
      final task = VideoTask(
        localId: DateTime.now().microsecondsSinceEpoch.toString(),
        remoteTaskId: '',
        status: VideoTaskStatus.processing,
        mode: _imageReferenceFile == null
            ? VideoTaskMode.textToImage
            : VideoTaskMode.imageToImage,
        prompt: prompt,
        model: model,
        aspectRatio: _aspectRatioForSize(_imageSize),
        size: _imageSize,
        motionScale: 0,
        createdAt: DateTime.now(),
        imagePath: _imageReferenceFile?.path ?? '',
      );
      final payload = <String, Object?>{
        'model': model,
        'prompt': prompt,
        'size': _imageSize,
        'quality': _imageQuality,
        'count': _imageCount.toString(),
        'negative_prompt': _negativePromptController.text.trim(),
        'seed': _seedController.text.trim(),
        'image_base64': referenceBase64,
      };

      await TaskStore.instance.add(task);
      unawaited(_dispatchImageTaskInBackground(task, baseUrl, apiKey, payload));

      if (!mounted) return;
      _showMessage('图片任务已加入队列');
      widget.onOpenTasks?.call();
    } catch (error) {
      if (!mounted) return;
      _showMessage('图片任务入队失败：$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }


  Future<void> _startVideoCreation() async {
    if (_submitting) return;

    final baseUrl = (await _storage.read(key: _baseUrlKey))?.trim() ?? '';
    final apiKey = (await _storage.read(key: _apiKeyKey))?.trim() ?? '';
    final model = _modelController.text.trim();
    final prompt = _promptController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      setState(() => _sheetOpen = true);
      return;
    }
    if (prompt.isEmpty) {
      _showMessage('请输入提示词');
      return;
    }
    if (model.isEmpty) {
      _showMessage('请选择或输入视频模型');
      return;
    }
    if (_needsFirstFrame && !_hasFirstFrame) {
      _showMessage('请提供首帧图片 URL 或本地图片');
      return;
    }
    if (_videoMode == VideoCreationMode.firstLastFrame && !_hasLastFrame) {
      _showMessage('请提供尾帧图片 URL 或本地图片');
      return;
    }
    if (_videoMode == VideoCreationMode.extendClip && !_hasClip) {
      _showMessage('请提供需要继续生成的视频片段 URL 或本地文件');
      return;
    }

    setState(() => _submitting = true);

    try {
      final imageBase64 = _firstFrameFile == null
          ? ''
          : base64Encode(await File(_firstFrameFile!.path).readAsBytes());
      final lastFrameBase64 = _lastFrameFile == null
          ? ''
          : base64Encode(await File(_lastFrameFile!.path).readAsBytes());
      final clipBase64 = _clipFile == null
          ? ''
          : base64Encode(await File(_clipFile!.path).readAsBytes());
      final audioBase64 = _audioFile?.path == null
          ? ''
          : base64Encode(await File(_audioFile!.path!).readAsBytes());
      final task = VideoTask(
        localId: DateTime.now().microsecondsSinceEpoch.toString(),
        remoteTaskId: '',
        status: VideoTaskStatus.processing,
        mode: _taskModeForVideoMode(),
        prompt: prompt,
        model: model,
        aspectRatio: _aspectRatioForSize(_size),
        size: _size,
        motionScale: _motion,
        createdAt: DateTime.now(),
        imagePath: _firstFrameFile?.path ?? '',
      );
      final payload = <String, Object?>{
        'model': model,
        'prompt': prompt,
        'legacy_prompt': _buildDispatchPrompt(prompt),
        'size': _size,
        'motion_scale': _motion.toStringAsFixed(3),
        'duration': _duration.round().toString(),
        'negative_prompt': _negativePromptController.text.trim(),
        'prompt_extension': _promptExtension.toString(),
        'watermark': _watermark.toString(),
        'seed': _seedController.text.trim(),
        'template': _templateController.text.trim(),
        'mode': _apiVideoMode(),
        'image_base64': imageBase64,
        'last_frame_base64': lastFrameBase64,
        'clip_base64': clipBase64,
        'audio_base64': audioBase64,
        'first_frame_url': _firstFrameUrlController.text.trim(),
        'last_frame_url': _lastFrameUrlController.text.trim(),
        'clip_url': _clipUrlController.text.trim(),
        'audio_url': _audioUrlController.text.trim(),
      };

      await TaskStore.instance.add(task);
      unawaited(_dispatchVideoTaskInBackground(task, baseUrl, apiKey, payload));

      if (!mounted) return;
      _showMessage('视频任务已加入队列');
      widget.onOpenTasks?.call();
    } catch (error) {
      if (!mounted) return;
      _showMessage('视频任务入队失败：$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }


  Future<void> _dispatchImageTaskInBackground(
    VideoTask task,
    String baseUrl,
    String apiKey,
    Map<String, Object?> payload,
  ) async {
    try {
      final result = await GoCoreBridge.dispatchImageTask(
        baseUrl: baseUrl,
        apiKey: apiKey,
        payload: payload,
      );
      final status = result.success
          ? _statusFromDispatch(result.status, result)
          : VideoTaskStatus.failed;
      await TaskStore.instance.update(
        task.copyWith(
          remoteTaskId: result.taskId.isEmpty ? task.remoteTaskId : result.taskId,
          status: status,
          errorMessage: result.success ? '' : result.error,
          resultUrl: result.resultUrl,
          resultBase64: result.resultBase64,
        ),
      );
      if (result.success && status == VideoTaskStatus.completed) {
        await TaskStore.instance.resumePendingDownloads();
      }
    } catch (error, stack) {
      debugPrint('Image dispatch background error: $error\nStack: $stack');
      await TaskStore.instance.update(
        task.copyWith(
          status: VideoTaskStatus.failed,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> _dispatchVideoTaskInBackground(
    VideoTask task,
    String baseUrl,
    String apiKey,
    Map<String, Object?> payload,
  ) async {
    try {
      final result = await GoCoreBridge.dispatchVideoTask(
        baseUrl: baseUrl,
        apiKey: apiKey,
        payload: payload,
      );
      final status = result.success
          ? _statusFromDispatch(result.status, result)
          : VideoTaskStatus.failed;
      await TaskStore.instance.update(
        task.copyWith(
          remoteTaskId: result.taskId.isEmpty ? task.remoteTaskId : result.taskId,
          status: status,
          errorMessage: result.success ? '' : result.error,
          resultUrl: result.resultUrl,
          resultBase64: result.resultBase64,
        ),
      );
      if (result.success && status == VideoTaskStatus.processing) {
        await TaskStore.instance.startNativePollingForProcessingTasks();
      } else if (result.success && status == VideoTaskStatus.completed) {
        await TaskStore.instance.resumePendingDownloads();
      }
    } catch (error, stack) {
      debugPrint('Video dispatch background error: $error\nStack: $stack');
      await TaskStore.instance.update(
        task.copyWith(
          status: VideoTaskStatus.failed,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  VideoTaskStatus _statusFromDispatch(
    String status,
    DispatchVideoTaskResult result,
  ) {
    if (result.resultUrl.isNotEmpty || result.resultBase64.isNotEmpty) {
      return VideoTaskStatus.completed;
    }
    return switch (status.trim().toLowerCase()) {
      'completed' || 'succeeded' || 'success' || 'finished' =>
        VideoTaskStatus.completed,
      'failed' || 'error' => VideoTaskStatus.failed,
      _ => VideoTaskStatus.processing,
    };
  }

  VideoTaskMode _taskModeForVideoMode() {
    return switch (_videoMode) {
      VideoCreationMode.promptOnly => VideoTaskMode.textToVideo,
      VideoCreationMode.extendClip => VideoTaskMode.extendVideo,
      VideoCreationMode.firstFrame || VideoCreationMode.firstLastFrame =>
        VideoTaskMode.imageToVideo,
    };
  }

  String _apiVideoMode() {
    return switch (_videoMode) {
      VideoCreationMode.firstLastFrame => 'keyframes',
      VideoCreationMode.promptOnly ||
      VideoCreationMode.firstFrame ||
      VideoCreationMode.extendClip =>
        'ti2vid',
    };
  }

  String _buildDispatchPrompt(String prompt) {
    final parts = <String>[
      prompt,
      '',
      'Generation mode: ${_videoMode.label}',
      'Duration: ${_duration.round()}s',
      'Prompt extension: ${_promptExtension ? 'on' : 'off'}',
      'Watermark: ${_watermark ? 'on' : 'off'}',
    ];
    if (_negativePromptController.text.trim().isNotEmpty) {
      parts.add('Negative prompt: ${_negativePromptController.text.trim()}');
    }
    if (_seedController.text.trim().isNotEmpty) {
      parts.add('Seed: ${_seedController.text.trim()}');
    }
    if (_templateController.text.trim().isNotEmpty) {
      parts.add('Template: ${_templateController.text.trim()}');
    }
    if (_firstFrameUrlController.text.trim().isNotEmpty) {
      parts.add('First frame URL: ${_firstFrameUrlController.text.trim()}');
    }
    if (_lastFrameUrlController.text.trim().isNotEmpty) {
      parts.add('Last frame URL: ${_lastFrameUrlController.text.trim()}');
    }
    if (_clipUrlController.text.trim().isNotEmpty) {
      parts.add('Extend clip URL: ${_clipUrlController.text.trim()}');
    }
    if (_audioUrlController.text.trim().isNotEmpty) {
      parts.add('Audio URL: ${_audioUrlController.text.trim()}');
    }
    if (_audioFile?.path != null) {
      parts.add('Local audio file: ${_audioFile!.name}');
    }
    return parts.join('\n');
  }

  bool get _needsFirstFrame =>
      _videoMode == VideoCreationMode.firstFrame ||
      _videoMode == VideoCreationMode.firstLastFrame;

  bool get _hasFirstFrame =>
      _firstFrameFile != null ||
      _firstFrameUrlController.text.trim().isNotEmpty;

  bool get _hasLastFrame =>
      _lastFrameFile != null || _lastFrameUrlController.text.trim().isNotEmpty;

  bool get _hasClip =>
      _clipFile != null || _clipUrlController.text.trim().isNotEmpty;

  String _aspectRatioForSize(String size) {
    if (size.contains('1080x1920') || size.contains('720x1280')) return '9:16';
    if (size.contains('1024x1024') || size.contains('768x768')) return '1:1';
    return '16:9';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WeaveScaffold(
      activeRoute: CreateWorkspace.routeName,
      bottomAction: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: _GradientButton(
          label: _submitting
              ? '提交中...'
              : _target == CreationTarget.video
              ? '生成视频'
                  : '生成图片',
          onTap: _submitting ? null : _startCreation,
        ),
      ),
      overlays: [
        if (_sheetOpen)
          _ConfigSheet(
            onClose: () => setState(() => _sheetOpen = false),
            onSettings: () {
              setState(() => _sheetOpen = false);
              widget.onOpenSettings?.call();
            },
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          _TargetSegmented(
            target: _target,
            onChanged: (target) => setState(() => _target = target),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _target == CreationTarget.video
                ? _VideoWorkspace(
                    key: const ValueKey('video-workspace'),
                    mode: _videoMode,
                    promptController: _promptController,
                    selectedModel: _selectedVideoModel,
                    models: _videoModels,
                    negativePromptController: _negativePromptController,
                    seedController: _seedController,
                    templateController: _templateController,
                    firstFrameUrlController: _firstFrameUrlController,
                    lastFrameUrlController: _lastFrameUrlController,
                    clipUrlController: _clipUrlController,
                    audioUrlController: _audioUrlController,
                    firstFrameFile: _firstFrameFile,
                    lastFrameFile: _lastFrameFile,
                    clipFile: _clipFile,
                    audioFile: _audioFile,
                    advancedOpen: _advancedOpen,
                    size: _size,
                    duration: _duration,
                    motion: _motion,
                    promptExtension: _promptExtension,
                    watermark: _watermark,
                    onModeChanged: (mode) => setState(() => _videoMode = mode),
                    onModelChanged: _selectVideoModel,
                    onPromptChanged: (_) => setState(() {}),
                    onPickImage: _pickImage,
                    onPickAudio: _pickAudio,
                    onAdvancedToggle: () =>
                        setState(() => _advancedOpen = !_advancedOpen),
                    onSizeChanged: (value) => setState(() => _size = value),
                    onDurationChanged: (value) =>
                        setState(() => _duration = value),
                    onMotionChanged: (value) => setState(() => _motion = value),
                    onPromptExtensionChanged: (value) =>
                        setState(() => _promptExtension = value),
                    onWatermarkChanged: (value) =>
                        setState(() => _watermark = value),
                  )
                : _ImageWorkspace(
                    key: const ValueKey('image-workspace'),
                    promptController: _promptController,
                    selectedModel: _selectedImageModel,
                    models: _imageModels,
                    negativePromptController: _negativePromptController,
                    seedController: _seedController,
                    referenceFile: _imageReferenceFile,
                    size: _imageSize,
                    quality: _imageQuality,
                    count: _imageCount,
                    onModelChanged: _selectImageModel,
                    onPromptChanged: (_) => setState(() {}),
                    onSizeChanged: (value) =>
                        setState(() => _imageSize = value),
                    onQualityChanged: (value) =>
                        setState(() => _imageQuality = value),
                    onCountChanged: (value) =>
                        setState(() => _imageCount = value),
                    onPickReference: _pickImageReference,
                  ),
          ),
        ],
      ),
    );
  }
}

class WeaveScaffold extends StatelessWidget {
  const WeaveScaffold({
    required this.activeRoute,
    required this.child,
    this.header,
    this.bottomAction,
    this.overlays = const [],
    super.key,
  });

  final String activeRoute;
  final Widget child;
  final Widget? header;
  final Widget? bottomAction;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            if (header != null) header!,
            Expanded(child: child),
            if (bottomAction != null) bottomAction!,
          ],
        ),
        ...overlays,
      ],
    );
  }
}

class _TargetSegmented extends StatelessWidget {
  const _TargetSegmented({required this.target, required this.onChanged});

  final CreationTarget target;
  final ValueChanged<CreationTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PillSegmented<CreationTarget>(
      value: target,
      values: const [CreationTarget.video, CreationTarget.image],
      labelOf: (value) => value == CreationTarget.video ? '视频生成' : '图片生成',
      onChanged: onChanged,
    );
  }
}

class _VideoWorkspace extends StatelessWidget {
  const _VideoWorkspace({
    required this.mode,
    required this.promptController,
    required this.selectedModel,
    required this.models,
    required this.negativePromptController,
    required this.seedController,
    required this.templateController,
    required this.firstFrameUrlController,
    required this.lastFrameUrlController,
    required this.clipUrlController,
    required this.audioUrlController,
    required this.firstFrameFile,
    required this.lastFrameFile,
    required this.clipFile,
    required this.audioFile,
    required this.advancedOpen,
    required this.size,
    required this.duration,
    required this.motion,
    required this.promptExtension,
    required this.watermark,
    required this.onModeChanged,
    required this.onModelChanged,
    required this.onPromptChanged,
    required this.onPickImage,
    required this.onPickAudio,
    required this.onAdvancedToggle,
    required this.onSizeChanged,
    required this.onDurationChanged,
    required this.onMotionChanged,
    required this.onPromptExtensionChanged,
    required this.onWatermarkChanged,
    super.key,
  });

  final VideoCreationMode mode;
  final TextEditingController promptController;
  final String? selectedModel;
  final List<String> models;
  final TextEditingController negativePromptController;
  final TextEditingController seedController;
  final TextEditingController templateController;
  final TextEditingController firstFrameUrlController;
  final TextEditingController lastFrameUrlController;
  final TextEditingController clipUrlController;
  final TextEditingController audioUrlController;
  final XFile? firstFrameFile;
  final XFile? lastFrameFile;
  final XFile? clipFile;
  final PlatformFile? audioFile;
  final bool advancedOpen;
  final String size;
  final double duration;
  final double motion;
  final bool promptExtension;
  final bool watermark;
  final ValueChanged<VideoCreationMode> onModeChanged;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onPromptChanged;
  final ValueChanged<LocalAssetSlot> onPickImage;
  final VoidCallback onPickAudio;
  final VoidCallback onAdvancedToggle;
  final ValueChanged<String> onSizeChanged;
  final ValueChanged<double> onDurationChanged;
  final ValueChanged<double> onMotionChanged;
  final ValueChanged<bool> onPromptExtensionChanged;
  final ValueChanged<bool> onWatermarkChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeGrid(mode: mode, onChanged: onModeChanged),
        const SizedBox(height: 12),
        _PromptCard(
          title: '提示词',
          hintText: '描述镜头、主体、动作、光线、风格和节奏...',
          controller: promptController,
          maxLines: 6,
          onChanged: onPromptChanged,
        ),
        const SizedBox(height: 12),
        if (mode != VideoCreationMode.promptOnly) ...[
          _ReferencePanel(
            mode: mode,
            firstFrameUrlController: firstFrameUrlController,
            lastFrameUrlController: lastFrameUrlController,
            clipUrlController: clipUrlController,
            firstFrameFile: firstFrameFile,
            lastFrameFile: lastFrameFile,
            clipFile: clipFile,
            onPickImage: onPickImage,
          ),
          const SizedBox(height: 12),
        ],
        _AudioPanel(
          controller: audioUrlController,
          audioFile: audioFile,
          onPickAudio: onPickAudio,
        ),
        const SizedBox(height: 12),
        _AdvancedToggle(open: advancedOpen, onTap: onAdvancedToggle),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _VideoAdvancedPanel(
            selectedModel: selectedModel,
            models: models,
            negativePromptController: negativePromptController,
            seedController: seedController,
            templateController: templateController,
            size: size,
            duration: duration,
            motion: motion,
            promptExtension: promptExtension,
            watermark: watermark,
            onSizeChanged: onSizeChanged,
            onModelChanged: onModelChanged,
            onDurationChanged: onDurationChanged,
            onMotionChanged: onMotionChanged,
            onPromptExtensionChanged: onPromptExtensionChanged,
            onWatermarkChanged: onWatermarkChanged,
          ),
          crossFadeState: advancedOpen
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}

class _ImageWorkspace extends StatelessWidget {
  const _ImageWorkspace({
    required this.promptController,
    required this.selectedModel,
    required this.models,
    required this.negativePromptController,
    required this.seedController,
    required this.referenceFile,
    required this.size,
    required this.quality,
    required this.count,
    required this.onModelChanged,
    required this.onPromptChanged,
    required this.onSizeChanged,
    required this.onQualityChanged,
    required this.onCountChanged,
    required this.onPickReference,
    super.key,
  });

  final TextEditingController promptController;
  final String? selectedModel;
  final List<String> models;
  final TextEditingController negativePromptController;
  final TextEditingController seedController;
  final XFile? referenceFile;
  final String size;
  final String quality;
  final int count;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onPromptChanged;
  final ValueChanged<String> onSizeChanged;
  final ValueChanged<String> onQualityChanged;
  final ValueChanged<int> onCountChanged;
  final VoidCallback onPickReference;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptCard(
          title: '图片提示词',
          hintText: '描述要生成的画面、角色、场景、构图和视觉风格...',
          controller: promptController,
          maxLines: 7,
          onChanged: onPromptChanged,
        ),
        const SizedBox(height: 12),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('图片模型'),
              _ModelDropdown(
                selectedModel: selectedModel,
                models: models,
                onChanged: onModelChanged,
              ),
              const SizedBox(height: 16),
              const _FieldLabel('图片尺寸'),
              _ChoiceWrap(
                value: size,
                values: const ['1024x1024', '1024x1536', '1536x1024', '720P'],
                onChanged: onSizeChanged,
              ),
              const SizedBox(height: 16),
              _ReferenceFilePicker(
                title: '参考图',
                filePath: referenceFile?.path,
                onPick: onPickReference,
              ),
              const SizedBox(height: 16),
              const _FieldLabel('\u8d28\u91cf'),
              _ChoiceWrap(
                value: quality,
                values: const ['standard', 'hd'],
                onChanged: onQualityChanged,
              ),
              const SizedBox(height: 16),
              const _FieldLabel('图片数量'),
              _CountStepper(value: count, onChanged: onCountChanged),
              const SizedBox(height: 16),
              const _FieldLabel('反向提示词'),
              TextField(
                controller: negativePromptController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '不希望出现的元素，模型支持时生效',
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('种子'),
              TextField(
                controller: seedController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '可选',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _ImageHint(),
      ],
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.mode, required this.onChanged});

  final VideoCreationMode mode;
  final ValueChanged<VideoCreationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.25,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: VideoCreationMode.values.map((item) {
        return _ModeCard(
          mode: item,
          selected: item == mode,
          onTap: () => onChanged(item),
        );
      }).toList(),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final VideoCreationMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.cardRadius,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.secondaryAccent.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: AppRadii.cardRadius,
          border: Border.all(
            color: selected ? AppColors.secondaryAccent : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(mode.icon,
                color: selected ? AppColors.secondaryAccent : AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mode.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mode.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.title,
    required this.hintText,
    required this.controller,
    required this.maxLines,
    required this.onChanged,
  });

  final String title;
  final String hintText;
  final TextEditingController controller;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.length;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(title),
          TextField(
            controller: controller,
            onChanged: onChanged,
            maxLength: 1200,
            maxLines: maxLines,
            decoration: InputDecoration(
              counterText: '',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hintText,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$length / 1200',
              style: TextStyle(
                color: length > 1080 ? AppColors.danger : AppColors.muted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferencePanel extends StatelessWidget {
  const _ReferencePanel({
    required this.mode,
    required this.firstFrameUrlController,
    required this.lastFrameUrlController,
    required this.clipUrlController,
    required this.firstFrameFile,
    required this.lastFrameFile,
    required this.clipFile,
    required this.onPickImage,
  });

  final VideoCreationMode mode;
  final TextEditingController firstFrameUrlController;
  final TextEditingController lastFrameUrlController;
  final TextEditingController clipUrlController;
  final XFile? firstFrameFile;
  final XFile? lastFrameFile;
  final XFile? clipFile;
  final ValueChanged<LocalAssetSlot> onPickImage;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mode == VideoCreationMode.firstFrame ||
              mode == VideoCreationMode.firstLastFrame)
            _AssetInput(
              title: '首帧 First frame',
              controller: firstFrameUrlController,
              filePath: firstFrameFile?.path,
              hintText: 'https://.../first-frame.png',
              onPick: () => onPickImage(LocalAssetSlot.firstFrame),
            ),
          if (mode == VideoCreationMode.firstLastFrame) ...[
            const SizedBox(height: 14),
            _AssetInput(
              title: '尾帧 Last frame',
              controller: lastFrameUrlController,
              filePath: lastFrameFile?.path,
              hintText: 'https://.../last-frame.png',
              onPick: () => onPickImage(LocalAssetSlot.lastFrame),
            ),
          ],
          if (mode == VideoCreationMode.extendClip)
            _AssetInput(
              title: '\u7ee7\u7eed Extend clip',
              controller: clipUrlController,
              filePath: clipFile?.path,
              hintText: 'https://.../clip.mp4',
              onPick: () => onPickImage(LocalAssetSlot.clip),
            ),
        ],
      ),
    );
  }
}

class _AudioPanel extends StatelessWidget {
  const _AudioPanel({
    required this.controller,
    required this.audioFile,
    required this.onPickAudio,
  });

  final TextEditingController controller;
  final PlatformFile? audioFile;
  final VoidCallback onPickAudio;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.graphic_eq_rounded,
                  size: 17, color: AppColors.primaryAccent),
              SizedBox(width: 6),
              Text(
                'Audio URL / \u672c\u5730\u97f3\u9891',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '可选',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _IconActionButton(
                icon: Icons.upload_file_rounded,
                onTap: onPickAudio,
              ),
            ],
          ),
          if (audioFile != null) ...[
            const SizedBox(height: 8),
            _FileChip(label: audioFile!.name),
          ],
        ],
      ),
    );
  }
}

class _AssetInput extends StatelessWidget {
  const _AssetInput({
    required this.title,
    required this.controller,
    required this.filePath,
    required this.hintText,
    required this.onPick,
  });

  final String title;
  final TextEditingController controller;
  final String? filePath;
  final String hintText;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final fileName = filePath?.split(Platform.pathSeparator).last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(title),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: hintText),
              ),
            ),
            const SizedBox(width: 10),
            _IconActionButton(icon: Icons.image_rounded, onTap: onPick),
          ],
        ),
        if (filePath != null) ...[
          const SizedBox(height: 8),
          _FileChip(label: fileName ?? filePath!),
        ],
      ],
    );
  }
}

class _VideoAdvancedPanel extends StatelessWidget {
  const _VideoAdvancedPanel({
    required this.selectedModel,
    required this.models,
    required this.negativePromptController,
    required this.seedController,
    required this.templateController,
    required this.size,
    required this.duration,
    required this.motion,
    required this.promptExtension,
    required this.watermark,
    required this.onSizeChanged,
    required this.onModelChanged,
    required this.onDurationChanged,
    required this.onMotionChanged,
    required this.onPromptExtensionChanged,
    required this.onWatermarkChanged,
  });

  final String? selectedModel;
  final List<String> models;
  final TextEditingController negativePromptController;
  final TextEditingController seedController;
  final TextEditingController templateController;
  final String size;
  final double duration;
  final double motion;
  final bool promptExtension;
  final bool watermark;
  final ValueChanged<String> onSizeChanged;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<double> onDurationChanged;
  final ValueChanged<double> onMotionChanged;
  final ValueChanged<bool> onPromptExtensionChanged;
  final ValueChanged<bool> onWatermarkChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('视频模型'),
          _ModelDropdown(
            selectedModel: selectedModel,
            models: models,
            onChanged: onModelChanged,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('尺寸 / 画幅'),
          _ChoiceWrap(
            value: size,
            values: const ['1024x576', '576x1024', '768x768', '720P', '1080P'],
            onChanged: onSizeChanged,
          ),
          const SizedBox(height: 16),
          _SliderField(
            label: '时长',
            valueLabel: '${duration.round()}s',
            value: duration,
            min: 3,
            max: 15,
            divisions: 12,
            onChanged: onDurationChanged,
          ),
          _SliderField(
            label: '运动幅度',
            valueLabel: motion.toStringAsFixed(2),
            value: motion,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: onMotionChanged,
          ),
          _SwitchRow(
            title: 'Prompt extension',
            subtitle: '让模型自动扩写提示词，模型支持时生效',
            value: promptExtension,
            onChanged: onPromptExtensionChanged,
          ),
          _SwitchRow(
            title: 'Watermark',
            subtitle: '控制是否添加水印，模型支持时生效',
            value: watermark,
            onChanged: onWatermarkChanged,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('反向提示词'),
          TextField(
            controller: negativePromptController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '不希望出现在视频中的内容'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CompactField(
                  label: '种子',
                  controller: seedController,
                  hintText: '可选',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactField(
                  label: '模板',
                  controller: templateController,
                  hintText: '可选',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.selectedModel,
    required this.models,
    required this.onChanged,
  });

  final String? selectedModel;
  final List<String> models;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = models.contains(selectedModel) ? selectedModel : null;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: AppRadii.inputRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: const Text('请先在设置页获取可用模型'),
          isExpanded: true,
          menuMaxHeight: 280,
          borderRadius: AppRadii.inputRadius,
          dropdownColor: AppColors.surface,
          iconEnabledColor: AppColors.muted,
          style: const TextStyle(
            color: AppColors.foreground,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          items: [
            for (final model in models)
              DropdownMenuItem(
                value: model,
                child: Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: models.isEmpty ? null : onChanged,
        ),
      ),
    );
  }
}

class _ReferenceFilePicker extends StatelessWidget {
  const _ReferenceFilePicker({
    required this.title,
    required this.filePath,
    required this.onPick,
  });

  final String title;
  final String? filePath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final fileName = filePath?.split(Platform.pathSeparator).last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(title),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: AppRadii.inputRadius,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  fileName ?? '可选，选择本地参考图片',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fileName == null
                        ? AppColors.muted
                        : AppColors.foreground,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _IconActionButton(icon: Icons.image_rounded, onTap: onPick),
          ],
        ),
      ],
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepperButton(
          icon: Icons.remove_rounded,
          onTap: value <= 1 ? null : () => onChanged(value - 1),
        ),
        Expanded(
          child: Center(
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        _StepperButton(
          icon: Icons.add_rounded,
          onTap: value >= 4 ? null : () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.secondaryAccent.withValues(alpha: 0.12),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
        foregroundColor: AppColors.secondaryAccent,
        disabledForegroundColor: AppColors.muted,
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.controller,
    required this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FieldLabel(label),
            Text(
              valueLabel,
              style: const TextStyle(
                color: AppColors.secondaryAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ChoiceWrap extends StatelessWidget {
  const _ChoiceWrap({
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((item) {
        final selected = item == value;
        return ChoiceChip(
          label: Text(item),
          selected: selected,
          onSelected: (_) => onChanged(item),
          selectedColor: AppColors.secondaryAccent.withValues(alpha: 0.18),
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          side: BorderSide(
            color: selected ? AppColors.secondaryAccent : AppColors.border,
          ),
        );
      }).toList(),
    );
  }
}

class _PillSegmented<T> extends StatelessWidget {
  const _PillSegmented({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: values.map((item) {
          final active = item == value;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => onChanged(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labelOf(item),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? AppColors.foreground : AppColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.muted,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
      label: const Text('生成参数'),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.buttonRadius,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.secondaryAccent.withValues(alpha: 0.12),
          borderRadius: AppRadii.buttonRadius,
          border: Border.all(
              color: AppColors.secondaryAccent.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, color: AppColors.secondaryAccent),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file_rounded,
              size: 14, color: AppColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageHint extends StatelessWidget {
  const _ImageHint();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: AppColors.primaryAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '生成后的图片可作为视频首帧、尾帧或角色参考素材使用。',
              style:
                  TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onTap == null
              ? const [AppColors.border, AppColors.border]
              : const [Color(0xFF10B981), Color(0xFF059669)],
        ),
        borderRadius: AppRadii.buttonRadius,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.buttonRadius,
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfigSheet extends StatelessWidget {
  const _ConfigSheet({required this.onClose, required this.onSettings});

  final VoidCallback onClose;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                  onTap: onClose, child: const SizedBox.expand()),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '\u672a\u914d\u7f6e API \u51ed\u636e',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'WeaveFlux 需要兼容 OpenAI 规范的 Base URL 和 API Key 才能开始创作。所有凭据仅存储在本地 Android KeyStore 中。',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.secondaryAccent,
                        ),
                        onPressed: onSettings,
                        child: const Text('前往端点设置'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on VideoCreationMode {
  String get label {
    return switch (this) {
      VideoCreationMode.promptOnly => 'Prompt only',
      VideoCreationMode.firstFrame => 'First frame',
      VideoCreationMode.firstLastFrame => 'First+Last',
      VideoCreationMode.extendClip => 'Extend a clip',
    };
  }

  String get description {
    return switch (this) {
      VideoCreationMode.promptOnly => '纯文本生成',
      VideoCreationMode.firstFrame => '首帧到视频',
      VideoCreationMode.firstLastFrame => '首尾帧控制',
      VideoCreationMode.extendClip => '继续已有片段',
    };
  }

  IconData get icon {
    return switch (this) {
      VideoCreationMode.promptOnly => Icons.notes_rounded,
      VideoCreationMode.firstFrame => Icons.filter_1_rounded,
      VideoCreationMode.firstLastFrame => Icons.compare_rounded,
      VideoCreationMode.extendClip => Icons.playlist_play_rounded,
    };
  }
}
