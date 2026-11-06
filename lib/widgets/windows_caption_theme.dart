import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WindowsCaptionTheme extends StatefulWidget {
  const WindowsCaptionTheme({super.key, required this.child});

  final Widget child;

  @override
  State<WindowsCaptionTheme> createState() => _WindowsCaptionThemeState();
}

class _WindowsCaptionThemeState extends State<WindowsCaptionTheme> {
  static const _channel = MethodChannel('todo/windows_caption');
  (int, int)? _colors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    final values = (
      colors.surfaceContainer.toARGB32() & 0xffffff,
      colors.onSurface.toARGB32() & 0xffffff,
    );
    if (_colors == values) return;
    _colors = values;
    _setColors(values);
  }

  Future<void> _setColors((int, int) values) async {
    try {
      await _channel.invokeMethod<void>('setColors', [values.$1, values.$2]);
    } on MissingPluginException {
      // Keep the system caption when no native runner is present.
    } on PlatformException catch (error) {
      debugPrint('Unable to apply the Windows caption theme: ${error.code}');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
