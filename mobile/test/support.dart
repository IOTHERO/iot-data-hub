// A mock hub for the widget tests: answers by "METHOD path" and keeps every request.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titiswitch/core/app_state.dart';

const org = 'o1';
final views = [
  {
    'device': {'device_id': 'd1', 'name': 'Kitchen'},
    'tags': [
      {'key': 'relay_1', 'kind': 'digital_output', 'display_name': {'en': 'Hood'}, 'writable': true},
      {'key': 'temp', 'kind': 'analog_input', 'display_name': {'en': 'Temperature'}},
    ],
  },
];

/// A mock hub: answers by "METHOD path", keeps every request.
class Hub {
  Hub([this.extra = const {}]);

  /// More answers, by "METHOD path" (a test's own); a function is called for each request.
  final Map<String, Object?> extra;
  final sent = <(String, String, Object?)>[];

  late final client = MockClient((r) async {
    final body = r.body.isEmpty ? null : json.decode(r.body);
    sent.add((r.method, r.url.path, body));
    final key = '${r.method} ${r.url.path}';
    if (extra.containsKey(key)) {
      var a = extra[key];
      if (a is Object? Function()) a = a();            // an answer that changes with the requests
      if (a == null) return http.Response('', 204);
      return http.Response.bytes(utf8.encode(json.encode(a)), 200, headers: {'content-type': 'application/json'});
    }
    Object? answer = switch (key) {
      'POST /api/auth/login' => {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 900},
      'GET /api/platform/my/views' => views,
      'GET /api/account/organizations' => [{'org_id': org, 'name': 'Villa', 'role_id': 'customer_owner'}],
      'GET /api/platform/my/local-keys' => {'devices': []},
      'GET /api/platform/organizations/$org/settings' => {
          'latitude': 35.7, 'longitude': 51.4, 'radius_m': 200,
          'tariff': {'tiers': [{'up_to_kwh': 100, 'price': 900}], 'peak_factor': 1.2, 'fixed': 0, 'tax_percent': 9},
        },
      'GET /api/platform/organizations/$org/contacts' => {
          'contacts': [{'contact_id': 1, 'name': 'Ali', 'phone': '09120000000', 'sms': true, 'call': false, 'command': true}],
          'pin_set': false, 'gateway': true,
        },
      'GET /api/platform/organizations/$org/holidays' => [
          {'date': '1405/01/01', 'gregorian': '2026-03-21', 'name': 'Nowruz', 'source': 'fixed'},
        ],
      _ => <String, dynamic>{},
    };
    if (r.method == 'PUT' && r.url.path.endsWith('/sms-pin')) return http.Response('', 204);
    return http.Response.bytes(utf8.encode(json.encode(answer)), 200, headers: {'content-type': 'application/json'});
  });
}

Future<AppState> signedIn(WidgetTester tester, Hub hub, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'lang': 'en', 'server': 'http://hub.test', ...prefs});
  FlutterSecureStorage.setMockInitialValues({});
  final state = (await tester.runAsync(AppState.open))!;
  await tester.runAsync(() => http.runWithClient(() => state.api.login('sara', 'x'), () => hub.client));
  return state;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}
