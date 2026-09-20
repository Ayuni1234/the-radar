/// Decouples the data layer from the sync service: the repository cannot
/// import Riverpod providers, so it reports failed writes through this
/// bridge and the sync provider subscribes at composition time.
class SyncBridge {
  SyncBridge._();
  static final SyncBridge instance = SyncBridge._();

  final List<void Function(String kind, String label, String? error)>
      _listeners = [];

  void addListener(
      void Function(String kind, String label, String? error) listener) {
    _listeners.add(listener);
  }

  void onWriteFailed(String kind, String label, String? error) {
    for (final l in _listeners) {
      l(kind, label, error);
    }
  }
}
