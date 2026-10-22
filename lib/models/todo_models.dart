/// Task days roll over at 04:00 Beijing time, regardless of device timezone.
DateTime taskDateForInstant(DateTime instant) {
  final shifted = instant.toUtc().add(const Duration(hours: 4));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

class Todo {
  final int id;
  String title;
  bool isCompleted;
  final String? date;
  final int? goalTaskId;
  final int? goalId;
  final String? goalTitle;
  final String? deadline;
  final bool isExpired;

  Todo({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.date,
    this.goalTaskId,
    this.goalId,
    this.goalTitle,
    this.deadline,
    this.isExpired = false,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] ?? 0,
      // 优先取 content，如果没有再取 title
      title: json['content'] ?? json['title'] ?? '',
      isCompleted: json['is_completed'] == 1 || json['is_completed'] == true,
      date: json['date'],
      goalTaskId: json['goal_task_id'],
      goalId: json['goal_id'],
      goalTitle: json['goal_title'],
      deadline: json['deadline'],
      isExpired: json['is_expired'] == true || json['is_expired'] == 1,
    );
  }
}

class GoalTask {
  final int id;
  final String content;
  final String? deadline;
  final bool isCompleted;
  final bool isExpired;
  final bool isInMyDay;

  GoalTask({
    required this.id,
    required this.content,
    this.deadline,
    this.isCompleted = false,
    this.isExpired = false,
    this.isInMyDay = false,
  });

  factory GoalTask.fromJson(Map<String, dynamic> json) => GoalTask(
    id: json['id'],
    content: json['content'],
    deadline: json['deadline'],
    isCompleted: json['is_completed'] == true || json['is_completed'] == 1,
    isExpired: json['status'] == 'expired',
    isInMyDay: json['is_in_my_day'] == true || json['is_in_my_day'] == 1,
  );
}

class LongTermGoal {
  final int id;
  final String title;
  final String description;
  final String? deadline;
  final String status;
  final List<GoalTask> tasks;

  LongTermGoal({
    required this.id,
    required this.title,
    this.description = '',
    this.deadline,
    this.status = 'active',
    required this.tasks,
  });

  int get completedTasks => tasks.where((task) => task.isCompleted).length;
  double get progress => tasks.isEmpty ? 0 : completedTasks / tasks.length;
  bool get isCompleted => tasks.isNotEmpty && completedTasks == tasks.length;
  bool get isExpired => !isCompleted && status == 'expired';

  factory LongTermGoal.fromJson(Map<String, dynamic> json) => LongTermGoal(
    id: json['id'],
    title: json['title'],
    description: json['description'] ?? '',
    deadline: json['deadline'],
    status: json['status'] ?? 'active',
    tasks: (json['tasks'] as List? ?? [])
        .map((item) => GoalTask.fromJson(item))
        .toList(),
  );
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
