// Security alerts of the home (the web app's alerts.js): a hallway PIR, a door magnet or a smoke
// detector tripped. The open ones, fetched again when the live stream says one changed; a new
// trip is announced once (the shell shows it and the phone vibrates).

import 'package:flutter/foundation.dart';

import 'api.dart';

class Alerts extends ChangeNotifier {
  Alerts(this.api);

  final Api api;
  List<Map<String, dynamic>> list = [];
  String query = '';

  /// The alert that just tripped (open, not seen): the shell tells the person, then clears it.
  final tripped = ValueNotifier<Map<String, dynamic>?>(null);

  List<Map<String, dynamic>> get unseen => list.where((a) => a['seen_at'] == null).toList();

  Map<String, dynamic>? of(String deviceId, String key) =>
      list.where((a) => a['device_id'] == deviceId && a['tag_key'] == key).firstOrNull;

  Future<void> load() async {
    try {
      final r = await api.call('GET', '/api/platform/my/alerts$query');
      if (r is! List) return;                     // an older hub without alerts
      list = r.cast<Map<String, dynamic>>();
      notifyListeners();
    } on ApiError {
      // offline: keep what is shown
    }
  }

  /// An ``alert`` event of the stream.
  Future<void> event(dynamic data) async {
    if (data is! Map) return;
    final before = list.where((a) => a['alert_id'] == data['alert_id']).firstOrNull;
    await load();
    final fresh = data['cleared_at'] == null && data['seen_at'] == null &&
        (before == null || before['trips'] != data['trips']);
    if (fresh) tripped.value = list.where((a) => a['alert_id'] == data['alert_id']).firstOrNull;
  }

  Future<void> _post(String path) async {
    await api.call('POST', path);
    await load();
  }

  Future<void> seen(int id) => _post('/api/platform/my/alerts/$id/seen');
  /// Cleared: off the list at once (a swiped card must leave now), then on the hub.
  Future<void> clear(int id) {
    list = list.where((a) => a['alert_id'] != id).toList();
    notifyListeners();
    return _post('/api/platform/my/alerts/$id/clear');
  }
  Future<void> seenAll() => _post('/api/platform/my/alerts/seen$query');
  Future<void> clearAll() => _post('/api/platform/my/alerts/clear$query');

  void reset() {
    list = [];
    notifyListeners();
  }
}
