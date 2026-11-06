// The automations of the home, as the web app's automationsPage (app/js/auto.js): the page
// header with "+", the Scenes | Automations switch, then one card per automation - its name, edit,
// on/off, and "if ... and ... then ..." chips with the next run. Delete is in the editor.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/kit.dart';
import 'automation_edit.dart';

/// The home new scenes and automations go to: the chosen one, else the first the user may change.
String? autoOrg(AppState s) {
  if (s.home != null) return s.home;
  final mine = s.homes.where((h) => h['personal'] == true).toList();
  if (mine.isNotEmpty) return mine.first['org_id'] as String;
  return s.homes.isEmpty ? null : s.homes.first['org_id'] as String;
}

/// The head of both tabs: h1 "auto.title" with the accent "+" button, then the .seg switch.
class AutoHeader extends StatelessWidget {
  const AutoHeader({super.key, required this.state, required this.scenes, required this.onPlus, this.onSeg});

  final AppState state;
  final bool scenes;
  final VoidCallback? onPlus;
  final ValueChanged<bool>? onSeg;            // true: scenes

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final s = state;
    Widget tab(bool forScenes, String label) {
      final on = forScenes == scenes;
      return Expanded(child: Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          onTap: on ? null : () => onSeg?.call(forScenes),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? tk.text : Colors.transparent, borderRadius: BorderRadius.circular(14)),
            child: Text(label, style: TextStyle(color: on ? tk.bg : tk.muted, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(s.t('auto.title'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tk.text))),
        Tooltip(
          message: s.t(scenes ? 'auto.new_scene' : 'auto.new'),
          child: Material(
            color: tk.accent,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onPlus,
                child: SizedBox(width: 44, height: 44, child: Icon(Icons.add_rounded, color: tk.accentInk))),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: tk.line)),
        child: Row(children: [tab(true, s.t('auto.scenes')), tab(false, s.t('auto.automations'))]),
      ),
    ]);
  }
}

/// A list of weekdays as the web app's days(): every day, "Sat to Wed", or the names.
String dayText(AppState s, Object? list) {
  final days = (list as List?)?.map((d) => (d as num).toInt()).toList();
  if (days == null || days.length == 7) return s.t('auto.every_day');
  days.sort();
  var run = true;
  for (var i = 1; i < days.length; i++) {
    if (days[i] != days[i - 1] + 1) run = false;
  }
  if (run && days.length > 2) return s.t('auto.day_range', {'from': s.t('week.${days.first}'), 'to': s.t('week.${days.last}')});
  return days.map((d) => s.t('week.$d')).join(s.i18n.rtl ? '، ' : ', ');
}

/// Chips of an automation (the web app's describe()): [tone, text] for when, and, then.
({List<(ChipTone, String)> when, List<(ChipTone, String)> and, List<String> then}) describe(
    AppState s, Map<String, dynamic> def, List<Map<String, dynamic>> views) {
  final n = s.i18n.num;
  Map<String, dynamic>? viewOf(Object? id) => views.where((v) => v['device']['device_id'] == id).firstOrNull;
  String tagName(Object? id, Object? key) {
    final v = viewOf(id);
    final tag = v == null ? null : (v['tags'] as List).cast<Map<String, dynamic>>().where((t) => t['key'] == key).firstOrNull;
    return tag == null ? '${key ?? ''}' : '${s.i18n.name(tag['display_name'])} (${v!['device']['name']})';
  }
  String value(Object? v) => v is bool ? s.t(v ? 'device.on' : 'device.off') : n(v);
  final tr = (def['trigger'] ?? const {}) as Map;
  const violet = ChipTone.violet;
  const ok = ChipTone.ok;
  final when = <(ChipTone, String)>[];
  switch (tr['type']) {
    case 'time':
      when.add((violet, s.t('auto.at_time', {'at': n(tr['at'])})));
      when.add((violet, dayText(s, tr['weekdays'])));
      if (tr['holidays'] == 'skip') when.add((violet, s.t('auto.no_holidays')));
      if (tr['holidays'] == 'only') when.add((violet, s.t('auto.only_holidays')));
    case 'interval':
      when.add((violet, s.t('auto.when_interval', {'n': n(tr['every_min'])})));
      final b = tr['between'] as List?;
      if (b != null) when.add((violet, s.t('auto.between', {'a': n(b[0]), 'b': n(b[1])})));
    case 'once':
      when.add((violet, s.t('auto.when_once', {'date': n(tr['date']), 'at': n(tr['at'])})));
    case 'value':
      when.add((ok, s.t('auto.when_value', {'tag': tagName(tr['device_id'], tr['tag']), 'op': s.t('op.${tr['op']}'),
        'value': value(tr['value'])})));
    case 'sun':
      final off = ((tr['offset_min'] ?? 0) as num).toInt();
      final event = s.t('auto.${tr['event']}');
      when.add((violet, off == 0 ? event : s.t(off < 0 ? 'auto.sun_before' : 'auto.sun_after', {'n': n(off.abs()), 'event': event})));
      if (tr['weekdays'] != null) when.add((violet, dayText(s, tr['weekdays'])));
    case 'presence':
      when.add((ok, s.t(tr['event'] == 'arrive' ? 'auto.when_arrive' : 'auto.when_leave')));
    default:
      final device = '${viewOf(tr['device_id'])?['device']['name'] ?? ''}';
      when.add((ok, tr['event'] == 'online' ? s.t('auto.when_online_x', {'device': device})
          : s.t('auto.when_offline_x', {'device': device, 'n': n((((tr['for_s'] ?? 60) as num) / 60).round())})));
  }
  if (tr['start'] != null || tr['end'] != null) {
    when.add((violet, s.t('auto.range_x', {'a': tr['start'] != null ? n(tr['start']) : '…', 'b': tr['end'] != null ? n(tr['end']) : '…'})));
  }
  final and = <(ChipTone, String)>[];
  for (final c in ((def['conditions'] as List?) ?? const []).cast<Map>()) {
    and.add((ok, s.t('auto.when_value', {'tag': tagName(c['device_id'], c['tag']), 'op': s.t('op.${c['op']}'), 'value': value(c['value'])})));
  }
  final window = def['window'] as Map?;
  final between = window?['between'] as List?;
  if (between != null) and.add((violet, s.t('auto.between', {'a': n(between[0]), 'b': n(between[1])})));
  if (window?['weekdays'] != null) and.add((violet, dayText(s, window!['weekdays'])));
  final then = [
    for (final a in ((def['actions'] as List?) ?? const []).cast<Map>())
      switch (a['type']) {
        'write' when a['value'] is bool =>
          s.t(a['value'] == true ? 'auto.turn_on_x' : 'auto.turn_off_x', {'x': tagName(a['device_id'], a['tag'])}),
        'write' => '${tagName(a['device_id'], a['tag'])} ← ${n(a['value'])}',
        'scene' => s.t('auto.run_scene'),
        'delay' => s.t('auto.wait', {'n': n(a['seconds'])}),
        'cycle' => s.t('auto.cycle_x', {'x': tagName(a['device_id'], a['tag'])}),
        _ => '${s.t('auto.notify_x', {'text': a['text'] ?? ''})} (${((a['channels'] as List?) ?? const ['email'])
            .map((c) => s.t('auto.via_$c')).join(s.i18n.rtl ? '، ' : ', ')})',
      },
  ];
  return (when: when, and: and, then: then);
}

/// "Next: 14 Aban 1405, 20:00" in Tehran time, Jalali in Persian.
String nextRun(I18n i18n, String iso) {
  final d = DateTime.tryParse(iso)?.toUtc().add(const Duration(hours: 3, minutes: 30));
  if (d == null) return iso;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${i18n.date(d)} ${i18n.num('${two(d.hour)}:${two(d.minute)}')}';
}

class AutomationsList extends StatefulWidget {
  const AutomationsList({super.key, required this.state});

  final AppState state;

  @override
  State<AutomationsList> createState() => AutomationsListState();
}

class AutomationsListState extends State<AutomationsList> {
  List<Map<String, dynamic>> autos = [];
  List<Map<String, dynamic>> views = [];
  bool loaded = false;
  String? error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final s = widget.state;
    final org = autoOrg(s);
    if (org == null) {
      if (mounted) setState(() => loaded = true);
      return;
    }
    try {
      final rows = (await s.api.call('GET', '/api/platform/organizations/$org/automations') as List).cast<Map<String, dynamic>>();
      autos = rows.where((a) => a['definition']?['timer'] != true).toList();   // timers: device page
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    try {
      views = (await s.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(org)}') as List)
          .cast<Map<String, dynamic>>();
    } on ApiError {
      views = [];
    }
    if (mounted) setState(() => loaded = true);
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

  Future<void> edit(Map<String, dynamic>? record) async {
    final org = (record?['org_id'] as String?) ?? autoOrg(widget.state);
    if (org == null) return;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => AutomationEditScreen(state: widget.state, orgId: org, record: record)));
    if (saved == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    if (autoOrg(s) == null) return Text(s.t('auto.no_home'), style: TextStyle(color: tk.muted));
    if (error != null) return Text(error!, style: TextStyle(color: tk.text));
    final active = autos.where((a) => a['enabled'] == true).length;
    final muted = TextStyle(fontSize: 13, color: tk.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(s.t('auto.active'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tk.text))),
        Text(s.t('auto.active_of', {'n': s.i18n.num(active), 'total': s.i18n.num(autos.length)}), style: muted),
      ]),
      const SizedBox(height: 14),
      if (loaded && autos.isEmpty)
        EmptyCard(icon: Icons.tune_rounded, text: s.t('auto.none')),
      for (final a in autos) ...[
        Builder(builder: (context) {
          final d = describe(s, (a['definition'] ?? const <String, dynamic>{}) as Map<String, dynamic>, views);
          final next = (a['next_runs'] as List?) ?? const [];
          return WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('${a['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: tk.text))),
              CircleIconButton(icon: Icons.edit_outlined, tooltip: s.t('auto.edit_x', {'x': a['name']}), onTap: () => edit(a)),
              const SizedBox(width: 6),
              TiSwitch(value: a['enabled'] == true,
                  onChanged: _busy.contains(a['automation_id']) ? null : (_) => _toggle(a)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(s.t('auto.if'), style: muted),
              for (final (tone, text) in d.when) WebChip(text, tone: tone),
              if (d.and.isNotEmpty) ...[
                Text(s.t('auto.and'), style: muted),
                for (final (tone, text) in d.and) WebChip(text, tone: tone),
              ],
              Text(s.t('auto.then'), style: muted),
              for (final text in d.then) WebChip(text, tone: ChipTone.accent),
            ]),
            if (next.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(s.t('auto.next', {'at': nextRun(s.i18n, '${next.first}')}), style: TextStyle(fontSize: 11, color: tk.muted)),
            ],
          ]));
        }),
        const SizedBox(height: 12),
      ],
    ]);
  }
}

/// The automations tab of the dock (the web app's #/auto/automations).
class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key, required this.state, this.onSeg});

  final AppState state;
  final ValueChanged<bool>? onSeg;

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  final _list = GlobalKey<AutomationsListState>();

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => _list.currentState?.load(),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 130), children: [
          AutoHeader(state: widget.state, scenes: false, onSeg: widget.onSeg,
              onPlus: () => _list.currentState?.edit(null)),
          const SizedBox(height: 18),
          AutomationsList(key: _list, state: widget.state),
        ]),
      );
}
