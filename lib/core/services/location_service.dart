import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/scan/models/scan_session.dart';

enum LocationStatus { waiting, ready, off, denied }

/// Where the phone is, for Location columns. While a sheet with one is open
/// in the scanner, the position is tracked in the background so a scan
/// never waits for a fix; place names (address, district, PIN…) are looked
/// up once per spot and cached.
class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  final ValueNotifier<LocationStatus> status = ValueNotifier(
    LocationStatus.waiting,
  );

  Position? _latest;
  StreamSubscription<Position>? _stream;
  Completer<Position?>? _firstFix;
  final _places = <String, Future<Place?>>{};
  late final _geocoding = Geocoding();

  /// A fix older than this is still used for the row, then improved.
  static const _staleAfter = Duration(minutes: 2);

  Position? get latest => _latest;

  bool get _fresh =>
      _latest != null &&
      DateTime.now().difference(_latest!.timestamp) < _staleAfter;

  /// Starts tracking. Never shows Android's "turn on location" dialog: if
  /// location is off, [status] says so and rows save without it.
  Future<void> start() async {
    if (_stream != null) return;
    _firstFix = Completer<Position?>();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _settle(LocationStatus.denied);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _settle(LocationStatus.off);
        return;
      }
      final last = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: true,
      );
      if (last != null) _use(last);
      _stream =
          Geolocator.getPositionStream(
            locationSettings: defaultTargetPlatform == TargetPlatform.android
                // The plain LocationManager: Google's fused provider asks for
                // "Location Accuracy" in a dialog that blocks the scanner.
                ? AndroidSettings(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 10,
                    forceLocationManager: true,
                  )
                : const LocationSettings(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 10,
                  ),
          ).listen(
            _use,
            onError: (Object e) {
              debugPrint('Location stream: $e');
              if (e is LocationServiceDisabledException) {
                _settle(LocationStatus.off);
              }
            },
          );
    } catch (e) {
      debugPrint('Location start failed: $e');
      _settle(LocationStatus.off);
    }
  }

  void stop() {
    _stream?.cancel();
    _stream = null;
    if (!(_firstFix?.isCompleted ?? true)) _firstFix!.complete(_latest);
    status.value = LocationStatus.waiting;
  }

  void _use(Position p) {
    _latest = p;
    status.value = LocationStatus.ready;
    if (!(_firstFix?.isCompleted ?? true)) _firstFix!.complete(p);
  }

  void _settle(LocationStatus s) {
    status.value = s;
    if (!(_firstFix?.isCompleted ?? true)) _firstFix!.complete(null);
  }

  /// A fresh position, waiting up to [wait] for one when the last is old.
  Future<Position?> position({
    Duration wait = const Duration(seconds: 20),
  }) async {
    if (_fresh) return _latest;
    final first = _firstFix;
    if (first != null && !first.isCompleted) {
      final p = await first.future.timeout(wait, onTimeout: () => _latest);
      if (p != null) return p;
    }
    return _latest;
  }

  /// The place at [p], looked up once per ~100 m and cached. Null offline
  /// or when the phone has no geocoder.
  Future<Place?> placeAt(Position p) {
    final key =
        '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}';
    return _places[key] ??= _lookUp(p).then((place) {
      if (place == null) _places.remove(key); // try again next time
      return place;
    });
  }

  Future<Place?> _lookUp(Position p) async {
    try {
      final marks = await _geocoding.placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
      final m = marks.firstOrNull;
      if (m == null) return null;
      return Place(
        street: m.street,
        subLocality: m.subLocality,
        locality: m.locality,
        district: m.subAdministrativeArea,
        state: m.administrativeArea,
        postalCode: m.postalCode,
        country: m.country,
      );
    } catch (e) {
      debugPrint('Place lookup failed: $e');
      return null;
    }
  }

  /// What a cell shows while location can't be had at all.
  String? get unavailableText => switch (status.value) {
    LocationStatus.off => 'Location off',
    LocationStatus.denied => 'Location denied',
    _ => null,
  };
}

/// A reverse-geocoded spot, trimmed to what Location columns show.
class Place {
  final String? street;
  final String? subLocality;
  final String? locality;
  final String? district;
  final String? state;
  final String? postalCode;
  final String? country;

  const Place({
    this.street,
    this.subLocality,
    this.locality,
    this.district,
    this.state,
    this.postalCode,
    this.country,
  });
}

String formatCoordinates(double lat, double lng) =>
    '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// A Location cell in [format]. Without a [place] (offline), place formats
/// fall back to the coordinates so the reading isn't lost.
String formatLocation(
  LocationFormat format,
  double lat,
  double lng,
  Place? place,
) {
  final coords = formatCoordinates(lat, lng);
  if (format == LocationFormat.coordinates || place == null) return coords;
  String join(List<String?> parts) {
    final seen = <String>[];
    for (final part in parts) {
      final p = part?.trim() ?? '';
      if (p.isNotEmpty && !seen.contains(p)) seen.add(p);
    }
    return seen.join(', ');
  }

  final value = switch (format) {
    LocationFormat.coordinates => coords,
    LocationFormat.address => join([
      place.street,
      place.subLocality,
      place.locality,
      [place.state, place.postalCode].whereType<String>().join(' '),
      place.country,
    ]),
    LocationFormat.area => join([place.subLocality, place.locality]),
    LocationFormat.district => join([place.district ?? place.locality]),
    LocationFormat.state => join([place.state]),
    LocationFormat.postalCode => join([place.postalCode]),
    LocationFormat.country => join([place.country]),
  };
  return value.isEmpty ? coords : value;
}
