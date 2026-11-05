// Local control over the home Wi-Fi while the internet is down (contract: docs/platform.md,
// "Local control"; the hub side is backend/local.py, the signing hub/platform/local_sign.py).
// The phone asks the device for a one-time nonce and signs the command with the device's local
// key (HMAC-SHA256); keys come from GET /api/platform/my/local-keys whenever the hub is reachable.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'discover_stub.dart' if (dart.library.io) 'discover_io.dart';
import 'store.dart';

class LocalKey {
  LocalKey(this.deviceId, this.key, this.localAddr, this.port);

  factory LocalKey.fromJson(Map<String, dynamic> j) => LocalKey(
      j['device_id'] as String, j['key'] as String, j['local_addr'] as String?, (j['port'] as int?) ?? 8080);

  final String deviceId;
  final String key;
  final String? localAddr;
  final int port;

  Map<String, dynamic> toJson() =>
      {'device_id': deviceId, 'key': key, 'local_addr': localAddr, 'port': port};
}

/// base64url(HMAC-SHA256(key, lines)) exactly as hub.platform.local_sign.sign.
String localSign(String key, List<String> lines) {
  final raw = base64Url.decode(key + '=' * ((4 - key.length % 4) % 4));
  final mac = Hmac(sha256, raw).convert(utf8.encode(lines.join('\n')));
  return base64Url.encode(mac.bytes).replaceAll('=', '');
}

/// Only addresses inside the house: a device can never send the phone to the internet.
/// (Parsed here, without dart:io, so the web build compiles too.)
bool privateHost(String host) {
  final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (h.endsWith('.local')) return true;
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (v4 != null) {
    final b = [for (var i = 1; i <= 4; i++) int.parse(v4[i]!)];
    if (b.any((x) => x > 255)) return false;
    return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254);
  }
  if (!h.contains(':')) return false;                       // a name: not inside the house
  return RegExp(r'^f[cd][0-9a-f]{0,2}:').hasMatch(h) ||     // fc00::/7
      RegExp(r'^fe[89ab][0-9a-f]?:').hasMatch(h);           // fe80::/10
}

class LocalControl {
  LocalControl(this.store);

  final Store store;
  final Map<String, String> _found = {};       // device_id -> host:port (mDNS, this run)
  bool _searched = false;

  Future<List<LocalKey>> keys() async {
    final raw = await store.secret('local.keys');
    if (raw == null) return [];
    return (json.decode(raw) as List).map((e) => LocalKey.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveKeys(List<dynamic> devices) =>
      store.setSecret('local.keys', json.encode(devices));

  Future<LocalKey?> keyOf(String deviceId) async {
    for (final k in await keys()) {
      if (k.deviceId == deviceId) return k;
    }
    return null;
  }

  Future<void> _discover() async {
    if (_searched) return;
    _searched = true;
    _found.addAll(await discoverDevices(privateHost));
  }

  Future<String?> _address(LocalKey k) async {
    await _discover();
    final found = _found[k.deviceId];
    if (found != null) return found;
    final addr = k.localAddr;
    return addr != null && privateHost(addr) ? '$addr:${k.port}' : null;
  }

  Future<Map<String, dynamic>?> _signed(LocalKey k, String path, Map<String, dynamic> fields,
      List<String> tail) async {
    final addr = await _address(k);
    if (addr == null) return null;
    // plain HTTP inside the house only (privateHost checked above)
    final base = Uri.parse('http://$addr');
    try {
      final n = await http.get(base.replace(path: '/local/v1/nonce')).timeout(const Duration(seconds: 3));
      final nonce = (json.decode(n.body) as Map<String, dynamic>)['nonce'] as String?;
      if (n.statusCode != 200 || nonce == null) return null;
      final sig = localSign(k.key, [k.deviceId, nonce, ...tail]);
      final r = await http
          .post(base.replace(path: path),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'nonce': nonce, 'sig': sig, ...fields}))
          .timeout(const Duration(seconds: 4));
      return json.decode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// A write over the Wi-Fi; the answer looks like POST /api/control/write's.
  Future<Map<String, dynamic>> write(String deviceId, String tag, Object? value) async {
    final k = await keyOf(deviceId);
    if (k == null) return {'result': 'rejected_offline', 'local': true};
    final valueJson = json.encode(value);
    final r = await _signed(k, '/local/v1/command', {'tag': tag, 'value_json': valueJson},
        ['command', tag, valueJson]);
    if (r != null && r['ok'] == true) return {'result': 'applied', 'value': r['value'], 'local': true};
    return {'result': r == null ? 'rejected_offline' : 'failed', 'local': true, 'message': r?['error']};
  }

  /// The values the devices have now, read over the Wi-Fi.
  Future<Map<String, Map<String, dynamic>>> states() async {
    final out = <String, Map<String, dynamic>>{};
    for (final k in await keys()) {
      final r = await _signed(k, '/local/v1/state', {}, ['state']);
      if (r != null && r['values'] is Map) out[k.deviceId] = Map<String, dynamic>.from(r['values'] as Map);
    }
    return out;
  }
}
