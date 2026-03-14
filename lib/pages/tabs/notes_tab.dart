import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../providers/todo_provider.dart';
import '../../models/todo_models.dart';

class NotesTab extends StatefulWidget {
  const NotesTab({super.key});

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<TodoProvider>().fetchNotes());
  }

  void _showNoteDialog({Note? note}) {
    final controller = TextEditingController(text: note?.content ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? '新便签' : '编辑便签'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(hintText: '记录这一刻的灵感...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final provider = context.read<TodoProvider>();
                if (note == null) {
                  provider.addNote(controller.text);
                } else {
                  provider.updateNote(note.id, controller.text);
                }
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: provider.isNotesLoading
          ? const Center(child: CircularProgressIndicator())
          : MasonryGridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              itemCount: provider.notes.length,
              itemBuilder: (context, index) {
                final note = provider.notes[index];
                // 模拟瀑布流随机高度
                return Card(
                  elevation: 1,
                  color: _getNoteColor(index),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showNoteDialog(note: note),
                    onLongPress: () => _showDeleteConfirm(note),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.content,
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            note.createdAt,
                            style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.4)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteDialog(),
        backgroundColor: Colors.amber[700],
        icon: const Icon(Icons.add),
        label: const Text('记笔记'),
      ),
    );
  }

  void _showDeleteConfirm(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除便签'),
        content: const Text('确定要删除这张便签吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // 先关闭对话框
              final success = await context.read<TodoProvider>().deleteNote(note.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ 删除成功'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ 删除失败，请重试'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
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

  Color _getNoteColor(int index) {
    final colors = [
      Colors.yellow[100]!,
      Colors.blue[100]!,
      Colors.green[100]!,
      Colors.orange[100]!,
      Colors.pink[100]!,
      Colors.purple[100]!,
    ];
    return colors[index % colors.length];
  }
}
