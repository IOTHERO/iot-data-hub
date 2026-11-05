// One device: its outputs (switches), settings (set-points, modes) and readings, as the product
// template describes them (GET /api/platform/my/devices/{id}/view). Refreshed every 5 s.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/widgets.dart';
import 'timers.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.state, required this.deviceId});

  final AppState state;
  final String deviceId;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  Map<String, dynamic>? view;
  String? error;
  Timer? _timer;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = widget.state;
    try {
      final v = await s.api.call('GET', '/api/platform/my/devices/${widget.deviceId}/view');
      view = v as Map<String, dynamic>;
      error = null;
    } on ApiError catch (e) {
      // offline: the device's entry in the kept home views
      final all = await s.api.call('GET', '/api/platform/my/views${s.query()}').catchError((_) => null);
      if (all is List) {
        view = all.cast<Map<String, dynamic>>().where((x) => x['device']['device_id'] == widget.deviceId).firstOrNull;
      }
      if (view == null) error = e.message;
    }
    if (mounted) setState(() {});
  }

  Future<void> _write(String key, Object? value) async {
    setState(() => _busy.add(key));
    final r = await sendCommand(context, widget.state, widget.deviceId, key, value);
    if (r != null && r['result'] == 'applied') {
      for (final t in (view!['tags'] as List)) {
        if (t['key'] == key) t['value'] = r['value'] ?? value;
      }
    }
    if (mounted) setState(() => _busy.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final v = view;
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: error == null ? const CircularProgressIndicator() : Text(error!)));
    }
    final d = v['device'] as Map<String, dynamic>;
    final tags = (v['tags'] as List).cast<Map<String, dynamic>>()
        .where((t) => (t['ui']?['visible'] ?? true) != false).toList()
      ..sort((a, b) => ((a['ui']?['order'] ?? 999) as num).compareTo((b['ui']?['order'] ?? 999) as num));
    final outputs = tags.where((t) => t['kind'] == 'digital_output').toList();
    final settings = tags.where((t) => t['kind'] == 'parameter' || (t['writable'] == true && t['kind'] != 'digital_output')).toList();
    final readings = tags.where((t) => !outputs.contains(t) && !settings.contains(t)).toList();
    final online = d['state'] == 'online';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d['name'] ?? d['identifier']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(online ? s.t('device.online') : s.t('device.offline'),
              style: TextStyle(fontSize: 12, color: online ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
          if (outputs.isNotEmpty)
            Section(icon: Icons.power_settings_new_rounded, title: s.t('sec.control'), hint: s.t('sec.control_hint'), children: [
              GridView.count(
                crossAxisCount: 4,                     // .outputs: four square tiles a row
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
                children: [for (final t in outputs) _OutputTile(state: s, tag: t, busy: _busy.contains(t['key']),
                    onTap: t['writable'] == true ? () => _write(t['key'] as String, t['value'] != true) : null)],
              ),
            ]),
          if (settings.isNotEmpty)
            Section(icon: Icons.tune_rounded, title: s.t('device.settings'), children: [
              for (final t in settings) _SettingRow(state: s, tag: t, busy: _busy.contains(t['key']),
                  write: (value) => _write(t['key'] as String, value)),
            ]),
          Section(icon: Icons.schedule_rounded, title: s.t('sec.plan'), hint: s.t('sec.plan_hint'), children: [
            TimersCard(state: s, deviceId: widget.deviceId,
                outputs: outputs.where((t) => t['writable'] == true).toList()),
          ]),
          if (readings.isNotEmpty)
            Section(icon: Icons.show_chart_rounded, title: s.t('sec.data'), hint: s.t('sec.data_hint'), children: [
              Card(child: Column(children: [
                for (final t in readings)
                  ListTile(
                    leading: Icon(iconFor(t['ui']?['icon'] as String? ?? t['icon'] as String?)),
                    title: Text(s.i18n.name(t['display_name'])),
                    trailing: Text(_value(s, t), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ])),
            ]),
        ]),
      ),
    );
  }
}

String _value(AppState s, Map<String, dynamic> t) {
  final v = t['value'];
  if (v == null) return '—';
  final states = t['states'] as Map?;
  if (states != null && states['$v'] != null) return '${states['$v']}';
  if (v is bool) return s.t(v ? 'device.on' : 'device.off');
  final unit = t['unit'] as String?;
  return '${s.i18n.num(v is num ? v.toDouble() : v)}${unit == null ? '' : ' $unit'}';
}

/// .out: a square tile; filled with the accent when on.
class _OutputTile extends StatelessWidget {
  const _OutputTile({required this.state, required this.tag, required this.busy, this.onTap});

  final AppState state;
  final Map<String, dynamic> tag;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = tag['value'] == true;
    final tk = Tk.of(context);
    final fg = on ? tk.accentInk : tk.muted;
    return Opacity(
      opacity: onTap == null ? 0.45 : (busy ? 0.6 : 1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: on ? tk.accent : tk.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: on ? Colors.transparent : tk.line2),
          boxShadow: on ? [BoxShadow(color: tk.accentSoft, blurRadius: 22, offset: const Offset(0, 8))] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: busy ? null : onTap,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(iconFor(tag['ui']?['icon'] as String? ?? tag['icon'] as String?), size: 24, color: fg),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(state.i18n.name(tag['display_name']), maxLines: 2, textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: fg, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.state, required this.tag, required this.busy, required this.write});

  final AppState state;
  final Map<String, dynamic> tag;
  final bool busy;
  final ValueChanged<Object?> write;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final states = (tag['states'] as Map?)?.map((k, v) => MapEntry(int.parse('$k'), '$v'));
    final writable = tag['writable'] == true && !busy;
    Widget control;
    if (states != null) {
      control = Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in states.entries)
          ChoiceChip(label: Text(e.value), selected: tag['value'] == e.key, onSelected: writable ? (_) => write(e.key) : null),
      ]);
    } else if (tag['data_type'] == 'bool') {
      control = TiSwitch(value: tag['value'] == true, onChanged: writable ? (v) => write(v) : null);
    } else {
      final value = (tag['value'] as num?)?.toDouble();
      final min = (tag['min'] as num?)?.toDouble() ?? 0;
      final max = (tag['max'] as num?)?.toDouble() ?? 100;
      control = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(onPressed: writable && value != null && value > min ? () => write(value - 1) : null,
            icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 72, child: Text(_value(s, tag), textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        IconButton.filledTonal(onPressed: writable && value != null && value < max ? () => write(value + 1) : null,
            icon: const Icon(Icons.add_rounded)),
      ]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.i18n.name(tag['display_name']), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          control,
        ]),
      ),
    ).withBottom(10);
  }
}

extension on Widget {
  Widget withBottom(double gap) => Padding(padding: EdgeInsets.only(bottom: gap), child: this);
}
