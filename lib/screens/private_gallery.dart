import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../theme/app_theme.dart';
import 'create_workspace.dart';

class PrivateGallery extends StatefulWidget {
  const PrivateGallery({super.key});

  static const routeName = '/gallery';

  @override
  State<PrivateGallery> createState() => _PrivateGalleryState();
}

class _PrivateGalleryState extends State<PrivateGallery> {
  final List<_GalleryItem> _items = [
    const _GalleryItem(
      id: 'vid-001',
      prompt: '赛博朋克东京街头的航拍镜头，霓虹灯在雨中闪烁...',
      date: '2 小时前',
      duration: '0:08',
      title: '赛博朋克\n东京夜景',
      colors: [Color(0xFF0A0A2E), Color(0xFF1A1A3E), Color(0xFF2D1B69)],
    ),
    const _GalleryItem(
      id: 'vid-002',
      prompt: '水墨风格山水画动态视频，云雾缭绕山间...',
      date: '5 小时前',
      duration: '0:05',
      title: '水墨山水\n云雾缭绕',
      colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D), Color(0xFF4A4A4A)],
    ),
    const _GalleryItem(
      id: 'vid-003',
      prompt: '4K time-lapse of aurora borealis over snow-capped mountains...',
      date: '昨天',
      duration: '0:12',
      title: '极光雪山\n延时摄影',
      colors: [Color(0xFF0A1628), Color(0xFF0D2137), Color(0xFF1A3A5C)],
    ),
    const _GalleryItem(
      id: 'vid-004',
      prompt:
          'Futuristic city concept art, flying vehicles, holographic ads...',
      date: '昨天',
      duration: '0:06',
      title: '未来城市\n概念设计',
      colors: [Color(0xFF1A0A2E), Color(0xFF2D1B4A), Color(0xFF4A2D6B)],
    ),
    const _GalleryItem(
      id: 'vid-005',
      prompt: '深海发光水母群游动，生物荧光在黑暗中闪烁...',
      date: '3 天前',
      duration: '0:10',
      title: '深海荧光\n水母群游',
      colors: [Color(0xFF0A1A2E), Color(0xFF0D2847), Color(0xFF1A4A6B)],
    ),
  ];

  _GalleryItem? _activeItem;
  bool _confirmingDelete = false;
  String? _toast;

  void _showToast(String message) {
    setState(() => _toast = message);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || _toast != message) return;
      setState(() => _toast = null);
    });
  }

  void _deleteActive() {
    final item = _activeItem;
    if (item == null) return;
    setState(() {
      _items.removeWhere((candidate) => candidate.id == item.id);
      _activeItem = null;
      _confirmingDelete = false;
    });
    _showToast('已删除本地缓存');
  }

  @override
  Widget build(BuildContext context) {
    return WeaveScaffold(
      activeRoute: PrivateGallery.routeName,
      header: _GalleryHeader(count: _items.length),
      overlays: [
        if (_activeItem != null)
          _PlayerOverlay(
            item: _activeItem!,
            confirmingDelete: _confirmingDelete,
            onClose: () => setState(() => _activeItem = null),
            onDownload: () => _showToast('正在导出至 Movies/WeaveFlux...'),
            onDelete: () => setState(() => _confirmingDelete = true),
            onCancelDelete: () => setState(() => _confirmingDelete = false),
            onConfirmDelete: _deleteActive,
          ),
        if (_toast != null) _Toast(message: _toast!),
      ],
      child: MasonryGridView.count(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _GalleryTile(
            item: item,
            onTap: () => setState(() => _activeItem = item),
          );
        },
      ),
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

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.item, required this.onTap});

  final _GalleryItem item;
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
                    aspectRatio: 9 / 16,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: item.colors,
                        ),
                      ),
                      child: Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.date,
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
                      child: Text(
                        item.duration,
                        style: const TextStyle(
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
}

class _PlayerOverlay extends StatefulWidget {
  const _PlayerOverlay({
    required this.item,
    required this.confirmingDelete,
    required this.onClose,
    required this.onDownload,
    required this.onDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  final _GalleryItem item;
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
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: widget.item.colors,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(32),
                    onTap: () => setState(() => _playing = !_playing),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: Colors.white.withValues(alpha: 0.15),
                          child: Icon(
                            _playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: AppColors.foreground,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      widget.item.prompt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
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
                '此操作将永久删除该视频的本地缓存文件。已导出至系统相册的副本不受影响。',
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

class _GalleryItem {
  const _GalleryItem({
    required this.id,
    required this.prompt,
    required this.date,
    required this.duration,
    required this.title,
    required this.colors,
  });

  final String id;
  final String prompt;
  final String date;
  final String duration;
  final String title;
  final List<Color> colors;
}
