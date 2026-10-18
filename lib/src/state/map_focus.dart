import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot "fly the Radar Map to this player / coordinate" request.
///
/// The Discover tab and the Passport schedule both deep-link into the map,
/// which lives in a sibling branch of the shell's [IndexedStack] — so the
/// request travels through this provider instead of an ancestor lookup.
class MapFocusRequest {
  const MapFocusRequest({
    required this.token,
    this.profileId,
    this.lat,
    this.lon,
    this.label,
  });

  /// Monotonic id, so two requests for the same player still fire.
  final int token;

  /// Host whose pitch pin should be selected.
  final String? profileId;
  final double? lat;
  final double? lon;
  final String? label;
}

final mapFocusProvider =
    NotifierProvider<MapFocusController, MapFocusRequest?>(MapFocusController.new);

class MapFocusController extends Notifier<MapFocusRequest?> {
  int _token = 0;

  @override
  MapFocusRequest? build() => null;

  void focusPlayer({
    required String profileId,
    String? label,
    double? lat,
    double? lon,
  }) {
    state = MapFocusRequest(
      token: ++_token,
      profileId: profileId,
      lat: lat,
      lon: lon,
      label: label,
    );
  }

  void focusPoint({
    required double lat,
    required double lon,
    String? label,
  }) {
    state = MapFocusRequest(
      token: ++_token,
      lat: lat,
      lon: lon,
      label: label,
    );
  }

  void clear() => state = null;
}
