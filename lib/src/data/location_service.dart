import 'package:geolocator/geolocator.dart';

/// User-facing GPS failure reason.
class LocationException implements Exception {
  LocationException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// One-shot device GPS fix for the post-composer quick actions.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Returns the device's present coordinates, requesting permission when
  /// needed. Throws [LocationException] with a user-facing reason otherwise.
  Future<({double lat, double lon})> getCurrent() async {
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
    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      throw LocationException(
          'Could not get a GPS fix in time — try again outdoors or move to '
          'open sky.');
    }
    return (lat: pos.latitude, lon: pos.longitude);
  }
}
