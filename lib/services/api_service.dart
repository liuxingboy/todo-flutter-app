import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  late Dio dio;

  // 用于在非 Widget 环境下进行页面跳转 (GlobalKey)
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // 是否正在刷新 Token 的标志
  bool _isRefreshing = false;
  // 等待刷新完成的请求队列
  List<void Function(String)> _failedRequestsQueue = [];

  static const String defaultIp = "8.138.22.227";
  static const String defaultPort = "8080";

  factory ApiService() {
    return _instance;
  }

  // 获取基础 URL
  String getBaseUrlSync(SharedPreferences prefs) {
    if (kIsWeb) {
      return "/api"; // Web 走 Nginx 代理
    } else {
      String ip = prefs.getString('server_ip') ?? defaultIp;
      String port = prefs.getString('server_port') ?? defaultPort;
      return "http://$ip:$port/api"; // 其他端直连后端
    }
  }

  ApiService._internal() {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        options.baseUrl = getBaseUrlSync(prefs);

        String? token = prefs.getString('access_token');
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        print("🌍 [API Request] ${options.method} ${options.baseUrl}${options.path}");
        return handler.next(options);
      },
      onResponse: (response, handler) async {
        print("✅ [API Response] ${response.statusCode} ${response.data}");

        // 检查业务代码是否为 401
        if (response.data is Map && response.data['code'] == 401) {
          return _handle401Error(response, handler);
        }

        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        print("❌ [API Error] ${e.message} at ${e.requestOptions.baseUrl}${e.requestOptions.path}");

        // 检查 HTTP 状态码是否为 401
        if (e.response?.statusCode == 401) {
          return _handle401Error(e.response!, handler);
        }

        return handler.next(e);
      },
    ));
  }

  // 核心：处理 401 错误并尝试无感刷新
  Future<void> _handle401Error(Response response, dynamic handler) async {
    RequestOptions requestOptions = response.requestOptions;

    // 如果已经在刷新中了，将当前请求加入队列等待
    if (_isRefreshing) {
      _failedRequestsQueue.add((newToken) {
        requestOptions.headers['Authorization'] = 'Bearer $newToken';
        // 重新发起请求并交给 handler
        _instance.dio.fetch(requestOptions).then((res) {
          if (handler is ErrorInterceptorHandler) {
            handler.resolve(res);
          } else if (handler is ResponseInterceptorHandler) {
            handler.resolve(res);
          }
        });
      });
      return;
    }

    _isRefreshing = true;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? refreshToken = prefs.getString('refresh_token');

      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception("No refresh token available");
      }

      print("🔄 [Token] Access Token 过期，尝试使用 Refresh Token 刷新...");

      // 静默调用刷新接口 (不使用当前拦截的 dio 实例，避免死循环)
      Dio refreshDio = Dio(BaseOptions(baseUrl: requestOptions.baseUrl));
      final refreshRes = await refreshDio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });

      if (refreshRes.data['code'] == 0) {
        String newAccessToken = refreshRes.data['data']['access_token'];
        print("✨ [Token] 刷新成功！获取到新 Token");

        // 持久化新 Token
        await prefs.setString('access_token', newAccessToken);

        // 处理等待队列中的请求
        _isRefreshing = false;
        for (var callback in _failedRequestsQueue) {
          callback(newAccessToken);
        }
        _failedRequestsQueue.clear();

        // 重新发起当前被拦截的请求
        requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
        final retryRes = await dio.fetch(requestOptions);

        if (handler is ErrorInterceptorHandler) {
          handler.resolve(retryRes);
        } else if (handler is ResponseInterceptorHandler) {
          handler.resolve(retryRes);
        }
      } else {
        // 刷新接口也返回了 401 或其他错误
        throw Exception("Refresh token invalid or expired");
      }
    } catch (e) {
      print("🚨 [Token] 刷新失败，强制跳转登录页: $e");
      _isRefreshing = false;
      _failedRequestsQueue.clear();
      _handleLogout();

      if (handler is ErrorInterceptorHandler) {
        handler.reject(DioException(requestOptions: requestOptions, error: "Authentication failed"));
      } else if (handler is ResponseInterceptorHandler) {
        handler.reject(DioException(requestOptions: requestOptions, error: "Authentication failed"));
      }
    }
  }

  // 清空本地缓存并跳转到登录
  Future<void> _handleLogout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('username');

    // 使用 GlobalKey 进行强制跳转
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> updateSettings(String ip, String port) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    await prefs.setString('server_port', port);
  }

  Future<String> getBaseUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return getBaseUrlSync(prefs);
  }
}
