import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final List<String> _titles = ['我的一天', '长期目标', '灵感便签'];

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
    setState(() => _currentIndex = 0);
    if (!_wideLayout) _scaffoldKey.currentState?.openDrawer();
  }

  void _openGoals() {
    _closeDrawer();
    setState(() => _currentIndex = 1);
  }

  Widget _navigation() => NavigationBar(
    selectedIndex: _currentIndex,
    onDestinationSelected: (index) => setState(() => _currentIndex = index),
    destinations: const [
      NavigationDestination(icon: Icon(Icons.sunny), label: '我的一天'),
      NavigationDestination(icon: Icon(Icons.flag_outlined), label: '长期目标'),
      NavigationDestination(icon: Icon(Icons.note_alt), label: '便签墙'),
    ],
  );

  void _showDonateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打赏作者', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                'http://8.138.22.227:8080/api/donate/qr',
                width: 250,
                height: 250,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    width: 250,
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 250,
                    height: 250,
                    color: Colors.grey[100],
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('二维码加载失败', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '感谢支持独立开发！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

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
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: _handleRefresh,
            tooltip: '刷新',
          ),
        ],
      ),
      // 将任务池改为侧滑抽屉 (Pool Drawer)
      drawer: _wideLayout ? null : Drawer(child: _poolPanel()),
      body: Row(
        children: [
          if (_wideLayout) ...[
            SizedBox(width: 320, child: _poolPanel()),
            const VerticalDivider(width: 1),
          ],
          Expanded(
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

  Widget _poolPanel() => SafeArea(
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
            decoration: const BoxDecoration(color: Colors.blue),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pool, size: 48, color: Colors.white),
                  const SizedBox(height: 8),
                  const Text(
                    '任务分类池',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: TaskPoolTab(onManageGoals: _openGoals)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.favorite, color: Colors.redAccent),
          title: const Text('打赏支持'),
          onTap: () {
            _closeDrawer();
            _showDonateDialog();
          },
        ),
        ListTile(
          leading: const Icon(Icons.cloud_circle, color: Colors.blue),
          title: const Text('共享文件大厅'),
          onTap: () {
            _closeDrawer();
            Navigator.pushNamed(context, '/shared_files');
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings, color: Colors.blueGrey),
          title: const Text('连接设置'),
          onTap: () {
            _closeDrawer();
            Navigator.pushNamed(context, '/settings');
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.grey),
          title: const Text('退出登录'),
          onTap: () {
            _closeDrawer();
            _logout();
          },
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}
