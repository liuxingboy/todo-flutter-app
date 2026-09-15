import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/android_downloads.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String _downloadDirectory = 'Download';
  bool _choosingDirectory = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (_isAndroid) _loadDownloadDirectory();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ipController.text = prefs.getString('server_ip') ?? ApiService.defaultIp;
      _portController.text = prefs.getString('server_port') ?? ApiService.defaultPort;
    });
  }

  Future<void> _loadDownloadDirectory() async {
    try {
      final directory = await AndroidDownloads.directory();
      if (mounted) setState(() => _downloadDirectory = directory);
    } on PlatformException catch (e) {
      if (mounted) _showDirectoryError(e);
    }
  }

  void _showDirectoryError(PlatformException e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message ?? '无法更新下载目录，请重试')),
    );
  }

  Future<void> _changeDownloadDirectory({bool reset = false}) async {
    setState(() => _choosingDirectory = true);
    try {
      final directory = reset
          ? await AndroidDownloads.resetDirectory()
          : await AndroidDownloads.chooseDirectory();
      if (mounted && directory != null) {
        setState(() => _downloadDirectory = directory);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载目录已更新：$directory')),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) _showDirectoryError(e);
    } finally {
      if (mounted) setState(() => _choosingDirectory = false);
    }
  }

  Future<void> _saveSettings() async {
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();

    if (ip.isEmpty || port.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP 和端口不能为空！')),
      );
      return;
    }

    await ApiService().updateSettings(ip, port);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 连接设置已更新'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器连接设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '配置后端服务器地址',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '修改后将立即生效，请确保服务器已启动且网络通畅。',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: '服务器 IP',
                hintText: '例如: 8.138.22.227',
                prefixIcon: const Icon(Icons.lan),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '端口',
                hintText: '例如: 8080',
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('保存并应用'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _ipController.text = ApiService.defaultIp;
                _portController.text = ApiService.defaultPort;
              },
              child: const Text('重置为默认值'),
            ),
            if (_isAndroid) ...[
              const Divider(height: 40),
              const Text('文件下载', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('下载目录'),
              const SizedBox(height: 4),
              SelectableText(_downloadDirectory),
              const SizedBox(height: 8),
              const Text(
                '默认保存到手机的 Download（下载）文件夹。选择其他目录后会自动记住，立即生效。',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _choosingDirectory ? null : () => _changeDownloadDirectory(),
                icon: const Icon(Icons.folder_open),
                label: Text(_choosingDirectory ? '正在选择目录…' : '选择下载目录'),
              ),
              TextButton(
                onPressed: _choosingDirectory ? null : () => _changeDownloadDirectory(reset: true),
                child: const Text('恢复默认下载目录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
