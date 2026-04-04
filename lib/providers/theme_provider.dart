import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'app_theme_mode';
  static const String _themeColorKey = 'app_theme_color';
  
  ThemeMode _themeMode = ThemeMode.system;
  String _selectedThemeName = 'Espo';

  ThemeMode get themeMode => _themeMode;
  String get selectedThemeName => _selectedThemeName;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final String? modeStr = prefs.getString(_themeModeKey);
    final String? colorStr = prefs.getString(_themeColorKey);

    if (modeStr != null) {
      if (modeStr == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (modeStr == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.system;
      }
    }

    if (colorStr != null) {
      _selectedThemeName = colorStr;
    }
    
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.dark) {
      await prefs.setString(_themeModeKey, 'dark');
    } else if (mode == ThemeMode.light) {
      await prefs.setString(_themeModeKey, 'light');
    } else {
      await prefs.setString(_themeModeKey, 'system');
    }
  }

  // Alias for backward compatibility
  Future<void> setTheme(ThemeMode mode) => setMode(mode);

  Future<void> setColorTheme(String name) async {
    _selectedThemeName = name;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeColorKey, name);
  }

  void toggleMode() {
    if (_themeMode == ThemeMode.dark) {
      setMode(ThemeMode.light);
    } else if (_themeMode == ThemeMode.light) {
      setMode(ThemeMode.system);
    } else {
      setMode(ThemeMode.dark);
    }
  }
}
