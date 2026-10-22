import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_client/pages/home_page.dart';
import 'package:todo_client/providers/todo_provider.dart';
import 'package:todo_client/services/api_service.dart';

import 'support/goal_api_adapter.dart';

void main() {
  late Dio originalDio;
  late TodoProvider provider;
  late GoalApiAdapter adapter;

  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    originalDio = ApiService().dio;
    adapter = GoalApiAdapter();
    ApiService().dio = Dio()..httpClientAdapter = adapter;
    provider = TodoProvider();
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    provider.dispose();
    ApiService().dio.close();
    ApiService().dio = originalDio;
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openGoals(WidgetTester tester) async {
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
  }

  testWidgets('phone keeps drawer and shows a dedicated goals destination', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844));
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    await openGoals(tester);
    expect(find.text('完成 Todo 项目'), findsOneWidget);
    expect(find.text('已经过期的目标'), findsOneWidget);
    final expiredTitle = tester.widget<Text>(find.text('已经过期的目标'));
    expect(expiredTitle.style!.decoration, TextDecoration.lineThrough);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop keeps task pool visible alongside goal page', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.text('任务分类池'), findsOneWidget);
    await openGoals(tester);
    expect(find.text('完成 Todo 项目'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'delete warns about all children and cancellation preserves them',
    (tester) async {
      await mount(tester, const Size(390, 1000));
      await openGoals(tester);
      await tester.tap(find.byTooltip('目标操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除目标及全部子任务'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全部 1 项子任务将被删除'), findsOneWidget);
      expect(find.textContaining('“我的一天”中的记录也会同步删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        adapter.requests.where((request) => request.method == 'DELETE'),
        isEmpty,
      );
      await tester.tap(find.byTooltip('目标操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除目标及全部子任务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部删除'));
      await tester.pumpAndSettle();
      expect(find.text('完成 Todo 项目'), findsNothing);
      expect(provider.myDayTodos.any((todo) => todo.goalId == 1), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'new goal supports an empty deadline and rejects an empty title',
    (tester) async {
      await mount(tester, const Size(320, 900));
      await openGoals(tester);
      await tester.tap(find.text('新建目标'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入内容'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '学习 C++ 网络编程');
      expect(find.text('不设截止日期'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        adapter.requests
            .singleWhere((request) => request.method == 'POST')
            .data['deadline'],
        isNull,
      );
      expect(find.text('学习 C++ 网络编程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
