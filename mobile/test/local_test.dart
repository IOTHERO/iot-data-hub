// The phone signs exactly as the hub and the devices expect (vectors from
// hub/platform/local_sign.py), and only addresses inside the house are used.

import 'package:flutter_test/flutter_test.dart';
import 'package:titiswitch/core/local.dart';

void main() {
  final key = 'A' * 43;

  test('command and state signatures match the hub', () {
    expect(localSign(key, ['dabc', 'n1', 'command', 'relay_1', 'true']),
        'StCoV4XdrVG68ljm7vTS1Mui7AlAg7ZjNR9uwmk2_nc');
    expect(localSign(key, ['dabc', 'n1', 'state']), '5Xk--2jQTmvevT_Xyb-7Wq2J7bAfJnVSGy4IxP4b2eo');
  });

  test('only private addresses', () {
    for (final ok in ['192.168.1.50', '10.0.0.7', '172.20.1.1', 'relay-0001.local', 'fe80::1', 'fd00::5']) {
      expect(privateHost(ok), isTrue, reason: ok);
    }
    for (final bad in ['8.8.8.8', '127.0.0.1', 'example.com', '172.32.0.1', '2001:db8::1']) {
      expect(privateHost(bad), isFalse, reason: bad);
    }
  });
}
