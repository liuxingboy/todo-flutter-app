import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_client/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installs connect to the N100 HTTPS domain', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(ApiService().getBaseUrlSync(prefs), 'https://todo.maopc.icu:443/api');
  });

  test('retired production settings move to N100 without clearing login', () async {
    SharedPreferences.setMockInitialValues({
      'server_ip': '8.138.16.235',
      'server_port': '8080',
      'access_token': 'existing-login',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(ApiService().getBaseUrlSync(prefs), 'https://todo.maopc.icu:443/api');
    expect(prefs.getString('access_token'), 'existing-login');
    expect(ApiService.serverHost(prefs), 'todo.maopc.icu');
    expect(ApiService.serverPort(prefs), '443');
    expect(ApiService.serverUsesHttps(prefs), isTrue);
  });

  test('custom legacy HTTP servers remain unchanged', () async {
    SharedPreferences.setMockInitialValues({'server_ip': '192.168.1.10', 'server_port': '8080'});
    final prefs = await SharedPreferences.getInstance();
    expect(ApiService().getBaseUrlSync(prefs), 'http://192.168.1.10:8080/api');
  });

  test('custom protocol preference persists after saving', () async {
    SharedPreferences.setMockInitialValues({});
    await ApiService().updateSettings('custom.example', '8443', useHttps: true);
    final prefs = await SharedPreferences.getInstance();
    expect(ApiService().getBaseUrlSync(prefs), 'https://custom.example:8443/api');
    await ApiService().updateSettings('custom.example', '8080');
    expect(ApiService().getBaseUrlSync(prefs), 'http://custom.example:8080/api');
  });
}
