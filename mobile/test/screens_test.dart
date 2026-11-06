// The editors against a mock hub: what they show from its answers and the bodies they send
// (the hub's models: GroupIn, SettingsIn with Tariff, ContactIn, the SMS PIN).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:titiswitch/screens/group_edit.dart';
import 'package:titiswitch/screens/home_settings.dart';
import 'package:titiswitch/ui/contacts.dart';
import 'package:titiswitch/ui/kit.dart';
import 'package:titiswitch/ui/theme.dart';

import 'support.dart';

void main() {
  testWidgets('the group editor sends a GroupIn with the chosen output', (tester) async {
    final hub = Hub();
    await http.runWithClient(() async {
      final state = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: GroupEditScreen(state: state, orgId: org)));
      await settle(tester);
      expect(find.text('Hood'), findsOneWidget);
      expect(find.text('Temperature'), findsNothing);          // only outputs
      await tester.enterText(find.byType(TextField).first, 'Kitchen lights');
      await tester.tap(find.text('Hood'));
      await tester.pump();
      await tester.tap(find.text(state.t('common.save')));
      await settle(tester);
    }, () => hub.client);
    final post = hub.sent.where((x) => x.$1 == 'POST' && x.$2 == '/api/platform/organizations/$org/groups').single;
    final body = post.$3 as Map;
    expect(body['name'], 'Kitchen lights');
    expect(body['device_ids'], ['d1']);
    expect(body['sections'][0]['outputs'], [{'device_id': 'd1', 'key': 'relay_1'}]);
  });

  testWidgets('home settings show the hub\'s values and send SettingsIn', (tester) async {
    final hub = Hub();
    await http.runWithClient(() async {
      final state = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: HomeSettingsScreen(state: state, home: const {'org_id': org, 'name': 'Villa', 'role_id': 'customer_owner'})));
      await settle(tester);
      expect(find.text('35.7'), findsOneWidget);
      expect(find.text('Nowruz'), findsOneWidget);
      await tester.tap(find.text(state.t('common.save')).first);
      await settle(tester);
      state.live.stop();                                       // started by the reload after saving
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));          // the snack bars' timers
    }, () => hub.client);
    final put = hub.sent.where((x) => x.$1 == 'PUT' && x.$2 == '/api/platform/organizations/$org/settings').single;
    final body = put.$3 as Map;
    expect(body['latitude'], 35.7);
    expect(body['radius_m'], 200);
    expect(body['tariff']['tiers'], [{'up_to_kwh': 100.0, 'price': 900.0}]);
    expect(body['tariff']['tax_percent'], 9.0);
    expect(hub.sent.where((x) => x.$2 == '/api/account/homes/$org'), isEmpty);   // the name did not change
  });

  testWidgets('a member who is not the owner cannot save the settings', (tester) async {
    final hub = Hub();
    await http.runWithClient(() async {
      final state = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: HomeSettingsScreen(state: state, home: const {'org_id': org, 'name': 'Villa', 'role_id': 'customer_member'})));
      await settle(tester);
      final save = tester.widget<WebButton>(find.widgetWithText(WebButton, state.t('common.save')).first);
      expect(save.onTap, isNull);
    }, () => hub.client);
  });

  testWidgets('the access page lists people without an account and sets the SMS PIN', (tester) async {
    final hub = Hub();
    await http.runWithClient(() async {
      final state = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: Scaffold(body: ListView(children: [ContactsSection(state: state, orgId: org, owner: true)]))));
      await settle(tester);
      expect(find.text('Ali'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, state.t('contacts.pin_hint')), '4821');
      await tester.tap(find.text(state.t('contacts.pin_set')));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));          // the snack bars' timers
    }, () => hub.client);
    final pin = hub.sent.where((x) => x.$2 == '/api/platform/organizations/$org/sms-pin').single;
    expect(pin.$3, {'pin': '4821'});
  });
}
