// The hub's REST API, as the web app uses it (app/js/core.js): bearer access token, rotating
// refresh token, errors {"error": code, "message"}. Without network the last answers of the
// server are shown, and writes go to the devices over the home Wi-Fi (local.dart).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local.dart';
import 'store.dart';

class ApiError implements Exception {
  ApiError(this.status, this.code, this.message);

  final int status;          // 0 = no network
  final String code;
  final String message;

  @override
  String toString() => message;
}

class Api {
  Api(this.store) : local = LocalControl(store);

  final Store store;
  final LocalControl local;
  final ValueNotifier<bool> offline = ValueNotifier(false);   // working from the phone's copy
  String? _access;
  bool mustChangePassword = false;           // the last sign-in asked for a new password

  static const _cached = ['/api/auth/me', '/api/account/organizations', '/api/platform/my/'];

  /// The hub address the user entered ("https://hub.example/app/" or the bare host); a maker's
  /// link may carry ?brand=<maker org> (the start page shows that maker, as the web app).
  String get server => store.get('server') ?? '';

  Future<void> setServer(String url) async {
    final brand = Uri.tryParse(url.trim())?.queryParameters['brand'];
    if (brand != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(brand)) await store.set('brand', brand);
    var u = url.trim().split('#').first.split('?').first;
    if (u.endsWith('/app/') || u.endsWith('/app')) u = u.substring(0, u.lastIndexOf('/app'));
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    await store.set('server', u);
  }

  /// HTTPS, or plain HTTP to a hub on a private address (a test server in the house).
  static bool allowedServer(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty) return false;
    final testing = u.host == 'localhost' || u.host == '127.0.0.1';   // a hub on this computer
    return u.scheme == 'https' || (u.scheme == 'http' && (privateHost(u.host) || testing));
  }

  Future<bool> get signedIn async => _access != null || await store.secret('refresh') != null;

  /// A valid access token for the live stream (refreshed when needed); null when signed out.
  Future<String?> accessToken({bool renew = false}) async {
    if (renew || _access == null) {
      try {
        if (!await _refresh()) return null;
      } on ApiError {
        return null;
      }
    }
    return _access;
  }

  /// Sign in; returns an MFA token when the account asks for a second step (then [verifyMfa]).
  Future<String?> login(String user, String password, {bool remember = true}) async {
    // remember: the phone keeps the session for months (HUB_REMEMBER_DAYS) - it is the person's own
    final r = await _send('POST', '/api/auth/login',
        {'username': user, 'password': password, 'remember': remember}, auth: false) as Map<String, dynamic>;
    if (r['mfa_required'] == true) return r['mfa_token'] as String;
    await _keep(r);
    return null;
  }

  /// The second step: the 6-digit code of the authenticator app (or a recovery code).
  Future<void> verifyMfa(String mfaToken, String code, {bool remember = true}) async {
    await _keep(await _send('POST', '/api/auth/mfa/verify',
        {'mfa_token': mfaToken, 'code': code, 'remember': remember}, auth: false) as Map<String, dynamic>);
  }

  /// Sign-in with a mobile number: the SMS code asked earlier (POST /api/account/phone/code).
  Future<void> verifyPhone(String phone, String code) async {
    await _keep(await _send('POST', '/api/account/phone/verify',
        {'phone': phone, 'code': code, 'remember': true}, auth: false) as Map<String, dynamic>);
  }

  /// Account requests that need no sign-in (sign-up, forgotten password, e-mail links).
  Future<dynamic> public(String method, String path, Object? body) => _send(method, path, body, auth: false);

  /// A picture (a product's image, a maker's logo); null when there is none or no network.
  Future<Uint8List?> bytes(String path, {bool auth = true}) async {
    if (server.isEmpty) return null;
    try {
      if (auth && _access == null && !await _refresh()) return null;
      final r = await http.get(Uri.parse('$server$path'),
          headers: {if (auth && _access != null) 'Authorization': 'Bearer $_access'}).timeout(const Duration(seconds: 12));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    final refresh = await store.secret('refresh');
    try {
      if (refresh != null) await _send('POST', '/api/auth/logout', {'refresh_token': refresh}, auth: false);
    } catch (_) {}
    _access = null;
    await store.setSecret('refresh', null);
    await store.setSecret('local.keys', null);
  }

  Future<void> _keep(Map<String, dynamic> tokens) async {
    _access = tokens['access_token'] as String?;
    mustChangePassword = tokens['must_change_password'] == true;
    await store.setSecret('refresh', tokens['refresh_token'] as String?);
  }

  Future<bool>? _refreshing;

  /// One refresh at a time: the refresh token rotates, so a second request with the same token
  /// (the home page, the live stream and the alerts all ask when the access token ends) would
  /// look like a stolen token and the server would end every session of the account.
  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final token = await store.secret('refresh');
    if (token == null) return false;
    try {
      await _keep(await _send('POST', '/api/auth/refresh', {'refresh_token': token}, auth: false)
          as Map<String, dynamic>);
      return true;
    } on ApiError catch (e) {
      // only a refusal of the token itself ends the session; no network, a busy or failing
      // server (429, 5xx) or a switch between Wi-Fi and mobile data must never sign the user out
      if (e.status != 401 && e.status != 403) rethrow;
      _access = null;
      await store.setSecret('refresh', null);
      return false;
    }
  }

  /// A request; without network the phone's copy (GET) or the device itself (writes).
  Future<dynamic> call(String method, String path, [Object? body]) async {
    try {
      if (_access == null && !await _refresh()) throw ApiError(401, 'not_authenticated', 'sign in');
      dynamic data;
      try {
        data = await _send(method, path, body);
      } on ApiError catch (e) {
        if (e.status != 401 || !await _refresh()) rethrow;
        data = await _send(method, path, body);
      }
      offline.value = false;
      if (method == 'GET' && _cached.any(path.startsWith)) {
        await store.set('cache:$path', json.encode(data));
      }
      return data;
    } on ApiError catch (e) {
      if (e.status != 0) rethrow;
      final answer = await _offline(method, path, body);
      if (answer == null) rethrow;
      offline.value = true;
      return answer;
    }
  }

  Future<dynamic> _offline(String method, String path, Object? body) async {
    if (method == 'POST' && path == '/api/control/write' && body is Map) {
      final m = RegExp(r'^platform\.devices\.([^.]+)\.([^.]+)$').firstMatch('${body['tag']}');
      if (m == null) return null;
      return local.write(m[1]!, m[2]!, body['value']);
    }
    if (method != 'GET') return null;
    final kept = store.get('cache:$path');
    if (kept == null) return null;
    final data = json.decode(kept);
    if (path.startsWith('/api/platform/my/views') && data is List) {
      final now = await local.states();            // what the devices say over the Wi-Fi
      for (final v in data) {
        final values = now[v['device']['device_id']];
        if (values == null) continue;
        v['device']['state'] = 'online';
        for (final t in v['tags'] as List) {
          if (values.containsKey(t['key'])) t['value'] = values[t['key']];
        }
      }
    }
    return data;
  }

  /// The local keys while the hub is reachable (owners and operators without limits).
  Future<void> refreshLocalKeys() async {
    try {
      final r = await call('GET', '/api/platform/my/local-keys') as Map<String, dynamic>;
      await local.saveKeys(r['devices'] as List);
    } catch (_) {}
  }

  Future<dynamic> _send(String method, String path, Object? body, {bool auth = true}) async {
    if (server.isEmpty) throw ApiError(0, 'no_server', 'no server address');
    final uri = Uri.parse('$server$path');
    final headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (auth && _access != null) headers['Authorization'] = 'Bearer $_access';
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = json.encode(body);
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 12)));
    } on TimeoutException {
      throw ApiError(0, 'network', 'network');
    } on http.ClientException {               // no network (also a SocketException inside)
      throw ApiError(0, 'network', 'network');
    } catch (e) {
      if ('$e'.contains('SocketException') || '$e'.contains('HandshakeException')) {
        throw ApiError(0, 'network', 'network');
      }
      rethrow;
    }
    if (r.statusCode == 204) return null;
    final text = utf8.decode(r.bodyBytes);
    final data = text.isEmpty ? null : json.decode(text);
    if (r.statusCode >= 400) {
      final m = data is Map ? data : const {};
      throw ApiError(r.statusCode, '${m['error'] ?? 'http_${r.statusCode}'}', '${m['message'] ?? r.statusCode}');
    }
    return data;
  }
}
