// Creating, editing and deleting a group: its name and icon and its sections - named parts
// such as "chandelier" = relay 1 and 2 of the kitchen controller - each with its outputs.
// The group's devices are the devices of the chosen outputs.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/widgets.dart';

const groupIcons = ['relay', 'chandelier', 'lamp', 'bulb', 'fan', 'snow', 'curtain', 'door', 'plug', 'tv', 'water', 'home'];

class GroupEditScreen extends StatefulWidget {
  const GroupEditScreen({super.key, required this.state, required this.orgId, this.group});

  final AppState state;
  final String orgId;
  final Map<String, dynamic>? group;     // null = a new group

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _Section {
  _Section(this.name, this.icon, this.outputs);

  final TextEditingController name;
  String icon;
  final Set<String> outputs;             // "<device_id>/<key>"
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  late final _name = TextEditingController(text: '${widget.group?['name'] ?? ''}');
  late String icon = '${widget.group?['icon'] ?? 'relay'}';
  late final List<_Section> sections = [
    for (final sec in ((widget.group?['sections'] as List?) ?? const []).cast<Map>())
      _Section(TextEditingController(text: '${sec['name']}'), '${sec['icon'] ?? 'bulb'}', {
        for (final o in ((sec['outputs'] as List?) ?? const []).cast<Map>()) '${o['device_id']}/${o['key']}'
      }),
  ];
  List<Map<String, dynamic>> views = [];

  String get _base => '/api/platform/organizations/${widget.orgId}/groups';

  @override
  void initState() {
    super.initState();
    if (sections.isEmpty) sections.add(_Section(TextEditingController(), 'bulb', {}));
    widget.state.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(widget.orgId)}').then((v) {
      if (mounted) setState(() => views = (v as List).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  Future<void> _save() async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    final used = sections.where((x) => x.outputs.isNotEmpty).toList();
    if (used.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('groups.pick_one'))));
      return;
    }
    final body = {
      'name': _name.text.trim().isEmpty ? s.t('groups.untitled') : _name.text.trim(),
      'icon': icon,
      'device_ids': {for (final x in used) for (final o in x.outputs) o.split('/').first}.toList(),
      'sections': [
        for (final x in used)
          {
            'name': x.name.text.trim().isEmpty ? s.t('groups.section') : x.name.text.trim(),
            'icon': x.icon,
            'outputs': [for (final o in x.outputs) {'device_id': o.split('/').first, 'key': o.split('/').last}],
          },
      ],
      'position': widget.group?['position'] ?? 0,
    };
    try {
      if (widget.group == null) {
        await s.api.call('POST', _base, body);
      } else {
        await s.api.call('PUT', '$_base/${widget.group!['group_id']}', body);
      }
      messenger.showSnackBar(SnackBar(content: Text(s.t('groups.saved'))));
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete() async {
    final s = widget.state;
    try {
      await s.api.call('DELETE', '$_base/${widget.group!['group_id']}');
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _icons(String current, ValueChanged<String> pick) {
    final tk = Tk.of(context);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final i in groupIcons)
        GestureDetector(
          onTap: () => pick(i),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: current == i ? tk.accentSoft : tk.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: current == i ? tk.accentLine : tk.line),
            ),
            child: Icon(iconFor(i), size: 20, color: current == i ? tk.accent : tk.muted),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(widget.group == null ? 'groups.new' : 'groups.edit')),
        actions: [
          if (widget.group != null)
            IconButton(tooltip: s.t('auto.delete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: GlowPage(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        WebField(label: s.t('groups.name'), child: TextField(controller: _name, decoration: InputDecoration(hintText: s.t('groups.name_hint')))),
        const SizedBox(height: 12),
        _icons(icon, (i) => setState(() => icon = i)),
        const SizedBox(height: 20),
        Text(s.t('groups.sections'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tk.text)),
        const SizedBox(height: 8),
        for (final sec in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: WebField(label: s.t('groups.section_name'), child: TextField(controller: sec.name,
                    decoration: InputDecoration(hintText: s.t('groups.section_hint'))))),
                IconButton(icon: const Icon(Icons.close_rounded),
                    onPressed: sections.length == 1 ? null : () => setState(() => sections.remove(sec))),
              ]),
              const SizedBox(height: 8),
              _icons(sec.icon, (i) => setState(() => sec.icon = i)),
              const SizedBox(height: 8),
              Text(s.t('groups.section_outputs'), style: TextStyle(fontSize: 12, color: tk.muted)),
              for (final v in views) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${v['device']['name'] ?? v['device']['identifier']}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
                ),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in (v['tags'] as List).cast<Map<String, dynamic>>().where((t) => t['kind'] == 'digital_output'))
                    FilterChip(
                      label: Text(s.i18n.name(t['display_name'])),
                      selected: sec.outputs.contains('${v['device']['device_id']}/${t['key']}'),
                      onSelected: (on) => setState(() {
                        final id = '${v['device']['device_id']}/${t['key']}';
                        on ? sec.outputs.add(id) : sec.outputs.remove(id);
                      }),
                    ),
                ]),
              ],
            ])),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() => sections.add(_Section(TextEditingController(), 'bulb', {}))),
          icon: const Icon(Icons.add_rounded), label: Text(s.t('groups.add_section')),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: Text(s.t('common.save'))),
      ])),
    );
  }
}
