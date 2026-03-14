import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/todo_provider.dart';

class TaskPoolTab extends StatefulWidget {
  const TaskPoolTab({super.key});

  @override
  State<TaskPoolTab> createState() => _TaskPoolTabState();
}

class _TaskPoolTabState extends State<TaskPoolTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<TodoProvider>().fetchPools());
  }

  // 弹窗：新建任务池
  void _showAddPoolDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建任务池'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '池子名称（如：面试准备）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<TodoProvider>().addPool(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  // 弹窗：向指定池子添加任务
  void _showAddTaskToPoolDialog(int poolId, String poolName) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加任务到 [$poolName]'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '任务内容'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<TodoProvider>().addTaskToPool(poolId, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  // 弹窗：删除任务池确认
  void _showDeletePoolConfirm(int poolId, String poolName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除该任务池吗？'),
        content: Text('池子 [$poolName] 内的所有任务模板也会被一并清空，此操作不可逆！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await context.read<TodoProvider>().deletePool(poolId);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ 任务池已删除'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ 删除失败，请重试'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();

    return Scaffold(
      body: provider.isPoolsLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: provider.pools.length,
              itemBuilder: (context, index) {
                final pool = provider.pools[index];
                return ExpansionTile(
                  leading: const Icon(Icons.folder_open, color: Colors.orange),
                  title: Text(pool.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        onPressed: () => _showAddTaskToPoolDialog(pool.id, pool.name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _showDeletePoolConfirm(pool.id, pool.name),
                      ),
                    ],
                  ),
                  children: [
                    ...pool.tasks.map((task) {
                      return ListTile(
                        contentPadding: const EdgeInsets.only(left: 40, right: 16),
                        title: Text(task.title),
                        trailing: IconButton(
                          icon: const Icon(Icons.input, color: Colors.blue),
                          tooltip: '导入到我的一天',
                          onPressed: () async {
                            await provider.importToMyDay(task.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已导入到“我的一天”')),
                              );
                            }
                          },
                        ),
                      );
                    }),
                    if (pool.tasks.isEmpty)
                      const ListTile(
                        title: Text('此池子暂无任务', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      )
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPoolDialog,
        backgroundColor: Colors.orange,
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }
}
