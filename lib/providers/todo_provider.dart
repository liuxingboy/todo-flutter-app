import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/todo_models.dart';
import '../services/api_service.dart';
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

  // --- 任务池 (Pools) 数据 ---
  List<TodoPool> _pools = [];
  bool _isPoolsLoading = false;
  List<TodoPool> get pools => _pools;
  bool get isPoolsLoading => _isPoolsLoading;

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

  TodoProvider() {
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    // 假设登录时存了 username，如果没有，则需要从 token 解析或专门接口获取
    _currentUsername = prefs.getString('username') ?? "";
    notifyListeners();
  }

  // ==================== 我的一天 (My Day) 逻辑 ====================

  Future<void> fetchMyDay() async {
    _isMyDayLoading = true;
    notifyListeners();
    try {
      final response = await ApiService().dio.get('/myday');
      if (response.data['code'] == 0) {
        List list = response.data['data'];
        _myDayTodos = list.map((item) => Todo.fromJson(item)).toList();
      }
    } catch (e) {
      print("Fetch MyDay Error: $e");
    } finally {
      _isMyDayLoading = false;
      notifyListeners();
    }
  }

  Future<void> addTodo(String content) async {
    try {
      // 后端要求字段名为 content
      final response = await ApiService().dio.post('/myday', data: {'content': content});
      if (response.data['code'] == 0) {
        await fetchMyDay();
      }
    } catch (e) {
      print("Add Todo Error: $e");
    }
  }

  Future<void> toggleTodoStatus(Todo todo) async {
    final oldStatus = todo.isCompleted;
    todo.isCompleted = !todo.isCompleted;
    notifyListeners();

    try {
      final response = await ApiService().dio.put('/myday/status', data: {
        'task_id': todo.id,
        'is_completed': todo.isCompleted
      });
      if (response.data['code'] != 0) {
        todo.isCompleted = oldStatus;
        notifyListeners();
      }
    } catch (e) {
      todo.isCompleted = oldStatus;
      notifyListeners();
      print("Toggle Status Error: $e");
    }
  }

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
      final response = await ApiService().dio.post('/myday/import', data: {'pool_task_id': poolTaskId});
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
      final response = await ApiService().dio.post('/pools', data: {'pool_name': poolName});
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
      final response = await ApiService().dio.post('/pools/task', data: {
        'pool_id': poolId,
        'content': content,
      });

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
      final response = await ApiService().dio.delete('/pools', data: {
        'pool_id': poolId,
      });

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

  Future<void> addNote(String content) async {
    try {
      await ApiService().dio.post('/notes', data: {'content': content});
      fetchNotes();
    } catch (e) {
      print("Add Note Error: $e");
    }
  }

  Future<void> updateNote(int id, String content) async {
    try {
      final response = await ApiService().dio.put('/notes', data: {
        'note_id': id,
        'content': content
      });
      if (response.data['code'] == 0) {
        fetchNotes();
      }
    } catch (e) {
      print("Update Note Error: $e");
    }
  }

  Future<bool> deleteNote(int id) async {
    try {
      final response = await ApiService().dio.delete('/notes', data: {'note_id': id});
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

      final response = await ApiService().dio.post('/files/upload', data: formData);
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
    try {
      // 获取下载目录
      Directory? downloadsDirectory;
      if (Platform.isAndroid) {
        downloadsDirectory = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDirectory = await getDownloadsDirectory();
      }

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
        savePath = "${downloadsDirectory.path}/$nameWithoutExtension($count)$extension";
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

      _downloadProgress.remove(file.id);
      notifyListeners();

      return response.statusCode == 200;
    } catch (e) {
      print("Download File Error: $e");
      _downloadProgress.remove(file.id);
      notifyListeners();
      return false;
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
