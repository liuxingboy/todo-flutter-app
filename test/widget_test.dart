import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_client/main.dart';
import 'package:todo_client/pages/home_page.dart';
import 'package:todo_client/providers/theme_preferences.dart';
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
    await tester.tap(find.byTooltip('收起侧栏'));
    await tester.pumpAndSettle();
    expect(find.text('任务分类池'), findsNothing);
    expect(find.text('完成 Todo 项目'), findsOneWidget);
    expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pumpAndSettle();
    expect(find.text('任务分类池'), findsOneWidget);
    expect(find.text('完成 Todo 项目'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme settings update the active route and save preferences', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => ThemePreferences(prefs)),
        ],
        child: const MyApp(initialRoute: '/home'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('森林绿'));
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.text('主题设置')));
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.colorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.dark,
      ).primary,
    );
    final restored = ThemePreferences(prefs);
    expect(restored.mode, ThemeMode.dark);
    expect(restored.palette, TodoPalette.green);
    restored.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'note cards render legacy bold and still open the original Markdown',
    (tester) async {
      await mount(tester, const Size(1280, 900));
      const source = '**周末计划， **\n\n下一行';
      adapter.overrideRequest = (request) async => adapter.respond(
        data: [
          {'id': 1, 'content': source, 'created_at': '2026-11-06'},
        ],
      );
      final refresh = provider.fetchNotes();
      await tester.pumpAndSettle();
      await refresh;
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();

      final cardPreview = find.byType(MarkdownBody);
      expect(cardPreview, findsOneWidget);
      final rendered = tester
          .widgetList<RichText>(
            find.descendant(of: cardPreview, matching: find.byType(RichText)),
          )
          .map((widget) => widget.text.toPlainText())
          .join('\n');
      expect(rendered, contains('周末计划，'));
      expect(rendered, isNot(contains('**')));

      await tester.tapAt(tester.getCenter(cardPreview));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(editor.text, source);
      await tester.enterText(find.byType(TextField), '新便签 ');
      editor.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.tap(find.byTooltip('加粗'));
      await tester.pumpAndSettle();
      expect(editor.text, '**新便签** ');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'note editor previews separately and keeps text after failed save',
    (tester) async {
      await mount(tester, const Size(1280, 900));
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记笔记'));
      await tester.pumpAndSettle();
      expect(find.text('任务分类池'), findsNothing);
      expect(find.byType(Markdown), findsNothing);

      await tester.enterText(find.byType(TextField), '周末清单');
      await tester.tap(find.byTooltip('标题'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('显示预览'));
      await tester.pumpAndSettle();
      expect(tester.widget<Markdown>(find.byType(Markdown)).data, '## 周末清单');
      expect(find.byType(TextField).hitTestable(), findsOneWidget);

      var failSave = true;
      adapter.overrideRequest = (request) async => request.method == 'POST'
          ? adapter.respond(code: failSave ? 500 : 0)
          : adapter.respond(data: []);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，正文已保留，请重试。'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '## 周末清单',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();

      failSave = false;
      await tester.tap(find.byType(TextField));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('记笔记'), findsOneWidget);
      expect(
        adapter.requests.where(
          (request) => request.method == 'POST' && request.path == '/notes',
        ),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

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
