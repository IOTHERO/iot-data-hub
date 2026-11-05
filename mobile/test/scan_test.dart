// The QR text of a device label gives the identifier and the claim code.

import 'package:flutter_test/flutter_test.dart';
import 'package:titiswitch/screens/scan.dart';

void main() {
  test('label QR', () {
    expect(parseLabel('https://hub.example/app/#/claim/CTRL-8R-0001/ABCD-EFGH-JKMN'),
        ('CTRL-8R-0001', 'ABCD-EFGH-JKMN'));
    expect(parseLabel('https://example.com/'), isNull);
  });
}
