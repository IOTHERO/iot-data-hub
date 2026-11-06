// Arriving home / leaving, as the web app's checkPresence (more.js): while the app is open, the
// phone's place is compared with the home's (settings: latitude, longitude, radius_m) and a
// change is reported once (POST .../presence), which runs the home's presence automations.

import 'package:geolocator/geolocator.dart';

import 'api.dart';
import 'store.dart';

/// Inside the home's circle? (null: the home has no place)
bool? insideHome(Map<String, dynamic> settings, double lat, double lon) {
  final hLat = settings['latitude'];
  final hLon = settings['longitude'];
  if (hLat is! num || hLon is! num) return null;
  final radius = (settings['radius_m'] as num?) ?? 150;
  return Geolocator.distanceBetween(hLat.toDouble(), hLon.toDouble(), lat, lon) <= radius;
}

Future<void> checkPresence(Api api, Store store, String? orgId) async {
  if (orgId == null || store.get('presence') == 'off') return;
  try {
    final settings = await api.call('GET', '/api/platform/organizations/$orgId/settings') as Map<String, dynamic>;
    if (settings['latitude'] == null || settings['longitude'] == null) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)));
    final inside = insideHome(settings, pos.latitude, pos.longitude);
    if (inside == null) return;
    final key = 'presence.$orgId';
    final before = store.get(key);
    final now = inside ? 'in' : 'out';
    if (before != null && before != now) {
      await api.call('POST', '/api/platform/organizations/$orgId/presence', {'event': inside ? 'arrive' : 'leave'});
    }
    await store.set(key, now);
  } catch (_) {
    // no permission, no fix or offline: nothing to report
  }
}
