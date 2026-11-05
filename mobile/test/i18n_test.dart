// The Jalali dates of the app match the hub's (hub/jalali.py).

import 'package:flutter_test/flutter_test.dart';
import 'package:titiswitch/core/i18n.dart';

void main() {
  test('gregorian to jalali', () {
    expect(I18n.jalali(2026, 11, 5), [1405, 8, 14]);
    expect(I18n.jalali(2026, 3, 21), [1405, 1, 1]);      // Nowruz
    expect(I18n.jalali(2025, 3, 20), [1403, 12, 30]);    // the last day of a leap year
    expect(I18n.jalali(2000, 1, 1), [1378, 10, 11]);
  });
}
