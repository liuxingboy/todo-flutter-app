import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_client/services/android_downloads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('todo_client/downloads');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('save reports the native destination and passes the temporary file', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveDownload');
      expect(call.arguments, {'sourcePath': '/cache/payload', 'fileName': '测试.txt'});
      return 'Download/测试 (1).txt';
    });
    expect(await AndroidDownloads.save('/cache/payload', '测试.txt'), 'Download/测试 (1).txt');
  });

  test('missing save result is a failure, not a successful download', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(AndroidDownloads.save('/cache/payload', 'file.txt'),
        throwsA(isA<PlatformException>()));
  });

  test('storage failure is propagated to the download caller', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'save_failed', message: '目录授权已失效');
    });
    await expectLater(AndroidDownloads.save('/cache/payload', 'file.txt'),
        throwsA(isA<PlatformException>().having((e) => e.message, 'message', '目录授权已失效')));
  });

  test('cancelling directory selection returns no replacement', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'chooseDirectory');
      return null;
    });
    expect(await AndroidDownloads.chooseDirectory(), isNull);
  });
}
