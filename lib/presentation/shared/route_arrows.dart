import 'dart:math' show asin, atan2, cos, pi, sin, sqrt;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Where a direction arrow sits on a travelled route, and which way it points
/// in degrees clockwise from north -- what [Marker.rotation] expects.
typedef RouteArrow = ({LatLng at, double bearing});

/// Stretches shorter than this are a parked bus's GPS jitter, not travel, and
/// would point an arrow somewhere random.
const _minSegmentMeters = 15.0;

/// One arrow per roughly [spacingMeters] of track, placed mid-way along the
/// segment that completes each stretch and pointing the way the bus drove it.
/// The first real segment always gets one, so even a short trip shows its
/// direction.
List<RouteArrow> directionArrows(
  List<LatLng> trail, {
  double spacingMeters = 400,
}) {
  final arrows = <RouteArrow>[];
  var travelled = spacingMeters;
  for (var i = 1; i < trail.length; i++) {
    final from = trail[i - 1];
    final to = trail[i];
    final length = distanceMeters(from, to);
    travelled += length;
    if (travelled < spacingMeters || length < _minSegmentMeters) continue;
    travelled = 0;
    arrows.add((
      at: LatLng(
        (from.latitude + to.latitude) / 2,
        (from.longitude + to.longitude) / 2,
      ),
      bearing: bearingDegrees(from, to),
    ));
  }
  return arrows;
}

/// Initial bearing from [from] to [to], degrees clockwise from north (0-360).
double bearingDegrees(LatLng from, LatLng to) {
  final lat1 = _radians(from.latitude);
  final lat2 = _radians(to.latitude);
  final dLng = _radians(to.longitude - from.longitude);
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

/// Great-circle distance in metres (haversine).
double distanceMeters(LatLng from, LatLng to) {
  const earthRadiusMeters = 6371000.0;
  final lat1 = _radians(from.latitude);
  final lat2 = _radians(to.latitude);
  final dLat = lat2 - lat1;
  final dLng = _radians(to.longitude - from.longitude);
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * earthRadiusMeters * asin(sqrt(h));
}

double _radians(double degrees) => degrees * pi / 180;

/// The arrow drawn along a travelled route. It points north, so
/// [Marker.rotation] turns it to the bearing. Drawn once and shared: the map
/// tab is rebuilt from scratch every time it is opened.
final Future<BitmapDescriptor> routeArrowIcon = _drawRouteArrow();

Future<BitmapDescriptor> _drawRouteArrow() async {
  const size = 64.0;
  final recorder = ui.PictureRecorder();
  final arrow = Path()
    ..moveTo(size / 2, 6)
    ..lineTo(size - 10, size - 8)
    ..lineTo(size / 2, size - 22)
    ..lineTo(10, size - 8)
    ..close();
  Canvas(recorder)
    // White outline so the arrow stays visible on top of the route line.
    ..drawPath(
      arrow,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeJoin = StrokeJoin.round,
    )
    // Red, the same as the arrows on the admin web's route history.
    ..drawPath(arrow, Paint()..color = const Color(0xffd32f2f));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    png!.buffer.asUint8List(),
    width: 18,
    height: 18,
  );
}
