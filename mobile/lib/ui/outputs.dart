// An output as the home names it (the web app's outputs.js): its name, icon, place among the
// home screen shortcuts and how it is switched - one key, two keys (on | off) or a momentary
// push that the hub releases after a moment (a door opener, a bell, a gate).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'kit.dart';
import 'widgets.dart';

const outputIcons = ['power', 'bulb', 'chandelier', 'lamp', 'fan', 'snow', 'flame', 'plug',
  'tv', 'curtain', 'door', 'lock', 'water', 'pump', 'leaf', 'bell'];

/// The home's icon for it, else the template's.
String? outIcon(Map<String, dynamic> tag) => tag['icon'] as String? ?? tag['ui']?['icon'] as String?;

bool isMomentary(Map<String, dynamic> tag) => tag['mode'] == 'momentary';

/// A push: on now, off after pulse_s (the hub turns it off, even if the app closes).
Future<Map<String, dynamic>?> pulseOutput(BuildContext context, AppState s, String deviceId, Map<String, dynamic> tag) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await s.api.call('POST', '/api/platform/my/devices/$deviceId/pulse',
        {'tag': tag['key'], 'seconds': (tag['pulse_s'] as num?) ?? 1}) as Map<String, dynamic>;
    final result = '${r['result']}';
    if (result != 'applied') {
      messenger.showSnackBar(SnackBar(content: Text(s.i18n.has('write.$result') ? s.t('write.$result') : '${r['message']}')));
    }
    return r;
  } on ApiError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message)));
    return null;
  }
}

/// The naming sheet; true when something was saved.
Future<bool> showLabelSheet(BuildContext context, AppState s, String deviceId, Map<String, dynamic> tag) async {
  final maker = s.i18n.name(tag['default_name'] ?? tag['display_name']);
  final name = TextEditingController(text: tag['default_name'] != null ? s.i18n.name(tag['display_name']) : '');
  final pulse = TextEditingController(text: '${tag['pulse_s'] ?? 1}');
  String? icon = tag['icon'] as String?;
  var favorite = tag['favorite'] == true;
  var mode = '${tag['mode'] ?? 'toggle'}';
  final customised = tag['default_name'] != null || tag['icon'] != null || favorite || mode != 'toggle';
  final answer = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final tk = Tk.of(c);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text(s.t('out.rename'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          WebField(label: s.t('out.name'), child: TextField(controller: name, maxLength: 40,
              decoration: InputDecoration(hintText: s.t('out.name_hint'),
                  helperText: s.t('out.default', {'name': maker})))),
          const SizedBox(height: 8),
          RowLabel(s.t('out.icon')),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final i in outputIcons)
              Semantics(
                button: true, selected: (icon ?? 'power') == i, label: i,
                child: GestureDetector(
                  onTap: () => set(() => icon = i == 'power' ? null : i),
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: (icon ?? 'power') == i ? tk.accentSoft : tk.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: (icon ?? 'power') == i ? tk.accentLine : tk.line),
                    ),
                    child: Icon(iconFor(i), size: 20, color: (icon ?? 'power') == i ? tk.accent : tk.muted),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          RowLabel(s.t('out.mode')),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'toggle', icon: const Icon(Icons.power_settings_new_rounded), label: Text(s.t('out.mode_toggle'))),
              ButtonSegment(value: 'dual', icon: const Icon(Icons.tune_rounded), label: Text(s.t('out.mode_dual'))),
              ButtonSegment(value: 'momentary', icon: const Icon(Icons.notifications_rounded), label: Text(s.t('out.mode_momentary'))),
            ],
            selected: {mode},
            onSelectionChanged: (v) => set(() => mode = v.first),
          ),
          if (mode == 'momentary') ...[
            const SizedBox(height: 10),
            WebField(label: s.t('out.pulse'), child: TextField(controller: pulse, textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(helperText: s.t('out.pulse_help'), helperMaxLines: 3))),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.star_rounded),
            title: Text(s.t('out.favorite')),
            value: favorite,
            onChanged: (v) => set(() => favorite = v),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(s.t('common.save'))),
          if (customised) TextButton(onPressed: () => Navigator.pop(c, 'reset'), child: Text(s.t('out.reset'))),
        ])),
      );
    }),
  );
  if (answer != 'save' && answer != 'reset') return false;
  final seconds = (double.tryParse(pulse.text.trim()) ?? 1).clamp(0.2, 600);
  final body = answer == 'reset'
      ? <String, dynamic>{}
      : {
          'name': name.text.trim().isEmpty ? null : name.text.trim(),
          'icon': icon,
          'favorite': favorite,
          'mode': mode,
          'pulse_s': mode == 'momentary' ? seconds : null,
        };
  try {
    await s.api.call('PUT', '/api/platform/my/devices/$deviceId/labels/${tag['key']}', body);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('out.saved'))));
    return true;
  } on ApiError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Inputs a module can carry (the web app's SENSOR_ICONS); the first three are alarms: the hub
/// opens an alert when one trips (backend/home_alerts.py).
const sensorIcons = ['motion', 'magnet', 'smoke', 'remote', 'ir', 'call', 'siren', 'door', 'water', 'thermo',
  'sensor', 'bolt'];
const alarmKinds = {'motion', 'magnet', 'smoke'};

/// Name an input and say what it is; true when saved.
Future<bool> showSensorSheet(BuildContext context, AppState s, String deviceId, Map<String, dynamic> tag) async {
  final maker = s.i18n.name(tag['default_name'] ?? tag['display_name']);
  final name = TextEditingController(text: tag['default_name'] != null ? s.i18n.name(tag['display_name']) : '');
  final template = tag['ui']?['icon'] as String?;
  var chosen = (tag['icon'] as String?) ?? template ?? 'sensor';
  final answer = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final tk = Tk.of(c);
      final alarm = alarmKinds.contains(chosen);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text(s.t('alarm.sensor_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          WebField(label: s.t('out.name'), child: TextField(controller: name, maxLength: 40,
              decoration: InputDecoration(hintText: s.t('out.name_hint'),
                  helperText: s.t('out.default', {'name': maker})))),
          const SizedBox(height: 8),
          RowLabel(s.t('alarm.sensor_kind')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final i in sensorIcons)
              Tooltip(
                message: s.i18n.has('sensor.kind_$i') ? s.t('sensor.kind_$i') : i,
                child: Semantics(
                  button: true, selected: chosen == i, label: s.i18n.has('sensor.kind_$i') ? s.t('sensor.kind_$i') : i,
                  child: GestureDetector(
                    onTap: () => set(() => chosen = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: chosen == i ? tk.accentSoft : tk.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: chosen == i ? tk.accentLine
                            : alarmKinds.contains(i) ? const Color(0x73FF4D5E) : tk.line),
                      ),
                      child: Icon(iconFor(i), color: chosen == i ? tk.accent : tk.muted),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text(s.t('sensor.kind_$chosen'), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
          const SizedBox(height: 4),
          Text(s.t(alarm ? 'alarm.is_alarm' : 'alarm.not_alarm'),
              style: TextStyle(fontSize: 12, height: 1.6, color: alarm ? const Color(0xFFFF4D5E) : tk.muted)),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(s.t('common.save'))),
          if (tag['default_name'] != null || tag['icon'] != null)
            TextButton(onPressed: () => Navigator.pop(c, 'reset'), child: Text(s.t('out.reset'))),
        ])),
      );
    }),
  );
  if (answer != 'save' && answer != 'reset') return false;
  final body = answer == 'reset'
      ? <String, dynamic>{}
      : {
          'name': name.text.trim().isEmpty ? null : name.text.trim(),
          'icon': chosen == template || chosen == 'sensor' ? null : chosen,
          'favorite': false,
          'mode': 'toggle',
        };
  try {
    await s.api.call('PUT', '/api/platform/my/devices/$deviceId/labels/${tag['key']}', body);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('out.saved'))));
    return true;
  } on ApiError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}
