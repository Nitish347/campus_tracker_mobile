import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_arrows.dart' show distanceMeters;

/// Where the drawn trip begins and where it stops.
typedef RouteEndpoints = ({LatLng start, LatLng stop});

/// Null when the bus has barely moved, where the two pins would sit on top of
/// each other and say nothing.
RouteEndpoints? routeEndpoints(List<LatLng> trail) {
  if (trail.length < 2) return null;
  final start = trail.first;
  final stop = trail.last;
  if (distanceMeters(start, stop) < 30) return null;
  return (start: start, stop: stop);
}

/// A green circle with a play triangle: where the trip began.
final Future<BitmapDescriptor> routeStartIcon = _drawPin(
  const Color(0xff15966d),
  (canvas, size, paint) => canvas.drawPath(
    Path()
      ..moveTo(size * 0.40, size * 0.30)
      ..lineTo(size * 0.72, size * 0.50)
      ..lineTo(size * 0.40, size * 0.70)
      ..close(),
    paint,
  ),
);

/// A red circle with a square: where the trip stopped.
final Future<BitmapDescriptor> routeStopIcon = _drawPin(
  const Color(0xffd32f2f),
  (canvas, size, paint) => canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(size * 0.32, size * 0.32, size * 0.36, size * 0.36),
      Radius.circular(size * 0.04),
    ),
    paint,
  ),
);

Future<BitmapDescriptor> _drawPin(
  Color color,
  void Function(Canvas canvas, double size, Paint paint) glyph,
) async {
  const size = 72.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const centre = Offset(size / 2, size / 2);
  canvas
    // White ring so the pin stays visible on top of the route line.
    ..drawCircle(centre, size / 2 - 2, Paint()..color = Colors.white)
    ..drawCircle(centre, size / 2 - 9, Paint()..color = color);
  glyph(canvas, size, Paint()..color = Colors.white);
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    png!.buffer.asUint8List(),
    width: 26,
    height: 26,
  );
}
