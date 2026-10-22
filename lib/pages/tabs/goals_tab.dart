import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/todo_models.dart';
import '../../providers/todo_provider.dart';
import '../../widgets/goal_widgets.dart';

class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key, this.onOpenPool});
  final VoidCallback? onOpenPool;

  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends State<GoalsTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<TodoProvider>().fetchGoals();
    });
  }

  Widget _goalCard(BuildContext context, LongTermGoal goal) {
    final provider = context.watch<TodoProvider>();
    final colors = Theme.of(context).colorScheme;
    final muted = goal.isCompleted || goal.isExpired;
    return Card(
      key: ValueKey('goal-${goal.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    goal.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      decoration: muted ? TextDecoration.lineThrough : null,
                      color: muted ? colors.onSurfaceVariant : colors.onSurface,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !provider.isGoalBusy,
                  tooltip: '目标操作',
                  onSelected: (action) {
                    if (action == 'edit') showGoalEditor(context, goal: goal);
                    if (action == 'delete') {
                      deleteGoalWithConfirmation(context, goal);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑目标')),
                    PopupMenuItem(value: 'delete', child: Text('删除目标及全部子任务')),
                  ],
                ),
              ],
            ),
            if (goal.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(goal.description),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GoalStatusLabel(
                  status: goal.isCompleted
                      ? 'completed'
                      : goal.isExpired
                      ? 'expired'
                      : 'active',
                ),
                Text(
                  goal.deadline == null ? '无截止日期' : '${goal.deadline} 截止',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: goal.progress,
              minHeight: 6,
              semanticsLabel: '${goal.title}完成进度',
              semanticsValue: '${(goal.progress * 100).floor()}',
            ),
            const SizedBox(height: 6),
            Text(
              '${goal.completedTasks} / ${goal.tasks.length} 项子任务已完成 · ${(goal.progress * 100).floor()}%',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            GoalTaskList(goal: goal),
            const Divider(),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: provider.isGoalBusy
                      ? null
                      : () => showGoalTaskEditor(context, goal.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加子任务'),
                ),
                if (widget.onOpenPool != null)
                  TextButton(
                    onPressed: widget.onOpenPool,
                    child: const Text('到任务池安排今天 →'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    return RefreshIndicator(
      onRefresh: provider.refreshTaskViews,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('长期目标', style: Theme.of(context).textTheme.headlineSmall),
              FilledButton.icon(
                onPressed: provider.isGoalBusy
                    ? null
                    : () => showGoalEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('新建目标'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.isGoalsLoading) const LinearProgressIndicator(),
          if (provider.goalsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.goalsError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: provider.isGoalsLoading
                        ? null
                        : provider.fetchGoals,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (!provider.isGoalsLoading &&
              provider.goalsError == null &&
              provider.goals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('还没有长期目标，先创建一个，再拆分子任务。')),
            ),
          ...provider.goals.map((goal) => _goalCard(context, goal)),
        ],
      ),
    );
  }
}
