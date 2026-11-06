// A home's security scenarios at the top of the scenes page, as the web app's security.js:
// burglar alarm (away), night (at home: doors and windows only), fire alarm, connection loss.
// Each is switched on or off; a tripped sensor is an alarm only while its scenario is on. The
// alarms go to the home's people, picked here by name: their numbers are kept on the home's
// access page (members.dart), with each member, where they are added and changed.
// Zones and the siren are not fixed pins: a zone is any input of any module given a type on its
// device page; the siren is whichever outputs of whichever modules the home picks here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/live.dart';
import '../screens/members.dart';
import '../screens/device.dart';
import 'kit.dart';

const _red = Color(0xFFFF4D5E);
const _scenarios = [
  ('burglar', Icons.lock_rounded, ['motion', 'magnet']),
  ('night', Icons.nightlight_round, ['magnet']),
  ('fire', Icons.local_fire_department_rounded, ['smoke']),
  ('offline', Icons.wifi_off_rounded, <String>[]),
];

class SecurityCard extends StatefulWidget {
  const SecurityCard({super.key, required this.state, required this.orgId});

  final AppState state;
  final String orgId;

  @override
  State<SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends State<SecurityCard> {
  Map<String, dynamic>? data;
  final Set<String> _busy = {};
  StreamSubscription<LiveEvent>? _live;

  AppState get s => widget.state;
  String get _path => '/api/platform/organizations/${widget.orgId}/security';

  @override
  void initState() {
    super.initState();
    _load();
    _live = s.live.events.listen((e) {      // switched on another phone of the home
      if (e.type == 'security' && e.data is Map && e.data['org_id'] == widget.orgId) _load();
    });
  }

  @override
  void didUpdateWidget(SecurityCard old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await s.api.call('GET', _path);
      data = r is Map<String, dynamic> ? r : null;
    } on ApiError {
      data = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _set(String key, bool on) async {
    HapticFeedback.mediumImpact();
    setState(() => _busy.add(key));
    final messenger = ScaffoldMessenger.of(context);
    try {
      data = await s.api.call('PUT', _path, {key: on}) as Map<String, dynamic>;
      messenger.showSnackBar(SnackBar(content: Text(s.t(on ? 'security.on' : 'security.off',
          {'name': s.t('security.$key')}))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy.remove(key));
  }

  /// Who gets the alarm SMS / call: the home's contacts, picked by name (their numbers are kept
  /// in the home settings).
  Future<void> _setRecipient(Map recipient, String kind, bool on) async {
    HapticFeedback.selectionClick();
    final people = ((data?['recipients'] as List?) ?? const []).cast<Map>();
    List<int> ids(String k) => [
          for (final x in people)
            if (identical(x, recipient) && k == kind ? on : x[k] == true) (x['contact_id'] as num).toInt(),
        ];
    final messenger = ScaffoldMessenger.of(context);
    try {
      data = await s.api.call('PUT', '$_path/recipients', {'sms': ids('sms'), 'call': ids('call')})
          as Map<String, dynamic>;
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    final home = s.homes.where((h) => h['org_id'] == widget.orgId).firstOrNull;
    if (home == null) return;
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => MembersScreen(state: s, orgId: widget.orgId, homeName: '${home['name'] ?? ''}')));
    _load();
  }

  /// .card.stack.tight with a strong title row, its small button at the end (web: .row.between).
  Widget _head(Tk tk, IconData icon, String title, Widget? button) => Row(children: [
        Icon(icon, size: 18, color: tk.text),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: tk.text))),
        if (button != null) Flexible(child: button),
      ]);

  Widget _note(Tk tk, String text, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: TextStyle(fontSize: 11, height: 1.8, color: warn ? tk.warn : tk.muted)),
      );

  /// Who is told: the home's people, picked by name (numbers are set on the access page).
  Widget _recipientsCard(Map<String, dynamic> d, Tk tk) {
    final people = ((d['recipients'] as List?) ?? const []).cast<Map>();
    final anyone = people.any((x) => x['sms'] == true || x['call'] == true);
    Widget pick(Map x, String kind) {
      final on = x[kind] == true;
      return Semantics(
        button: true,
        selected: on,
        label: '${x['name']}: ${s.t(kind == 'sms' ? 'contacts.sms_long' : 'contacts.call_long')}',
        child: WebChip(s.t(kind == 'sms' ? 'contacts.sms' : 'contacts.call'),
            icon: kind == 'sms' ? Icons.sms_outlined : Icons.call_outlined,
            tone: on ? ChipTone.accent : ChipTone.plain,
            onTap: () => _setRecipient(x, kind, !on)),
      );
    }
    return WebCard(tight: true, warn: !anyone, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head(tk, Icons.groups_outlined, s.t('security.recipients'),
          WebButton(s.t(people.isEmpty ? 'security.add_people' : 'security.numbers'), small: true,
              icon: Icons.groups_outlined, onTap: _openSettings)),
      _note(tk, s.t(people.isEmpty ? 'security.no_contacts' : 'security.recipients_help')),
      for (final x in people)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Reading(
            start: Text('${x['name']}', style: TextStyle(fontSize: 13, color: tk.text)),
            end: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [pick(x, 'sms'), pick(x, 'call')]),
          ),
        ),
    ]));
  }

  /// The siren: which outputs (module + relay) sound, and for how long.
  Widget _sirenCard(Map<String, dynamic> d, Tk tk) {
    final sirens = ((d['sirens'] as List?) ?? const []).cast<Map>();
    final minutes = (((d['siren_s'] as num?) ?? 180) / 60).round();
    return WebCard(tight: true, warn: sirens.isEmpty, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head(tk, Icons.notifications_none_rounded, s.t('security.siren'),
          WebButton(s.t(sirens.isEmpty ? 'security.siren_pick' : 'security.siren_change'), small: true,
              icon: Icons.notifications_none_rounded, onTap: _pickSirens)),
      _note(tk, sirens.isEmpty ? s.t('security.siren_none')
          : s.t('security.siren_set', {'n': s.i18n.num(sirens.length), 'min': s.i18n.num(minutes)})),
      if (sirens.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in sirens)
              WebChip('${x['device_name']} · ${x['name']}', tone: ChipTone.danger, icon: Icons.notifications_none_rounded),
          ]),
        ),
    ]));
  }

  Future<void> _pickSirens() async {
    List<Map<String, dynamic>> views;
    try {
      views = (await s.api.call('GET', '/api/platform/my/views?org=${Uri.encodeQueryComponent(widget.orgId)}') as List)
          .cast<Map<String, dynamic>>();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final chosen = {for (final x in ((data?['sirens'] as List?) ?? const []).cast<Map>()) '${x['device_id']}/${x['key']}'};
    var seconds = ((data?['siren_s'] as num?) ?? 180).toInt();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final tk = Tk.of(c);
        return SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text(s.t('security.siren'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(s.t('security.siren_help'), style: TextStyle(fontSize: 12, height: 1.6, color: tk.muted)),
          for (final v in views)
            if ((v['tags'] as List).any((t) => t['writable'] == true && t['data_type'] == 'bool')) ...[
              const SizedBox(height: 12),
              Text('${v['device']['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in (v['tags'] as List).cast<Map<String, dynamic>>()
                    .where((t) => t['writable'] == true && t['data_type'] == 'bool'))
                  FilterChip(
                    label: Text(s.i18n.name(t['display_name'])),
                    selected: chosen.contains('${v['device']['device_id']}/${t['key']}'),
                    selectedColor: _red.withValues(alpha: 0.25),
                    onSelected: (on) => set(() {
                      final id = '${v['device']['device_id']}/${t['key']}';
                      on ? chosen.add(id) : chosen.remove(id);
                    }),
                  ),
              ]),
            ],
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: const [60, 120, 180, 300, 600, 900].contains(seconds) ? seconds : 180,
            decoration: InputDecoration(labelText: s.t('security.siren_time')),
            items: [for (final m in [1, 2, 3, 5, 10, 15])
              DropdownMenuItem(value: m * 60, child: Text(s.t('security.minutes', {'n': s.i18n.num(m)})))],
            onChanged: (v) => seconds = v ?? 180,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('common.save'))),
        ]));
      }),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      data = await s.api.call('PUT', _path, {
        'sirens': [for (final id in chosen) {'device_id': id.split('/').first, 'key': id.split('/').last}],
        'siren_s': seconds,
      }) as Map<String, dynamic>;
      messenger.showSnackBar(SnackBar(content: Text(s.t('common.saved'))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() {});
  }

  /// The alarm zones, by the module each is wired to; defined on the device page.
  /// The alarm zones, by the module each is wired to; a row opens that module's page, where they
  /// are named and given a kind.
  Widget _zonesCard(Map<String, dynamic> d, Tk tk) {
    final zones = ((d['zones'] as List?) ?? const []).cast<Map>();
    final byDevice = <String, List<Map>>{};
    for (final z in zones) {
      byDevice.putIfAbsent('${z['device_id']}', () => []).add(z);
    }
    IconData kindIcon(Object? kind) => kind == 'smoke' ? Icons.local_fire_department_outlined
        : kind == 'magnet' ? Icons.sensor_door_outlined : Icons.directions_walk_rounded;
    return WebCard(tight: true, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head(tk, Icons.sensors_rounded, s.t('security.zones'), null),
      _note(tk, s.t('security.zones_help')),
      for (final e in byDevice.entries)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Reading(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => DeviceScreen(state: s, deviceId: e.key))),
            start: Text('${e.value.first['device_name']}', style: TextStyle(fontSize: 13, color: tk.text)),
            end: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
              for (final z in e.value) WebChip('${z['name']}', icon: kindIcon(z['kind'])),
            ]),
          ),
        ),
      if (zones.isEmpty) _note(tk, s.t('security.no_sensors'), warn: true),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) return const SizedBox.shrink();
    final tk = Tk.of(context);
    final armed = d['burglar'] == true || d['night'] == true;
    final sensors = (d['sensors'] as Map?) ?? const {};
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.shield_outlined, color: tk.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(s.t('security.title'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tk.text))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                color: armed ? _red : tk.surface2),
            child: Text(s.t(armed ? 'security.armed' : 'security.disarmed'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: armed ? Colors.white : tk.muted)),
          ),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.08,
          children: [
            for (final (key, icon, kinds) in _scenarios)
              _ScenarioTile(
                title: s.t('security.$key'),
                help: s.t('security.${key}_help'),
                icon: icon,
                on: d[key] == true,
                alarm: key == 'burglar' || key == 'night',
                busy: _busy.contains(key),
                count: kinds.isEmpty ? null : kinds.fold<int>(0, (n, k) => n + ((sensors[k] as num?)?.toInt() ?? 0)),
                countText: (n) => n > 0 ? s.t('security.sensors', {'n': s.i18n.num(n)}) : s.t('security.no_sensors'),
                onChanged: (v) => _set(key, v),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _sirenCard(d, tk),
        const SizedBox(height: 10),
        _zonesCard(d, tk),
        const SizedBox(height: 10),
        _recipientsCard(d, tk),
      ]),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({required this.title, required this.help, required this.icon, required this.on,
      required this.alarm, required this.busy, required this.count, required this.countText, required this.onChanged});

  final String title;
  final String help;
  final IconData icon;
  final bool on;
  final bool alarm;               // burglar / night: red while on
  final bool busy;
  final int? count;
  final String Function(int) countText;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final tone = alarm ? _red : tk.accent;
    return Semantics(
      toggled: on,
      label: title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? tone.withValues(alpha: 0.13) : tk.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: on ? tone.withValues(alpha: 0.45) : tk.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 38, height: 38,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(13),
                  color: on ? tone : tk.surface2),
              child: Icon(icon, size: 20, color: on ? (alarm ? Colors.white : tk.accentInk) : tk.muted),
            ),
            const Spacer(),
            Opacity(opacity: busy ? 0.5 : 1, child: TiSwitch(value: on, onChanged: busy ? null : onChanged)),
          ]),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: tk.text)),
          const SizedBox(height: 2),
          Expanded(child: Text(help, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.5, color: tk.muted))),
          if (count != null)
            Text(countText(count!), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: count! > 0 ? tk.text : tk.warn)),
        ]),
      ),
    );
  }
}
