import 'package:flutter_test/flutter_test.dart';
import 'package:scansheet/core/services/location_service.dart';
import 'package:scansheet/features/scan/models/scan_session.dart';

void main() {
  const lat = 28.6139391, lng = 77.2090212;
  const place = Place(
    street: 'Janpath',
    subLocality: 'Connaught Place',
    locality: 'New Delhi',
    district: 'New Delhi',
    state: 'Delhi',
    postalCode: '110001',
    country: 'India',
  );
  String f(LocationFormat format, [Place? p = place]) =>
      formatLocation(format, lat, lng, p);

  test('each format picks its part of the place', () {
    expect(f(LocationFormat.coordinates), '28.613939,77.209021');
    expect(
      f(LocationFormat.address),
      'Janpath, Connaught Place, New Delhi, Delhi 110001, India',
    );
    expect(f(LocationFormat.area), 'Connaught Place, New Delhi');
    expect(f(LocationFormat.district), 'New Delhi');
    expect(f(LocationFormat.state), 'Delhi');
    expect(f(LocationFormat.postalCode), '110001');
    expect(f(LocationFormat.country), 'India');
  });

  test('offline, place formats keep the coordinates', () {
    expect(f(LocationFormat.postalCode, null), '28.613939,77.209021');
  });

  test('a missing part falls back sensibly', () {
    const town = Place(locality: 'Siliguri', country: 'India');
    expect(f(LocationFormat.district, town), 'Siliguri');
    expect(f(LocationFormat.postalCode, town), '28.613939,77.209021');
  });

  test('the format survives save and load, coordinates by default', () {
    const col = SessionColumn(
      name: 'PIN code',
      type: SessionColumnType.location,
      locationFormat: LocationFormat.postalCode,
    );
    expect(
      SessionColumn.fromMap(col.toMap()).locationFormat,
      LocationFormat.postalCode,
    );
    expect(
      SessionColumn.fromMap({
        'name': 'Location',
        'type': 'location',
      }).locationFormat,
      LocationFormat.coordinates,
    );
  });

  test('location cells start empty and never block the row', () {
    final session = ScanSession(
      id: 's',
      name: 'n',
      createdAt: DateTime(2026),
      columns: const [
        SessionColumn(name: 'Code', type: SessionColumnType.scan),
        SessionColumn(name: 'Where', type: SessionColumnType.location),
      ],
    );
    expect(session.buildEmptyRow(0).values, ['', '']);
  });
}
