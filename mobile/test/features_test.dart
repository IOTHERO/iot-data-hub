// The web app's features the Flutter app gained: output names and switch types, the momentary
// push, the connection order, edge equipment, the maker's brand, a new home, deleting the account.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:titiswitch/core/connection.dart';
import 'package:titiswitch/screens/edge_add.dart';
import 'package:titiswitch/screens/me.dart';
import 'package:titiswitch/ui/outputs.dart';
import 'package:titiswitch/ui/theme.dart';
import 'package:titiswitch/ui/widgets.dart';

import 'support.dart';

final hood = {'key': 'relay_1', 'kind': 'digital_output', 'display_name': {'en': 'Hood'}, 'writable': true};

Future<void> pumpPage(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: Scaffold(body: page)));
}

void main() {
  test('a maker colour picks the nearest of the five accents', () {
    expect(nearestAccent('#A0A0FF'), 'violet');
    expect(nearestAccent('#18B5CF'), '');               // TiTiSwitch cyan
    expect(nearestAccent('#F0B060'), 'gold');
    expect(nearestAccent('red'), '');
  });

  test('connection: per home on the phone, local hub address checked', () {
    expect(Connection.validLocal('http://192.168.1.10:8000'), isTrue);
    expect(Connection.validLocal('http://192.168.1.10:8000/app'), isFalse);
    expect(Connection.validLocal(''), isTrue);
  });

  testWidgets('the server address keeps a maker link (?brand=) and drops it from the address', (tester) async {
    final hub = Hub();
    final s = await signedIn(tester, hub);
    await tester.runAsync(() => s.api.setServer('https://hub.example/app/?brand=maker_1#/home'));
    expect(s.api.server, 'https://hub.example');
    expect(s.store.get('brand'), 'maker_1');
  });

  testWidgets('the naming sheet sends LabelIn: a momentary output with its push length', (tester) async {
    final hub = Hub({'PUT /api/platform/my/devices/d1/labels/relay_1': {'ok': true}});
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      late BuildContext ctx;
      await pumpPage(tester, Builder(builder: (c) { ctx = c; return const SizedBox(); }));
      final saved = showLabelSheet(ctx, s, 'd1', Map.of(hood));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Gate');
      await tester.tap(find.text(s.t('out.mode_momentary')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '2.5');
      await tester.tap(find.text(s.t('common.save')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(await saved, isTrue);
    }, () => hub.client);
    final put = hub.sent.singleWhere((x) => x.$1 == 'PUT');
    expect(put.$3, {'name': 'Gate', 'icon': null, 'favorite': false, 'mode': 'momentary', 'pulse_s': 2.5});
  });

  testWidgets('a momentary push asks the hub for the pulse', (tester) async {
    final hub = Hub({'POST /api/platform/my/devices/d1/pulse': {'result': 'applied'}});
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      late BuildContext ctx;
      await pumpPage(tester, Builder(builder: (c) { ctx = c; return const SizedBox(); }));
      await tester.runAsync(() => pulseOutput(ctx, s, 'd1', {...hood, 'mode': 'momentary', 'pulse_s': 3}));
    }, () => hub.client);
    expect(hub.sent.singleWhere((x) => x.$2.endsWith('/pulse')).$3, {'tag': 'relay_1', 'seconds': 3});
  });

  testWidgets('connection order: internet only writes through the hub, "always SMS" does not', (tester) async {
    final hub = Hub({'POST /api/control/write': {'result': 'applied', 'value': true}});
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub, {'home': org});
      late BuildContext ctx;
      await pumpPage(tester, Builder(builder: (c) { ctx = c; return const SizedBox(); }));
      await tester.runAsync(() => const Connection(order: 'cloud').save(s.store, org));
      final r = await tester.runAsync(() => sendCommand(ctx, s, 'd1', 'relay_1', true));
      expect(r?['result'], 'applied');
      await tester.runAsync(() => const Connection(order: 'sms').save(s.store, org));
      final none = await tester.runAsync(() => sendCommand(ctx, s, 'd1', 'relay_1', false));
      expect(none, isNull);
      await tester.pump();
      expect(find.text(s.t('sms.not_enabled')), findsOneWidget);   // no SMS key for it yet
    }, () => hub.client);
    expect(hub.sent.where((x) => x.$2 == '/api/control/write').length, 1);
  });

  testWidgets('edge equipment: the hub, product, protocol and address go into ChildIn', (tester) async {
    final hub = Hub({
      'GET /api/platform/my/devices': [
        {'device_id': 'h1', 'name': 'Edge hub', 'product_kind': 'edge_hub', 'access': 'owner'},
        {'device_id': 'd1', 'name': 'Kitchen', 'product_kind': 'controller', 'access': 'owner'},
      ],
      'GET /api/platform/catalog': [
        {'product_id': 'p1', 'name': 'Meter', 'code': 'PM-1', 'latest_published': 3, 'protocols': ['native', 'modbus_tcp']},
      ],
      'GET /api/platform/protocols': {
        'modbus_tcp': {'connection': [
          {'name': 'host', 'type': 'string', 'required': true},
          {'name': 'port', 'type': 'integer', 'default': 502},
          {'name': 'timeout', 'type': 'number'},
        ]},
      },
      'POST /api/platform/my/devices/h1/children': {'device_id': 'c1'},
    });
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: EdgeAddScreen(state: s)));
      await settle(tester);
      expect(find.text('Edge hub'), findsWidgets);
      expect(find.text(s.t('conn.timeout')), findsNothing);       // only required fields, port, unit id
      await tester.enterText(field(s.t('conn.host')), '192.168.1.50');
      await tester.enterText(field(s.t('conn.port')), '1502');
      await tester.tap(find.text(s.t('edge.add')));
      await settle(tester);
    }, () => hub.client);
    final post = hub.sent.singleWhere((x) => x.$1 == 'POST' && x.$2.endsWith('/children'));
    expect(post.$3, {'product_id': 'p1', 'version': 3, 'protocol': 'modbus_tcp',
        'connection': {'host': '192.168.1.50', 'port': 1502}, 'enabled': true});
  });

  testWidgets('me: pending invitations, a new home, deleting the account', (tester) async {
    final hub = Hub({
      'GET /api/auth/me': {'display_name': 'Sara', 'email': 'sara@example.test'},
      'GET /api/account/invitations': [{'kind': 'organization', 'org_name': 'Villa'}],
      'POST /api/account/homes': {'org_id': 'o2', 'name': 'Office'},
      'POST /api/account/delete': null,
      'POST /api/auth/logout': null,
    });
    var out = false;
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.runAsync(s.load);
      s.live.stop();
      await tester.binding.setSurfaceSize(const Size(420, 3200));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
          home: Scaffold(body: MeScreen(state: s, signedOut: () => out = true))));
      await settle(tester);
      expect(find.text(s.t('invite.organization', {'org': 'Villa'})), findsOneWidget);

      await tester.tap(find.text(s.t('homes.new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Office');
      await tester.tap(find.text(s.t('homes.create')));
      await settle(tester);
      expect(s.home, 'o2');

      await tester.tap(find.text(s.t('account.delete')));
      await tester.pumpAndSettle();
      await tester.enterText(field(s.t('auth.password')), 'secret');
      await tester.enterText(field(s.t('account.type_delete')), 'DELETE');
      await tester.tap(find.widgetWithText(FilledButton, s.t('account.delete')));
      await settle(tester);
      s.live.stop();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => hub.client);
    expect(hub.sent.singleWhere((x) => x.$2 == '/api/account/homes').$3, {'name': 'Office'});
    expect(hub.sent.singleWhere((x) => x.$2 == '/api/account/delete').$3, {'password': 'secret', 'confirm': 'DELETE'});
    expect(out, isTrue);
  });
}
