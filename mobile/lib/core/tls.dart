// A hub with its own certificate (deploy/setup.sh: a private CA on a LAN or a PC with WSL): the
// phone does not know that CA, and Dart trusts only the system's roots - even a CA the user
// installs in Android's settings is not used. So the user approves the server's certificate once,
// after comparing its fingerprint with the one setup.sh printed; from then on exactly that
// certificate is accepted for exactly that host and port (a pin), and nothing else is relaxed.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'store.dart';

/// SHA-256 of the certificate as "AB:CD:...", the form `openssl x509 -fingerprint -sha256` prints.
String fingerprint(X509Certificate cert) =>
    sha256.convert(cert.der).bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

/// The approved certificates, by "host:port" -> fingerprint (kept in the phone's settings).
class TrustedCerts {
  TrustedCerts(this._store) {
    final raw = _store.get(_key);
    if (raw != null) {
      try {
        _pins.addAll((jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v')));
      } on FormatException {
        // a damaged entry: nothing approved
      }
    }
  }

  static const _key = 'tls.pins';
  final Store _store;
  final Map<String, String> _pins = {};

  bool accepts(X509Certificate cert, String host, int port) => _pins['$host:$port'] == fingerprint(cert);

  Future<void> approve(String host, int port, String print) async {
    _pins['$host:$port'] = print;
    await _store.set(_key, jsonEncode(_pins));
  }

  Future<void> forget(String host, int port) async {
    _pins.remove('$host:$port');
    await _store.set(_key, jsonEncode(_pins));
  }
}

/// Every HTTPS connection of the app: the system's roots as always; a certificate the system
/// refuses passes only when it is the one approved for that host and port.
class PinnedOverrides extends HttpOverrides {
  PinnedOverrides(this.trusted);

  final TrustedCerts trusted;

  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context)
    ..badCertificateCallback = (cert, host, port) => trusted.accepts(cert, host, port);
}

/// What a server answered when its certificate is not trusted: the certificate to show the user.
class UntrustedServer {
  UntrustedServer(this.cert, this.host, this.port);

  final X509Certificate cert;
  final String host;
  final int port;
  String get print => fingerprint(cert);
}

/// Try the hub at [base]: null when it answers over a trusted connection, the certificate when
/// TLS fails only because the phone does not know its issuer. Other failures throw.
Future<UntrustedServer?> checkServer(Uri base, TrustedCerts trusted) async {
  if (base.scheme != 'https') return null;
  X509Certificate? seen;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (cert, host, port) {
      if (trusted.accepts(cert, host, port)) return true;
      seen = cert;
      return false;
    };
  try {
    final req = await client.getUrl(base.replace(path: '/api/health'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain<void>();
    return null;
  } on HandshakeException {
    final cert = seen;
    if (cert == null) rethrow;
    return UntrustedServer(cert, base.host, base.hasPort ? base.port : 443);
  } finally {
    client.close(force: true);
  }
}
