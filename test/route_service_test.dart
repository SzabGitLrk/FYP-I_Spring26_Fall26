import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:university_point_locator/services/route_service.dart';

/// Precision-6 encoded polylines (what Valhalla ships in `leg.shape`),
/// produced by a reference encoder and verified to round-trip:
///   legA -> (27.588, 68.222), (27.578, 68.2235), (27.568, 68.222)
///   legB -> (27.568, 68.222), (27.561, 68.221)
///   onePoint -> a single point, so `< 2` after decoding.
const String legA = '_yyrs@_b}baC~oRw|A~oRv|A';
const String legB = '_wrqs@_b}baCntLn}@';
const String onePoint = '_yyrs@_b}baC';

void main() {
  // A realistic `geometries=geojson` OSRM answer: the shape lives under
  // routes[0].geometry.coordinates as GeoJSON [lon, lat] pairs.
  final osrmBody = jsonEncode({
    'code': 'Ok',
    'routes': [
      {
        'distance': 2210.9,
        'duration': 310.5,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [68.222, 27.588],
            [68.2235, 27.578],
            [68.222, 27.568],
          ],
        },
        'legs': [
          {
            'distance': 2210.9,
            'duration': 310.5,
            'steps': [
              {
                'maneuver': {
                  'type': 'depart',
                  'location': [68.222, 27.588],
                  'bearing_after': 180,
                },
                'name': 'VIP Road',
                'distance': 2210.9,
              },
              {
                'maneuver': {
                  'type': 'arrive',
                  'location': [68.222, 27.568],
                },
                'name': 'PTS Road',
                'distance': 0,
              },
            ],
          },
        ],
      },
    ],
    'waypoints': <Object>[],
  });

  group('RouteService.fetchRoute', () {
    test('parses an OSRM route from geometry.coordinates [lon, lat]', () async {
      http.Request? seen;
      final service = RouteService(client: MockClient((request) async {
        seen = request;
        return http.Response(osrmBody, 200);
      }));

      final route = await service.fetchRoute([
        LatLng(27.588, 68.222),
        LatLng(27.568, 68.222),
      ]);

      expect(route, isNotNull);
      expect(route!.source, 'OSRM');
      expect(seen, isNotNull);
      expect(seen!.url.host, 'router.project-osrm.org');
      // Waypoints travel longitude-first, joined by ';' in visit order.
      expect(seen!.url.path, contains('68.222,27.588;68.222,27.568'));
      expect(seen!.headers['User-Agent'], contains('UniversityPointLocator'));

      expect(route.points, hasLength(3));
      expect(route.points[0].latitude, closeTo(27.588, 1e-9));
      expect(route.points[0].longitude, closeTo(68.222, 1e-9));
      expect(route.points[1].latitude, closeTo(27.578, 1e-9));
      expect(route.points[1].longitude, closeTo(68.2235, 1e-9));
      expect(route.points[2].latitude, closeTo(27.568, 1e-9));
      expect(route.points[2].longitude, closeTo(68.222, 1e-9));
      expect(route.steps, hasLength(2));
      expect(route.steps.first.instruction, contains('VIP Road'));
    });

    test('falls back to Valhalla and concatenates every leg shape', () async {
      final valhallaBody = jsonEncode({
        'trip': {
          'legs': [
            {'shape': legA, 'maneuvers': <Object>[]},
            {'shape': legB, 'maneuvers': <Object>[]},
          ],
        },
      });
      final seen = <Uri>[];
      final service = RouteService(client: MockClient((request) async {
        seen.add(request.url);
        if (request.url.host == 'valhalla1.openstreetmap.de') {
          return http.Response(valhallaBody, 200);
        }
        return http.Response('upstream connect error', 500);
      }));

      final route = await service.fetchRoute([
        LatLng(27.588, 68.222),
        LatLng(27.568, 68.222),
      ]);

      // OSRM asked first, Valhalla second - in that order.
      expect(seen, hasLength(2));
      expect(seen[0].host, 'router.project-osrm.org');
      expect(seen[1].host, 'valhalla1.openstreetmap.de');
      expect(seen[1].queryParameters.keys, contains('json'));

      expect(route, isNotNull);
      expect(route!.source, 'Valhalla');
      // legA (3 points) + legB (2 points), appended in leg order.
      expect(route.points, hasLength(5));
      expect(route.points[0].latitude, closeTo(27.588, 1e-9));
      expect(route.points[2].latitude, closeTo(27.568, 1e-9));
      expect(route.points[3].latitude, closeTo(27.568, 1e-9));
      expect(route.points[4].latitude, closeTo(27.561, 1e-9));
      expect(route.points[4].longitude, closeTo(68.221, 1e-9));
      // Legs without maneuvers produce geometry-only guidance.
      expect(route.steps, isEmpty);
    });

    test('discards an OSRM answer whose geometry is an encoded string',
        () async {
      // geometries=polyline mode: route.geometry is a String, not a GeoJSON
      // object - no coordinates list to read, so the OSRM leg must not
      // produce points and Valhalla has to answer instead.
      final seen = <Uri>[];
      final service = RouteService(client: MockClient((request) async {
        seen.add(request.url);
        if (request.url.host == 'valhalla1.openstreetmap.de') {
          return http.Response(
            jsonEncode({
              'trip': {
                'legs': [
                  {'shape': legA, 'maneuvers': <Object>[]},
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {'geometry': '_p~iF~ps|U_ulLnnqC', 'legs': <Object>[]},
            ],
          }),
          200,
        );
      }));

      final route = await service.fetchRoute([
        LatLng(27.588, 68.222),
        LatLng(27.568, 68.222),
      ]);

      expect(seen, hasLength(2));
      expect(route, isNotNull);
      expect(route!.source, 'Valhalla');
      expect(route.points, hasLength(3));
    });

    test('survives a non-JSON body and a rate-limit style reply', () async {
      final service = RouteService(client: MockClient((request) async {
        if (request.url.host == 'router.project-osrm.org') {
          return http.Response('<html>429 Too Many Requests</html>', 200);
        }
        return http.Response('Bad Gateway', 502);
      }));

      expect(
        await service.fetchRoute([LatLng(1, 2), LatLng(3, 4)]),
        isNull,
      );
    });

    test('returns null when every router fails with HTTP errors', () async {
      final hosts = <String>[];
      final service = RouteService(client: MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response('not found', 404);
      }));

      expect(
        await service.fetchRoute([LatLng(1, 2), LatLng(3, 4)]),
        isNull,
      );
      expect(hosts, [
        'router.project-osrm.org',
        'valhalla1.openstreetmap.de',
      ]);
    });

    test('returns null when the transport itself fails', () async {
      final service = RouteService(client: MockClient((request) async {
        throw http.ClientException('connection reset');
      }));

      expect(
        await service.fetchRoute([LatLng(1, 2), LatLng(3, 4)]),
        isNull,
      );
    });

    test('rejects a Valhalla leg that decodes to fewer than two points',
        () async {
      final service = RouteService(client: MockClient((request) async {
        if (request.url.host == 'valhalla1.openstreetmap.de') {
          return http.Response(
            jsonEncode({
              'trip': {
                'legs': [
                  {'shape': onePoint, 'maneuvers': <Object>[]},
                ],
              },
            }),
            200,
          );
        }
        return http.Response('upstream error', 503);
      }));

      expect(
        await service.fetchRoute([LatLng(1, 2), LatLng(3, 4)]),
        isNull,
      );
    });

    test('short-circuits below two waypoints without a network call',
        () async {
      final service = RouteService(client: MockClient((request) async {
        fail('no HTTP request expected for <2 waypoints');
      }));

      expect(await service.fetchRoute([LatLng(1, 2)]), isNull);
      expect(await service.fetchRoute(const []), isNull);
    });
  });
}
