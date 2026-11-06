import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/todo_models.dart';
import '../services/api_service.dart';
import '../services/android_downloads.dart';
import '../services/browser_download.dart'
    if (dart.library.js_interop) '../services/browser_download_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodoProvider with ChangeNotifier {
  // --- 用户信息 ---
  String _currentUsername = "";
  String get currentUsername => _currentUsername;

  // --- 我的一天 (My Day) 数据 ---
  List<Todo> _myDayTodos = [];
  bool _isMyDayLoading = false;
  List<Todo> get myDayTodos => _myDayTodos;
  bool get isMyDayLoading => _isMyDayLoading;
  String? _serverTaskDate;
  DateTime get taskDate => _serverTaskDate == null
      ? taskDateForInstant(DateTime.now())
      : DateTime.parse(_serverTaskDate!);

  // --- 任务池 (Pools) 数据 ---
  List<TodoPool> _pools = [];
  bool _isPoolsLoading = false;
  List<TodoPool> get pools => _pools;
  bool get isPoolsLoading => _isPoolsLoading;

  List<LongTermGoal> _goals = [];
  List<LongTermGoal> get goals => _goals;
  bool _isGoalsLoading = false;
  bool get isGoalsLoading => _isGoalsLoading;
  bool _isGoalSaving = false;
  bool get isGoalSaving => _isGoalSaving;
  String? _goalsError;
  String? get goalsError => _goalsError;
  String? _goalActionError;
  String? get goalActionError => _goalActionError;
  int _goalsFetchVersion = 0;
  int _myDayFetchVersion = 0;
  final Set<int> _updatingTodoIds = {};
  bool isTodoUpdating(int id) => _updatingTodoIds.contains(id);
  bool get isGoalBusy => _isGoalSaving || _updatingTodoIds.isNotEmpty;

  // --- 灵感便签 (Notes) 数据 ---
  List<Note> _notes = [];
  bool _isNotesLoading = false;
  List<Note> get notes => _notes;
  bool get isNotesLoading => _isNotesLoading;

  // --- 共享文件 (Shared Files) 数据 ---
  List<SharedFile> _sharedFiles = [];
  bool _isFilesLoading = false;
  List<SharedFile> get sharedFiles => _sharedFiles;
  bool get isFilesLoading => _isFilesLoading;

  Map<int, double> _downloadProgress = {};
  Map<int, double> get downloadProgress => _downloadProgress;
  final Map<int, String> downloadLocations = {};
  final Map<int, String> downloadErrors = {};

  TodoProvider() {
    _loadUserInfo();
  }

  // 全局刷新：重新拉取所有数据
  Future<void> refreshAll() async {
    // 并发执行所有拉取操作
    await Future.wait([
      fetchMyDay(),
      fetchPools(),
      fetchGoals(),
      fetchNotes(),
      fetchSharedFiles(),
      _loadUserInfo(),
    ]);
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    // 假设登录时存了 username，如果没有，则需要从 token 解析或专门接口获取
    _currentUsername = prefs.getString('username') ?? "";
    notifyListeners();
  }

  // ==================== 我的一天 (My Day) 逻辑 ====================

  Future<void> fetchMyDay() async {
    final version = ++_myDayFetchVersion;
    _isMyDayLoading = true;
    notifyListeners();
    try {
      final response = await ApiService().dio.get('/myday');
      if (response.data['code'] == 0 && version == _myDayFetchVersion) {
        List list = response.data['data'];
        _myDayTodos = list.map((item) => Todo.fromJson(item)).toList();
        _serverTaskDate = response.data['task_date'];
      }
    } catch (e) {
      print("Fetch MyDay Error: $e");
    } finally {
      if (version == _myDayFetchVersion) _isMyDayLoading = false;
      notifyListeners();
    }
  }

  Future<void> addTodo(String content) async {
    try {
      // 后端要求字段名为 content
      final response = await ApiService().dio.post(
        '/myday',
        data: {'content': content},
      );
      if (response.data['code'] == 0) {
        await fetchMyDay();
      }
    } catch (e) {
      print("Add Todo Error: $e");
    }
  }

  Future<bool> toggleTodoStatus(Todo todo) async {
    if (isTodoUpdating(todo.id) || (todo.goalTaskId != null && isGoalBusy)) {
      return false;
    }
    _updatingTodoIds.add(todo.id);
    final oldStatus = todo.isCompleted;
    todo.isCompleted = !todo.isCompleted;
    notifyListeners();

    try {
      final response = await ApiService().dio.put(
        '/myday/status',
        data: {'task_id': todo.id, 'is_completed': todo.isCompleted},
      );
      if (response.data['code'] != 0) {
        todo.isCompleted = oldStatus;
        return false;
      }
      if (todo.goalTaskId != null) await refreshTaskViews();
      return true;
    } catch (e) {
      todo.isCompleted = oldStatus;
      print("Toggle Status Error: $e");
      return false;
    } finally {
      _updatingTodoIds.remove(todo.id);
      notifyListeners();
    }
  }

  // Goal tasks keep one persistent completion state, shared by all views.
  Future<void> refreshTaskViews() async {
    await Future.wait([fetchMyDay(), fetchGoals()]);
  }

  Future<void> fetchGoals() async {
    final version = ++_goalsFetchVersion;
    _isGoalsLoading = true;
    _goalsError = null;
    notifyListeners();
    try {
      final response = await ApiService().dio.get('/goals');
      if (response.statusCode != 200 ||
          response.data is! Map ||
          response.data['code'] != 0 ||
          response.data['data'] is! List) {
        throw StateError('Invalid goal response');
      }
      final goals = (response.data['data'] as List)
          .map((item) => LongTermGoal.fromJson(item))
          .toList();
      if (version == _goalsFetchVersion) _goals = goals;
    } catch (e) {
      if (version == _goalsFetchVersion) {
        _goalsError = '长期目标同步失败，请检查连接或确认后端已更新后重试';
      }
    } finally {
      if (version == _goalsFetchVersion) _isGoalsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _mutateGoal(
    String method,
    String path, {
    Map<String, dynamic>? data,
    VoidCallback? onSuccess,
  }) async {
    if (isGoalBusy) return false;
    _isGoalSaving = true;
    _goalActionError = null;
    notifyListeners();
    try {
      final response = await ApiService().dio.request(
        path,
        data: data,
        options: Options(method: method),
      );
      if (response.statusCode != 200 ||
          response.data is! Map ||
          response.data['code'] != 0) {
        _goalActionError = response.statusCode == 409
            ? '该子任务已经完成，请先取消完成再加入今天'
            : '操作失败，请检查连接并刷新后重试';
        return false;
      }
      // Invalidate reads started before this mutation, including on slow clients.
      ++_goalsFetchVersion;
      ++_myDayFetchVersion;
      onSuccess?.call();
      notifyListeners();
      await refreshTaskViews();
      return true;
    } catch (e) {
      _goalActionError = '操作失败，请检查连接并刷新后重试';
      return false;
    } finally {
      _isGoalSaving = false;
      notifyListeners();
    }
  }

  Future<bool> saveGoal({
    int? id,
    required String title,
    required String description,
    String? deadline,
  }) => _mutateGoal(
    id == null ? 'POST' : 'PUT',
    id == null ? '/goals' : '/goals/$id',
    data: {
      'title': title.trim(),
      'description': description,
      'deadline': deadline,
    },
  );

  Future<bool> deleteGoal(int id) => _mutateGoal(
    'DELETE',
    '/goals/$id',
    onSuccess: () {
      _goals.removeWhere((goal) => goal.id == id);
      _myDayTodos.removeWhere((todo) => todo.goalId == id);
    },
  );

  Future<bool> saveGoalTask({
    required int goalId,
    int? taskId,
    required String content,
    String? deadline,
  }) => _mutateGoal(
    taskId == null ? 'POST' : 'PUT',
    taskId == null ? '/goals/$goalId/tasks' : '/goals/tasks/$taskId',
    data: {'content': content.trim(), 'deadline': deadline},
  );

  Future<bool> deleteGoalTask(int taskId) => _mutateGoal(
    'DELETE',
    '/goals/tasks/$taskId',
    onSuccess: () {
      for (final goal in _goals) {
        goal.tasks.removeWhere((task) => task.id == taskId);
      }
      _myDayTodos.removeWhere((todo) => todo.goalTaskId == taskId);
    },
  );

  Future<bool> setGoalTaskStatus(int taskId, bool completed) => _mutateGoal(
    'PUT',
    '/goals/tasks/$taskId/status',
    data: {'is_completed': completed},
  );

  Future<bool> addGoalTaskToMyDay(int taskId) =>
      _mutateGoal('POST', '/goals/tasks/$taskId/myday');

  // ==================== 任务池 (Pools) 逻辑 ====================

  Future<void> fetchPools() async {
    _isPoolsLoading = true;
    notifyListeners();
    try {
      final response = await ApiService().dio.get('/pools');
      if (response.data['code'] == 0) {
        List list = response.data['data'];
        _pools = list.map((item) => TodoPool.fromJson(item)).toList();
      }
    } catch (e) {
      print("Fetch Pools Error: $e");
    } finally {
      _isPoolsLoading = false;
      notifyListeners();
    }
  }

  Future<void> importToMyDay(int poolTaskId) async {
    try {
      // 后端要求字段名为 pool_task_id
      final response = await ApiService().dio.post(
        '/myday/import',
        data: {'pool_task_id': poolTaskId},
      );
      if (response.data['code'] == 0) {
        fetchMyDay();
      }
    } catch (e) {
      print("Import Error: $e");
    }
  }

  // ==================== 任务池 (Pools) 额外功能 ====================

  Future<void> addPool(String poolName) async {
    try {
      final response = await ApiService().dio.post(
        '/pools',
        data: {'pool_name': poolName},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        fetchPools();
      }
    } catch (e) {
      print("Add Pool Error: $e");
    }
  }

  Future<void> addTaskToPool(int poolId, String content) async {
    try {
      final response = await ApiService().dio.post(
        '/pools/task',
        data: {'pool_id': poolId, 'content': content},
      );

      final data = response.data;
      // 增加类型判断，防止后端返回非 JSON 导致崩溃
      if (data is Map && data['code'] == 0) {
        fetchPools();
      } else if (data is String && data.contains("success")) {
        // 如果后端只返回了 "success" 字符串，也视为成功
        fetchPools();
      }
    } catch (e) {
      print("Add Task to Pool Error: $e");
    }
  }

  Future<bool> deletePool(int poolId) async {
    try {
      final response = await ApiService().dio.delete(
        '/pools',
        data: {'pool_id': poolId},
      );

      if (response.data['code'] == 0) {
        _pools.removeWhere((p) => p.id == poolId);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print("Delete Pool Error: $e");
      return false;
    }
  }

  Future<bool> deletePoolTask(int poolId, int taskId) async {
    try {
      final response = await ApiService().dio.delete('/pools/tasks/$taskId');
      if (response.data['code'] == 0) {
        // 本地移除任务
        final poolIndex = _pools.indexWhere((p) => p.id == poolId);
        if (poolIndex != -1) {
          _pools[poolIndex].tasks.removeWhere((t) => t.id == taskId);
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      print("Delete Pool Task Error: $e");
      return false;
    }
  }

  // ==================== 灵感便签 (Notes) 逻辑 ====================

  Future<void> fetchNotes() async {
    _isNotesLoading = true;
    notifyListeners();
    try {
      final response = await ApiService().dio.get('/notes');
      if (response.data['code'] == 0) {
        List list = response.data['data'];
        _notes = list.map((item) => Note.fromJson(item)).toList();
      }
    } catch (e) {
      print("Fetch Notes Error: $e");
    } finally {
      _isNotesLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addNote(String content) async {
    try {
      final response = await ApiService().dio.post(
        '/notes',
        data: {'content': content},
      );
      if (response.data['code'] != 0) return false;
      fetchNotes();
      return true;
    } catch (e) {
      print("Add Note Error: $e");
      return false;
    }
  }

  Future<bool> updateNote(int id, String content) async {
    try {
      final response = await ApiService().dio.put(
        '/notes',
        data: {'note_id': id, 'content': content},
      );
      if (response.data['code'] == 0) {
        fetchNotes();
        return true;
      }
    } catch (e) {
      print("Update Note Error: $e");
    }
    return false;
  }

  Future<bool> deleteNote(int id) async {
    try {
      final response = await ApiService().dio.delete(
        '/notes',
        data: {'note_id': id},
      );
      if (response.data['code'] == 0) {
        _notes.removeWhere((note) => note.id == id);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print("Delete Note Error: $e");
      return false;
    }
  }

  // ==================== 共享文件 (Shared Files) 逻辑 ====================

  Future<void> fetchSharedFiles() async {
    _isFilesLoading = true;
    notifyListeners();
    try {
      final response = await ApiService().dio.get('/files');
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        List list = data['data'];
        _sharedFiles = list.map((item) => SharedFile.fromJson(item)).toList();
      } else if (data is Map && data['code'] == 401) {
        print("Fetch Files: Token expired");
      }
    } catch (e) {
      print("Fetch Files Error: $e");
    } finally {
      _isFilesLoading = false;
      notifyListeners();
    }
  }

  Future<bool> uploadFile(String filePath, String fileName) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await ApiService().dio.post(
        '/files/upload',
        data: formData,
      );
      final data = response.data;

      if (data is Map && data['code'] == 0) {
        fetchSharedFiles();
        return true;
      }

      // 处理错误情况
      if (response.statusCode == 413) {
        print("Upload Error: File too large (413)");
      }

      return false;
    } catch (e) {
      print("Upload File Error: $e");
      return false;
    }
  }

  Future<bool> downloadFile(SharedFile file) async {
    if (_downloadProgress.containsKey(file.id)) return false;
    downloadLocations.remove(file.id);
    downloadErrors.remove(file.id);
    _downloadProgress[file.id] = 0;
    notifyListeners();
    try {
      if (kIsWeb) {
        final response = await ApiService().dio.post<Map<String, dynamic>>(
          '/files/download-ticket/${file.id}',
          options: Options(validateStatus: (status) => status == 200),
        );
        final data = response.data;
        if (response.statusCode != 200 || data == null || data['code'] != 0) {
          return false;
        }
        final url = data['data']?['download_url'];
        if (url is! String || url.isEmpty) return false;
        saveBrowserDownload(url, file.fileName);
        return true;
      }

      if (Platform.isAndroid) {
        // Download privately first, then publish through Android's storage APIs.
        final cache = await getTemporaryDirectory();
        final temporary = await cache.createTemp('gtd-download-');
        try {
          final sourcePath = '${temporary.path}/payload';
          await ApiService().dio.download(
            '/files/download/${file.id}',
            sourcePath,
            options: Options(validateStatus: (status) => status == 200),
            onReceiveProgress: (received, total) {
              if (total > 0) {
                _downloadProgress[file.id] = (received / total).clamp(0.0, 1.0);
                notifyListeners();
              }
            },
          );
          downloadLocations[file.id] = await AndroidDownloads.save(
            sourcePath,
            file.fileName,
          );
          return true;
        } finally {
          // Cleanup must not turn an already completed save into a failure.
          try {
            await temporary.delete(recursive: true);
          } catch (e) {
            debugPrint('Download temporary cleanup failed: $e');
          }
        }
      }

      Directory? downloadsDirectory = await getDownloadsDirectory();
      if (downloadsDirectory == null) {
        downloadsDirectory = await getApplicationDocumentsDirectory();
      }

      String savePath = "${downloadsDirectory.path}/${file.fileName}";

      // 处理重名
      int count = 1;
      while (await File(savePath).exists()) {
        String nameWithoutExtension = file.fileName.contains('.')
            ? file.fileName.substring(0, file.fileName.lastIndexOf('.'))
            : file.fileName;
        String extension = file.fileName.contains('.')
            ? file.fileName.substring(file.fileName.lastIndexOf('.'))
            : '';
        savePath =
            "${downloadsDirectory.path}/$nameWithoutExtension($count)$extension";
        count++;
      }

      final response = await ApiService().dio.download(
        '/files/download/${file.id}',
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _downloadProgress[file.id] = received / total;
            notifyListeners();
          }
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      downloadErrors[file.id] = e is PlatformException
          ? (e.message ?? '文件保存失败，请重新选择下载目录')
          : '文件下载失败，请检查网络、登录状态和剩余空间后重试';
      print("Download File Error: $e");
      return false;
    } finally {
      _downloadProgress.remove(file.id);
      notifyListeners();
    }
  }

  Future<bool> deleteFile(int id) async {
    try {
      // 修正：根据文档，路径应为 /api/files/{file_id}
      final response = await ApiService().dio.delete('/files/$id');
      final data = response.data;

      if (data is Map && data['code'] == 0) {
        _sharedFiles.removeWhere((f) => f.id == id);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print("Delete File Error: $e");
      return false;
    }
  }
}
