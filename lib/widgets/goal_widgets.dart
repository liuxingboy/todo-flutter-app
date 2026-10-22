import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo_models.dart';
import '../providers/todo_provider.dart';

Future<void> showGoalEditor(BuildContext context, {LongTermGoal? goal}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GoalEditor(goal: goal),
    );

Future<void> showGoalTaskEditor(
  BuildContext context,
  int goalId, {
  GoalTask? task,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _GoalEditor(goalId: goalId, task: task),
);

Future<void> deleteGoalWithConfirmation(
  BuildContext context,
  LongTermGoal goal,
) async {
  final provider = context.read<TodoProvider>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除长期目标？'),
      content: Text(
        '“${goal.title}”及其全部 ${goal.tasks.length} 项子任务将被删除，'
        '这些子任务在“我的一天”中的记录也会同步删除。此操作无法撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            '全部删除',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final success = await provider.deleteGoal(goal.id);
  if (context.mounted && !success) showGoalError(context, provider);
}

void showGoalError(BuildContext context, TodoProvider provider) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(provider.goalActionError ?? '操作未完成，请稍后重试')),
  );
}

class GoalStatusLabel extends StatelessWidget {
  const GoalStatusLabel({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (status) {
      'expired' => '已过期',
      'completed' => '已完成',
      _ => '进行中',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status == 'active'
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: status == 'active'
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.goal, this.goalId, this.task});
  final LongTermGoal? goal;
  final int? goalId;
  final GoalTask? task;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _deadline;
  bool _saving = false;
  String? _error;

  bool get _isTask => widget.goalId != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.task?.content ?? widget.goal?.title ?? '',
    );
    _description = TextEditingController(text: widget.goal?.description ?? '');
    _deadline = widget.task?.deadline ?? widget.goal?.deadline;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline == null
          ? DateTime.now()
          : DateTime.parse(_deadline!),
      firstDate: DateTime(1000),
      lastDate: DateTime(9999, 12, 31),
      helpText: '选择截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (date != null && mounted) {
      setState(
        () => _deadline =
            '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final provider = context.read<TodoProvider>();
    final success = _isTask
        ? await provider.saveGoalTask(
            goalId: widget.goalId!,
            taskId: widget.task?.id,
            content: _title.text,
            deadline: _deadline,
          )
        : await provider.saveGoal(
            id: widget.goal?.id,
            title: _title.text,
            description: _description.text,
            deadline: _deadline,
          );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = provider.goalActionError ?? '操作未完成，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.goal != null || widget.task != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text('${editing ? '编辑' : '新建'}${_isTask ? '子任务' : '长期目标'}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  autofocus: true,
                  maxLength: _isTask ? 500 : 200,
                  decoration: InputDecoration(
                    labelText: _isTask ? '子任务内容' : '目标名称',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入内容' : null,
                ),
                if (!_isTask)
                  TextFormField(
                    controller: _description,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '目标说明（可选）'),
                    validator: (value) =>
                        utf8.encode(value ?? '').length > 10000
                        ? '说明内容过长，请缩短后再保存'
                        : null,
                  ),
                const SizedBox(height: 16),
                const Text('截止日期（可选）'),
                const Text(
                  '截止日次日北京时间 04:00 前均有效',
                  style: TextStyle(fontSize: 12),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_deadline ?? '不设截止日期'),
                    ),
                    if (_deadline != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _deadline = null),
                        child: const Text('清除日期'),
                      ),
                  ],
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

class GoalTaskList extends StatelessWidget {
  const GoalTaskList({
    super.key,
    required this.goal,
    this.selectForToday = false,
  });
  final LongTermGoal goal;
  final bool selectForToday;

  Future<void> _deleteTask(BuildContext context, GoalTask task) async {
    final provider = context.read<TodoProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除子任务？'),
        content: Text('“${task.content}”及其在“我的一天”中的关联记录将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await provider.deleteGoalTask(task.id);
    if (context.mounted && !success) showGoalError(context, provider);
  }

  Widget _tile(BuildContext context, GoalTask task) {
    final provider = context.watch<TodoProvider>();
    final muted = task.isCompleted || task.isExpired;
    final colors = Theme.of(context).colorScheme;
    final title = Text(
      task.content,
      style: TextStyle(
        decoration: muted ? TextDecoration.lineThrough : null,
        color: muted ? colors.onSurfaceVariant : colors.onSurface,
      ),
    );
    final subtitle = Text(
      [
        if (task.isExpired) '已过期',
        task.deadline == null ? '无截止日期' : '${task.deadline} 截止',
      ].join(' · '),
      style: const TextStyle(fontSize: 12),
    );
    return ListTile(
      key: ValueKey('goal-task-${selectForToday ? 'pool' : 'goal'}-${task.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: selectForToday
          ? Icon(task.isExpired ? Icons.event_busy : Icons.task_alt, size: 20)
          : Checkbox(
              value: task.isCompleted,
              onChanged: provider.isGoalBusy
                  ? null
                  : (value) async {
                      final success = await provider.setGoalTaskStatus(
                        task.id,
                        value!,
                      );
                      if (context.mounted && !success) {
                        showGoalError(context, provider);
                      }
                    },
            ),
      title: title,
      subtitle: subtitle,
      trailing: selectForToday
          ? (task.isCompleted
                ? const Text('已完成', style: TextStyle(fontSize: 12))
                : TextButton(
                    onPressed: provider.isGoalBusy || task.isInMyDay
                        ? null
                        : () async {
                            final success = await provider.addGoalTaskToMyDay(
                              task.id,
                            );
                            if (!context.mounted) return;
                            if (!success) {
                              showGoalError(context, provider);
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已加入“我的一天”')),
                            );
                          },
                    child: Text(task.isInMyDay ? '已选今天' : '加入今天'),
                  ))
          : PopupMenuButton<String>(
              enabled: !provider.isGoalBusy,
              tooltip: '子任务操作',
              onSelected: (action) {
                if (action == 'edit') {
                  showGoalTaskEditor(context, goal.id, task: task);
                }
                if (action == 'delete') _deleteTask(context, task);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑子任务')),
                PopupMenuItem(value: 'delete', child: Text('删除子任务')),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = goal.tasks.where(
      (task) => !task.isCompleted && !task.isExpired,
    );
    final completed = goal.tasks.where((task) => task.isCompleted);
    final expired = goal.tasks.where(
      (task) => !task.isCompleted && task.isExpired,
    );
    return Column(
      children: [
        ...active.map((task) => _tile(context, task)),
        if (completed.isNotEmpty)
          ExpansionTile(
            key: PageStorageKey('goal-completed-$selectForToday-${goal.id}'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              '已完成（${completed.length}）',
              style: const TextStyle(fontSize: 13),
            ),
            children: completed.map((task) => _tile(context, task)).toList(),
          ),
        ...expired.map((task) => _tile(context, task)),
        if (goal.tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('暂无子任务，可在长期目标页添加'),
          ),
      ],
    );
  }
}
