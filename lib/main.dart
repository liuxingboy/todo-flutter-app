import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart'; // 新增
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/shared_files_page.dart';
import 'providers/todo_provider.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日期本地化数据（解决 zh_CN 报错问题）
  await initializeDateFormatting('zh_CN', null);

  final prefs = await SharedPreferences.getInstance();
  final String? token = prefs.getString('access_token');

  runApp(
    // 在这里包裹 MultiProvider，让整个 App 都能访问到 TodoProvider
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TodoProvider()),
      ],
      child: MyApp(initialRoute: (token != null && token.isNotEmpty) ? '/home' : '/login'),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo Client',
      navigatorKey: ApiService.navigatorKey, // 绑定 GlobalKey
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/settings': (context) => const SettingsPage(),
        '/shared_files': (context) => const SharedFilesPage(),
        '/home': (context) => const HomePage(),
      },
    );
  }
}
