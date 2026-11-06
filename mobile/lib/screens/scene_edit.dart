// Creating, editing and deleting a scene: its name, icon (the web app's eight), and the steps -
// switch an output on or off, or wait some seconds - in order.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/widgets.dart';

const sceneIcons = ['moon', 'sun', 'out', 'arrive', 'cinema', 'power', 'home', 'bulb'];

class SceneEditScreen extends StatefulWidget {
  const SceneEditScreen({super.key, required this.state, required this.orgId, this.scene});

  final AppState state;
  final String orgId;
  final Map<String, dynamic>? scene;      // null = a new scene

  @override
  State<SceneEditScreen> createState() => _SceneEditScreenState();
}

class _SceneEditScreenState extends State<SceneEditScreen> {
  late final _name = TextEditingController(text: '${widget.scene?['name'] ?? ''}');
  late String icon = '${widget.scene?['icon'] ?? 'power'}';
  late final List<Map<String, dynamic>> steps = [
    for (final a in ((widget.scene?['actions'] as List?) ?? const []).cast<Map>()) Map<String, dynamic>.from(a),
  ];
  List<Map<String, dynamic>> views = [];

  String get _base => '/api/platform/organizations/${widget.orgId}/scenes';

  @override
  void initState() {
    super.initState();
    widget.state.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(widget.orgId)}').then((v) {
      if (mounted) setState(() => views = (v as List).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  List<Map<String, dynamic>> _outs(String? id) {
    final v = views.where((x) => x['device']['device_id'] == id).firstOrNull;
    return v == null ? [] : (v['tags'] as List).cast<Map<String, dynamic>>()
        .where((t) => t['kind'] == 'digital_output' && t['writable'] == true).toList();
  }

  List<Map<String, dynamic>> get _devices => views.where((v) => _outs(v['device']['device_id'] as String).isNotEmpty).toList();

  Future<void> _save() async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    if (!steps.any((x) => x['type'] == 'write')) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.no_actions'))));
      return;
    }
    final body = {
      'name': _name.text.trim().isEmpty ? s.t('auto.untitled') : _name.text.trim(),
      'icon': icon,
      'actions': steps,
      if (widget.scene?['sms_keyword'] != null) 'sms_keyword': widget.scene!['sms_keyword'],
    };
    try {
      if (widget.scene == null) {
        await s.api.call('POST', _base, body);
      } else {
        await s.api.call('PUT', '$_base/${widget.scene!['scene_id']}', body);
      }
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.scene_saved'))));
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete() async {
    final s = widget.state;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      content: Text(s.t('auto.delete_scene_confirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('auto.delete'))),
      ],
    ));
    if (ok != true) return;
    try {
      await s.api.call('DELETE', '$_base/${widget.scene!['scene_id']}');
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(widget.scene == null ? 'auto.new_scene' : 'auto.edit_scene')),
        actions: [
          if (widget.scene != null)
            IconButton(tooltip: s.t('auto.delete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: GlowPage(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: s.t('auto.name'), hintText: s.t('auto.scene_name_hint'))),
        const SizedBox(height: 16),
        Text(s.t('auto.icon'), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in sceneIcons)
            GestureDetector(
              onTap: () => setState(() => icon = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: icon == i ? tk.tone(i).withValues(alpha: 0.18) : tk.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: icon == i ? tk.tone(i) : tk.line),
                ),
                child: Icon(iconFor(i), color: tk.tone(i)),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Text(s.t('auto.scene_actions'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tk.text)),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++) _step(i),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _devices.isEmpty ? null : () => setState(() {
              final d = _devices.first['device']['device_id'] as String;
              steps.add({'type': 'write', 'device_id': d, 'tag': _outs(d).first['key'], 'value': true});
            }),
            icon: const Icon(Icons.add_rounded), label: Text(s.t('auto.add_action')),
          )),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() => steps.add({'type': 'delay', 'seconds': 5})),
            icon: const Icon(Icons.hourglass_bottom_rounded), label: Text(s.t('auto.wait', {'n': 5})),
          ),
        ]),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: Text(s.t('auto.save'))),
      ])),
    );
  }

  Widget _step(int i) {
    final s = widget.state;
    final x = steps[i];
    Widget body;
    if (x['type'] == 'delay') {
      body = Row(children: [
        const Icon(Icons.hourglass_bottom_rounded),
        const SizedBox(width: 8),
        Expanded(child: Slider(value: ((x['seconds'] as num).toDouble()).clamp(1, 300), min: 1, max: 300, divisions: 299,
            label: s.i18n.num((x['seconds'] as num).round()),
            onChanged: (v) => setState(() => x['seconds'] = v.round()))),
        Text(s.t('auto.wait', {'n': (x['seconds'] as num).round()})),
      ]);
    } else {
      final devices = _devices;
      body = Column(children: [
        DropdownButtonFormField<String>(
          initialValue: devices.any((v) => v['device']['device_id'] == x['device_id']) ? x['device_id'] as String : null,
          items: [for (final v in devices)
            DropdownMenuItem(value: v['device']['device_id'] as String, child: Text('${v['device']['name'] ?? v['device']['identifier']}'))],
          onChanged: (v) => setState(() {
            x['device_id'] = v;
            final outs = _outs(v);
            if (outs.isNotEmpty) x['tag'] = outs.first['key'];
          }),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _outs(x['device_id'] as String?).any((t) => t['key'] == x['tag']) ? x['tag'] as String : null,
            decoration: InputDecoration(labelText: s.t('auto.output')),
            items: [for (final t in _outs(x['device_id'] as String?))
              DropdownMenuItem(value: t['key'] as String, child: Text(s.i18n.name(t['display_name'])))],
            onChanged: (v) => setState(() => x['tag'] = v),
          )),
          TiSwitch(value: x['value'] == true, onChanged: (v) => setState(() => x['value'] = v)),
        ]),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Expanded(child: body),
          Column(children: [
            IconButton(icon: const Icon(Icons.keyboard_arrow_up_rounded), visualDensity: VisualDensity.compact,
                onPressed: i == 0 ? null : () => setState(() => steps.insert(i - 1, steps.removeAt(i)))),
            IconButton(icon: const Icon(Icons.close_rounded), visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => steps.removeAt(i))),
          ]),
        ]),
      ),
    );
  }
}
