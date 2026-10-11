import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:university_point_locator/utils/geo_snapping.dart';

void main() {
  // A ~1 km east-west road line just north of lat 25.4 (Larkana scale).
  // At this latitude one degree of longitude is ~100.5 km, so the line
  // spans 68.3500 -> 68.3600 at a constant latitude.
  final List<LatLng> line = const [
    LatLng(25.4000, 68.3500),
    LatLng(25.4000, 68.3600),
  ];

  test('snaps a nearby fix onto the closest point of the line', () {
    // ~111 m north of the line's midpoint: must land ON the line, due
    // south of itself (same longitude).
    final LatLng off = LatLng(25.4010, 68.3550);
    final LatLng snapped = snapToRoute(off, line, 150);

    expect(snapped.latitude, closeTo(25.4000, 1e-4));
    expect(snapped.longitude, closeTo(68.3550, 1e-4));
  });

  test('leaves a fix that is far from the line untouched', () {
    // ~1.1 km north: beyond any sane snap radius - a real detour or a bad
    // fix must be shown where it actually is, never faked onto the route.
    final LatLng off = LatLng(25.4100, 68.3550);
    final LatLng snapped = snapToRoute(off, line, 50);
    expect(identical(snapped, off), isTrue);
  });

  test('clamps a projection past the end of the line to the endpoint', () {
    // Due east of the last vertex: the closest point on the geometry is
    // the end vertex itself, not the extended line.
    final LatLng beyond = LatLng(25.4000, 68.3650);
    final LatLng snapped = snapToRoute(beyond, line, 6000);
    expect(snapped.latitude, closeTo(25.4000, 1e-6));
    expect(snapped.longitude, closeTo(68.3600, 1e-6));
  });

  test('degenerate geometry never moves the point', () {
    final LatLng p = LatLng(25.4, 68.35);
    expect(identical(snapToRoute(p, const [], 50), p), isTrue);
    expect(
      identical(snapToRoute(p, [LatLng(25.4, 68.35)], 50), p),
      isTrue,
    );
  });

  test('a fix already on the line stays put', () {
    final LatLng on = LatLng(25.4000, 68.3520);
    final LatLng snapped = snapToRoute(on, line, 50);
    expect(snapped.latitude, closeTo(on.latitude, 1e-6));
    expect(snapped.longitude, closeTo(on.longitude, 1e-6));
  });

  test('a non-positive snap radius never moves the point', () {
    final LatLng off = LatLng(25.4001, 68.3550);
    expect(identical(snapToRoute(off, line, 0), off), isTrue);
  });
}
