import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:campus_tracker_mobile/presentation/shared/route_arrows.dart';

void main() {
  const start = LatLng(26.9124, 75.7873);

  test('bearing is measured clockwise from north', () {
    expect(bearingDegrees(start, const LatLng(26.9224, 75.7873)), closeTo(0, 0.5));
    expect(bearingDegrees(start, const LatLng(26.9124, 75.7973)), closeTo(90, 0.5));
    expect(bearingDegrees(start, const LatLng(26.9024, 75.7873)), closeTo(180, 0.5));
    expect(bearingDegrees(start, const LatLng(26.9124, 75.7773)), closeTo(270, 0.5));
  });

  test('arrows point the way the bus drove, one per stretch', () {
    // Due east in ~500 m hops: three segments, each longer than the spacing.
    final trail = [
      for (var i = 0; i < 4; i++)
        LatLng(start.latitude, start.longitude + i * 0.005),
    ];
    final arrows = directionArrows(trail);
    expect(arrows, hasLength(3));
    for (final arrow in arrows) {
      expect(arrow.bearing, closeTo(90, 1));
    }
  });

  test('a parked bus gets no arrows from its GPS jitter', () {
    final trail = [start, const LatLng(26.91241, 75.78731), start];
    expect(directionArrows(trail), isEmpty);
  });
}
