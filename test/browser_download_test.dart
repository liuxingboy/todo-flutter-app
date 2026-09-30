@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_client/models/todo_models.dart';
import 'package:todo_client/providers/todo_provider.dart';
import 'package:todo_client/services/api_service.dart';
import 'package:todo_client/services/browser_download_web.dart';
import 'package:web/web.dart' as web;

class DownloadAdapter implements HttpClientAdapter {
  DownloadAdapter(
    this.status, {
    this.url = '/api/files/browser-download/7?ticket=test',
  });
  final int status;
  final String url;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/files/download-ticket/7');
    expect(options.method, 'POST');
    return ResponseBody.fromString(
      jsonEncode({
        'code': status == 200 ? 0 : status,
        'data': {'download_url': url},
      }),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
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
        expect(
          anchor.getAttribute('href'),
          '/api/files/browser-download/7?ticket=test',
        );
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
    id: 7,
    fileName: name,
    size: 0,
    uploadTime: '',
    uploader: 'test',
  );

  test(
    'web download dispatches original Unicode filename and clears progress',
    () async {
      ApiService().dio = Dio()..httpClientAdapter = DownloadAdapter(200);
      final result = await provider.downloadFile(file('共享 文档.txt'));
      expect(result, isTrue);
      expect(downloads, ['共享 文档.txt']);
      expect(provider.downloadProgress, isEmpty);
    },
  );

  test('empty extensionless files can also be downloaded', () async {
    ApiService().dio = Dio()..httpClientAdapter = DownloadAdapter(200);
    expect(await provider.downloadFile(file('README')), isTrue);
    expect(downloads, ['README']);
    expect(provider.downloadProgress, isEmpty);
  });

  test(
    'HTTP failure does not save an error response and clears progress',
    () async {
      ApiService().dio = Dio()..httpClientAdapter = DownloadAdapter(404);
      expect(await provider.downloadFile(file('missing.txt')), isFalse);
      expect(downloads, isEmpty);
      expect(provider.downloadProgress, isEmpty);
    },
  );

  test('rejects external download URLs', () async {
    ApiService().dio = Dio()
      ..httpClientAdapter = DownloadAdapter(
        200,
        url: 'https://example.com/file',
      );
    expect(await provider.downloadFile(file('test.txt')), isFalse);
    expect(downloads, isEmpty);
    expect(provider.downloadProgress, isEmpty);
  });

  test('rejects unrelated and protocol-relative URLs', () {
    for (final url in [
      '//example.com/api/files/browser-download/7',
      '/api/auth/login',
    ]) {
      expect(() => saveBrowserDownload(url, 'test.txt'), throwsArgumentError);
    }
  });
}
