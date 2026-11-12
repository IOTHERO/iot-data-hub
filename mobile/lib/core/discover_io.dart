// Finding devices on the home Wi-Fi by mDNS (_titiswitch._tcp, TXT id=<device_id>): phones only.

import 'package:multicast_dns/multicast_dns.dart';

/// device_id -> "host:port" of every device answering within a few seconds.
Future<Map<String, String>> discoverDevices(bool Function(String host) allowed) async {
  final found = <String, String>{};
  final client = MDnsClient();
  try {
    await client.start();
    const wait = Duration(seconds: 2);
    // devices (_titiswitch) and central hubs (_titihub, TXT id=<hub_id>)
    for (final service in const ['_titiswitch._tcp.local', '_titihub._tcp.local']) {
      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(service), timeout: wait)) {
        String? id;
        await for (final txt in client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName), timeout: wait)) {
          for (final line in txt.text.split('\n')) {
            if (line.startsWith('id=')) id = line.substring(3);
          }
        }
        await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName), timeout: wait)) {
          await for (final a in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target), timeout: wait)) {
            if (id != null && allowed(a.address.address)) found[id] = '${a.address.address}:${srv.port}';
          }
        }
      }
    }
  } catch (_) {
    // no multicast on this network: the address the hub told us is used
  } finally {
    client.stop();
  }
  return found;
}
