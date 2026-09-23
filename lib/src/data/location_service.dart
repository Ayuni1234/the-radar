import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// User-facing GPS failure reason.
class LocationException implements Exception {
  const LocationException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// One-shot device GPS fix for the post-composer quick actions.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Stage 1: generous high-accuracy window — phones under a roof or tree
  /// canopy often need this long before the first precise fix arrives.
  static const _highAccuracyTimeout = Duration(seconds: 25);

  /// Stage 2: low-accuracy retry (cell/wifi triangulation) — needs no sky
  /// view, answers fast, and is plenty precise for a feed post pin.
  static const _lowAccuracyTimeout = Duration(seconds: 15);

  /// Test seam: when set, replaces the real GPS pipeline in widget tests
  /// (throw [LocationException] from it to exercise the fallbacks).
  @visibleForTesting
  static Future<({double lat, double lon})> Function()? overrideForTesting;

  /// Returns the device's present coordinates, requesting permission when
  /// needed. Throws [LocationException] with a user-facing reason otherwise.
  Future<({double lat, double lon})> getCurrent() async {
    final override = overrideForTesting;
    if (override != null) return override();

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException(
          'Location services are off — enable GPS and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
          'Location permission is permanently denied — enable it in device '
          'settings to pin your spot.');
    }

    // Stage 1 — high accuracy, generous deadline.
    var pos = await _attempt(
      const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: _highAccuracyTimeout,
      ),
    );
    // Stage 2 — low-accuracy fallback: often succeeds where the sky is
    // blocked, and a coarse fix still beats no pin at all.
    pos ??= await _attempt(
      const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: _lowAccuracyTimeout,
      ),
    );
    if (pos == null) {
      throw LocationException(
          'Could not get a GPS fix in time — try again outdoors or move to '
          'open sky.');
    }
    return (lat: pos.latitude, lon: pos.longitude);
  }

  /// One GPS attempt; null when it times out or errors (caller retries with
  /// different settings or gives up with the user-facing message).
  Future<Position?> _attempt(LocationSettings settings) async {
    try {
      return await Geolocator.getCurrentPosition(locationSettings: settings);
    } catch (_) {
      return null;
    }
  }
}
