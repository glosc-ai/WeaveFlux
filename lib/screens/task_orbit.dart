import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'create_workspace.dart';

class TaskOrbit extends StatefulWidget {
  const TaskOrbit({super.key});

  static const routeName = '/tasks';

  @override
  State<TaskOrbit> createState() => _TaskOrbitState();
}

class _TaskOrbitState extends State<TaskOrbit> {
  final List<_TaskItem> _tasks = [
    const _TaskItem(
      status: _TaskStatus.processing,
      title: '赛博朋克\n东京夜景',
      prompt: '一段赛博朋克东京街头的航拍镜头，霓虹灯在雨中闪烁...',
      model: 'kling-v2',
      ratio: '16:9',
      time: '2 分钟前',
    ),
    const _TaskItem(
      status: _TaskStatus.failed,
      title: '极光下的\n雪山延时',
      prompt: '4K time-lapse of aurora borealis over snow-capped mountains...',
      model: 'kling-v2',
      ratio: '9:16',
      time: '12 分钟前',
      errorCode: 'HTTP 401 Unauthorized',
      errorBody:
          '{\n  "error": {\n    "code": "invalid_api_key",\n    "message": "The API key provided is not valid",\n    "type": "authentication_error"\n  }\n}',
    ),
    const _TaskItem(
      status: _TaskStatus.completed,
      title: '水墨山水\n云雾缭绕',
      prompt: '水墨风格山水画动态视频，云雾缭绕...',
      model: 't2v-default',
      ratio: '1:1',
      time: '1 小时前',
    ),
    const _TaskItem(
      status: _TaskStatus.processing,
      title: '未来城市\n概念设计',
      prompt:
          'Futuristic city concept art, flying vehicles, holographic ads...',
      model: 'kling-v2',
      ratio: '16:9',
      time: '刚刚',
    ),
  ];

  void _toggleExpanded(int index) {
    if (_tasks[index].status != _TaskStatus.failed) return;
    setState(() {
      _tasks[index] = _tasks[index].copyWith(
        expanded: !_tasks[index].expanded,
      );
    });
  }

  void _retry(int index) {
    setState(() {
      _tasks[index] = _tasks[index].copyWith(
        status: _TaskStatus.processing,
        expanded: false,
        time: '刚刚',
      );
    });

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _tasks[index] = _tasks[index].copyWith(status: _TaskStatus.completed);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return WeaveScaffold(
      activeRoute: TaskOrbit.routeName,
      header: const _TaskHeader(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        itemCount: _tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _TaskCard(
            task: _tasks[index],
            onTap: () => _toggleExpanded(index),
            onRetry: () => _retry(index),
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onTap,
    required this.onRetry,
  });

  final _TaskItem task;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final leftColor = switch (task.status) {
      _TaskStatus.processing => AppColors.secondaryAccent,
      _TaskStatus.failed => AppColors.danger,
      _TaskStatus.completed => AppColors.primaryAccent,
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
            color: task.status == _TaskStatus.failed
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
                              children: [task.model, task.ratio, task.time]
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StatusIndicator(status: task.status),
                    ],
                  ),
                  if (task.expanded) _ErrorDetail(task: task, onRetry: onRetry),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.task});

  final _TaskItem task;

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
        gradient: task.status == _TaskStatus.completed
            ? const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              )
            : null,
      ),
      child: task.status == _TaskStatus.completed
          ? const Icon(
              Icons.check_rounded,
              color: AppColors.primaryAccent,
              size: 18,
            )
          : Text(
              task.title,
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

  final _TaskStatus status;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          switch (status) {
            _TaskStatus.processing => const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.secondaryAccent,
                  backgroundColor: AppColors.border,
                ),
              ),
            _TaskStatus.failed => const Icon(
                Icons.error_outline_rounded,
                color: AppColors.danger,
                size: 24,
              ),
            _TaskStatus.completed => const Icon(
                Icons.check_rounded,
                color: AppColors.primaryAccent,
                size: 20,
              ),
          },
          const SizedBox(height: 4),
          Text(
            switch (status) {
              _TaskStatus.processing => 'Go 核心\n轮询中',
              _TaskStatus.failed => '生成失败',
              _TaskStatus.completed => '已完成',
            },
            textAlign: TextAlign.center,
            style: TextStyle(
              color: switch (status) {
                _TaskStatus.processing => AppColors.secondaryAccent,
                _TaskStatus.failed => AppColors.danger,
                _TaskStatus.completed => AppColors.primaryAccent,
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
  const _ErrorDetail({required this.task, required this.onRetry});

  final _TaskItem task;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
              '${task.errorCode}\n${task.errorBody}',
              style: const TextStyle(
                color: AppColors.danger,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

enum _TaskStatus { processing, failed, completed }

class _TaskItem {
  const _TaskItem({
    required this.status,
    required this.title,
    required this.prompt,
    required this.model,
    required this.ratio,
    required this.time,
    this.errorCode = '',
    this.errorBody = '',
    this.expanded = false,
  });

  final _TaskStatus status;
  final String title;
  final String prompt;
  final String model;
  final String ratio;
  final String time;
  final String errorCode;
  final String errorBody;
  final bool expanded;

  _TaskItem copyWith({
    _TaskStatus? status,
    String? time,
    bool? expanded,
  }) {
    return _TaskItem(
      status: status ?? this.status,
      title: title,
      prompt: prompt,
      model: model,
      ratio: ratio,
      time: time ?? this.time,
      errorCode: errorCode,
      errorBody: errorBody,
      expanded: expanded ?? this.expanded,
    );
  }
}
