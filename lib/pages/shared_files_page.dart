import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/todo_provider.dart';
import '../models/todo_models.dart';

class SharedFilesPage extends StatefulWidget {
  const SharedFilesPage({super.key});

  @override
  State<SharedFilesPage> createState() => _SharedFilesPageState();
}

class _SharedFilesPageState extends State<SharedFilesPage> {
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<TodoProvider>().fetchSharedFiles());
  }

  Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      setState(() {
        _isUploading = true;
      });

      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      final success = await context.read<TodoProvider>().uploadFile(filePath, fileName);

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 文件上传成功'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 文件上传失败'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showDeleteConfirm(SharedFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除该文件吗？'),
        content: const Text('此操作不可逆，文件将从服务器彻底移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await context.read<TodoProvider>().deleteFile(file.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 文件已删除'), backgroundColor: Colors.green),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('❌ 删除失败'), backgroundColor: Colors.red),
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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('共享文件大厅'),
            if (provider.currentUsername.isNotEmpty)
              Text('当前用户: ${provider.currentUsername}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.fetchSharedFiles(),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => provider.fetchSharedFiles(),
            child: provider.isFilesLoading && provider.sharedFiles.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : provider.sharedFiles.isEmpty
                    ? const Center(child: Text('暂无共享文件'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: provider.sharedFiles.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final file = provider.sharedFiles[index];
                          final isOwner = file.uploader == provider.currentUsername;
                          final progress = provider.downloadProgress[file.id];

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.withOpacity(0.1),
                              child: const Icon(Icons.insert_drive_file, color: Colors.blue),
                            ),
                            title: Text(file.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${file.formattedSize} • 上传者: ${file.uploader}'),
                                Text(file.uploadTime, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if (progress != null) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(value: progress),
                                ]
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.download, color: Colors.blue),
                                  onPressed: progress != null
                                      ? null
                                      : () async {
                                          final success = await provider.downloadFile(file);
                                          if (mounted && success) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('✅ 文件下载成功'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        },
                                ),
                                // 增加一点间距
                                const SizedBox(width: 8),
                                // 只有上传者是自己才显示删除图标
                                if (file.uploader.trim() == provider.currentUsername.trim() || provider.currentUsername == "admin")
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _showDeleteConfirm(file),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在上传文件...', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _pickAndUploadFile,
        label: const Text('上传文件'),
        icon: const Icon(Icons.upload_file),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
