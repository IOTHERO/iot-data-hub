// Creating and editing an automation: name, what starts it (time on chosen weekdays, a device's
// value, every N minutes, someone arriving or leaving) and what it switches. Anything this
// screen does not edit (conditions, window, other triggers such as sunrise) is kept as it was.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';

class AutomationEditScreen extends StatefulWidget {
  const AutomationEditScreen({super.key, required this.state, required this.orgId, this.record});

  final AppState state;
  final String orgId;
  final Map<String, dynamic>? record;       // null = a new automation

  @override
  State<AutomationEditScreen> createState() => _AutomationEditScreenState();
}

class _Action {
  _Action(this.deviceId, this.tag, this.value);

  String deviceId;
  String tag;
  bool value;
}

class _AutomationEditScreenState extends State<AutomationEditScreen> {
  late final Map<String, dynamic> def = Map<String, dynamic>.from(
      (widget.record?['definition'] as Map?) ?? const {});
  late final _name = TextEditingController(text: '${widget.record?['name'] ?? ''}');
  List<Map<String, dynamic>> views = [];

  // the trigger being edited
  late String kind = _kindOf(def['trigger'] as Map?);
  String at = '08:00';
  Set<int> weekdays = {};
  int everyMin = 15;
  String presence = 'arrive';
  String? valueDevice;
  String? valueTag;
  String op = 'gt';
  final _threshold = TextEditingController();
  final List<_Action> actions = [];
  bool _busy = false;

  static const _kinds = ['time', 'value', 'interval', 'presence'];

  String _kindOf(Map? t) => t == null ? 'time' : (_kinds.contains(t['type']) ? t['type'] as String : 'keep');

  @override
  void initState() {
    super.initState();
    final t = (def['trigger'] as Map?) ?? const {};
    at = '${t['at'] ?? '08:00'}';
    weekdays = {...((t['weekdays'] as List?) ?? const []).cast<int>()};
    everyMin = (t['every_min'] as int?) ?? 15;
    presence = '${t['event'] ?? 'arrive'}' == 'leave' ? 'leave' : 'arrive';
    valueDevice = t['device_id'] as String?;
    valueTag = t['tag'] as String?;
    op = '${t['op'] ?? 'gt'}';
    if (t['value'] != null) _threshold.text = '${t['value']}';
    for (final a in ((def['actions'] as List?) ?? const []).cast<Map>()) {
      if (a['type'] == 'write' && a['value'] is bool) {
        actions.add(_Action('${a['device_id']}', '${a['tag']}', a['value'] as bool));
      }
    }
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      views = (await widget.state.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(widget.orgId)}')
              as List).cast<Map<String, dynamic>>();
    } on ApiError {
      views = [];
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _tags(String? deviceId, {required bool outputs}) {
    final v = views.where((x) => x['device']['device_id'] == deviceId).firstOrNull;
    if (v == null) return [];
    return (v['tags'] as List).cast<Map<String, dynamic>>().where((t) => outputs
        ? t['kind'] == 'digital_output' && t['writable'] == true
        : t['kind'] != 'digital_output').toList();
  }

  String _deviceName(Map<String, dynamic> v) => '${v['device']['name'] ?? v['device']['identifier']}';

  Map<String, dynamic> _trigger() {
    final keep = Map<String, dynamic>.from((def['trigger'] as Map?) ?? const {});
    return switch (kind) {
      'time' => {'type': 'time', 'at': at, if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort()},
      'interval' => {'type': 'interval', 'every_min': everyMin},
      'presence' => {'type': 'presence', 'event': presence},
      'value' => {
          'type': 'value', 'device_id': valueDevice, 'tag': valueTag, 'op': op,
          'value': num.tryParse(_threshold.text.trim()) ??
              (_threshold.text.trim() == 'true' ? true : (_threshold.text.trim() == 'false' ? false : _threshold.text.trim())),
        },
      _ => keep,
    };
  }

  Future<void> _save() async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    if (actions.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.no_actions'))));
      return;
    }
    final others = ((def['actions'] as List?) ?? const [])
        .cast<Map>().where((a) => !(a['type'] == 'write' && a['value'] is bool)).toList();   // kept
    final body = {
      ...def,
      'name': _name.text.trim().isEmpty ? s.t('auto.untitled') : _name.text.trim(),
      'enabled': widget.record?['enabled'] ?? true,
      'trigger': _trigger(),
      'actions': [
        for (final a in actions) {'type': 'write', 'device_id': a.deviceId, 'tag': a.tag, 'value': a.value},
        ...others,
      ],
    };
    setState(() => _busy = true);
    try {
      final base = '/api/platform/organizations/${widget.orgId}/automations';
      if (widget.record == null) {
        await s.api.call('POST', base, body);
      } else {
        await s.api.call('PUT', '$base/${widget.record!['automation_id']}', body);
      }
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.saved'))));
      if (mounted) Navigator.pop(context, true);
      return;
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Run the saved actions once now, whatever the trigger (the web app's "test").
  Future<void> _test() async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await s.api.call('POST',
          '/api/platform/organizations/${widget.orgId}/automations/${widget.record!['automation_id']}/test') as Map;
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.tested', {'n': s.i18n.num(((r['detail'] as List?) ?? const []).length)}))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete() async {
    final s = widget.state;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      content: Text(s.t('auto.delete_confirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('auto.delete'))),
      ],
    ));
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.api.call('DELETE', '/api/platform/organizations/${widget.orgId}/automations/${widget.record!['automation_id']}');
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickTime() async {
    final parts = at.split(':');
    final picked = await showTimePicker(context: context,
        initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts.last) ?? 0));
    if (picked != null) {
      setState(() => at = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final devices = views.where((v) => _tags(v['device']['device_id'] as String, outputs: true).isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(widget.record == null ? 'auto.new' : 'auto.edit')),
        actions: [
          if (widget.record != null)
            TextButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.play_arrow_rounded),
                label: Text(s.t('auto.test'))),
          if (widget.record != null)
            IconButton(tooltip: s.t('auto.delete'), icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _busy ? null : _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: s.t('auto.name'))),
        const SizedBox(height: 22),
        Text(s.t('auto.if'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: kind,
          items: [
            for (final k in _kinds) DropdownMenuItem(value: k, child: Text(s.t('auto.kind_$k'))),
            if (kind == 'keep') DropdownMenuItem(value: 'keep', child: Text(s.t('auto.kind_${(def['trigger'] as Map)['type']}'))),
          ],
          onChanged: (v) => setState(() => kind = v ?? kind),
        ),
        const SizedBox(height: 12),
        if (kind == 'time') ...[
          OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded),
              label: Text(s.t('auto.at_time', {'at': at}))),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 0; d < 7; d++)
              WebTab(s.t('week.$d'), on: weekdays.contains(d),
                  onTap: () => setState(() => weekdays.contains(d) ? weekdays.remove(d) : weekdays.add(d))),
          ]),
          Text(weekdays.isEmpty ? s.t('auto.every_day') : '', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ],
        if (kind == 'interval') ...[
          Text('${s.t('auto.every_min')}: ${s.i18n.num(everyMin)}'),
          Slider(value: everyMin.toDouble(), min: 1, max: 240, divisions: 239,
              onChanged: (v) => setState(() => everyMin = v.round())),
        ],
        if (kind == 'presence')
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'arrive', label: Text(s.t('auto.when_arrive'))),
              ButtonSegment(value: 'leave', label: Text(s.t('auto.when_leave'))),
            ],
            selected: {presence},
            onSelectionChanged: (v) => setState(() => presence = v.first),
          ),
        if (kind == 'value') ...[
          DropdownButtonFormField<String>(
            initialValue: views.any((v) => v['device']['device_id'] == valueDevice) ? valueDevice : null,
            hint: Text(s.t('auto.value_of')),
            items: [for (final v in views) DropdownMenuItem(value: v['device']['device_id'] as String, child: Text(_deviceName(v)))],
            onChanged: (v) => setState(() { valueDevice = v; valueTag = null; }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _tags(valueDevice, outputs: false).any((t) => t['key'] == valueTag) ? valueTag : null,
            items: [for (final t in _tags(valueDevice, outputs: false))
              DropdownMenuItem(value: t['key'] as String, child: Text(s.i18n.name(t['display_name'])))],
            onChanged: (v) => setState(() => valueTag = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: op,
              decoration: InputDecoration(labelText: s.t('auto.op')),
              items: [for (final o in ['gt', 'lt', 'eq', 'ne', 'ge', 'le'])
                DropdownMenuItem(value: o, child: Text(s.t('op.$o')))],
              onChanged: (v) => setState(() => op = v ?? op),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _threshold, textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('auto.threshold')))),
          ]),
        ],
        const SizedBox(height: 24),
        Text(s.t('auto.then'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (views.isNotEmpty && devices.isEmpty) Text(s.t('auto.no_outputs')),
        for (final a in actions)
          Card(child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              DropdownButtonFormField<String>(
                initialValue: devices.any((v) => v['device']['device_id'] == a.deviceId) ? a.deviceId : null,
                items: [for (final v in devices) DropdownMenuItem(value: v['device']['device_id'] as String, child: Text(_deviceName(v)))],
                onChanged: (v) => setState(() {
                  a.deviceId = v ?? a.deviceId;
                  final outs = _tags(a.deviceId, outputs: true);
                  if (outs.isNotEmpty) a.tag = outs.first['key'] as String;
                }),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  initialValue: _tags(a.deviceId, outputs: true).any((t) => t['key'] == a.tag) ? a.tag : null,
                  decoration: InputDecoration(labelText: s.t('auto.output')),
                  items: [for (final t in _tags(a.deviceId, outputs: true))
                    DropdownMenuItem(value: t['key'] as String, child: Text(s.i18n.name(t['display_name'])))],
                  onChanged: (v) => setState(() => a.tag = v ?? a.tag),
                )),
                const SizedBox(width: 8),
                TiSwitch(value: a.value, onChanged: (v) => setState(() => a.value = v)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => actions.remove(a))),
              ]),
            ]),
          )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: devices.isEmpty ? null : () => setState(() {
            final d = devices.first;
            actions.add(_Action(d['device']['device_id'] as String,
                _tags(d['device']['device_id'] as String, outputs: true).first['key'] as String, true));
          }),
          icon: const Icon(Icons.add_rounded),
          label: Text(s.t('auto.add_action')),
        ),
        const SizedBox(height: 26),
        FilledButton(onPressed: _busy ? null : _save, child: Text(s.t('auto.save'))),
      ]),
    );
  }
}
