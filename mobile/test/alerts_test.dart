// Security alarms and the home layout: the alarm list marks seen, a swipe clears one, the button
// clears all; the home sections keep the order and visibility the person chose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:titiswitch/screens/alerts.dart';
import 'package:titiswitch/screens/custom_edit.dart';
import 'package:titiswitch/ui/theme.dart';

import 'support.dart';

Map<String, dynamic> alert(int id) => {
      'alert_id': id, 'org_id': org, 'device_id': 'd1', 'tag_key': 'pir', 'kind': 'motion',
      'started_at': '2026-11-05T10:00:00Z', 'last_at': '2026-11-05T10:05:00Z', 'trips': 2,
      'seen_at': null, 'device_name': 'Kitchen', 'room': 'Hall', 'tag_name': {'en': 'Hall PIR'},
    };

void main() {
  testWidgets('the alarm list: seen, a swipe clears one, the button clears all', (tester) async {
    final open = [alert(1), alert(2)];
    final hub = Hub({
      'GET /api/platform/my/alerts': () => open,
      'POST /api/platform/my/alerts/1/seen': () {
        open[0] = {...open[0], 'seen_at': '2026-11-05T10:06:00Z'};
        return {'changed': 1};
      },
      'POST /api/platform/my/alerts/2/clear': () {
        open.removeWhere((a) => a['alert_id'] == 2);
        return {'changed': 1};
      },
      'POST /api/platform/my/alerts/clear': () {
        final n = open.length;
        open.clear();
        return {'changed': n};
      },
    });
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.runAsync(s.alerts.load);
      expect(s.alerts.unseen.length, 2);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: AlertsScreen(state: s)));
      await settle(tester);
      expect(find.text(s.t('alarm.kind_motion', {'name': 'Hall PIR'})), findsNWidgets(2));
      expect(find.textContaining('Kitchen · Hall'), findsNWidgets(2));

      await tester.tap(find.text(s.t('alarm.mark_seen')).first);
      await settle(tester);
      await tester.fling(find.byKey(const ValueKey('alert-2')), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const ValueKey('alert-2')), findsNothing);
      expect(find.text(s.t('alarm.seen')), findsOneWidget);          // alert 1, seen
      await tester.tap(find.text(s.t('alarm.clear_all')));
      await settle(tester);
      expect(find.text(s.t('alarm.none')), findsOneWidget);
    }, () => hub.client);
    final posts = [for (final x in hub.sent) if (x.$1 == 'POST' && x.$2.contains('/alerts')) x.$2];
    expect(posts, ['/api/platform/my/alerts/1/seen', '/api/platform/my/alerts/2/clear', '/api/platform/my/alerts/clear']);
  });

  testWidgets('a new trip is announced once; a seen or cleared one is not', (tester) async {
    final hub = Hub({'GET /api/platform/my/alerts': [alert(1)]});
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.runAsync(() => s.alerts.event(alert(1)));
      expect(s.alerts.tripped.value?['alert_id'], 1);
      s.alerts.tripped.value = null;
      await tester.runAsync(() => s.alerts.event({...alert(1), 'seen_at': '2026-11-05T10:06:00Z'}));
      expect(s.alerts.tripped.value, isNull);
    }, () => hub.client);
  });

  testWidgets('home layout: order and visibility are kept on the phone', (tester) async {
    final s = await signedIn(tester, Hub());
    expect([for (final r in s.homeLayout) r.$1], ['today', 'custom', 'quick', 'groups', 'devices']);
    await tester.runAsync(() => s.setHomeLayout([('devices', true), ('quick', false), ('today', true), ('groups', true)]));
    // a section missing from what was kept (a newer app's section) joins at the end, shown
    expect(s.homeLayout, [('devices', true), ('quick', false), ('today', true), ('groups', true), ('custom', true)]);
    await tester.runAsync(() => s.setHomeLayout(null));
    expect(s.homeLayout.first, ('today', true));
  });

  testWidgets('my own section: picked from any module and scenes, in my order', (tester) async {
    final s = await signedIn(tester, Hub());
    final views = [
      {'device': {'device_id': 'out8', 'name': 'Outputs'}, 'tags': [
        {'key': 'relay_3', 'data_type': 'bool', 'writable': true, 'display_name': {'en': 'Siren'}},
      ]},
      {'device': {'device_id': 'in8', 'name': 'Inputs'}, 'tags': [
        {'key': 'in_1', 'data_type': 'bool', 'writable': false, 'display_name': {'en': 'Front door'}},
      ]},
    ];
    final scenes = [{'scene_id': 7, 'name': 'Night'}];
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
        home: CustomEditScreen(state: s, views: views, scenes: scenes)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Security');
    await tester.tap(find.text('Front door'));
    await tester.tap(find.text('Night'));
    await tester.tap(find.text('Siren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.t('common.save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.customTitle, 'Security');
    expect([for (final x in s.customItems) x['type']], ['sensor', 'scene', 'out']);   // the order picked
    expect(s.customItems.last, {'type': 'out', 'device_id': 'out8', 'key': 'relay_3'});
  });
}
