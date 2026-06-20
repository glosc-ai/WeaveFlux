import 'dart:async';

import 'package:flutter/material.dart';

import '../services/model_catalog.dart';
import '../services/task_store.dart';
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
  Timer? _taskPollTimer;

  static const _pages = [
    CreateWorkspace(),
    TaskOrbit(),
    PrivateGallery(),
    SettingsPanel(),
  ];

  void _openSettings() {
    setState(() => _currentIndex = 3);
  }

  void _openTasks() {
    setState(() => _currentIndex = 1);
  }

  @override
  void initState() {
    super.initState();
    TaskStore.instance.load();
    ModelCatalog.instance.refreshFromSavedCredentials();
    TaskStore.instance.pollProcessingTasks();
    _taskPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => TaskStore.instance.pollProcessingTasks(),
    );
  }

  @override
  void dispose() {
    _taskPollTimer?.cancel();
    super.dispose();
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
                children: [
                  CreateWorkspace(
                    onOpenSettings: _openSettings,
                    onOpenTasks: _openTasks,
                  ),
                  _pages[1],
                  _pages[2],
                  _pages[3],
                ],
              ),
            ),
            _BottomNav(
              currentIndex: _currentIndex,
              onChanged: (index) => setState(() => _currentIndex = index),
            ),
          ],
        ),
      ),
    );
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
      _NavItem('创作', Icons.auto_awesome),
      _NavItem('任务', Icons.track_changes),
      _NavItem('画廊', Icons.grid_view_rounded),
      _NavItem('设置', Icons.settings_outlined),
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
