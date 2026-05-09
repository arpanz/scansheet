import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'qr_style_profile.dart';

class QrStyleService {
  static const _profilesKey = 'qr_style_profiles_v1';
  static const _activeProfileIdKey = 'qr_style_active_profile_id_v1';

  static Future<List<QrStyleProfile>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) {
      final seeded = [
        QrStyleProfile.defaultProfile(),
        QrStyleProfile.brandProfile(),
      ];
      await _saveProfiles(seeded);
      await prefs.setString(_activeProfileIdKey, seeded.first.id);
      return seeded;
    }

    final decoded = (jsonDecode(raw) as List)
        .map((e) => QrStyleProfile.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    if (decoded.isEmpty) {
      final seeded = [
        QrStyleProfile.defaultProfile(),
        QrStyleProfile.brandProfile(),
      ];
      await _saveProfiles(seeded);
      await prefs.setString(_activeProfileIdKey, seeded.first.id);
      return seeded;
    }
    return decoded;
  }

  static Future<void> _saveProfiles(List<QrStyleProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(profiles.map((e) => e.toJson()).toList());
    await prefs.setString(_profilesKey, raw);
  }

  static Future<String> getActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeProfileIdKey);
    if (id != null && id.isNotEmpty) return id;
    final profiles = await getProfiles();
    final fallback = profiles.first.id;
    await prefs.setString(_activeProfileIdKey, fallback);
    return fallback;
  }

  static Future<QrStyleProfile> getActiveProfile() async {
    final profiles = await getProfiles();
    final id = await getActiveProfileId();
    return profiles.firstWhere((p) => p.id == id, orElse: () => profiles.first);
  }

  static Future<void> setActiveProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileIdKey, profileId);
  }

  static Future<List<QrStyleProfile>> upsertProfile(
    QrStyleProfile profile,
  ) async {
    final profiles = await getProfiles();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await _saveProfiles(profiles);
    return profiles;
  }

  static Future<List<QrStyleProfile>> createProfileFromLegacy(
    QrStyleProfile profile,
  ) async {
    final profiles = await upsertProfile(profile);
    await setActiveProfile(profile.id);
    return profiles;
  }

  /// Deletes the profile with [profileId]. The 'default' preset is protected
  /// and will not be removed. If the list would become empty after deletion,
  /// the default preset is re-seeded. Returns the updated list.
  static Future<List<QrStyleProfile>> deleteProfile(String profileId) async {
    if (profileId == 'default') return getProfiles();
    final profiles = await getProfiles();
    profiles.removeWhere((p) => p.id == profileId);
    if (profiles.isEmpty) {
      profiles.add(QrStyleProfile.defaultProfile());
    }
    await _saveProfiles(profiles);
    // If deleted profile was active, fall back to first available.
    final activeId = await getActiveProfileId();
    if (activeId == profileId) {
      await setActiveProfile(profiles.first.id);
    }
    return profiles;
  }

  static Future<List<QrStyleProfile>> resetToDefaults() async {
    final seeded = [
      QrStyleProfile.defaultProfile(),
      QrStyleProfile.brandProfile(),
    ];
    await _saveProfiles(seeded);
    await setActiveProfile(seeded.first.id);
    return seeded;
  }
}
