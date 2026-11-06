import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TodoPalette {
  purple('经典紫', Colors.deepPurple),
  blue('海洋蓝', Colors.blue),
  green('森林绿', Colors.green),
  orange('暖橙', Colors.deepOrange);

  const TodoPalette(this.label, this.seedColor);

  final String label;
  final Color seedColor;
}

class ThemePreferences extends ChangeNotifier {
  ThemePreferences(this._prefs)
    : _mode = ThemeMode.values.firstWhere(
        (mode) => mode.name == _prefs.getString(_modeKey),
        orElse: () => ThemeMode.system,
      ),
      _palette = TodoPalette.values.firstWhere(
        (palette) => palette.name == _prefs.getString(_paletteKey),
        orElse: () => TodoPalette.purple,
      );

  static const _modeKey = 'appearance_mode';
  static const _paletteKey = 'appearance_palette';
  final SharedPreferences _prefs;
  ThemeMode _mode;
  TodoPalette _palette;

  ThemeMode get mode => _mode;
  TodoPalette get palette => _palette;

  ThemeData themeFor(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: palette.seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colors,
      appBarTheme: AppBarThemeData(
        backgroundColor: colors.surfaceContainer,
        foregroundColor: colors.onSurface,
      ),
      useMaterial3: true,
    );
  }

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    await _prefs.setString(_modeKey, value.name);
  }

  Future<void> setPalette(TodoPalette value) async {
    if (_palette == value) return;
    _palette = value;
    notifyListeners();
    await _prefs.setString(_paletteKey, value.name);
  }
}
