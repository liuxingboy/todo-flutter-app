class Todo {
  final int id;
  String title;
  bool isCompleted;
  final String? date;

  Todo({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.date,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] ?? 0,
      // 优先取 content，如果没有再取 title
      title: json['content'] ?? json['title'] ?? '',
      isCompleted: json['is_completed'] == 1 || json['is_completed'] == true,
      date: json['date'],
    );
  }
}

class TodoPool {
  final int id;
  final String name;
  final List<Todo> tasks;

  TodoPool({required this.id, required this.name, required this.tasks});

  factory TodoPool.fromJson(Map<String, dynamic> json) {
    var list = json['tasks'] as List? ?? [];
    return TodoPool(
      id: json['id'] ?? 0,
      // 对齐后端的 pool_name
      name: json['pool_name'] ?? json['name'] ?? '',
      tasks: list.map((i) => Todo.fromJson(i)).toList(),
    );
  }
}

class Note {
  final int id;
  String content;
  final String createdAt;

  Note({required this.id, required this.content, required this.createdAt});

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] ?? 0,
      content: json['content'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class SharedFile {
  final int id;
  final String fileName;
  final int size;
  final String uploadTime;
  final String uploader;

  SharedFile({
    required this.id,
    required this.fileName,
    required this.size,
    required this.uploadTime,
    required this.uploader,
  });

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      id: json['id'] ?? 0,
      fileName: json['file_name'] ?? '',
      size: json['size'] ?? 0,
      uploadTime: json['upload_time'] ?? '',
      uploader: json['uploader'] ?? '',
    );
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
