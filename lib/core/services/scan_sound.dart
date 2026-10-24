import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Scanner beeps, so a scan can be confirmed without looking at the phone.
/// [ok] for a row added or counted, [notice] for anything that didn't add a
/// row (a value change, a repeat to check).
class ScanSound {
  ScanSound._();

  static AudioPool? _ok, _notice;
  static Future<void>? _loading;

  // Mix with music or a call on the floor instead of pausing it.
  static final _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  /// Loads both sounds; call when a scanner opens so the first beep is quick.
  static Future<void> warmUp() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      Future<AudioPool> pool(String file) => AudioPool.create(
        source: AssetSource('sounds/$file'),
        maxPlayers: 3,
        playerMode: PlayerMode.lowLatency,
        audioContext: _context,
      );
      _ok = await pool('scan_ok.wav');
      _notice = await pool('scan_notice.wav');
    } catch (e) {
      // A phone without audio shouldn't break scanning.
      debugPrint('Scan sounds unavailable: $e');
    }
  }

  static void ok() => _play(_ok);
  static void notice() => _play(_notice);

  static void _play(AudioPool? pool) {
    if (pool == null) return;
    pool.start().catchError((Object e) {
      debugPrint('Scan sound failed: $e');
      return () async {};
    });
  }
}
