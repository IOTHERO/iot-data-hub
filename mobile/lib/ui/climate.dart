// The air-conditioner card of the web app (app/js/climate.js): the tags of a device whose
// ui.role is climate_power / climate_setpoint / climate_mode / climate_fan / climate_temp, as
// one card - the set temperature large between - and +, the power button, mode and fan chips.

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'kit.dart';
import 'widgets.dart';

const climateRoles = ['climate_power', 'climate_setpoint', 'climate_mode', 'climate_fan', 'climate_temp'];

/// The climate tags of a view, by role (empty when the device has none).
Map<String, Map<String, dynamic>> climateSet(List<Map<String, dynamic>> tags) => {
      for (final t in tags)
        if (climateRoles.contains(t['ui']?['role'])) '${t['ui']['role']}'.substring(8): t,
    };

class ClimateCard extends StatelessWidget {
  const ClimateCard({super.key, required this.state, required this.set, required this.busy, required this.write});

  final AppState state;
  final Map<String, Map<String, dynamic>> set;     // power, setpoint, mode, fan, temp
  final Set<String> busy;
  final void Function(String key, Object? value) write;

  bool _can(Map<String, dynamic>? t) => t != null && t['writable'] == true && !busy.contains(t['key']);

  @override
  Widget build(BuildContext context) {
    final s = state;
    final tk = Tk.of(context);
    final power = set['power'];
    final sp = set['setpoint'];
    final on = power == null || power['value'] == true;
    final target = (sp?['value'] as num?)?.toDouble();
    final step = '${sp?['data_type']}'.startsWith('float') ? 0.5 : 1.0;
    final lo = (sp?['min'] as num?)?.toDouble() ?? 16;
    final hi = (sp?['max'] as num?)?.toDouble() ?? 30;
    Widget chips(Map<String, dynamic> t) {
      final states = (t['states'] as Map?)?.map((k, v) => MapEntry(int.parse('$k'), '$v')) ?? const <int, String>{};
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in states.entries)
          WebTab(e.value, on: t['value'] == e.key,
              onTap: _can(t) && on ? () => write(t['key'] as String, e.key) : null),
      ]);
    }

    return GlassCard(
      lit: on,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.i18n.name(power?['display_name'] ?? sp?['display_name']),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tk.text)),
            if (set['mode'] != null)
              Text(_state(set['mode']!), style: TextStyle(fontSize: 12, color: tk.muted)),
          ])),
          if (power != null)
            GestureDetector(
              onTap: _can(power) ? () => write(power['key'] as String, !on) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? tk.ok : tk.surface2,
                  boxShadow: on ? [BoxShadow(color: tk.ok.withValues(alpha: 0.45), blurRadius: 18)] : null,
                ),
                child: Icon(Icons.power_settings_new_rounded, color: on ? tk.accentInk : tk.muted),
              ),
            ),
        ]),
        if (sp != null) ...[
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _Step(icon: Icons.add_rounded,
                onTap: _can(sp) && on && target != null && target + step <= hi ? () => write(sp['key'] as String, target + step) : null),
            Column(children: [
              Text(s.t('climate.target'), style: TextStyle(fontSize: 12, color: tk.muted)),
              Text.rich(TextSpan(children: [
                TextSpan(text: target == null ? '—' : s.i18n.num(target),
                    style: TextStyle(fontSize: 52, fontWeight: FontWeight.w300, color: on ? tk.text : tk.muted)),
                TextSpan(text: ' ${sp['unit'] ?? '°C'}', style: TextStyle(fontSize: 16, color: tk.muted)),
              ])),
            ]),
            _Step(icon: Icons.remove_rounded,
                onTap: _can(sp) && on && target != null && target - step >= lo ? () => write(sp['key'] as String, target - step) : null),
          ]),
        ],
        if (set['temp'] != null)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: tk.surface2, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.thermostat_rounded, size: 16, color: tk.muted),
                const SizedBox(width: 4),
                Text('${s.i18n.name(set['temp']!['display_name'])} ${_state(set['temp']!)}',
                    style: TextStyle(fontSize: 12, color: tk.muted)),
              ]),
            ),
          ),
        if (set['mode'] != null) ...[
          const SizedBox(height: 16),
          Text(s.i18n.name(set['mode']!['display_name']), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
          const SizedBox(height: 8),
          chips(set['mode']!),
        ],
        if (set['fan'] != null) ...[
          const SizedBox(height: 16),
          Text(s.i18n.name(set['fan']!['display_name']), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
          const SizedBox(height: 8),
          chips(set['fan']!),
        ],
      ]),
    );
  }

  String _state(Map<String, dynamic> t) {
    final v = t['value'];
    if (v == null) return '—';
    final states = t['states'] as Map?;
    if (states != null && states['$v'] != null) return '${states['$v']}';
    return '${state.i18n.num(v is num ? v.toDouble() : v)}${t['unit'] == null ? '' : '${t['unit']}'}';
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: tk.surface2,
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
            child: SizedBox(width: 56, height: 56, child: Icon(icon, color: tk.text))),
      ),
    );
  }
}

/// Icons for the climate role, used where a climate tag shows alone.
IconData climateIcon(String? role) => iconFor(role == 'climate_temp' ? 'thermo' : 'snow');
