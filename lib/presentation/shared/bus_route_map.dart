import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_arrows.dart';

/// Map for following one bus: the route it has travelled, with red direction
/// arrows, and a camera that tracks it until the user moves the map.
///
/// Shared by the driver's Map tab and the parent's Track tab so both behave
/// the same way.
class BusRouteMap extends StatefulWidget {
  const BusRouteMap({
    super.key,
    required this.focus,
    required this.markers,
    this.trail = const [],
    this.subject,
    this.height = 360,
    this.zoom = 14,
  });

  /// Where the camera goes: the bus being followed.
  final LatLng focus;

  /// Bus and landmark pins. The direction arrows are added alongside them.
  final Set<Marker> markers;

  /// Where the bus has been, oldest first.
  final List<LatLng> trail;

  /// What is being followed, e.g. the selected child. Changing it re-centres
  /// the camera even if the user had panned away.
  final Object? subject;

  final double height;
  final double zoom;

  @override
  State<BusRouteMap> createState() => _BusRouteMapState();
}

class _BusRouteMapState extends State<BusRouteMap> {
  GoogleMapController? _map;
  BitmapDescriptor? _arrow;

  // The camera follows the bus until the user pans or zooms the map
  // themselves; the button on the map brings it back. Without this, every
  // poll would yank the camera away from wherever they were looking.
  bool _followBus = true;
  // True while the camera moves because *we* moved it, so that move is not
  // mistaken for the user's. Starts true to ignore the map's own settling
  // when it first loads.
  bool _movingCamera = true;

  @override
  void initState() {
    super.initState();
    routeArrowIcon.then((icon) {
      if (mounted) setState(() => _arrow = icon);
    });
  }

  @override
  void didUpdateWidget(BusRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject) _followBus = true;
    // initialCameraPosition is only read when the map is created, so a newer
    // position (refresh, poll) would otherwise move the marker while the
    // camera stayed put -- leaving the bus off-screen.
    if (oldWidget.focus != widget.focus && _followBus) {
      _moveCamera(widget.focus);
    }
  }

  void _moveCamera(LatLng target) {
    final map = _map;
    if (map == null) return;
    _movingCamera = true;
    map.animateCamera(CameraUpdate.newLatLng(target));
  }

  @override
  Widget build(BuildContext context) {
    final arrow = _arrow;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GoogleMap(
              // Without this the surrounding ListView and pull-to-refresh
              // claim every drag, so the map could not be panned or zoomed.
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
              onMapCreated: (controller) => _map = controller,
              onCameraMoveStarted: () {
                if (!_movingCamera) _followBus = false;
              },
              onCameraIdle: () => _movingCamera = false,
              initialCameraPosition: CameraPosition(
                target: widget.focus,
                zoom: widget.zoom,
              ),
              markers: {
                ...widget.markers,
                if (arrow != null)
                  for (final (index, step)
                      in directionArrows(widget.trail).indexed)
                    Marker(
                      markerId: MarkerId('route-arrow-$index'),
                      position: step.at,
                      // Flat markers turn with the map, so each arrow keeps
                      // pointing along the road it was drawn on.
                      flat: true,
                      rotation: step.bearing,
                      anchor: const Offset(0.5, 0.5),
                      icon: arrow,
                      consumeTapEvents: true,
                    ),
              },
              polylines: {
                // Where the bus has actually been, from the positions the
                // backend stored -- not a guessed route.
                if (widget.trail.length > 1)
                  Polyline(
                    polylineId: const PolylineId('route-travelled'),
                    points: widget.trail,
                    color: const Color(0xff0f6b55),
                    width: 5,
                    jointType: JointType.round,
                  ),
              },
              mapToolbarEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: 'Centre on bus',
                backgroundColor: Colors.white,
                onPressed: () {
                  _followBus = true;
                  _moveCamera(widget.focus);
                },
                child: const Icon(
                  Icons.my_location,
                  color: Color(0xff0f6b55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
