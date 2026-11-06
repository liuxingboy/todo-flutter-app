import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_preferences.dart';
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
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String _downloadDirectory = 'Download';
  bool _choosingDirectory = false;
  bool _useHttps = true;

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
      _ipController.text = ApiService.serverHost(prefs);
      _portController.text = ApiService.serverPort(prefs);
      _useHttps = ApiService.serverUsesHttps(prefs);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.message ?? '无法更新下载目录，请重试')));
  }

  Future<void> _changeDownloadDirectory({bool reset = false}) async {
    setState(() => _choosingDirectory = true);
    try {
      final directory = reset
          ? await AndroidDownloads.resetDirectory()
          : await AndroidDownloads.chooseDirectory();
      if (mounted && directory != null) {
        setState(() => _downloadDirectory = directory);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载目录已更新：$directory')));
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

    final portNumber = int.tryParse(port);
    if (ip.isEmpty ||
        ip.contains('://') ||
        ip.contains('/') ||
        portNumber == null ||
        portNumber < 1 ||
        portNumber > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入域名或 IP（不含协议和路径），端口范围为 1–65535。')),
      );
      return;
    }

    await ApiService().updateSettings(ip, port, useHttps: _useHttps);

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

  void _showDonateDialog() {
    final colors = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('打赏作者', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                'http://8.138.22.227:8080/api/donate/qr',
                width: 250,
                height: 250,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    width: 250,
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 250,
                    height: 250,
                    color: colors.surfaceContainerHighest,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image,
                          size: 48,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '二维码加载失败',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '感谢支持独立开发！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
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
    final showLogout = ModalRoute.of(context)?.settings.arguments == true;
    final appearance = context.watch<ThemePreferences>();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '主题设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('外观'),
              trailing: DropdownButton<ThemeMode>(
                value: appearance.mode,
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
                onChanged: (mode) {
                  if (mode != null) appearance.setMode(mode);
                },
              ),
            ),
            const Text('主题配色'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final palette in TodoPalette.values)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: palette.seedColor),
                    label: Text(palette.label),
                    selected: appearance.palette == palette,
                    onSelected: (_) => appearance.setPalette(palette),
                  ),
              ],
            ),
            const Divider(height: 40),
            const Text(
              '连接设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '修改后将立即生效，请确保服务器已启动且网络通畅。',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: '服务器域名或 IP',
                hintText: '例如: todo.maopc.icu',
                prefixIcon: const Icon(Icons.lan),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '端口',
                hintText: '例如: 443',
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('使用 HTTPS'),
              subtitle: const Text('Todo 正式服务器使用 HTTPS，端口为 443。'),
              value: _useHttps,
              onChanged: (value) => setState(() => _useHttps = value),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('保存并应用'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _ipController.text = ApiService.defaultIp;
                  _portController.text = ApiService.defaultPort;
                  _useHttps = true;
                });
              },
              child: const Text('重置为默认值'),
            ),
            if (_isAndroid) ...[
              const Divider(height: 40),
              const Text(
                '文件下载',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('下载目录'),
              const SizedBox(height: 4),
              SelectableText(_downloadDirectory),
              const SizedBox(height: 8),
              Text(
                '默认保存到手机的 Download（下载）文件夹。选择其他目录后会自动记住，立即生效。',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _choosingDirectory
                    ? null
                    : () => _changeDownloadDirectory(),
                icon: const Icon(Icons.folder_open),
                label: Text(_choosingDirectory ? '正在选择目录…' : '选择下载目录'),
              ),
              TextButton(
                onPressed: _choosingDirectory
                    ? null
                    : () => _changeDownloadDirectory(reset: true),
                child: const Text('恢复默认下载目录'),
              ),
            ],
            const Divider(height: 40),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.favorite_outline),
              title: const Text('打赏支持'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showDonateDialog,
            ),
            if (showLogout)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                onTap: _logout,
              ),
          ],
        ),
      ),
    );
  }
}
