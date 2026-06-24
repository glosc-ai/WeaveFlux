import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'create_workspace.dart';
import 'private_gallery.dart';
import 'settings_panel.dart';
import 'task_orbit.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  final Set<int> _visitedPages = <int>{0};

  void _openSettings() {
    _selectPage(3);
  }

  void _openTasks() {
    _selectPage(1);
  }

  void _selectPage(int index) {
    setState(() {
      _currentIndex = index;
      _visitedPages.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: List<Widget>.generate(
                  4,
                  (index) => _visitedPages.contains(index)
                      ? _buildPage(index)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            _BottomNav(
              currentIndex: _currentIndex,
              onChanged: _selectPage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    return switch (index) {
      0 => CreateWorkspace(
          onOpenSettings: _openSettings,
          onOpenTasks: _openTasks,
        ),
      1 => const TaskOrbit(),
      2 => const PrivateGallery(),
      3 => const SettingsPanel(),
      _ => const SizedBox.shrink(),
    };
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem('\u521b\u4f5c', Icons.auto_awesome),
      _NavItem('\u4efb\u52a1', Icons.track_changes),
      _NavItem('\u753b\u5eca', Icons.grid_view_rounded),
      _NavItem('\u8bbe\u7f6e', Icons.settings_outlined),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var index = 0; index < items.length; index++)
            Expanded(
              child: InkWell(
                borderRadius: AppRadii.inputRadius,
                onTap: index == currentIndex ? null : () => onChanged(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[index].icon,
                        size: 20,
                        color: index == currentIndex
                            ? AppColors.primaryAccent
                            : AppColors.muted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[index].label,
                        style: TextStyle(
                          color: index == currentIndex
                              ? AppColors.primaryAccent
                              : AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
