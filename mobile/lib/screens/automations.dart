// The automations of the home: what starts them, on/off, delete; a tap edits one, the button
// makes a new one (automation_edit.dart).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import 'automation_edit.dart';

class AutomationsList extends StatefulWidget {
  const AutomationsList({super.key, required this.state});

  final AppState state;

  @override
  State<AutomationsList> createState() => _AutomationsListState();
}

class _AutomationsListState extends State<AutomationsList> {
  List<Map<String, dynamic>> autos = [];
  bool loaded = false;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = widget.state;
    final orgs = s.home != null ? [s.home!] : s.homes.map((h) => h['org_id'] as String).toList();
    final all = <Map<String, dynamic>>[];
    for (final org in orgs) {
      try {
        final rows = (await s.api.call('GET', '/api/platform/organizations/$org/automations') as List)
            .cast<Map<String, dynamic>>();
        all.addAll(rows.where((a) => a['definition']?['timer'] != true));   // timers: device page
      } on ApiError {
        // no automation rights in that home
      }
    }
    if (mounted) setState(() { autos = all; loaded = true; });
  }

  String _when(Map<String, dynamic> a) {
    final s = widget.state;
    final t = (a['definition']?['trigger'] ?? const {}) as Map;
    String value(Object? v) => v is bool ? s.t(v ? 'device.on' : 'device.off') : s.i18n.num(v);
    return switch (t['type']) {
      'time' => s.t('auto.when_time', {'days': s.t('auto.every_day'), 'at': t['at'] ?? ''}),
      'interval' => s.t('auto.when_interval', {'n': t['every_min'] ?? ''}),
      'once' => s.t('auto.when_once', {'date': t['date'] ?? '', 'at': t['at'] ?? ''}),
      'value' => s.t('auto.when_value', {'tag': t['tag'] ?? '', 'op': s.t('op.${t['op']}'), 'value': value(t['value'])}),
      'offline' => t['event'] == 'online' ? s.t('device.online') : s.t('auto.when_offline'),
      'presence' => s.t(t['event'] == 'leave' ? 'auto.when_leave' : 'auto.when_arrive'),
      'sun' => () {
          final event = s.t('auto.${t['event']}');
          final off = ((t['offset_min'] ?? 0) as num).toInt();
          return off == 0 ? event : s.t(off < 0 ? 'auto.sun_before' : 'auto.sun_after', {'n': off.abs(), 'event': event});
        }(),
      _ => '${t['type'] ?? ''}',
    };
  }

  Future<void> _toggle(Map<String, dynamic> a) async {
    final s = widget.state;
    final id = a['automation_id'] as int;
    setState(() => _busy.add(id));
    try {
      await s.api.call('PUT', '/api/platform/organizations/${a['org_id']}/automations/$id',
          {'name': a['name'], 'enabled': a['enabled'] != true, ...(a['definition'] as Map<String, dynamic>)});
      a['enabled'] = a['enabled'] != true;
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _edit(String org, Map<String, dynamic>? record) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => AutomationEditScreen(state: widget.state, orgId: org, record: record)));
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final s = widget.state;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(s.t('auto.delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('auto.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.api.call('DELETE', '/api/platform/organizations/${a['org_id']}/automations/${a['automation_id']}');
      _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final owned = s.homes.where((h) => h['role_id'] == 'customer_owner' || h['role_id'] == 'customer_member');
    final org = s.home ?? (owned.isEmpty ? null : owned.first['org_id'] as String);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (org != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.tonalIcon(
            onPressed: () => _edit(org, null),
            icon: const Icon(Icons.add_rounded),
            label: Text(s.t('auto.new')),
          ),
        ),
      if (loaded && autos.isEmpty) GlassCard(child: Text(s.t('auto.none'))),
      for (final a in autos)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              onTap: () => _edit(a['org_id'] as String, a),
              contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 6),
              title: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_when(a)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TiSwitch(value: a['enabled'] == true,
                    onChanged: _busy.contains(a['automation_id']) ? null : (_) => _toggle(a)),
                IconButton(tooltip: s.t('auto.delete'), icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _delete(a)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// The automations tab of the dock.
class AutomationsPage extends StatelessWidget {
  const AutomationsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 130), children: [
        Text(state.t('auto.automations'),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Tk.of(context).text)),
        const SizedBox(height: 16),
        AutomationsList(state: state),
      ]);
}
