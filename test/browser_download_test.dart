@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_client/models/todo_models.dart';
import 'package:todo_client/providers/todo_provider.dart';
import 'package:todo_client/services/api_service.dart';
import 'package:web/web.dart' as web;

class DownloadAdapter implements HttpClientAdapter {
  DownloadAdapter(this.status, this.bytes);
  final int status;
  final List<int> bytes;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    expect(options.path, '/files/download/7');
    expect(options.responseType, ResponseType.bytes);
    return ResponseBody.fromBytes(bytes, status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio originalDio;
  late TodoProvider provider;
  late JSFunction onClick;
  final downloads = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    originalDio = ApiService().dio;
    downloads.clear();
    onClick = ((web.Event event) {
      final target = event.target;
      if (target != null && target.isA<web.HTMLAnchorElement>()) {
        final anchor = target as web.HTMLAnchorElement;
        expect(anchor.href, startsWith('blob:'));
        downloads.add(anchor.download);
        event.preventDefault(); // Verify dispatch without saving test files.
      }
    }).toJS;
    web.document.addEventListener('click', onClick);
    provider = TodoProvider();
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    web.document.removeEventListener('click', onClick);
    ApiService().dio.close();
    ApiService().dio = originalDio;
    provider.dispose();
  });

  SharedFile file(String name) => SharedFile(
        id: 7, fileName: name, size: 0, uploadTime: '', uploader: 'test');

  test('web download dispatches original Unicode filename and clears progress', () async {
    ApiService().dio = Dio()..httpClientAdapter = DownloadAdapter(200, [0, 1, 255]);
    final result = await provider.downloadFile(file('共享 文档.txt'));
    expect(result, isTrue);
    expect(downloads, ['共享 文档.txt']);
    expect(provider.downloadProgress, isEmpty);
  });

  test('empty extensionless files can also be downloaded', () async {
    ApiService().dio = Dio()..httpClientAdapter = DownloadAdapter(200, []);
    expect(await provider.downloadFile(file('README')), isTrue);
    expect(downloads, ['README']);
    expect(provider.downloadProgress, isEmpty);
  });

  test('HTTP failure does not save an error response and clears progress', () async {
    ApiService().dio = Dio()..httpClientAdapter = DownloadAdapter(404, [123, 125]);
    expect(await provider.downloadFile(file('missing.txt')), isFalse);
    expect(downloads, isEmpty);
    expect(provider.downloadProgress, isEmpty);
  });
}
