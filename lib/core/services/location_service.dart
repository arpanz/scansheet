import 'package:geolocator/geolocator.dart';

/// Provides GPS coordinates for location-type session columns.
/// Caches the last position for 30 seconds to avoid spamming GPS
/// during rapid scanning sessions.
class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  Position? _lastPosition;
  DateTime? _lastFetch;

  static const _cacheDuration = Duration(seconds: 30);

  /// Returns a "lat,lng" string, e.g. "28.613939,77.209021".
  /// Returns a descriptive error string if permission is denied or GPS fails.
  Future<String> getLocationString() async {
    // Return cached value if still fresh
    if (_lastPosition != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return _format(_lastPosition!);
    }

    // Check and request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'Location denied';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location blocked';
    }

    // Check if location services are enabled on device
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location off';
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // ~100m, fast & battery-friendly
          timeLimit: Duration(seconds: 8),
        ),
      );
      _lastPosition = pos;
      _lastFetch = DateTime.now();
      return _format(pos);
    } on LocationServiceDisabledException {
      return 'Location off';
    } catch (_) {
      // Fall back to last known position if available
      if (_lastPosition != null) return _format(_lastPosition!);
      return 'Location unavailable';
    }
  }

  /// Clears the cache, forcing a fresh GPS fetch on the next call.
  void clearCache() {
    _lastPosition = null;
    _lastFetch = null;
  }

  String _format(Position p) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';
}
