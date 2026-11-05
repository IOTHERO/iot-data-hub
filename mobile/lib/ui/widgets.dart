// Small building blocks shared by the screens (the web app's section, tile and toast).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';

/// A titled section: icon tile, title, hint, then its content (app/js/core.js section()).
class Section extends StatelessWidget {
  const Section({super.key, required this.icon, required this.title, this.hint, required this.children});

  final IconData icon;
  final String title;
  final String? hint;
  final List<Widget> children;

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
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

/// A command from the app; the answer as a short message (done, pending, refused).
Future<Map<String, dynamic>?> sendCommand(BuildContext context, AppState s, String deviceId, String key,
    Object? value) async {
  final messenger = ScaffoldMessenger.of(context);
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
    messenger.showSnackBar(SnackBar(content: Text(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message)));
    return null;
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
      _ => Icons.toggle_on_rounded,
    };
