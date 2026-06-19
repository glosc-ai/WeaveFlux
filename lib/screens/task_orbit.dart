import 'package:flutter/material.dart';

import '../models/video_task.dart';
import '../services/task_store.dart';
import '../theme/app_theme.dart';
import 'create_workspace.dart';

class TaskOrbit extends StatefulWidget {
  const TaskOrbit({super.key});

  static const routeName = '/tasks';

  @override
  State<TaskOrbit> createState() => _TaskOrbitState();
}

class _TaskOrbitState extends State<TaskOrbit> {
  final Set<String> _expandedTaskIds = <String>{};

  void _toggleExpanded(VideoTask task) {
    if (task.status != VideoTaskStatus.failed) return;
    setState(() {
      if (!_expandedTaskIds.add(task.localId)) {
        _expandedTaskIds.remove(task.localId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WeaveScaffold(
      activeRoute: TaskOrbit.routeName,
      header: const _TaskHeader(),
      child: ValueListenableBuilder<List<VideoTask>>(
        valueListenable: TaskStore.instance.tasks,
        builder: (context, tasks, _) {
          if (tasks.isEmpty) {
            return const _EmptyTasks();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _TaskCard(
                task: task,
                expanded: _expandedTaskIds.contains(task.localId),
                onTap: () => _toggleExpanded(task),
              );
            },
          );
        },
      ),
    );
  }
}

class _TaskHeader extends StatelessWidget {
  const _TaskHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '任务轨道',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text(
              '异步任务队列 · 本地 Go 核心轮询',
              textAlign: TextAlign.left,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '暂无生成任务',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.expanded,
    required this.onTap,
  });

  final VideoTask task;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leftColor = switch (task.status) {
      VideoTaskStatus.processing => AppColors.secondaryAccent,
      VideoTaskStatus.failed => AppColors.danger,
      VideoTaskStatus.completed => AppColors.primaryAccent,
    };

    return InkWell(
      borderRadius: AppRadii.cardRadius,
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.cardRadius,
          border: Border.all(
            color: task.status == VideoTaskStatus.failed
                ? AppColors.danger.withValues(alpha: 0.25)
                : AppColors.border,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              left: 0,
              right: null,
              child: Container(width: 3, color: leftColor),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _Thumb(task: task),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.prompt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              runSpacing: 2,
                              children: [
                                task.model,
                                task.aspectRatio,
                                task.size,
                                _relativeTime(task.createdAt),
                              ]
                                  .map(
                                    (text) => Text(
                                      text,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Task ID: ${task.remoteTaskId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StatusIndicator(status: task.status),
                    ],
                  ),
                  if (expanded) _ErrorDetail(task: task),
                ],
              ),
            ),
          ],
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.task});

  final VideoTask task;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: AppRadii.inputRadius,
        gradient: task.status == VideoTaskStatus.completed
            ? const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              )
            : null,
      ),
      child: task.status == VideoTaskStatus.completed
          ? const Icon(
              Icons.check_rounded,
              color: AppColors.primaryAccent,
              size: 18,
            )
          : Text(
              task.mode == VideoTaskMode.imageToVideo ? 'I2V\n生成中' : 'T2V\n生成中',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final VideoTaskStatus status;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          switch (status) {
            VideoTaskStatus.processing => const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.secondaryAccent,
                  backgroundColor: AppColors.border,
                ),
              ),
            VideoTaskStatus.failed => const Icon(
                Icons.error_outline_rounded,
                color: AppColors.danger,
                size: 24,
              ),
            VideoTaskStatus.completed => const Icon(
                Icons.check_rounded,
                color: AppColors.primaryAccent,
                size: 20,
              ),
          },
          const SizedBox(height: 4),
          Text(
            switch (status) {
              VideoTaskStatus.processing => 'Go 核心\n轮询中',
              VideoTaskStatus.failed => '生成失败',
              VideoTaskStatus.completed => '已完成',
            },
            textAlign: TextAlign.center,
            style: TextStyle(
              color: switch (status) {
                VideoTaskStatus.processing => AppColors.secondaryAccent,
                VideoTaskStatus.failed => AppColors.danger,
                VideoTaskStatus.completed => AppColors.primaryAccent,
              },
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorDetail extends StatelessWidget {
  const _ErrorDetail({required this.task});

  final VideoTask task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: AppRadii.inputRadius,
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          task.errorMessage,
          style: const TextStyle(
            color: AppColors.danger,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}
