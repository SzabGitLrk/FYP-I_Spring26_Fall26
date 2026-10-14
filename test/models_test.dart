import 'package:flutter_test/flutter_test.dart';
import 'package:university_point_locator/models/bus.dart';
import 'package:university_point_locator/models/bus_location.dart';
import 'package:university_point_locator/models/pickup_point.dart';
import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/models/university.dart';

void main() {
  group('BusLocation.fromJson', () {
    test('reads a full row and coerces numeric columns to double', () {
      final loc = BusLocation.fromJson({
        'id': 5,
        'bus_id': 3,
        // PostgREST happily sends whole numbers for double columns.
        'latitude': 27,
        'longitude': 68,
        'speed': 18,
        'heading': 90,
        'next_stop_index': 2,
        'timestamp': '2026-01-02T03:04:05Z',
      });

      expect(loc.id, 5);
      expect(loc.busId, 3);
      expect(loc.latitude, isA<double>());
      expect(loc.latitude, closeTo(27, 1e-9));
      expect(loc.longitude, closeTo(68, 1e-9));
      expect(loc.speed, isA<double>());
      expect(loc.speed, closeTo(18, 1e-9));
      expect(loc.heading, closeTo(90, 1e-9));
      expect(loc.nextStopIndex, 2);
      expect(loc.timestamp.isUtc, isTrue);
      expect(loc.timestamp.year, 2026);
      expect(loc.timestamp.month, 1);
      expect(loc.timestamp.day, 2);
    });

    test('fills schema-null columns instead of taking the list down', () {
      final loc = BusLocation.fromJson({
        'id': 1,
        'bus_id': null,
        'latitude': 1.5,
        'longitude': 2.5,
        'speed': null,
        'heading': null,
        'next_stop_index': null,
        'timestamp': null,
      });

      expect(loc.busId, 0);
      expect(loc.speed, 0);
      expect(loc.heading, 0);
      expect(loc.nextStopIndex, 0);
      // A NULL timestamp must NEVER fall back to "now": the freshness
      // pipeline ages rows against server stamps to defeat ghost buses, and
      // a fabricated fresh stamp would keep a dead bus on the map forever.
      // Epoch 0 = maximally stale, the honest default.
      expect(
        loc.timestamp,
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    test('fails loudly when a required column is missing', () {
      expect(
        () => BusLocation.fromJson({'id': 1}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('BusLocation.estimatedTimeTo', () {
    BusLocation busAt(double lat, double speed) => BusLocation(
      id: 1,
      busId: 1,
      latitude: lat,
      longitude: 68.222,
      speed: speed,
      heading: 0,
      nextStopIndex: 0,
      timestamp: DateTime.now(),
    );

    test('stopped AT the stop means arrived (0 min), not "unknown"', () {
      expect(busAt(27.578, 0).estimatedTimeTo(27.578, 68.222), 0);
      // speed <= 1 counts as stopped, not only a hard 0.
      expect(busAt(27.578, 1).estimatedTimeTo(27.578, 68.222), 0);
    });

    test('stopped away from the stop yields no phantom estimate', () {
      // ~1.11 km north of the stop.
      expect(busAt(27.578, 0).estimatedTimeTo(27.588, 68.222), isNull);
      expect(busAt(27.578, 1).estimatedTimeTo(27.588, 68.222), isNull);
    });

    test('moving bus reports ceil(distance / speed), never rounding down', () {
      // 0.01 deg of latitude ~ 1.112 km; at 20 km/h -> 3.34 min -> 4.
      expect(busAt(27.578, 20).estimatedTimeTo(27.588, 68.222), 4);
      // Same distance at 1.5 km/h -> 44.5 min -> 45.
      expect(busAt(27.578, 1.5).estimatedTimeTo(27.588, 68.222), 45);
    });

    test('distanceTo matches the Haversine scale (~1.112 km per 0.01 deg)', () {
      expect(busAt(27.578, 0).distanceTo(27.588, 68.222), closeTo(1.112, 0.01));
    });
  });

  group('Bus.fromJson', () {
    test('reads a full row', () {
      final bus = Bus.fromJson({
        'id': 7,
        'route_id': 2,
        'bus_number': 'PB-1234',
        'driver_name': 'Ravi Kumar',
        'driver_phone': '+91 90000 00000',
        'capacity': 42,
        'status': 'inactive',
        'created_at': '2026-01-02T03:04:05.123456Z',
      });

      expect(bus.id, 7);
      expect(bus.routeId, 2);
      expect(bus.busNumber, 'PB-1234');
      expect(bus.driverName, 'Ravi Kumar');
      expect(bus.driverPhone, '+91 90000 00000');
      expect(bus.capacity, 42);
      expect(bus.status, 'inactive');
      expect(bus.createdAt.isUtc, isTrue);
      expect(bus.createdAt.millisecond, 123);
    });

    test('defaults nullable columns instead of crashing every bus list', () {
      final before = DateTime.now();
      final bus = Bus.fromJson({
        'id': 1,
        'route_id': null,
        'bus_number': 'UNASSIGNED',
        'driver_name': null,
        'driver_phone': null,
        'capacity': null,
        'status': null,
        'created_at': null,
      });
      final after = DateTime.now();

      expect(bus.routeId, 0); // matches no route
      expect(bus.driverName, isNull);
      expect(bus.driverPhone, isNull);
      expect(bus.capacity, 20);
      expect(bus.status, 'active');
      expect(!bus.createdAt.isBefore(before), isTrue);
      expect(!bus.createdAt.isAfter(after), isTrue);
    });
  });

  group('PickupPoint.fromJson', () {
    test('reads a full row', () {
      final point = PickupPoint.fromJson({
        'id': 11,
        'route_id': 2,
        'point_name': 'PTS Gate',
        'latitude': 27.588,
        'longitude': 68.222,
        'address': 'Main Campus Road',
        'landmark': 'Near the boys hostel',
        'order_index': 3,
        'estimated_time_from_previous': 5,
        'created_at': '2026-01-02T03:04:05Z',
      });

      expect(point.id, 11);
      expect(point.routeId, 2);
      expect(point.pointName, 'PTS Gate');
      expect(point.latitude, closeTo(27.588, 1e-9));
      expect(point.longitude, closeTo(68.222, 1e-9));
      expect(point.address, 'Main Campus Road');
      expect(point.landmark, 'Near the boys hostel');
      expect(point.orderIndex, 3);
      expect(point.estimatedTimeFromPrevious, 5);
      expect(point.createdAt.isUtc, isTrue);
    });

    test('keeps nullable columns null and defaults the FK', () {
      final point = PickupPoint.fromJson({
        'id': 1,
        'route_id': null,
        'point_name': 'Library',
        'latitude': 27,
        'longitude': 68,
        'address': null,
        'landmark': null,
        'order_index': 1,
        'estimated_time_from_previous': null,
        'created_at': null,
      });

      expect(point.routeId, 0);
      expect(point.address, isNull);
      expect(point.landmark, isNull);
      expect(point.estimatedTimeFromPrevious, isNull);
      expect(point.createdAt, isNotNull);
    });
  });

  group('RouteModel.fromJson', () {
    test('reads a full row', () {
      final route = RouteModel.fromJson({
        'id': 4,
        'university_id': 9,
        'route_name': 'Route A - City Circle',
        'description': 'Via VIP Road',
        'created_at': '2026-01-02T03:04:05Z',
      });

      expect(route.id, 4);
      expect(route.universityId, 9);
      expect(route.routeName, 'Route A - City Circle');
      expect(route.description, 'Via VIP Road');
      expect(route.createdAt.isUtc, isTrue);
    });

    test('defaults the nullable FK and keeps description null', () {
      final route = RouteModel.fromJson({
        'id': 1,
        'university_id': null,
        'route_name': 'Bare',
        'description': null,
        'created_at': null,
      });

      expect(route.universityId, 0);
      expect(route.description, isNull);
      expect(route.createdAt, isNotNull);
    });
  });

  group('University.fromJson', () {
    test('reads a full row', () {
      final university = University.fromJson({
        'id': 2,
        'name': 'Punjab State Technical University',
        'city': 'Ludhiana',
        'created_at': '2026-01-02T03:04:05Z',
      });

      expect(university.id, 2);
      expect(university.name, 'Punjab State Technical University');
      expect(university.city, 'Ludhiana');
      expect(university.createdAt.isUtc, isTrue);
    });

    test('falls back to now when created_at is missing', () {
      final before = DateTime.now();
      final university = University.fromJson({
        'id': 3,
        'name': 'Test University',
        'city': 'Test City',
        'created_at': null,
      });
      final after = DateTime.now();

      expect(!university.createdAt.isBefore(before), isTrue);
      expect(!university.createdAt.isAfter(after), isTrue);
    });
  });
}
