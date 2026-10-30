import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This phone as the free plan sees it: an id that survives reinstalls and
/// cleared app data, and a clock that changing the phone's date can't move.
class DeviceService {
  DeviceService._();

  static const _channel = MethodChannel('scansheet/device');
  static const _anchorKey = 'clock_anchor_v1';

  static String? _id;

  /// Server time at the last anchor, carried forward by [_sinceBase].
  static DateTime? _base;
  static final _sinceBase = Stopwatch();

  /// SHA-256 of ANDROID_ID (MainActivity.kt); null off Android.
  static Future<String?> id() async {
    if (_id != null || !Platform.isAndroid) return _id;
    try {
      _id = await _channel.invokeMethod<String>('deviceId');
    } catch (e) {
      debugPrint('Device id unavailable: $e');
    }
    return _id;
  }

  /// Milliseconds since boot, sleep included; settings can't change it.
  static Future<int?> _elapsed() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('elapsedRealtime');
    } catch (_) {
      return null;
    }
  }

  /// The server's time carried forward since we last heard from it, when
  /// that was since the phone started; otherwise the phone's own clock.
  static DateTime now() =>
      _base == null ? DateTime.now() : _base!.add(_sinceBase.elapsed);

  /// Re-reads the time since boot. Dart's stopwatch stops while the phone
  /// sleeps, so call this on start and on resume.
  static Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final anchor = prefs.getStringList(_anchorKey);
    final elapsed = await _elapsed();
    if (anchor == null || anchor.length != 2 || elapsed == null) return;
    final serverMs = int.tryParse(anchor[0]);
    final anchorElapsed = int.tryParse(anchor[1]);
    if (serverMs == null || anchorElapsed == null) return;
    if (elapsed < anchorElapsed) {
      // Rebooted since: the phone's clock until the server is heard again.
      _base = null;
      return;
    }
    _base = DateTime.fromMillisecondsSinceEpoch(
      serverMs + elapsed - anchorElapsed,
    );
    _sinceBase
      ..reset()
      ..start();
  }

  /// [server] is the server's time, just read.
  static Future<void> anchor(DateTime server) async {
    final elapsed = await _elapsed();
    if (elapsed == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_anchorKey, [
      '${server.millisecondsSinceEpoch}',
      '$elapsed',
    ]);
    _base = server;
    _sinceBase
      ..reset()
      ..start();
  }
}
