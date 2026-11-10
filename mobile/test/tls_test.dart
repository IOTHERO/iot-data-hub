// A hub with its own certificate (core/tls.dart), against a real HTTPS server on this machine: the
// phone shows the certificate first, accepts it only after it is approved, and only for that host
// and port; the rest of TLS stays as strict as before.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titiswitch/core/store.dart';
import 'package:titiswitch/core/tls.dart';

import 'fixtures/test_hub_cert.dart';

void main() {
  late HttpServer server;
  late HttpServer other;                   // the same certificate on another port: another server
  late Uri base;

  Future<HttpServer> serve() async {
    final ctx = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(testHubCert))
      ..usePrivateKeyBytes(utf8.encode(testHubKey));
    final s = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    s.listen((req) {
      req.response
        ..statusCode = 200
        ..write('{"status":"ok"}');
      req.response.close();
    });
    return s;
  }

  setUp(() async {
    server = await serve();
    other = await serve();
    // by address, not "localhost" (which may be ::1 first, where the server does not listen)
    base = Uri.parse('https://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    await other.close(force: true);
  });

  test('an unknown certificate is shown, then accepted only once approved', () async {
    SharedPreferences.setMockInitialValues({});
    final trusted = TrustedCerts(await Store.open());

    final first = await checkServer(base, trusted);
    expect(first, isNotNull);
    expect(first!.host, '127.0.0.1');
    expect(first.port, server.port);
    expect(first.print, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));

    // the whole app (HttpOverrides) refuses it before approval
    await HttpOverrides.runZoned(() async {
      await expectLater(http.get(base.replace(path: '/api/health')), throwsA(isA<Exception>()));
    }, createHttpClient: PinnedOverrides(trusted).createHttpClient);

    await trusted.approve(first.host, first.port, first.print);
    expect(await checkServer(base, trusted), isNull);
    await HttpOverrides.runZoned(() async {
      final r = await http.get(base.replace(path: '/api/health'));
      expect(r.statusCode, 200);
    }, createHttpClient: PinnedOverrides(trusted).createHttpClient);

    // the approval is for that host and port only, and survives a restart of the app
    final again = TrustedCerts(await Store.open());
    expect(await checkServer(base, again), isNull);
    expect(await checkServer(base.replace(port: other.port), again), isNotNull);
    await again.forget('127.0.0.1', server.port);
    expect(await checkServer(base, again), isNotNull);
  });
}
