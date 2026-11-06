// The home's security scenarios: a switch sends only that scenario, the sensors are counted, and
// who gets the alarms is picked by name from the home's contacts (their numbers stay in the home
// settings and are never shown here).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:titiswitch/ui/kit.dart';
import 'package:titiswitch/ui/security.dart';
import 'package:titiswitch/ui/theme.dart';

import 'support.dart';

void main() {
  testWidgets('security scenarios: switch the burglar alarm, pick who gets the SMS', (tester) async {
    var modes = {'burglar': false, 'night': false, 'fire': true, 'offline': true};
    var people = [
      {'contact_id': 1, 'name': 'Ali', 'sms': false, 'call': false},
      {'contact_id': 2, 'name': 'Mina', 'sms': false, 'call': true},
    ];
    Map<String, Object> answer() => {...modes, 'sensors': {'motion': 2, 'magnet': 1}, 'recipients': people,
      'contacts': people.where((p) => p['sms'] == true || p['call'] == true).length};
    final hub = Hub({
      'GET /api/platform/organizations/$org/security': answer,
      'PUT /api/platform/organizations/$org/security': () {
        modes = {...modes, 'burglar': true};
        return answer();
      },
      'PUT /api/platform/organizations/$org/security/recipients': () {
        people = [{...people[0], 'sms': true}, people[1]];
        return answer();
      },
    });
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: Scaffold(body: ListView(children: [SecurityCard(state: s, orgId: org)]))));
      await settle(tester);
      expect(find.text(s.t('security.disarmed')), findsOneWidget);
      expect(find.text(s.t('security.sensors', {'n': s.i18n.num(3)})), findsOneWidget);     // burglar: 2 + 1
      expect(find.text('Ali'), findsOneWidget);
      expect(find.textContaining('0912'), findsNothing);                                       // names only

      await tester.tap(find.byType(TiSwitch).first);               // the burglar alarm
      await settle(tester);
      expect(find.text(s.t('security.armed')), findsOneWidget);

      await tester.tap(find.text(s.t('contacts.sms')).first);       // Ali: SMS
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));             // the snack bars
    }, () => hub.client);
    final puts = hub.sent.where((x) => x.$1 == 'PUT').toList();
    expect(puts.first.$3, {'burglar': true});
    expect(puts.last.$2, '/api/platform/organizations/$org/security/recipients');
    expect(puts.last.$3, {'sms': [1], 'call': [2]});               // Mina keeps her call
  });
}
