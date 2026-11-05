// Home, laid out like the web app's (app/js/views.js home): greeting and home picker with the
// bell and avatar, today in the home, quick scenes, favourite shortcuts, groups, and the devices
// as a two-column grid whose switch turns all their outputs on or off. Pull down to refresh.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/widgets.dart';
import 'device.dart';
import 'notifications.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state, required this.openMe});

  final AppState state;
  final VoidCallback openMe;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? summary;
  List<Map<String, dynamic>> views = [];
  List<Map<String, dynamic>> scenes = [];
  List<Map<String, dynamic>> groups = [];
  final Set<String> _busy = {};
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _org {
    final s = widget.state;
    return s.home ?? (s.homes.isNotEmpty ? s.homes.first['org_id'] as String : null);
  }

  Future<void> _load() async {
    final s = widget.state;
    try {
      final q = s.query();
      final results = await Future.wait([
        s.api.call('GET', '/api/platform/my/summary$q'),
        s.api.call('GET', '/api/platform/my/views$q'),
      ]);
      summary = results[0] as Map<String, dynamic>;
      views = (results[1] as List).cast<Map<String, dynamic>>();
      final org = _org;
      if (org != null) {
        scenes = (await s.api.call('GET', '/api/platform/organizations/$org/scenes').catchError((_) => [])
                as List).cast<Map<String, dynamic>>();
        groups = (await s.api.call('GET', '/api/platform/organizations/$org/groups').catchError((_) => [])
                as List).cast<Map<String, dynamic>>();
      }
      error = null;
    } on ApiError catch (e) {
      error = s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message;
    } catch (e) {
      error = '$e';                              // never a silent empty screen
    }
    if (mounted) setState(() {});
  }

  String _greeting(AppState s) {
    final h = DateTime.now().hour;
    return s.t(h < 12 ? 'home.morning' : (h < 17 ? 'home.afternoon' : 'home.evening'));
  }

  List<Map<String, dynamic>> _outputs(Map<String, dynamic> v) => (v['tags'] as List)
      .cast<Map<String, dynamic>>()
      .where((t) => t['kind'] == 'digital_output' && (t['ui']?['visible'] ?? true) != false)
      .toList();

  Future<void> _set(String deviceId, Map<String, dynamic> tag, bool value) async {
    final key = '$deviceId/${tag['key']}';
    setState(() => _busy.add(key));
    final r = await sendCommand(context, widget.state, deviceId, tag['key'] as String, value);
    if (r != null && r['result'] == 'applied') tag['value'] = r['value'] ?? value;
    if (mounted) setState(() => _busy.remove(key));
  }

  /// The switch of a device card: every output off when any is on, else every output on.
  Future<void> _all(Map<String, dynamic> v, bool on) async {
    final id = v['device']['device_id'] as String;
    await Future.wait([
      for (final t in _outputs(v).where((t) => t['writable'] == true && (t['value'] == true) != on)) _set(id, t, on),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final homeName = s.home == null
        ? s.t('me.my_home')
        : '${s.homes.firstWhere((h) => h['org_id'] == s.home, orElse: () => {'name': s.t('me.my_home')})['name']}';
    final favs = [
      for (final v in views)
        for (final t in _outputs(v).where((t) => t['favorite'] == true)) (v, t),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 52, 20, 130), children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: s.homes.length > 1 ? () => _pickHome(context) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(s), style: TextStyle(fontSize: 13, color: tk.muted)),
                Row(children: [
                  Flexible(child: Text(homeName, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: tk.text))),
                  if (s.homes.length > 1) Icon(Icons.expand_more_rounded, color: tk.muted),
                ]),
              ]),
            ),
          ),
          CircleIconButton(icon: Icons.notifications_none_rounded, tooltip: s.t('nav.notifications'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(state: s)))),
          const SizedBox(width: 10),
          Avatar(name: '${s.me?['display_name'] ?? ''}', onTap: widget.openMe),
        ]),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!)),
        if (summary != null)
          Section(icon: Icons.bolt_rounded, title: s.t('sec.today'), hint: s.t('sec.today_hint'), children: [
            Row(children: [
              StatTile(label: s.t('home.temperature'),
                  value: summary!['temperature'] == null ? '—' : '${s.i18n.num((summary!['temperature'] as num).toDouble())}°'),
              const SizedBox(width: 10),
              StatTile(label: s.t('home.power_now'),
                  value: summary!['power_kw'] == null ? '—' : s.i18n.num((summary!['power_kw'] as num).toDouble()),
                  unit: 'kW'),
              const SizedBox(width: 10),
              StatTile(label: s.t('home.alerts'), value: s.i18n.num(summary!['alerts'] ?? 0),
                  unit: s.t('home.active_alerts'), warn: ((summary!['alerts'] ?? 0) as num) > 0),
            ]),
          ]),
        if (scenes.isNotEmpty || favs.isNotEmpty)
          Section(icon: Icons.star_outline_rounded, title: s.t('sec.quick'), hint: s.t('sec.quick_hint'), children: [
            if (scenes.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: scenes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => ScenePill(
                    icon: iconFor(scenes[i]['icon'] as String?),
                    tone: tk.tone(scenes[i]['icon'] as String?),
                    label: '${scenes[i]['name']}',
                    onTap: () => _runScene(scenes[i]),
                  ),
                ),
              ),
            if (favs.isNotEmpty) ...[
              const SizedBox(height: 16),
              RowLabel(s.t('home.favorites')),
              const SizedBox(height: 10),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: favs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _FavChip(
                    state: s, view: favs[i].$1, tag: favs[i].$2,
                    busy: _busy.contains('${favs[i].$1['device']['device_id']}/${favs[i].$2['key']}'),
                    onTap: () => _set(favs[i].$1['device']['device_id'] as String, favs[i].$2, favs[i].$2['value'] != true),
                  ),
                ),
              ),
            ],
          ]),
        if (groups.isNotEmpty)
          Section(icon: Icons.grid_view_rounded, title: s.t('sec.groups'), hint: s.t('sec.groups_hint'), children: [
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _GroupCard(state: s, group: groups[i], views: views,
                    onTap: () => _openGroup(groups[i])),
              ),
            ),
          ]),
        Section(icon: Icons.home_outlined, title: s.t('sec.devices'), hint: s.t('sec.devices_hint'), children: [
          if (views.isEmpty && error == null) GlassCard(child: Text(s.t('home.empty'))),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.12,
            children: [
              for (final v in views)
                _DeviceCard(
                  state: s, view: v, outputs: _outputs(v),
                  open: () async {
                    await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DeviceScreen(state: s, deviceId: v['device']['device_id'] as String)));
                    _load();
                  },
                  toggle: (on) => _all(v, on),
                ),
            ],
          ),
        ]),
      ]),
    );
  }

  Future<void> _runScene(Map<String, dynamic> scene) async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.api.call('POST', '/api/platform/organizations/${scene['org_id']}/scenes/${scene['scene_id']}/run');
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.scene_done'))));
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// A group: its outputs in one sheet, each with its switch.
  Future<void> _openGroup(Map<String, dynamic> g) async {
    final s = widget.state;
    final refs = [
      for (final sec in ((g['sections'] as List?) ?? const []).cast<Map>())
        for (final o in ((sec['outputs'] as List?) ?? const []).cast<Map>()) o,
    ];
    await showModalBottomSheet(
      context: context,
      backgroundColor: Tk.of(context).bg2,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final rows = <Widget>[];
        for (final ref in refs) {
          final v = views.where((x) => x['device']['device_id'] == ref['device_id']).firstOrNull;
          final t = v == null ? null : _outputs(v).where((x) => x['key'] == ref['key']).firstOrNull;
          if (v == null || t == null) continue;
          rows.add(ListTile(
            leading: IconTile(icon: iconFor(t['ui']?['icon'] as String? ?? t['icon'] as String?), size: 38, radius: 13,
                on: t['value'] == true),
            title: Text(s.i18n.name(t['display_name'])),
            subtitle: Text('${v['device']['name'] ?? ''}'),
            trailing: TiSwitch(value: t['value'] == true, onChanged: t['writable'] == true
                ? (on) async { await _set(v['device']['device_id'] as String, t, on); set(() {}); } : null),
          ));
        }
        return SafeArea(child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('${g['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ...rows,
        ]));
      }),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickHome(BuildContext context) async {
    final s = widget.state;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Tk.of(context).bg2,
      builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(s.t('home.every')), onTap: () => Navigator.pop(context, '')),
        for (final h in s.homes)
          ListTile(leading: const Icon(Icons.home_rounded), title: Text('${h['name']}'),
              onTap: () => Navigator.pop(context, h['org_id'] as String)),
      ])),
    );
    if (picked == null) return;
    await s.setHome(picked.isEmpty ? null : picked);
    _load();
  }
}

/// .fav: a favourite output; filled icon when on.
class _FavChip extends StatelessWidget {
  const _FavChip({required this.state, required this.view, required this.tag, required this.busy, required this.onTap});

  final AppState state;
  final Map<String, dynamic> view;
  final Map<String, dynamic> tag;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final on = tag['value'] == true;
    final offline = view['device']['state'] != 'online';
    return Opacity(
      opacity: offline ? 0.5 : 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150),
        child: GlassCard(
          radius: 20, lit: on,
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 14, 10),
          onTap: offline || busy || tag['writable'] != true ? null : onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconTile(icon: iconFor(tag['ui']?['icon'] as String? ?? tag['icon'] as String?), size: 38, radius: 13,
                on: on, strong: true),
            const SizedBox(width: 10),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.i18n.name(tag['display_name']),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tk.text)),
              Text(state.t(on ? 'device.on' : 'device.off'), style: TextStyle(fontSize: 11, color: on ? tk.accent : tk.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// .group-card: icon, name and how many devices are online.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.state, required this.group, required this.views, required this.onTap});

  final AppState state;
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> views;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final ids = ((group['device_ids'] as List?) ?? const []).cast<String>();
    final online = views.where((v) => ids.contains(v['device']['device_id']) && v['device']['state'] == 'online').length;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 148),
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: tk.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(iconFor(group['icon'] as String?), size: 19, color: tk.accent),
          ),
          const SizedBox(width: 10),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${group['name']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tk.text)),
            Text('${state.i18n.num(ids.length)} · ${state.t('home.online')} ${state.i18n.num(online)}',
                style: TextStyle(fontSize: 11, color: tk.muted)),
          ]),
        ]),
      ),
    );
  }
}

/// .dev: icon tile and the all-outputs switch on top, name and state below; lit when any is on.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.state, required this.view, required this.outputs, required this.open,
      required this.toggle});

  final AppState state;
  final Map<String, dynamic> view;
  final List<Map<String, dynamic>> outputs;
  final VoidCallback open;
  final ValueChanged<bool> toggle;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final tk = Tk.of(context);
    final d = view['device'] as Map<String, dynamic>;
    final on = outputs.where((t) => t['value'] == true).length;
    final online = d['state'] == 'online';
    final writable = outputs.any((t) => t['writable'] == true);
    return Opacity(
      opacity: online ? 1 : 0.55,
      child: GlassCard(
        lit: on > 0,
        padding: const EdgeInsets.all(14),
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(icon: Icons.grid_view_rounded, on: on > 0),
            const Spacer(),
            if (outputs.isNotEmpty) TiSwitch(value: on > 0, onChanged: online && writable ? toggle : null),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['name'] ?? d['identifier']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: tk.text)),
            const SizedBox(height: 2),
            Text(
              online
                  ? (outputs.isEmpty ? s.t('device.online') : s.t('device.on_count', {'n': on, 'total': outputs.length}))
                  : s.t('device.offline'),
              style: TextStyle(fontSize: 12, color: on > 0 && online ? tk.accent : tk.muted),
            ),
          ]),
        ]),
      ),
    );
  }
}
