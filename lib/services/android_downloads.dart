import 'package:flutter/services.dart';

/// Android owns persisted directory grants and publishes completed downloads.
class AndroidDownloads {
  static const _channel = MethodChannel('todo_client/downloads');

  static Future<String> directory() async =>
      await _channel.invokeMethod<String>('getDirectory') ?? 'Download';

  static Future<String?> chooseDirectory() =>
      _channel.invokeMethod<String>('chooseDirectory');

  static Future<String> resetDirectory() async =>
      await _channel.invokeMethod<String>('resetDirectory') ?? 'Download';

  static Future<String> save(String sourcePath, String fileName) async {
    final location = await _channel.invokeMethod<String>('saveDownload', {
      'sourcePath': sourcePath,
      'fileName': fileName,
    });
    if (location == null || location.isEmpty) {
      throw PlatformException(code: 'save_failed', message: '未能确认文件保存位置');
    }
    return location;
  }
}
