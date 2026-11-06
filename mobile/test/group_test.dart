// The group page, as the web app's #/group/{id}: a named part with its master switch, the values,
// and "all on" writing every output that is off through /api/control/write.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:titiswitch/screens/group.dart';
import 'package:titiswitch/ui/theme.dart';

import 'support.dart';

void main() {
  testWidgets('a group shows its parts and values; all on writes the outputs', (tester) async {
    final hub = Hub({
      'GET /api/platform/organizations/$org/groups': [
        {'group_id': 4, 'name': 'Kitchen', 'device_ids': ['d1'],
          'sections': [{'name': 'Lights', 'icon': 'bulb', 'outputs': [{'device_id': 'd1', 'key': 'relay_1'}]}]},
      ],
      'POST /api/control/write': {'result': 'applied', 'value': true},
      'GET /api/platform/my/views': [
        for (final v in views) {...v, 'device': {...(v['device'] as Map), 'state': 'online'}},
      ],
    });
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: GroupScreen(state: s, orgId: org, groupId: 4)));
      await settle(tester);
      expect(find.text('Kitchen'), findsNWidgets(2));            // the group, and its device's tab
      expect(find.text('Lights'), findsOneWidget);                 // the named part
      expect(find.text(s.t('groups.combined')), findsOneWidget);    // the "all of it" tab
      expect(find.text('Temperature'), findsOneWidget);             // a value
      await tester.tap(find.text(s.t('device.all_on')));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => hub.client);
    final writes = hub.sent.where((x) => x.$2 == '/api/control/write').toList();
    expect(writes.length, 1);
    expect((writes.single.$3 as Map)['tag'], 'platform.devices.d1.relay_1');
    expect((writes.single.$3 as Map)['value'], true);
  });
}
