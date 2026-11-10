// A hub with its own certificate (core/tls.dart), against a real HTTPS server on this machine: the
// phone shows the certificate first, accepts it only after it is approved, and only for that host
// and port; the rest of TLS stays as strict as before.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titiswitch/core/store.dart';
import 'package:titiswitch/core/tls.dart';

void main() {
  late HttpServer server;
  late Uri base;

  setUp(() async {
    final ctx = SecurityContext()
      ..useCertificateChain('test/fixtures/test-hub.crt.pem')
      ..usePrivateKey('test/fixtures/test-hub.key.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    server.listen((req) {
      req.response
        ..statusCode = 200
        ..write('{"status":"ok"}');
      req.response.close();
    });
    base = Uri.parse('https://localhost:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('an unknown certificate is shown, then accepted only once approved', () async {
    SharedPreferences.setMockInitialValues({});
    final trusted = TrustedCerts(await Store.open());

    final first = await checkServer(base, trusted);
    expect(first, isNotNull);
    expect(first!.host, 'localhost');
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
    expect(await checkServer(base.replace(host: '127.0.0.1'), again), isNotNull);
    await again.forget('localhost', server.port);
    expect(await checkServer(base, again), isNotNull);
  });
}
