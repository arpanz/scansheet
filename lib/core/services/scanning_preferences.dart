import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DuplicateHandling { warn, increment, skip, allow }

class ScanningPreferences extends ChangeNotifier {
  static const _keySoundEnabled      = 'scan_pref_sound';
  static const _keyVibrateEnabled    = 'scan_pref_vibrate';
  static const _keyTorchDefault      = 'scan_pref_torch';
  static const _keyAutoFocus         = 'scan_pref_autofocus';
  static const _keyDuplicateHandling = 'scan_pref_duplicate';
  static const _keyDefaultTemplate   = 'scan_pref_default_template';

  bool _soundEnabled                  = true;
  bool _vibrateEnabled                = true;
  bool _torchDefault                  = false;
  bool _autoFocus                     = true;
  DuplicateHandling _duplicateHandling = DuplicateHandling.warn;
  String? _defaultTemplateName;

  bool get soundEnabled            => _soundEnabled;
  bool get vibrateEnabled          => _vibrateEnabled;
  bool get torchDefault            => _torchDefault;
  bool get autoFocus               => _autoFocus;
  DuplicateHandling get duplicateHandling => _duplicateHandling;
  String? get defaultTemplateName  => _defaultTemplateName;

  /// Call once in main() before runApp.
  static Future<ScanningPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final instance = ScanningPreferences();
    instance._soundEnabled   = prefs.getBool(_keySoundEnabled)   ?? true;
    instance._vibrateEnabled = prefs.getBool(_keyVibrateEnabled) ?? true;
    instance._torchDefault   = prefs.getBool(_keyTorchDefault)   ?? false;
    instance._autoFocus      = prefs.getBool(_keyAutoFocus)      ?? true;
    final dupRaw             = prefs.getString(_keyDuplicateHandling);
    instance._duplicateHandling = DuplicateHandling.values.firstWhere(
      (e) => e.name == dupRaw,
      orElse: () => DuplicateHandling.warn,
    );
    instance._defaultTemplateName = prefs.getString(_keyDefaultTemplate);
    return instance;
  }

  Future<void> setSoundEnabled(bool v) async {
    _soundEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySoundEnabled, v);
  }

  Future<void> setVibrateEnabled(bool v) async {
    _vibrateEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVibrateEnabled, v);
  }

  Future<void> setTorchDefault(bool v) async {
    _torchDefault = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTorchDefault, v);
  }

  Future<void> setAutoFocus(bool v) async {
    _autoFocus = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoFocus, v);
  }

  Future<void> setDuplicateHandling(DuplicateHandling v) async {
    _duplicateHandling = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDuplicateHandling, v.name);
  }

  Future<void> setDefaultTemplateName(String? v) async {
    _defaultTemplateName = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_keyDefaultTemplate);
    } else {
      await prefs.setString(_keyDefaultTemplate, v);
    }
  }
}
