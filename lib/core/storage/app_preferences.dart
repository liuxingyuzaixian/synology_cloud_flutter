import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();

  static SharedPreferences? _instance;

  static Future<SharedPreferences> init() async {
    _instance ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  static SharedPreferences get instance {
    final prefs = _instance;
    if (prefs == null) {
      throw StateError('AppPreferences.init() must be called before use.');
    }
    return prefs;
  }

  static String getString(String key, {String defaultValue = ''}) {
    return instance.getString(key) ?? defaultValue;
  }

  static Future<bool> putString(String key, String value) {
    return instance.setString(key, value);
  }

  static bool getBool(String key, {bool defaultValue = false}) {
    return instance.getBool(key) ?? defaultValue;
  }

  static Future<bool> putBool(String key, bool value) {
    return instance.setBool(key, value);
  }

  static int getInt(String key, {int defaultValue = 0}) {
    return instance.getInt(key) ?? defaultValue;
  }

  static Future<bool> putInt(String key, int value) {
    return instance.setInt(key, value);
  }

  static Future<bool> remove(String key) {
    return instance.remove(key);
  }
}
