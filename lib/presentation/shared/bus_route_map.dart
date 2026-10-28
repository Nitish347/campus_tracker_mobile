import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/maps_config.dart';
import 'route_arrows.dart';
import 'route_endpoints.dart';

/// Map for following one bus: the route it has travelled, with red direction
/// arrows and start/stop pins, and a camera that tracks it until the user
/// moves the map.
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
    this.loading = false,
    this.glowing = false,
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

  /// Covers the map with a loader while a newly selected bus's route loads, so
  /// the previous bus's map is never shown under the new bus's name.
  final bool loading;

  /// Pulses a glow around the bus, for a bus that is running.
  final bool glowing;

  final double height;
  final double zoom;

  @override
  State<BusRouteMap> createState() => _BusRouteMapState();
}

class _BusRouteMapState extends State<BusRouteMap> {
  GoogleMapController? _map;
  BitmapDescriptor? _arrow;
  BitmapDescriptor? _startPin;
  BitmapDescriptor? _stopPin;

  // The pulse is drawn as two circles that grow and fade, half a cycle apart.
  // Stepped by a timer rather than every frame: each step updates a native map
  // overlay, and ten a second reads as smooth without the cost.
  static const _pulseStep = Duration(milliseconds: 100);
  static const _pulsePerStep = 0.055;
  Timer? _pulseTimer;
  double _pulse = 0;
  double _zoomLevel = 14;

  // The camera follows the bus until the user pans or zooms the map
  // themselves; the button on the map brings it back. Without this, every
  // poll would yank the camera away from wherever they were looking.
  bool _followBus = true;
  // True while the camera moves because *we* moved it, so that move is not
  // mistaken for the user's. Starts true to ignore the map's own settling
  // when it first loads.
  bool _movingCamera = true;

  late final Future<bool> _mapsAvailable = MapsConfig.hasApiKey();

  @override
  void initState() {
    super.initState();
    _zoomLevel = widget.zoom;
    routeArrowIcon.then((icon) {
      if (mounted) setState(() => _arrow = icon);
    });
    routeStartIcon.then((icon) {
      if (mounted) setState(() => _startPin = icon);
    });
    routeStopIcon.then((icon) {
      if (mounted) setState(() => _stopPin = icon);
    });
    _syncPulse();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  // Runs only while there is a running bus to show: a timer left ticking would
  // keep rebuilding the map for nothing.
  void _syncPulse() {
    final shouldPulse = widget.glowing && !widget.loading;
    if (shouldPulse && _pulseTimer == null) {
      _pulseTimer = Timer.periodic(_pulseStep, (_) {
        if (!mounted) return;
        setState(() => _pulse = (_pulse + _pulsePerStep) % 1);
      });
    } else if (!shouldPulse && _pulseTimer != null) {
      _pulseTimer!.cancel();
      _pulseTimer = null;
    }
  }

  // Circles are sized in metres, so a fixed on-screen size needs the metres a
  // screen point covers at the current zoom and latitude.
  Set<Circle> _glowCircles() {
    if (!widget.glowing) return const {};
    final metresPerPoint =
        156543.03392 *
        math.cos(widget.focus.latitude * math.pi / 180) /
        math.pow(2, _zoomLevel);
    return {
      for (final (index, offset) in const [0.0, 0.5].indexed)
        () {
          final t = (_pulse + offset) % 1;
          return Circle(
            circleId: CircleId('bus-glow-$index'),
            center: widget.focus,
            radius: (10 + 34 * t) * metresPerPoint,
            fillColor: const Color(0xff34d399).withValues(alpha: 0.38 * (1 - t)),
            strokeWidth: 0,
          );
        }(),
    };
  }

  @override
  void didUpdateWidget(BusRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
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
    return FutureBuilder<bool>(
      future: _mapsAvailable,
      builder: (context, snapshot) {
        // While _mapsAvailable is still pending, snapshot.data is null --
        // not false -- so this must wait for `done` rather than only
        // special-casing the false result. Building the real map on that
        // first, pre-resolution frame is exactly what still crashed iOS.
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(height: widget.height);
        }
        if (snapshot.data == false) return _MapUnavailable(height: widget.height);
        return _buildMap(context);
      },
    );
  }

  Widget _buildMap(BuildContext context) {
    final arrow = _arrow;
    final endpoints = routeEndpoints(widget.trail);
    final startPin = _startPin;
    final stopPin = _stopPin;
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
              // Read by the next pulse step, so no rebuild is needed here.
              onCameraMove: (position) => _zoomLevel = position.zoom,
              onCameraIdle: () => _movingCamera = false,
              initialCameraPosition: CameraPosition(
                target: widget.focus,
                zoom: widget.zoom,
              ),
              circles: _glowCircles(),
              markers: {
                ...widget.markers,
                if (endpoints != null && startPin != null)
                  Marker(
                    markerId: const MarkerId('route-start'),
                    position: endpoints.start,
                    icon: startPin,
                    anchor: const Offset(0.5, 0.5),
                    infoWindow: const InfoWindow(title: 'Start of route'),
                  ),
                if (endpoints != null && stopPin != null)
                  Marker(
                    markerId: const MarkerId('route-stop'),
                    position: endpoints.stop,
                    icon: stopPin,
                    anchor: const Offset(0.5, 0.5),
                    infoWindow: const InfoWindow(title: 'Stop'),
                  ),
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
            if (widget.loading) const _MapLoading(),
          ],
        ),
      ),
    );
  }
}

/// Opaque, so nothing of the previous bus's map shows through while loading.
class _MapLoading extends StatelessWidget {
  const _MapLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffeef2f2),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xff0f6b55),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Loading route...',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xff4b5a6b),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of GoogleMap when the platform has no working Maps key --
/// currently only reachable on iOS (see MapsConfig), since Android renders a
/// watermarked map rather than failing outright.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        color: const Color(0xffdff4ec),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.map_outlined, size: 32, color: Color(0xff0f6b55)),
            SizedBox(height: 8),
            Text(
              'Live map unavailable',
              style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xff172033)),
            ),
            SizedBox(height: 4),
            Text(
              'Maps isn\'t configured on this device yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff5b6b66), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
