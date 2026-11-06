import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/todo_provider.dart';

class MyDayTab extends StatefulWidget {
  const MyDayTab({super.key, this.onOpenPool});
  final VoidCallback? onOpenPool;

  @override
  State<MyDayTab> createState() => _MyDayTabState();
}

class _MyDayTabState extends State<MyDayTab> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<TodoProvider>().fetchMyDay();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submitTask() {
    if (_inputController.text.isNotEmpty) {
      context.read<TodoProvider>().addTodo(_inputController.text);
      _inputController.clear();
      // 收起键盘
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final colors = Theme.of(context).colorScheme;
    final today = provider.taskDate;
    final dateStr = DateFormat('MM月dd日').format(today);
    final weekdayStr = DateFormat('EEEE', 'zh_CN').format(today);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 大字号日期头部
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的一天',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
                Text(
                  '$dateStr, $weekdayStr · 每天 04:00 更新',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 2. 临时任务输入框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.add, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: '准备做点什么？',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _submitTask(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: _submitTask,
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (widget.onOpenPool != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onOpenPool,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('从任务池选取'),
                ),
              ),
            ),

          // 3. 任务列表
          Expanded(
            child: provider.isMyDayLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: provider.myDayTodos.length,
                    itemBuilder: (context, index) {
                      final todo = provider.myDayTodos[index];
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          elevation: 0,
                          color: todo.isCompleted || todo.isExpired
                              ? colors.surfaceContainerHigh
                              : colors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: colors.outlineVariant),
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: Text(
                              todo.title,
                              style: TextStyle(
                                decoration: todo.isCompleted || todo.isExpired
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: todo.isCompleted || todo.isExpired
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                              ),
                            ),
                            subtitle: todo.goalTaskId == null
                                ? null
                                : Text(
                                    [
                                      '长期目标 · ${todo.goalTitle}',
                                      if (todo.isExpired && !todo.isCompleted)
                                        '已过期',
                                      if (todo.deadline != null)
                                        '${todo.deadline} 截止',
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                            value: todo.isCompleted,
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            onChanged:
                                provider.isTodoUpdating(todo.id) ||
                                    (todo.goalTaskId != null &&
                                        provider.isGoalBusy)
                                ? null
                                : (_) async {
                                    final success = await provider
                                        .toggleTodoStatus(todo);
                                    if (context.mounted && !success) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('状态更新失败，请刷新后重试'),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
