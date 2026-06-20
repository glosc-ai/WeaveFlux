import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:video_player/video_player.dart';

import '../models/video_task.dart';
import '../services/media_store_exporter.dart';
import '../services/task_store.dart';
import '../theme/app_theme.dart';
import 'create_workspace.dart';

class PrivateGallery extends StatefulWidget {
  const PrivateGallery({super.key});

  static const routeName = '/gallery';

  @override
  State<PrivateGallery> createState() => _PrivateGalleryState();
}

class _PrivateGalleryState extends State<PrivateGallery> {
  VideoTask? _activeTask;
  bool _confirmingDelete = false;
  String? _toast;

  void _showToast(String message) {
    setState(() => _toast = message);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || _toast != message) return;
      setState(() => _toast = null);
    });
  }

  Future<void> _exportActive() async {
    final task = _activeTask;
    if (task == null || task.localVideoPath.isEmpty) return;
    try {
      await MediaStoreExporter.instance.exportVideo(
        localPath: task.localVideoPath,
        displayName: 'weaveflux_${task.localId}.mp4',
      );
      _showToast('已成功保存至系统相册');
    } catch (error) {
      _showToast('导出失败：$error');
    }
  }

  Future<void> _deleteActive() async {
    final task = _activeTask;
    if (task == null) return;
    try {
      final path = task.localVideoPath;
      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await TaskStore.instance.update(
        task.copyWith(localVideoPath: ''),
      );
      if (!mounted) return;
      setState(() {
        _activeTask = null;
        _confirmingDelete = false;
      });
      _showToast('已删除本地沙盒视频');
    } catch (error) {
      _showToast('删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<VideoTask>>(
      valueListenable: TaskStore.instance.tasks,
      builder: (context, tasks, _) {
        final items = tasks
            .where((task) =>
                task.status == VideoTaskStatus.completed &&
                task.localVideoPath.isNotEmpty &&
                File(task.localVideoPath).existsSync())
            .toList();

        return WeaveScaffold(
          activeRoute: PrivateGallery.routeName,
          header: _GalleryHeader(count: items.length),
          overlays: [
            if (_activeTask != null)
              _PlayerOverlay(
                task: _activeTask!,
                confirmingDelete: _confirmingDelete,
                onClose: () => setState(() => _activeTask = null),
                onDownload: _exportActive,
                onDelete: () => setState(() => _confirmingDelete = true),
                onCancelDelete: () => setState(() => _confirmingDelete = false),
                onConfirmDelete: _deleteActive,
              ),
            if (_toast != null) _Toast(message: _toast!),
          ],
          child: items.isEmpty
              ? const _EmptyGallery()
              : MasonryGridView.count(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final task = items[index];
                    return _GalleryTile(
                      task: task,
                      onTap: () => setState(() => _activeTask = task),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('私密画廊',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count 个作品',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '暂无已下载到本地沙盒的视频',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.task, required this.onTap});

  final VideoTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.cardRadius,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadii.cardRadius,
        child: Container(
          color: AppColors.surface,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: task.aspectRatio == '16:9' ? 16 / 9 : 9 / 16,
                    child: _VideoThumb(path: task.localVideoPath),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _relativeTime(task.createdAt),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 8,
                right: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      color: Colors.black.withValues(alpha: 0.7),
                      child: const Text(
                        '本地',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.path});

  final String path;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final file = File(widget.path);
    if (!await file.exists()) return;
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.pause();
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    } catch (_) {
      await controller.dispose();
      if (!mounted || _controller != controller) return;
      _controller = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_ready && controller != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.primaryAccent,
              size: 32,
            ),
          ),
        ],
      );
    }
    return Container(
      alignment: Alignment.center,
      color: Colors.white.withValues(alpha: 0.04),
      child: const Icon(Icons.movie_creation_outlined, color: AppColors.muted),
    );
  }
}

class _PlayerOverlay extends StatefulWidget {
  const _PlayerOverlay({
    required this.task,
    required this.confirmingDelete,
    required this.onClose,
    required this.onDownload,
    required this.onDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  final VideoTask task;
  final bool confirmingDelete;
  final VoidCallback onClose;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancelDelete;
  final VoidCallback onConfirmDelete;

  @override
  State<_PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<_PlayerOverlay> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    final file = File(widget.task.localVideoPath);
    if (!await file.exists()) return;
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    } catch (_) {
      await controller.dispose();
      if (!mounted || _controller != controller) return;
      _controller = null;
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !_ready) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final playing = controller?.value.isPlaying ?? false;

    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: _ready && controller != null
                  ? FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryAccent,
                      ),
                    ),
            ),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: _togglePlayback,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: 64,
                      height: 64,
                      color: Colors.white.withValues(alpha: 0.15),
                      child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: AppColors.foreground,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 104,
              child: Text(
                widget.task.prompt,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 13, height: 1.5),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: _GlassCircleButton(
                icon: Icons.close_rounded,
                onTap: widget.onClose,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GlassCircleButton(
                    icon: Icons.file_download_outlined,
                    accent: AppColors.primaryAccent,
                    onTap: widget.onDownload,
                  ),
                  const SizedBox(width: 24),
                  _GlassCircleButton(
                    icon: Icons.delete_outline_rounded,
                    accent: AppColors.danger,
                    onTap: widget.onDelete,
                  ),
                ],
              ),
            ),
            if (widget.confirmingDelete)
              _ConfirmDialog(
                onCancel: widget.onCancelDelete,
                onConfirm: widget.onConfirmDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.white.withValues(alpha: 0.1),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child:
                  Icon(icon, color: accent ?? AppColors.foreground, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 36),
              const SizedBox(height: 12),
              const Text('确认删除',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                '此操作只会删除应用沙盒内的视频文件，不会影响已经导出到系统相册的副本。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.06)),
                      onPressed: onCancel,
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger),
                      onPressed: onConfirm,
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 100,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryAccent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
