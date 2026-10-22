import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_client/providers/todo_provider.dart';
import 'package:todo_client/services/api_service.dart';

import 'support/goal_api_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio originalDio;
  late TodoProvider provider;
  late GoalApiAdapter adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    originalDio = ApiService().dio;
    adapter = GoalApiAdapter();
    ApiService().dio = Dio(
      BaseOptions(validateStatus: (status) => status != null && status < 500),
    )..httpClientAdapter = adapter;
    provider = TodoProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.refreshTaskViews();
  });

  tearDown(() {
    provider.dispose();
    ApiService().dio.close();
    ApiService().dio = originalDio;
  });

  test(
    'completion from My Day updates the goal and undo updates daily state',
    () async {
      final todo = provider.myDayTodos.singleWhere(
        (todo) => todo.goalTaskId == 11,
      );
      expect(await provider.toggleTodoStatus(todo), isTrue);
      expect(provider.goals.first.isCompleted, isTrue);
      expect(provider.goals.first.progress, 1);
      expect(await provider.setGoalTaskStatus(11, false), isTrue);
      expect(provider.goals.first.progress, 0);
      expect(
        provider.myDayTodos
            .singleWhere((todo) => todo.goalTaskId == 11)
            .isCompleted,
        isFalse,
      );
    },
  );

  test(
    'goal deletion removes all local references even if subsequent reads fail',
    () async {
      adapter.overrideRequest = (options) async {
        if (options.method == 'DELETE') {
          expect(options.path, '/goals/1');
          adapter.removed = true;
          return adapter.respond();
        }
        return adapter.respond(status: 500, code: 500);
      };
      expect(await provider.deleteGoal(1), isTrue);
      expect(provider.goals.map((goal) => goal.id), [2]);
      expect(provider.myDayTodos.map((todo) => todo.id), [100]);
      expect(provider.goalsError, isNotNull);
    },
  );

  test('failed deletion preserves goal, child and daily entries', () async {
    adapter.failMutation = true;
    expect(await provider.deleteGoal(1), isFalse);
    expect(provider.goals.first.tasks.single.id, 11);
    expect(provider.myDayTodos.any((todo) => todo.goalTaskId == 11), isTrue);
    expect(provider.goalActionError, isNotNull);
    expect(provider.isGoalBusy, isFalse);
  });

  test('failed daily completion rolls back its optimistic checkbox', () async {
    adapter.failMutation = true;
    final todo = provider.myDayTodos.singleWhere(
      (todo) => todo.goalTaskId == 11,
    );
    expect(await provider.toggleTodoStatus(todo), isFalse);
    expect(todo.isCompleted, isFalse);
    expect(provider.goals.first.progress, 0);
    expect(provider.isTodoUpdating(todo.id), isFalse);
  });

  test(
    'nullable deadlines are sent as JSON null and preserved after saving',
    () async {
      expect(
        await provider.saveGoal(
          title: '  不设日期  ',
          description: '',
          deadline: null,
        ),
        isTrue,
      );
      final mutation = adapter.requests.singleWhere(
        (request) => request.method == 'POST',
      );
      expect(mutation.data, {
        'title': '不设日期',
        'description': '',
        'deadline': null,
      });
      expect(provider.goals.first.deadline, isNull);
    },
  );

  test('an old in-flight list cannot resurrect a goal deleted later', () async {
    final pending = Completer<ResponseBody>();
    final oldData = [adapter.goal(), adapter.expiredGoal()];
    var holdFirst = true;
    adapter.overrideRequest = (options) async {
      if (options.method == 'DELETE') {
        adapter.removed = true;
        return adapter.respond();
      }
      if (options.path == '/goals' && holdFirst) {
        holdFirst = false;
        return pending.future;
      }
      return adapter.respond(
        data: options.path == '/goals'
            ? [adapter.expiredGoal()]
            : adapter.daily(),
      );
    };
    final oldRead = provider.fetchGoals();
    await Future<void>.delayed(Duration.zero);
    expect(await provider.deleteGoal(1), isTrue);
    pending.complete(adapter.respond(data: oldData));
    await oldRead;
    expect(provider.goals.map((goal) => goal.id), [2]);
  });
}
