// One group of devices, as the web app's groupPage (app/js/more.js): the header with the device
// count and the gear (the group editor), tabs to see all of it or one device or one model, the
// group's named parts each with a master switch, the other outputs, all on / all off and the values.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/live.dart';
import '../ui/kit.dart';
import '../ui/outputs.dart';
import '../ui/widgets.dart';
import 'device.dart';
import 'group_edit.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.state, required this.orgId, required this.groupId});

  final AppState state;
  final String orgId;
  final int groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

typedef _Out = ({Map<String, dynamic> v, Map<String, dynamic> x});

class _GroupScreenState extends State<GroupScreen> {
  Map<String, dynamic>? group;
  List<Map<String, dynamic>> views = [];
  String? error;
  bool loaded = false;
  bool editing = false;
  final Set<String> _busy = {};
  late String filter = widget.state.store.get('app.group.${widget.groupId}') ?? 'all';
  StreamSubscription<LiveEvent>? _live;
  Timer? _timer;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _load();
    _live = s.live.events.listen((e) {
      final changed = e.type == 'samples' ? applySamples(views, e.data) : applyStatus(views, e.data);
      if (changed && mounted) setState(() {});
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _live?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final org = widget.orgId;
      final groups = (await s.api.call('GET', '/api/platform/organizations/$org/groups') as List).cast<Map<String, dynamic>>();
      group = groups.where((g) => '${g['group_id']}' == '${widget.groupId}').firstOrNull;
      final all = (await s.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(org)}') as List)
          .cast<Map<String, dynamic>>();
      final ids = ((group?['device_ids'] as List?) ?? const []).cast<String>();
      views = all.where((v) => ids.contains(v['device']['device_id'])).toList();
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => loaded = true);
  }

  bool _isOut(Map<String, dynamic> x) =>
      x['writable'] == true && (x['data_type'] == 'bool' || x['kind'] == 'digital_output');

  Future<void> _write(_Out o, bool value) async {
    final id = '${o.v['device']['device_id']}';
    final key = '${o.x['key']}';
    setState(() => _busy.add('$id/$key'));
    final r = await sendCommand(context, s, id, key, value, offline: o.v['device']['state'] != 'online');
    if (r != null && r['result'] == 'applied') o.x['value'] = r['value'] ?? value;
    if (mounted) setState(() => _busy.remove('$id/$key'));
  }

  Future<void> _all(List<_Out> outs, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    await Future.wait([for (final o in outs.where((o) => (o.x['value'] == true) != value)) _write(o, value)]);
    messenger.showSnackBar(SnackBar(content: Text(s.t('device.done'))));
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => GroupEditScreen(state: s, orgId: widget.orgId, group: group)));
    if (changed == true) _load();
  }

  Widget _tile(_Out o, {String? sub}) {
    final id = '${o.v['device']['device_id']}';
    final offline = o.v['device']['state'] != 'online';
    final tile = OutputTile(
      state: s, tag: o.x, busy: _busy.contains('$id/${o.x['key']}'), editing: editing,
      write: editing ? (_) async { if (await showLabelSheet(context, s, id, o.x)) _load(); }
          : offline ? null : (on) => _write(o, on),
      push: editing ? () async { if (await showLabelSheet(context, s, id, o.x)) _load(); }
          : offline ? null : () async { await pulseOutput(context, s, id, o.x); _load(); },
    );
    if (sub == null) return tile;
    return Column(children: [
      Expanded(child: tile),
      const SizedBox(height: 2),
      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Tk.of(context).muted)),
    ]);
  }

  Widget _grid(List<_Out> outs, {bool subs = false}) => GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: subs ? 0.7 : 0.82,
        children: [for (final o in outs) _tile(o, sub: subs ? '${o.v['device']['name']}' : null)],
      );

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final g = group;
    if (g == null) {
      return WebPage(title: '', children: [
        if (!loaded) const Center(child: CircularProgressIndicator())
        else Text(error ?? s.t('groups.gone'), style: TextStyle(color: tk.muted)),
      ]);
    }
    final models = <String, String>{for (final v in views) '${v['device']['product_id']}': '${v['product'] ?? ''}'};
    final chips = <(String, String)>[
      ('all', s.t('groups.combined')),
      for (final v in views) ('device:${v['device']['device_id']}', '${v['device']['name']}'),
      if (models.length > 1) for (final e in models.entries) ('model:${e.key}', s.t('groups.model', {'name': e.value})),
    ];
    if (!chips.any((c) => c.$1 == filter)) filter = 'all';
    final shown = views.where((v) => filter == 'all' || filter == 'device:${v['device']['device_id']}'
        || filter == 'model:${v['device']['product_id']}').toList();
    final combined = shown.length > 1;
    final outs = <_Out>[
      for (final v in shown)
        for (final x in (v['tags'] as List).cast<Map<String, dynamic>>().where(_isOut)) (v: v, x: x),
    ];
    final reads = <_Out>[
      for (final v in shown)
        for (final x in (v['tags'] as List).cast<Map<String, dynamic>>().where((x) => x['writable'] != true)) (v: v, x: x),
    ];
    String ref(Object? d, Object? k) => '$d:$k';
    final byRef = {for (final o in outs) ref(o.v['device']['device_id'], o.x['key']): o};
    final sections = [
      for (final sec in ((g['sections'] as List?) ?? const []).cast<Map<String, dynamic>>())
        (sec: sec, outs: [
          for (final o in ((sec['outputs'] as List?) ?? const []).cast<Map>())
            if (byRef[ref(o['device_id'], o['key'])] != null) byRef[ref(o['device_id'], o['key'])]!,
        ]),
    ].where((x) => filter == 'all' || x.outs.isNotEmpty).toList();
    final inParts = {for (final x in sections) for (final o in x.outs) ref(o.v['device']['device_id'], o.x['key'])};
    final rest = outs.where((o) => !inParts.contains(ref(o.v['device']['device_id'], o.x['key']))).toList();
    final onCount = outs.where((o) => o.x['value'] == true).length;
    final online = views.where((v) => v['device']['state'] == 'online').length;
    final h2 = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text);
    Widget twoButtons() => Row(children: [
          Expanded(child: WebButton(s.t('device.all_on'), kind: BtnKind.primary, onTap: () => _all(outs, true))),
          const SizedBox(width: 10),
          Expanded(child: WebButton(s.t('device.all_off_btn'), onTap: () => _all(outs, false))),
        ]);
    return WebPage(
      title: '${g['name']}',
      sub: s.t('groups.count', {'n': s.i18n.num(views.length), 'on': s.i18n.num(online)}),
      right: CircleIconButton(icon: Icons.settings_outlined, tooltip: s.t('groups.edit'), onTap: _edit),
      children: [
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (key, label) in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: WebTab(label, on: filter == key, onTap: () {
                setState(() => filter = key);
                s.store.set('app.group.${widget.groupId}', key);
              }),
            ),
        ])),
        if (outs.isNotEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(s.t('groups.sections'), style: h2)),
              WebChip(s.t(editing ? 'out.edit_done' : 'out.edit_mode'), icon: editing ? Icons.check_rounded : Icons.edit_outlined,
                  tone: editing ? ChipTone.accent : ChipTone.plain, onTap: () => setState(() => editing = !editing)),
            ]),
            if (editing) ...[
              const SizedBox(height: 8),
              Text(s.t('out.edit_hint'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
            ],
            for (final x in sections) ...[
              const SizedBox(height: 14),
              _SectionCard(state: s, sec: x.sec, outs: x.outs, grid: _grid(x.outs),
                  onEdit: _edit, onAll: (on) => _all(x.outs, on)),
            ],
            const SizedBox(height: 14),
            WebButton(s.t('groups.add_section'), icon: Icons.add_rounded, kind: BtnKind.dashed, block: true, onTap: _edit),
          ]),
        if (rest.isNotEmpty)
          Container(              // .card.big-card
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: tk.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(s.t(sections.isNotEmpty ? 'groups.others' : 'device.outputs'), style: h2)),
                Text(s.t('device.on_count', {'n': s.i18n.num(onCount), 'total': s.i18n.num(outs.length)}),
                    style: TextStyle(fontSize: 13, color: tk.accent)),
              ]),
              const SizedBox(height: 16),
              _grid(rest, subs: combined),
              const SizedBox(height: 16),
              twoButtons(),
            ]),
          ),
        if (outs.isNotEmpty && rest.isEmpty) twoButtons(),
        if (reads.isNotEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('device.readings'), style: h2),
            const SizedBox(height: 12),
            for (final o in reads) ...[
              Reading(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DeviceScreen(state: s, deviceId: '${o.v['device']['device_id']}'))),
                start: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.i18n.name(o.x['display_name']), style: TextStyle(color: tk.muted)),
                  if (combined) Text('${o.v['device']['name']}', style: TextStyle(fontSize: 11, color: tk.muted)),
                ]),
                end: Text.rich(TextSpan(children: [
                  TextSpan(text: o.x['value'] == null ? '—' : o.x['value'] is bool
                      ? s.t(o.x['value'] == true ? 'device.on' : 'device.off') : s.i18n.num(o.x['value']),
                      style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
                  TextSpan(text: ' ${o.x['unit'] ?? ''}', style: TextStyle(fontSize: 12, color: tk.muted)),
                ])),
              ),
              const SizedBox(height: 10),
            ],
          ]),
        if (outs.isEmpty && reads.isEmpty) Text(s.t('groups.empty'), style: TextStyle(color: tk.muted)),
      ],
    );
  }
}

/// .section-card: the part's icon and name (a touch edits it), how many are on, a master switch,
/// then its outputs; lit while any is on.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.state, required this.sec, required this.outs, required this.grid,
      required this.onEdit, required this.onAll});

  final AppState state;
  final Map<String, dynamic> sec;
  final List<_Out> outs;
  final Widget grid;
  final VoidCallback onEdit;
  final ValueChanged<bool> onAll;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final tk = Tk.of(context);
    final on = outs.where((o) => o.x['value'] == true).length;
    final canUse = outs.any((o) => o.v['device']['state'] == 'online');
    return GlassCard(
      lit: on > 0,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(15),
            child: Row(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: on > 0 ? tk.accent : tk.surface2, borderRadius: BorderRadius.circular(15),
                      boxShadow: on > 0 ? [BoxShadow(color: tk.accentGlow, blurRadius: 18)] : null),
                  child: Icon(iconFor('${sec['icon'] ?? 'bulb'}'), color: on > 0 ? tk.accentInk : tk.muted)),
              const SizedBox(width: 12),
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sec['name']}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tk.text)),
                Text(outs.isNotEmpty && on == outs.length ? s.t('device.all_on_state')
                    : s.t('device.on_count', {'n': s.i18n.num(on), 'total': s.i18n.num(outs.length)}),
                    style: TextStyle(fontSize: 11, color: tk.muted)),
              ])),
            ]),
          )),
          TiSwitch(value: on > 0, onChanged: canUse ? (_) => onAll(on == 0) : null),
        ]),
        const SizedBox(height: 14),
        outs.isEmpty ? Text(s.t('groups.section_empty'), style: TextStyle(fontSize: 11, color: tk.muted)) : grid,
      ]),
    );
  }
}
