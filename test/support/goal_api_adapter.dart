import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class GoalApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool removed = false;
  bool completed = false;
  bool selected = true;
  bool failMutation = false;
  bool failReads = false;
  String title = '完成 Todo 项目';
  String? deadline = '2099-12-31';
  Future<ResponseBody> Function(RequestOptions)? overrideRequest;

  Map<String, dynamic> goal() => {
    'id': 1,
    'title': title,
    'description': '分步推进项目',
    'deadline': deadline,
    'status': completed ? 'completed' : 'active',
    'tasks': [
      {
        'id': 11,
        'content': '完成登录模块',
        'deadline': null,
        'is_completed': completed,
        'status': completed ? 'completed' : 'active',
        'is_in_my_day': selected,
      },
    ],
  };

  Map<String, dynamic> expiredGoal() => {
    'id': 2,
    'title': '已经过期的目标',
    'description': '',
    'deadline': '2020-01-01',
    'status': 'expired',
    'tasks': [
      {
        'id': 21,
        'content': '已过期的子任务',
        'deadline': '2020-01-01',
        'is_completed': false,
        'status': 'expired',
        'is_in_my_day': false,
      },
    ],
  };

  List<Map<String, dynamic>> daily() => [
    {'id': 100, 'content': '普通每日任务', 'is_completed': false},
    if (!removed && selected)
      {
        'id': 101,
        'content': '完成登录模块',
        'is_completed': completed,
        'goal_task_id': 11,
        'goal_id': 1,
        'goal_title': title,
        'deadline': null,
        'is_expired': false,
      },
  ];

  ResponseBody respond({Object? data, int status = 200, int code = 0}) =>
      ResponseBody.fromString(
        jsonEncode({'code': code, 'msg': 'test', 'data': data}),
        status,
        headers: {
          'content-type': ['application/json'],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (overrideRequest != null) return overrideRequest!(options);
    if (options.method == 'GET') {
      if (failReads) return respond(status: 500, code: 500);
      return respond(
        data: switch (options.path) {
          '/goals' => [if (!removed) goal(), expiredGoal()],
          '/myday' => daily(),
          '/pools' || '/notes' || '/files' => [],
          _ => throw StateError('Unexpected GET ${options.path}'),
        },
      );
    }
    if (failMutation) return respond(status: 500, code: 500);
    final data = options.data as Map<String, dynamic>?;
    switch ('${options.method} ${options.path}') {
      case 'DELETE /goals/1':
        removed = true;
      case 'PUT /myday/status':
        completed = data!['is_completed'];
      case 'PUT /goals/tasks/11/status':
        completed = data!['is_completed'];
      case 'POST /goals/tasks/11/myday':
        selected = true;
      case 'POST /goals':
        title = data!['title'];
        deadline = data['deadline'];
        removed = false;
      default:
        throw StateError(
          'Unexpected mutation ${options.method} ${options.path}',
        );
    }
    return respond(data: {'id': 1});
  }

  @override
  void close({bool force = false}) {}
}
