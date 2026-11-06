import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/todo_provider.dart';
import '../models/todo_models.dart';
import 'tabs/my_day_tab.dart';
import 'tabs/task_pool_tab.dart';
import 'tabs/notes_tab.dart';
import 'tabs/goals_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _dateTimer;
  DateTime _lastDate = taskDateForInstant(DateTime.now());
  bool _wideLayout = false;
  bool _sidebarCollapsed = false;

  final List<String> _titles = ['我的一天', '长期目标', '灵感便签'];
  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.sunny), label: '我的一天'),
    NavigationDestination(icon: Icon(Icons.flag_outlined), label: '长期目标'),
    NavigationDestination(icon: Icon(Icons.note_alt), label: '便签墙'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final date = taskDateForInstant(DateTime.now());
      if (date != _lastDate) {
        _lastDate = date;
        context.read<TodoProvider>().refreshTaskViews();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _lastDate = taskDateForInstant(DateTime.now());
      context.read<TodoProvider>().refreshTaskViews();
      context.read<TodoProvider>().fetchPools();
    }
  }

  @override
  void dispose() {
    _dateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _openTaskPool() {
    setState(() {
      _currentIndex = 0;
      _sidebarCollapsed = false;
    });
    if (!_wideLayout) _scaffoldKey.currentState?.openDrawer();
  }

  void _openGoals() {
    _closeDrawer();
    setState(() => _currentIndex = 1);
  }

  Widget _navigation() => NavigationBar(
    selectedIndex: _currentIndex,
    onDestinationSelected: (index) => setState(() => _currentIndex = index),
    destinations: _destinations,
  );

  void _openSettings() {
    _closeDrawer();
    Navigator.pushNamed(context, '/settings', arguments: true);
  }

  void _openSharedFiles() {
    _closeDrawer();
    Navigator.pushNamed(context, '/shared_files');
  }

  Widget _compactNavigation() => NavigationRail(
    selectedIndex: _currentIndex,
    onDestinationSelected: (index) => setState(() => _currentIndex = index),
    scrollable: true,
    destinations: [
      for (final destination in _destinations)
        NavigationRailDestination(
          icon: Tooltip(message: destination.label, child: destination.icon),
          label: Text(destination.label),
        ),
    ],
    trailing: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.cloud_circle_outlined),
          tooltip: '共享文件大厅',
          onPressed: _openSharedFiles,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: '设置',
          onPressed: _openSettings,
        ),
      ],
    ),
  );

  Future<void> _handleRefresh() async {
    // 弹出加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在同步数据...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      await context.read<TodoProvider>().refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 数据已同步'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 刷新失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _wideLayout = MediaQuery.sizeOf(context).width >= 1000;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: _wideLayout
            ? IconButton(
                icon: Icon(_sidebarCollapsed ? Icons.menu : Icons.menu_open),
                tooltip: _sidebarCollapsed ? '展开侧栏' : '收起侧栏',
                onPressed: () => setState(() {
                  _sidebarCollapsed = !_sidebarCollapsed;
                }),
              )
            : null,
        title: Text(_titles[_currentIndex]),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleRefresh,
            tooltip: '刷新',
          ),
        ],
      ),
      // 将任务池改为侧滑抽屉 (Pool Drawer)
      drawer: _wideLayout ? null : Drawer(child: _poolPanel(colors)),
      body: Row(
        children: [
          if (_wideLayout) ...[
            Visibility(
              visible: !_sidebarCollapsed,
              maintainState: true,
              child: SizedBox(width: 320, child: _poolPanel(colors)),
            ),
            if (_sidebarCollapsed) _compactNavigation(),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            key: const ValueKey('home-content'),
            child: IndexedStack(
              index: _currentIndex,
              children: [
                MyDayTab(onOpenPool: _openTaskPool),
                GoalsTab(onOpenPool: _openTaskPool),
                const NotesTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _wideLayout ? null : _navigation(),
    );
  }

  Widget _poolPanel(ColorScheme colors) => SafeArea(
    child: Column(
      children: [
        if (_wideLayout) _navigation(),
        if (_wideLayout)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('任务分类池', style: TextStyle(fontSize: 18)),
          ),
        if (!_wideLayout)
          DrawerHeader(
            decoration: BoxDecoration(color: colors.primaryContainer),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pool, size: 48, color: colors.onPrimaryContainer),
                  const SizedBox(height: 8),
                  Text(
                    '任务分类池',
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: TaskPoolTab(onManageGoals: _openGoals)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.cloud_circle, color: Colors.blue),
          title: const Text('共享文件大厅'),
          onTap: _openSharedFiles,
        ),
        ListTile(
          leading: const Icon(Icons.settings, color: Colors.blueGrey),
          title: const Text('设置'),
          onTap: _openSettings,
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}
