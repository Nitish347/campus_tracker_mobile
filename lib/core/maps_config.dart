import 'dart:io';

import 'package:flutter/services.dart';

import 'api_log.dart';

/// Whether the platform has a live Google Maps key.
///
/// Android silently degrades to a watermarked map without a key, so it's
/// never in question there. iOS hard-crashes the moment a GoogleMap view is
/// created without one (see ios/Runner/AppDelegate.swift), so callers must
/// check this first and render a fallback instead when it's false.
class MapsConfig {
  MapsConfig._();

  static const _channel = MethodChannel('com.adimove.app/config');
  static bool? _cached;

  static Future<bool> hasApiKey() async {
    if (!Platform.isIOS) return true;
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final result = await _channel.invokeMethod<bool>('hasMapsApiKey');
      apiLog('[maps] hasMapsApiKey -> $result');
      return _cached = result ?? false;
    } catch (error) {
      apiLog('[maps] hasMapsApiKey check failed: $error');
      return _cached = false;
    }
  }
}
