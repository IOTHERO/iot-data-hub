// How this phone reaches a home's devices (the web app's connection(), home settings): over the
// internet, then the devices themselves over the home Wi-Fi (local.dart) or the home's local
// hub, then a signed SMS. Kept on this phone per home.

import 'dart:convert';

import 'store.dart';

class Connection {
  const Connection({this.order = 'auto', this.local = ''});

  /// auto: internet -> home Wi-Fi / local hub -> SMS; cloud: internet only; sms: always SMS.
  final String order;

  /// The home's local hub (http://192.168.1.10:8000), optional.
  final String local;

  static const orders = ['auto', 'cloud', 'sms'];

  /// A private-network hub address as the web app accepts it.
  static bool validLocal(String url) => url.isEmpty || RegExp(r'^https?://[^\s/]+(:\d+)?/?$').hasMatch(url);

  static Connection of(Store store, String? orgId) {
    if (orgId == null) return const Connection();
    try {
      final m = json.decode(store.get('connect.$orgId') ?? '{}') as Map<String, dynamic>;
      final order = orders.contains(m['order']) ? m['order'] as String : 'auto';
      return Connection(order: order, local: '${m['local'] ?? ''}');
    } catch (_) {
      return const Connection();
    }
  }

  Future<void> save(Store store, String orgId) => store.set('connect.$orgId',
      json.encode({'order': order, 'local': local.replaceFirst(RegExp(r'/$'), '')}));
}
