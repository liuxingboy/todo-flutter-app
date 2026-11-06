import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../models/todo_models.dart';
import '../providers/todo_provider.dart';
import '../widgets/note_markdown.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.note});

  final Note? note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final String _original = widget.note?.content ?? '';
  late String _content = _original;
  late final _editor = TextEditingController(text: _original);
  final _focus = FocusNode();
  final _undo = UndoHistoryController();
  bool _preview = false;
  bool _saving = false;
  bool _confirmingExit = false;
  String? _saveError;

  bool get _dirty => _content != _original;

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onEdit);
  }

  void _onEdit() {
    if (_content == _editor.text) return;
    setState(() {
      _content = _editor.text;
      _saveError = null;
    });
  }

  @override
  void dispose() {
    _editor.dispose();
    _focus.dispose();
    _undo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _confirmingExit || _content.trim().isEmpty) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final provider = context.read<TodoProvider>();
    final note = widget.note;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final saved = await (note == null
        ? provider.addNote(_content)
        : provider.updateNote(note.id, _content));
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _saveError = '保存失败，正文已保留，请重试。';
      });
    }
  }

  Future<void> _requestExit() async {
    if (_saving || _confirmingExit) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingExit = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _confirmingExit = false;
    if (mounted && discard == true) Navigator.of(context).pop();
  }

  TextSelection get _selection => _editor.selection.isValid
      ? _editor.selection
      : TextSelection.collapsed(offset: _content.length);

  void _replace(int start, int end, String value, TextSelection selection) {
    if (_saving) return;
    _editor.value = TextEditingValue(
      text: _content.replaceRange(start, end, value),
      selection: selection,
    );
    _focus.requestFocus();
  }

  void _bold() {
    final selection = _selection;
    var start = selection.start;
    var end = selection.end;
    if (!selection.isCollapsed) {
      final selected = _content.substring(start, end);
      final trimmed = selected.trim();
      if (trimmed.isEmpty) return;
      start += selected.length - selected.trimLeft().length;
      end = start + trimmed.length;
    }
    if (!selection.isCollapsed &&
        start >= 2 &&
        end + 2 <= _content.length &&
        _content.substring(start - 2, start) == '**' &&
        _content.substring(end, end + 2) == '**') {
      _replace(
        start - 2,
        end + 2,
        _content.substring(start, end),
        TextSelection(baseOffset: start - 2, extentOffset: end - 2),
      );
      return;
    }
    final selected = _content.substring(start, end);
    _replace(
      start,
      end,
      '**$selected**',
      TextSelection(baseOffset: start + 2, extentOffset: end + 2),
    );
  }

  static final _lineMarker = RegExp(
    r'^(?:#{1,6} |[-*+] (?:\[[ xX]\] )?|\d+[.)] )',
  );

  void _formatLines(String Function(int) marker) {
    final selection = _selection;
    final start = selection.start == 0
        ? 0
        : _content.lastIndexOf('\n', selection.start - 1) + 1;
    final last = !selection.isCollapsed && _content[selection.end - 1] == '\n'
        ? selection.end - 1
        : selection.end;
    final nextLine = _content.indexOf('\n', last);
    final end = nextLine < 0 ? _content.length : nextLine;
    final lines = _content.substring(start, end).split('\n');
    final replacement = List.generate(lines.length, (index) {
      if (lines.length > 1 && lines[index].trim().isEmpty) return lines[index];
      return '${marker(index)}${lines[index].replaceFirst(_lineMarker, '')}';
    }).join('\n');
    final delta = replacement.length - (end - start);
    _replace(
      start,
      end,
      replacement,
      selection.isCollapsed
          ? TextSelection.collapsed(
              offset: (selection.start + delta).clamp(
                start,
                start + replacement.length,
              ),
            )
          : TextSelection(
              baseOffset: start,
              extentOffset: start + replacement.length,
            ),
    );
  }

  Widget _toolbar(bool enabled) => ValueListenableBuilder<UndoHistoryValue>(
    valueListenable: _undo,
    builder: (context, history, _) => Wrap(
      children: [
        IconButton(
          tooltip: '撤销',
          icon: const Icon(Icons.undo),
          onPressed: enabled && history.canUndo ? _undo.undo : null,
        ),
        IconButton(
          tooltip: '重做',
          icon: const Icon(Icons.redo),
          onPressed: enabled && history.canRedo ? _undo.redo : null,
        ),
        IconButton(
          tooltip: '标题',
          icon: const Icon(Icons.title),
          onPressed: enabled ? () => _formatLines((_) => '## ') : null,
        ),
        IconButton(
          tooltip: '加粗',
          icon: const Icon(Icons.format_bold),
          onPressed: enabled ? _bold : null,
        ),
        IconButton(
          tooltip: '无序列表',
          icon: const Icon(Icons.format_list_bulleted),
          onPressed: enabled ? () => _formatLines((_) => '- ') : null,
        ),
        IconButton(
          tooltip: '编号列表',
          icon: const Icon(Icons.format_list_numbered),
          onPressed: enabled
              ? () => _formatLines((index) => '${index + 1}. ')
              : null,
        ),
        IconButton(
          tooltip: '待办清单',
          icon: const Icon(Icons.checklist),
          onPressed: enabled ? () => _formatLines((_) => '- [ ] ') : null,
        ),
      ],
    ),
  );

  Widget _buildPreview() => _content.trim().isEmpty
      ? const Center(child: Text('暂无内容可预览'))
      : Markdown(
          data: _content,
          selectable: true,
          padding: const EdgeInsets.all(20),
          softLineBreak: true,
          inlineSyntaxes: noteInlineSyntaxes,
          imageBuilder: noteImagePlaceholder,
        );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _requestExit,
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: _requestExit),
            title: Text(widget.note == null ? '新便签' : '编辑便签'),
            actions: [
              IconButton(
                tooltip: _preview ? '隐藏预览' : '显示预览',
                isSelected: _preview,
                selectedIcon: const Icon(Icons.visibility_off_outlined),
                icon: const Icon(Icons.visibility_outlined),
                onPressed: () {
                  setState(() => _preview = !_preview);
                  if (!_preview) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _focus.requestFocus();
                    });
                  }
                },
              ),
              TextButton(
                onPressed: _saving || _content.trim().isEmpty ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final split = constraints.maxWidth >= 760;
                final previewOnly = _preview && !split;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _toolbar(!_saving && !previewOnly),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: IndexedStack(
                              index: previewOnly ? 1 : 0,
                              sizing: StackFit.expand,
                              children: [
                                ExcludeFocus(
                                  excluding: previewOnly,
                                  child: TextField(
                                    controller: _editor,
                                    undoController: _undo,
                                    focusNode: _focus,
                                    autofocus: true,
                                    expands: true,
                                    maxLines: null,
                                    readOnly: _saving,
                                    textAlignVertical: TextAlignVertical.top,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.all(20),
                                      hintText: '记录这一刻的灵感…',
                                    ),
                                  ),
                                ),
                                if (previewOnly)
                                  _buildPreview()
                                else
                                  const SizedBox.shrink(),
                              ],
                            ),
                          ),
                          if (split && _preview) ...[
                            const VerticalDivider(width: 1),
                            Expanded(child: _buildPreview()),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Semantics(
                        liveRegion: _saveError != null,
                        child: Text(
                          _saveError ??
                              (_saving
                                  ? '正在保存…'
                                  : _dirty
                                  ? '有未保存的修改'
                                  : 'Ctrl+S 保存'),
                          style: TextStyle(
                            color: _saveError == null
                                ? colors.onSurfaceVariant
                                : colors.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
