import 'package:flutter/foundation.dart';

class ThemeManager {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  /// false = Light mode (default), true = Dark mode
  final ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(false);

  void toggleTheme() {
    isDarkMode.value = !isDarkMode.value;
  }
}
