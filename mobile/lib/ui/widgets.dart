// Small building blocks shared by the screens (the web app's section, tile and toast).

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/connection.dart';
import 'sms_sheet.dart';

/// A titled section: icon tile, title, hint, then its content (app/js/core.js section()).
class Section extends StatelessWidget {
  const Section({super.key, required this.icon, required this.title, this.hint, required this.children,
      this.action});

  final IconData icon;
  final String title;
  final String? hint;
  final List<Widget> children;
  final Widget? action;               // e.g. the pencil of the person's own section

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
            ),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ])),
          if (action != null) action!,
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

/// A command from the app, the way this phone is set to reach the home (connection.dart); the
/// answer as a short message (done, pending, refused). Null when it did not go through the hub.
Future<Map<String, dynamic>?> sendCommand(BuildContext context, AppState s, String deviceId, String key,
    Object? value, {bool offline = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  final way = Connection.of(s.store, s.homeOrg);
  if (value is bool && (way.order == 'sms' || (offline && way.order == 'auto'))) {
    if (way.order == 'auto') {                      // the device may still hear the home Wi-Fi
      final r = await s.api.local.write(deviceId, key, value);
      if (r['result'] == 'applied') return r;
    }
    if (context.mounted) {
      way.order == 'sms'
          ? await showSmsSheet(context, s, deviceId, preset: {key: value})
          : await _fallback(context, s, way, deviceId, key, value);
    }
    return null;
  }
  try {
    final r = await s.api.call('POST', '/api/control/write',
        {'tag': 'platform.devices.$deviceId.$key', 'value': value, 'reason': 'app'}) as Map<String, dynamic>;
    final result = '${r['result']}';
    if (result != 'applied') {
      final text = r['status'] == 'pending_confirmation'
          ? s.t('device.pending')
          : (s.i18n.has('write.$result') ? s.t('write.$result') : '${r['message'] ?? result}');
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }
    return r;
  } on ApiError catch (e) {
    if (e.status == 0 && way.order == 'auto' && value is bool && context.mounted) {
      await _fallback(context, s, way, deviceId, key, value);       // no internet and no Wi-Fi way
      return null;
    }
    messenger.showSnackBar(SnackBar(content: Text(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message)));
    return null;
  }
}

/// Neither the internet nor the home Wi-Fi reached the device: the home's local hub or an SMS.
Future<void> _fallback(BuildContext context, AppState s, Connection way, String deviceId, String key, bool value) async {
  final answer = await showDialog<String>(context: context, builder: (c) => AlertDialog(
    title: Text(s.t('connect.failed')),
    content: Text(s.t(way.local.isEmpty ? 'connect.failed_help' : 'connect.failed_local')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('common.cancel'))),
      if (way.local.isNotEmpty)
        TextButton(onPressed: () => Navigator.pop(c, 'local'), child: Text(s.t('connect.open_local'))),
      FilledButton(onPressed: () => Navigator.pop(c, 'sms'), child: Text(s.t('sms.quick'))),
    ],
  ));
  if (answer == 'local') {
    await launchUrl(Uri.parse('${way.local}/app/#/device/$deviceId'), mode: LaunchMode.externalApplication);
  } else if (answer == 'sms' && context.mounted) {
    await showSmsSheet(context, s, deviceId, preset: {key: value});
  }
}

/// Icons of the web app's names (template ui.icon, scene icons).
IconData iconFor(String? name) => switch (name) {
      'moon' => Icons.nightlight_round,
      'sun' => Icons.wb_sunny_rounded,
      'out' => Icons.logout_rounded,
      'arrive' => Icons.login_rounded,
      'cinema' => Icons.movie_rounded,
      'power' => Icons.power_settings_new_rounded,
      'bulb' || 'lamp' => Icons.lightbulb_rounded,
      'chandelier' => Icons.light_rounded,
      'fan' => Icons.mode_fan_off_rounded,
      'snow' => Icons.ac_unit_rounded,
      'door' => Icons.door_front_door_rounded,
      'plug' => Icons.power_rounded,
      'tv' => Icons.tv_rounded,
      'curtain' => Icons.curtains_rounded,
      'water' || 'pump' => Icons.water_drop_rounded,
      'motion' => Icons.directions_walk_rounded,
      'magnet' => Icons.sensor_window_rounded,
      'smoke' => Icons.local_fire_department_rounded,
      'remote' => Icons.settings_remote_rounded,
      'thermo' => Icons.thermostat_rounded,
      'relay' => Icons.grid_view_rounded,
      'home' => Icons.home_rounded,
      'flame' => Icons.whatshot_rounded,
      'alert' => Icons.warning_amber_rounded,
      'bolt' => Icons.bolt_rounded,
      'ir' => Icons.sensors_rounded,
      'call' => Icons.call_rounded,
      'siren' => Icons.campaign_rounded,
      'sensor' => Icons.sensors_rounded,
      'grip' => Icons.drag_handle_rounded,
      'lock' => Icons.lock_rounded,
      'leaf' => Icons.eco_rounded,
      'bell' => Icons.notifications_rounded,
      'hub' => Icons.hub_rounded,
      _ => Icons.toggle_on_rounded,
    };
