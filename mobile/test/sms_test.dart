// The app signs SMS commands exactly as the hub and the device check them
// (vector from backend/api/home.py sms_signature).

import 'package:flutter_test/flutter_test.dart';
import 'package:titiswitch/screens/device_settings.dart';

void main() {
  test('sms signature', () {
    expect(smsSignature('A' * 43, 'dabc', 1700000000, ['relay_1=1', 'relay_3=0']), '8670d3f10b945953');
  });
}
