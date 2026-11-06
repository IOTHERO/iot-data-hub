// Arranging the person's own home section (the web app's customEditor): its name, the outputs,
// sensors and scenes picked from any module of the home, dragged into the order they like.
// Kept on this phone (AppState.customItems).

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';

class CustomEditScreen extends StatefulWidget {
  const CustomEditScreen({super.key, required this.state, required this.views, required this.scenes});

  final AppState state;
  final List<Map<String, dynamic>> views;
  final List<Map<String, dynamic>> scenes;

  @override
  State<CustomEditScreen> createState() => _CustomEditScreenState();
}

String customId(Map<String, dynamic> x) =>
    x['type'] == 'scene' ? 'scene/${x['scene_id']}' : '${x['type']}/${x['device_id']}/${x['key']}';

class _CustomEditScreenState extends State<CustomEditScreen> {
  late final _title = TextEditingController(text: widget.state.customTitle);
  late final List<Map<String, dynamic>> chosen = widget.state.customItems;

  AppState get s => widget.state;

  String _label(Map<String, dynamic> x) {
    if (x['type'] == 'scene') {
      return '${widget.scenes.where((sc) => '${sc['scene_id']}' == '${x['scene_id']}').firstOrNull?['name'] ?? '—'}';
    }
    final v = widget.views.where((v) => v['device']['device_id'] == x['device_id']).firstOrNull;
    final t = (v?['tags'] as List?)?.cast<Map<String, dynamic>>().where((t) => t['key'] == x['key']).firstOrNull;
    return t == null ? '—' : '${s.i18n.name(t['display_name'])} · ${v!['device']['name']}';
  }

  IconData _icon(Map<String, dynamic> x) => x['type'] == 'scene' ? Icons.star_rounded
      : x['type'] == 'sensor' ? Icons.sensors_rounded : Icons.power_settings_new_rounded;

  void _toggle(Map<String, dynamic> x) => setState(() {
        final i = chosen.indexWhere((c) => customId(c) == customId(x));
        i >= 0 ? chosen.removeAt(i) : chosen.add(x);
      });

  Widget _chip(Map<String, dynamic> x, String label, IconData icon) {
    final on = chosen.any((c) => customId(c) == customId(x));
    return FilterChip(
      avatar: Icon(on ? Icons.check_rounded : icon, size: 16),
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => _toggle(x),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('custom.edit')), actions: [
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            await s.setCustom(_title.text.trim(), chosen);
            nav.pop(true);
          },
          child: Text(s.t('common.save')),
        ),
      ]),
      body: GlowPage(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        WebField(label: s.t('custom.title'), child: TextField(controller: _title, maxLength: 30,
            decoration: InputDecoration(hintText: s.t('custom.title_default')))),
        const SizedBox(height: 8),
        RowLabel(s.t('custom.order')),
        Text(s.t('custom.order_help'), style: TextStyle(fontSize: 12, color: tk.muted)),
        const SizedBox(height: 8),
        if (chosen.isEmpty) Text(s.t('custom.none_chosen'), style: TextStyle(color: tk.muted)),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => setState(() => chosen.insert(to, chosen.removeAt(from))),
          children: [
            for (final (i, x) in chosen.indexed)
              Container(
                key: ValueKey(customId(x)),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tk.line)),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Semantics(
                      label: '${s.t('layout.drag')}: ${_label(x)}',
                      child: Padding(padding: const EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle_rounded, color: tk.muted)),
                    ),
                  ),
                  Icon(_icon(x), size: 18, color: tk.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_label(x), style: TextStyle(fontSize: 13, color: tk.text))),
                  IconButton(tooltip: s.t('auto.delete'), icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => chosen.removeAt(i))),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 18),
        RowLabel(s.t('custom.pick')),
        if (widget.scenes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(s.t('auto.scenes'), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final sc in widget.scenes)
              _chip({'type': 'scene', 'scene_id': sc['scene_id']}, '${sc['name']}', Icons.star_outline_rounded),
          ]),
        ],
        for (final v in widget.views) ...[
          if ((v['tags'] as List).any((t) => t['data_type'] == 'bool')) ...[
            const SizedBox(height: 12),
            Text('${v['device']['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in (v['tags'] as List).cast<Map<String, dynamic>>().where((t) => t['data_type'] == 'bool'))
                _chip({'type': t['writable'] == true ? 'out' : 'sensor', 'device_id': v['device']['device_id'], 'key': t['key']},
                    s.i18n.name(t['display_name']),
                    t['writable'] == true ? Icons.power_settings_new_rounded : Icons.sensors_rounded),
            ]),
          ],
        ],
      ])),
    );
  }
}
