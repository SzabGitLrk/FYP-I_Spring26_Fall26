import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:university_point_locator/navigation/route_follower.dart';
import 'package:university_point_locator/navigation/route_step.dart';

void main() {
  group('RouteStep.fromOsrmRoute', () {
    test('synthesises readable instructions from OSRM maneuvers', () {
      final steps = RouteStep.fromOsrmRoute({
        'legs': [
          {
            'steps': [
              {
                'maneuver': {
                  'type': 'depart',
                  'location': [68.222, 27.588],
                  'bearing_after': 180,
                },
                'name': 'VIP Road',
                'distance': 120.5,
              },
              {
                'maneuver': {
                  'type': 'turn',
                  'modifier': 'right',
                  'location': [68.223, 27.580],
                },
                'name': 'College Rd',
                'distance': 300,
              },
              {
                'maneuver': {
                  'type': 'roundabout',
                  'exit': 2,
                  'location': [68.224, 27.575],
                },
                'name': '',
                'distance': 80,
              },
              {
                'maneuver': {
                  'type': 'arrive',
                  'modifier': 'left',
                  'location': [68.225, 27.572],
                },
                'name': 'PTS Road',
                'distance': 0,
              },
            ],
          },
        ],
      });

      expect(steps, hasLength(4));
      expect(steps[0].instruction, 'Head south on VIP Road');
      expect(steps[1].instruction, 'Turn right onto College Rd');
      expect(steps[2].instruction, 'At the roundabout, take exit 2');
      expect(steps[3].instruction, 'Arrive at your stop');

      expect(steps[1].maneuver, 'turn-right');
      expect(steps[0].maneuver, startsWith('depart'));
      expect(steps[3].maneuver, startsWith('arrive'));

      // GeoJSON [lon, lat] -> LatLng(lat, lon).
      expect(steps[1].location.latitude, closeTo(27.580, 1e-9));
      expect(steps[1].location.longitude, closeTo(68.223, 1e-9));
      expect(steps[0].distance, closeTo(120.5, 1e-9));
    });

    test('tolerates a malformed body without throwing', () {
      expect(RouteStep.fromOsrmRoute({'legs': 'not a list'}), isEmpty);
      expect(
        RouteStep.fromOsrmRoute({
          'legs': [
            {
              'steps': [
                {'maneuver': 'not a map'},
                <String, dynamic>{'maneuver': {'location': 'bad'}},
              ],
            },
          ],
        }),
        isEmpty,
      );
    });
  });

  group('RouteStep.fromValhallaTrip', () {
    test('reads maneuvers, km lengths and supplied instructions', () {
      final steps = RouteStep.fromValhallaTrip({
        'legs': [
          {
            'maneuvers': [
              {
                'type': 'straight',
                'instruction': 'Head south on VIP Road',
                'street_name': 'VIP Road',
                'length': 0.12,
                'start_location': {'lat': 27.588, 'lon': 68.222},
              },
              {
                'type': 'slight right',
                'street_name': 'Canal Rd',
                'length': 0.3,
                'start_location': {'lat': 27.580, 'lon': 68.223},
              },
              {
                'type': 'dest',
                'street_name': 'PTS Road',
                'length': 0.01,
                'start_location': {'lat': 27.572, 'lon': 68.225},
              },
            ],
          },
        ],
      });

      expect(steps, hasLength(3));
      expect(steps[0].instruction, 'Head south on VIP Road');
      // Kilometers -> meters.
      expect(steps[0].distance, closeTo(120, 1e-9));
      expect(steps[1].maneuver, 'slight-right');
      // Missing instruction falls back to a synthesised one.
      expect(steps[1].instruction, 'Bear right onto Canal Rd');
      // Arrival keeps the icon key stable across both routers.
      expect(steps[2].maneuver, 'arrive');
      expect(steps[2].instruction, 'Arrive at your stop');
    });
  });

  group('RouteStep.formatDistance', () {
    test('switches from meters to kilometers at 1000 m', () {
      expect(RouteStep.formatDistance(0), '0 m');
      expect(RouteStep.formatDistance(850), '850 m');
      expect(RouteStep.formatDistance(1200), '1.2 km');
    });
  });

  group('RouteFollower', () {
    // ~2.21 km straight north-south, mirroring the real PTS route's first
    // leg (stops share a longitude there).
    final route = [LatLng(27.588, 68.222), LatLng(27.568, 68.222)];

    test('projects a position onto the route and splits progress', () {
      final follower = RouteFollower(points: route, steps: const []);
      expect(follower.totalMeters, closeTo(2211, 5));

      final progress = follower.update(LatLng(27.578, 68.222));
      expect(progress.distanceAlong, closeTo(follower.totalMeters / 2, 5));
      expect(progress.remainingMeters, closeTo(follower.totalMeters / 2, 5));
      expect(progress.distanceOffRoute, lessThan(1));
      expect(progress.arrived, isFalse);
      // Without steps the follower still reports a usable distance-to-next.
      expect(progress.distanceToManeuver, closeTo(progress.remainingMeters, 1e-9));
    });

    test('flags an off-route position with its distance', () {
      final follower = RouteFollower(points: route, steps: const []);
      // ~99 m east of the midpoint.
      final progress = follower.update(LatLng(27.578, 68.223));
      expect(progress.distanceOffRoute, inInclusiveRange(85, 115));
      expect(progress.arrived, isFalse);
    });

    test('reports arrival near the route end', () {
      final follower = RouteFollower(points: route, steps: const []);
      // A few meters from the last route point.
      final progress = follower.update(LatLng(27.56805, 68.2223));
      expect(progress.arrived, isTrue);
      expect(progress.distanceOffRoute, lessThan(45));
    });

    test('advances to the next step once its maneuver point is passed', () {
      final steps = [
        RouteStep(
          instruction: 'Turn right onto College Road',
          maneuver: 'turn-right',
          distance: 1105,
          roadName: 'College Road',
          location: LatLng(27.578, 68.222),
        ),
        RouteStep(
          instruction: 'Arrive at your stop',
          maneuver: 'arrive',
          distance: 1106,
          roadName: '',
          location: LatLng(27.568, 68.222),
        ),
      ];
      final follower = RouteFollower(points: route, steps: steps);

      final before = follower.update(LatLng(27.587, 68.222));
      expect(before.nextStepIndex, 0);
      expect(before.distanceToManeuver, closeTo(995, 10));

      final after = follower.update(LatLng(27.5775, 68.222));
      expect(after.nextStepIndex, 1);

      // Past every maneuver but not at the end: stays on the last step.
      final lastLeg = follower.update(LatLng(27.569, 68.222));
      expect(lastLeg.nextStepIndex, 1);
      expect(lastLeg.arrived, isFalse);
    });
  });
}
