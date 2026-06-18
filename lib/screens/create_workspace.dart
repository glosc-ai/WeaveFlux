import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum CreationMode { textToVideo, imageToVideo }

class CreateWorkspace extends StatefulWidget {
  const CreateWorkspace({this.onOpenSettings, super.key});

  static const routeName = '/';

  final VoidCallback? onOpenSettings;

  @override
  State<CreateWorkspace> createState() => _CreateWorkspaceState();
}

class _CreateWorkspaceState extends State<CreateWorkspace> {
  final _promptController = TextEditingController();
  final _modelController = TextEditingController(text: 't2v-default-model');
  CreationMode _mode = CreationMode.textToVideo;
  bool _advancedOpen = true;
  String _ratio = '16:9';
  double _motion = 0.5;
  bool _sheetOpen = false;

  @override
  void dispose() {
    _promptController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WeaveScaffold(
      activeRoute: CreateWorkspace.routeName,
      bottomAction: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: _GradientButton(
          label: '开始织影',
          onTap: () => setState(() => _sheetOpen = true),
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
          _SegmentedMode(
            mode: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          const SizedBox(height: 20),
          _PromptCard(
            mode: _mode,
            controller: _promptController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _AdvancedToggle(
            open: _advancedOpen,
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _AdvancedPanel(
              modelController: _modelController,
              ratio: _ratio,
              motion: _motion,
              onRatioChanged: (value) => setState(() => _ratio = value),
              onMotionChanged: (value) => setState(() => _motion = value),
            ),
            crossFadeState: _advancedOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
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

class _SegmentedMode extends StatelessWidget {
  const _SegmentedMode({required this.mode, required this.onChanged});

  final CreationMode mode;
  final ValueChanged<CreationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: '文生视频',
            active: mode == CreationMode.textToVideo,
            onTap: () => onChanged(CreationMode.textToVideo),
          ),
          _SegmentButton(
            label: '图生视频',
            active: mode == CreationMode.imageToVideo,
            onTap: () => onChanged(CreationMode.imageToVideo),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
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
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppColors.foreground : AppColors.muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.mode,
    required this.controller,
    required this.onChanged,
  });

  final CreationMode mode;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.length;

    return Container(
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: mode == CreationMode.textToVideo
          ? Column(
              children: [
                TextField(
                  controller: controller,
                  onChanged: onChanged,
                  maxLength: 500,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText:
                        '描述你想要的画面...\n例如：一段赛博朋克东京街头的航拍镜头，霓虹灯在雨中闪烁，慢动作 cinematic',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$length / 500',
                    style: TextStyle(
                      color: length > 450 ? AppColors.danger : AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            )
          : Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: AppRadii.inputRadius,
                border: Border.all(
                  color: AppColors.border,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0x1F3B82F6),
                    child: Icon(Icons.upload_rounded,
                        color: AppColors.secondaryAccent),
                  ),
                  SizedBox(height: 10),
                  Text('+ 选择参考图片', style: TextStyle(color: AppColors.muted)),
                  SizedBox(height: 4),
                  Text(
                    '支持 JPG / PNG，最大 10MB',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ],
              ),
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
      icon: Text(open ? '▴' : '▾', style: const TextStyle(fontSize: 10)),
      label: const Text('高级选项'),
    );
  }
}

class _AdvancedPanel extends StatelessWidget {
  const _AdvancedPanel({
    required this.modelController,
    required this.ratio,
    required this.motion,
    required this.onRatioChanged,
    required this.onMotionChanged,
  });

  final TextEditingController modelController;
  final String ratio;
  final double motion;
  final ValueChanged<String> onRatioChanged;
  final ValueChanged<double> onMotionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('模型'),
          TextField(
            controller: modelController,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('画面比例'),
          Row(
            children: [
              _RatioButton(
                label: '16:9 横屏',
                ratio: '16:9',
                graphicSize: const Size(32, 18),
                selected: ratio == '16:9',
                onTap: onRatioChanged,
              ),
              const SizedBox(width: 10),
              _RatioButton(
                label: '9:16 竖屏',
                ratio: '9:16',
                graphicSize: const Size(18, 32),
                selected: ratio == '9:16',
                onTap: onRatioChanged,
              ),
              const SizedBox(width: 10),
              _RatioButton(
                label: '1:1 方形',
                ratio: '1:1',
                graphicSize: const Size(22, 22),
                selected: ratio == '1:1',
                onTap: onRatioChanged,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _FieldLabel('动态幅度'),
              Text(
                motion.toStringAsFixed(2),
                style: const TextStyle(
                  color: AppColors.secondaryAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: motion,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: onMotionChanged,
          ),
        ],
      ),
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

class _RatioButton extends StatelessWidget {
  const _RatioButton({
    required this.label,
    required this.ratio,
    required this.graphicSize,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String ratio;
  final Size graphicSize;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.secondaryAccent : AppColors.muted;

    return Expanded(
      child: InkWell(
        borderRadius: AppRadii.inputRadius,
        onTap: () => onTap(ratio),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.secondaryAccent.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: AppRadii.inputRadius,
            border: Border.all(
                color: selected ? AppColors.secondaryAccent : AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                width: graphicSize.width,
                height: graphicSize.height,
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF059669)],
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
                      '未配置 API 密钥',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'WeaveFlux 需要兼容 OpenAI 规范的 Base URL 和 API Key 才能开始创作。所有凭证仅存储在本地 Android KeyStore 中。',
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
