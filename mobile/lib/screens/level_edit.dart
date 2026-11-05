// An access level of a home (the web app's level editor): its name, the ticked permissions,
// which outputs it covers (all, or chosen ones; rooms and groups already in it are kept), the
// hours it may operate in, and "only the scenarios he made". Enforced by the hub.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';

const levelPermissions = [
  'device.view', 'device.operate', 'scene.run', 'automation.manage', 'timer.manage',
  'energy.view', 'device.share', 'org.members', 'home.settings', 'ticket.manage',
];

class LevelEditScreen extends StatefulWidget {
  const LevelEditScreen({super.key, required this.state, required this.orgId, this.level});

  final AppState state;
  final String orgId;
  final Map<String, dynamic>? level;          // null = a new level

  @override
  State<LevelEditScreen> createState() => _LevelEditScreenState();
}

class _LevelEditScreenState extends State<LevelEditScreen> {
  late final _name = TextEditingController(text: '${widget.level?['name'] ?? ''}');
  late final Set<String> perms = {...((widget.level?['permissions'] as List?) ?? const ['device.view', 'device.operate']).cast<String>(), 'device.view'};
  late final Map<String, dynamic> scope = Map<String, dynamic>.from((widget.level?['scope'] as Map?) ?? const {});
  late final Set<String> outputs = {
    for (final o in ((scope['outputs'] as List?) ?? const []).cast<Map>()) '${o['device_id']}/${o['key']}'
  };
  late bool limited = outputs.isNotEmpty || ((scope['rooms'] as List?)?.isNotEmpty ?? false) ||
      ((scope['groups'] as List?)?.isNotEmpty ?? false);
  late bool hoursOn = widget.level?['schedule'] != null;
  late Set<int> days = {...(((widget.level?['schedule'] as Map?)?['weekdays'] as List?) ?? const []).cast<int>()};
  late String from = '${(widget.level?['schedule'] as Map?)?['from'] ?? '08:00'}';
  late String to = '${(widget.level?['schedule'] as Map?)?['to'] ?? '18:00'}';
  late bool ownOnly = widget.level?['own_only'] == true;
  List<Map<String, dynamic>> views = [];
  bool _busy = false;

  String get _base => '/api/platform/organizations/${widget.orgId}/levels';

  @override
  void initState() {
    super.initState();
    widget.state.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(widget.orgId)}').then((v) {
      if (mounted) setState(() => views = (v as List).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  Future<String?> _time(String now) async {
    final p = now.split(':');
    final t = await showTimePicker(context: context,
        initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    return t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    String? problem;
    if (_name.text.trim().isEmpty) problem = s.t('levels.need_name');
    if (limited && outputs.isEmpty && ((scope['rooms'] as List?)?.isEmpty ?? true) &&
        ((scope['groups'] as List?)?.isEmpty ?? true)) {
      problem = s.t('levels.need_scope');
    }
    if (hoursOn && days.isEmpty) problem = s.t('levels.need_day');
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final body = {
      'name': _name.text.trim(),
      'permissions': levelPermissions.where(perms.contains).toList(),
      'scope': limited
          ? {
              'rooms': scope['rooms'] ?? const [],
              'groups': scope['groups'] ?? const [],
              'outputs': [
                for (final o in outputs) {'device_id': o.split('/').first, 'key': o.split('/').last}
              ],
            }
          : {'rooms': const [], 'groups': const [], 'outputs': const []},
      'schedule': hoursOn ? {'weekdays': days.toList()..sort(), 'from': from, 'to': to} : null,
      'own_only': ownOnly,
    };
    setState(() => _busy = true);
    try {
      if (widget.level == null) {
        await s.api.call('POST', _base, body);
      } else {
        await s.api.call('PUT', '$_base/${widget.level!['role_id']}', body);
      }
      messenger.showSnackBar(SnackBar(content: Text(s.t('common.saved'))));
      if (mounted) Navigator.pop(context, true);
      return;
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final s = widget.state;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      content: Text(s.t('levels.delete_confirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('auto.delete'))),
      ],
    ));
    if (ok != true) return;
    try {
      await s.api.call('DELETE', '$_base/${widget.level!['role_id']}');
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(widget.level == null ? 'levels.new' : 'levels.edit')),
        actions: [
          if (widget.level != null)
            IconButton(tooltip: s.t('auto.delete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: s.t('levels.name'), hintText: s.t('levels.name_hint'))),
        const SizedBox(height: 20),
        Text(s.t('levels.ticks'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        Card(child: Column(children: [
          for (final p in levelPermissions)
            CheckboxListTile(
              value: perms.contains(p),
              title: Text(s.t('perm.${p.replaceAll('.', '_')}')),
              onChanged: p == 'device.view' ? null : (v) => setState(() => v == true ? perms.add(p) : perms.remove(p)),
            ),
        ])),
        const SizedBox(height: 20),
        Text(s.t('levels.scope'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        RadioGroup<bool>(
          groupValue: limited,
          onChanged: (v) => setState(() => limited = v ?? limited),
          child: Column(children: [
            RadioListTile(value: false, title: Text(s.t('levels.scope_all'))),
            RadioListTile(value: true, title: Text(s.t('levels.scope_pick'))),
          ]),
        ),
        if (limited)
          Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final v in views) ...[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                child: Text('${v['device']['name'] ?? v['device']['identifier']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final t in (v['tags'] as List).cast<Map<String, dynamic>>().where((t) => t['kind'] == 'digital_output'))
                CheckboxListTile(
                  dense: true,
                  value: outputs.contains('${v['device']['device_id']}/${t['key']}'),
                  title: Text(s.i18n.name(t['display_name'])),
                  onChanged: (on) => setState(() {
                    final id = '${v['device']['device_id']}/${t['key']}';
                    on == true ? outputs.add(id) : outputs.remove(id);
                  }),
                ),
            ],
          ])),
        const SizedBox(height: 12),
        SwitchListTile(
          value: hoursOn,
          title: Text(s.t('levels.hours_on')),
          subtitle: Text(s.t('levels.hours_help')),
          onChanged: (v) => setState(() => hoursOn = v),
        ),
        if (hoursOn) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 0; d < 7; d++)
              FilterChip(label: Text(s.t('week.$d')), selected: days.contains(d),
                  onSelected: (on) => setState(() => on ? days.add(d) : days.remove(d))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async {
              final t = await _time(from);
              if (t != null) setState(() => from = t);
            }, child: Text(s.i18n.num(from)))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('—')),
            Expanded(child: OutlinedButton(onPressed: () async {
              final t = await _time(to);
              if (t != null) setState(() => to = t);
            }, child: Text(s.i18n.num(to)))),
          ]),
        ],
        const SizedBox(height: 8),
        SwitchListTile(value: ownOnly, title: Text(s.t('levels.own_only')), onChanged: (v) => setState(() => ownOnly = v)),
        const SizedBox(height: 18),
        FilledButton(onPressed: _busy ? null : _save, child: Text(s.t('common.save'))),
      ]),
    );
  }
}
