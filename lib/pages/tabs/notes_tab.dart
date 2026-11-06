import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../providers/todo_provider.dart';
import '../../models/todo_models.dart';
import '../../widgets/note_markdown.dart';
import '../note_editor_page.dart';

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

  void _openEditor({Note? note}) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final previewStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: const TextStyle(fontSize: 15, height: 1.4),
      h1: theme.textTheme.titleLarge,
      h2: theme.textTheme.titleMedium,
      h3: theme.textTheme.titleSmall,
    );

    return Scaffold(
      body: provider.isNotesLoading && provider.notes.isEmpty
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
                  key: ValueKey(note.id),
                  elevation: 1,
                  color: colors.brightness == Brightness.dark
                      ? Color.alphaBlend(
                          _getNoteColor(index).withValues(alpha: 0.16),
                          colors.surfaceContainerHigh,
                        )
                      : _getNoteColor(index),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openEditor(note: note),
                    onLongPress: () => _showDeleteConfirm(note),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IgnorePointer(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 168),
                              child: SingleChildScrollView(
                                primary: false,
                                physics: const NeverScrollableScrollPhysics(),
                                child: MarkdownBody(
                                  data: note.content,
                                  softLineBreak: true,
                                  styleSheet: previewStyle,
                                  inlineSyntaxes: noteInlineSyntaxes,
                                  imageBuilder: noteImagePlaceholder,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            note.createdAt,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // 先关闭对话框
              final success = await context.read<TodoProvider>().deleteNote(
                note.id,
              );
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
