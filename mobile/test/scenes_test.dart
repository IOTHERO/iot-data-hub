// The scenes and automations tabs, as the web app's #/auto pages: a scene's clock button makes a
// time automation that runs it, and an automation card reads "if ... then ..." in chips.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:titiswitch/screens/automations.dart';
import 'package:titiswitch/screens/scenes.dart';
import 'package:titiswitch/ui/theme.dart';

import 'support.dart';

void main() {
  testWidgets('a scene is scheduled on chosen weekdays, not on holidays', (tester) async {
    final hub = Hub({
      'GET /api/platform/organizations/$org/scenes': [
        {'scene_id': 7, 'org_id': org, 'name': 'Evening', 'icon': 'moon', 'actions': [{'device_id': 'd1', 'tag': 'relay_1', 'value': true}]},
      ],
      'POST /api/platform/organizations/$org/automations': {'automation_id': 1},
    });
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.runAsync(s.load);
      s.live.stop();
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: Scaffold(body: ScenesScreen(state: s))));
      await settle(tester);
      expect(find.text(s.t('auto.title')), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);

      await tester.tap(find.byTooltip(s.t('auto.schedule_x', {'x': 'Evening'})));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.t('week.6')));                 // not on Fridays
      await tester.tap(find.text(s.t('auto.holidays_any')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.t('auto.holidays_skip')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.t('auto.save')));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => hub.client);
    final post = hub.sent.singleWhere((x) => x.$1 == 'POST' && x.$2 == '/api/platform/organizations/$org/automations');
    expect(post.$3, {
      'name': 'Evening at 20:00',
      'trigger': {'type': 'time', 'at': '20:00', 'weekdays': [0, 1, 2, 3, 4, 5], 'holidays': 'skip'},
      'actions': [{'type': 'scene', 'scene_id': 7}],
    });
  });

  testWidgets('an automation card shows its trigger and actions as chips', (tester) async {
    final hub = Hub({
      'GET /api/platform/organizations/$org/automations': [
        {'automation_id': 3, 'org_id': org, 'name': 'Hood at night', 'enabled': true, 'next_runs': ['2026-11-06T18:30:00Z'],
          'definition': {'trigger': {'type': 'time', 'at': '22:00', 'weekdays': [0, 1, 2, 3, 4]},
            'actions': [{'type': 'write', 'device_id': 'd1', 'tag': 'relay_1', 'value': true}]}},
      ],
    });
    await http.runWithClient(() async {
      final s = await signedIn(tester, hub);
      await tester.runAsync(s.load);
      s.live.stop();
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: Scaffold(body: AutomationsPage(state: s))));
      await settle(tester);
      expect(find.text('Hood at night'), findsOneWidget);
      expect(find.text(s.t('auto.at_time', {'at': '22:00'})), findsOneWidget);
      expect(find.text(s.t('auto.day_range', {'from': s.t('week.0'), 'to': s.t('week.4')})), findsOneWidget);
      expect(find.text(s.t('auto.turn_on_x', {'x': 'Hood (Kitchen)'})), findsOneWidget);
      expect(find.text(s.t('auto.active_of', {'n': '1', 'total': '1'})), findsOneWidget);
      expect(find.textContaining('22:00'), findsWidgets);          // the next run, Tehran time
      await tester.pumpWidget(const SizedBox());
    }, () => hub.client);
  });
}
