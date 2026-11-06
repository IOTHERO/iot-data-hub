// Home, laid out like the web app's (app/js/views.js home): greeting and home picker with the
// bell and avatar, today in the home, quick scenes, favourite shortcuts, groups, and the devices
// as a two-column grid whose switch turns all their outputs on or off. Pull down to refresh.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/live.dart';
import '../ui/hscroll.dart';
import '../ui/kit.dart';
import '../ui/outputs.dart';
import '../ui/widgets.dart';
import 'alerts.dart';
import 'custom_edit.dart';
import 'device.dart';
import 'group_edit.dart';
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
  bool loaded = false;                   // the first answer is in (no "no devices" before it)

  StreamSubscription<LiveEvent>? _live;

  @override
  void initState() {
    super.initState();
    _load();
    _live = widget.state.live.events.listen((e) {      // values change as they happen
      final changed = e.type == 'samples' ? applySamples(views, e.data) : applyStatus(views, e.data);
      if (changed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
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
    loaded = true;
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
    final device = views.where((v) => v['device']['device_id'] == deviceId).firstOrNull?['device'];
    if (isMomentary(tag)) {                          // a push: on, the hub turns it off
      if (!value) {
        if (mounted) setState(() => _busy.remove(key));
        return;
      }
      await pulseOutput(context, widget.state, deviceId, tag);
      if (mounted) setState(() => _busy.remove(key));
      return;
    }
    final r = await sendCommand(context, widget.state, deviceId, tag['key'] as String, value,
        offline: device != null && device['state'] != 'online');
    if (r != null && r['result'] == 'applied') tag['value'] = r['value'] ?? value;
    if (mounted) setState(() => _busy.remove(key));
  }

  /// The switch of a device card: every output off when any is on, else every output on.
  Future<void> _all(Map<String, dynamic> v, bool on) async {
    final id = v['device']['device_id'] as String;
    await Future.wait([
      for (final t in _outputs(v).where((t) => t['writable'] == true && !isMomentary(t) && (t['value'] == true) != on)) _set(id, t, on),
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
    // the order a person thinks in (how is the home, do something now, groups, every device);
    // each person may reorder or hide them (Me > home layout)
    final blocks = <String, Widget? Function()>{
      'today': () => summary == null ? null : Section(icon: Icons.bolt_rounded, title: s.t('sec.today'),
          hint: s.t('sec.today_hint'), children: [
            ListenableBuilder(listenable: s.alerts, builder: (context, _) => Row(children: [
              StatTile(label: s.t('home.temperature'),
                  value: summary!['temperature'] == null ? '—' : '${s.i18n.num((summary!['temperature'] as num).toDouble())}°'),
              const SizedBox(width: 10),
              StatTile(label: s.t('home.power_now'),
                  value: summary!['power_kw'] == null ? '—' : s.i18n.num((summary!['power_kw'] as num).toDouble()),
                  unit: 'kW'),
              const SizedBox(width: 10),
              StatTile(label: s.t('home.alerts'),
                  value: s.i18n.num(((summary!['alerts'] ?? 0) as num).toInt() + s.alerts.list.length),
                  unit: s.t('home.active_alerts'),
                  warn: ((summary!['alerts'] ?? 0) as num) > 0 || s.alerts.list.isNotEmpty,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlertsScreen(state: s)))),
            ])),
          ]),
      'custom': () => _custom(s, tk),
      'quick': () => scenes.isEmpty && favs.isEmpty ? null : Section(icon: Icons.star_outline_rounded,
          title: s.t('sec.quick'), hint: s.t('sec.quick_hint'), children: [
            if (scenes.isNotEmpty)
              HScroll(height: 52, moreLabel: s.t('common.more_next'), children: [
                for (final sc in scenes)
                  ScenePill(
                    icon: iconFor(sc['icon'] as String?),
                    tone: tk.tone(sc['icon'] as String?),
                    label: '${sc['name']}',
                    onTap: () => _runScene(sc),
                  ),
              ]),
            if (favs.isNotEmpty) ...[
              const SizedBox(height: 16),
              RowLabel(s.t('home.favorites')),
              const SizedBox(height: 10),
              HScroll(height: 64, moreLabel: s.t('common.more_next'), children: [
                for (final f in favs)
                  _FavChip(
                    state: s, view: f.$1, tag: f.$2,
                    busy: _busy.contains('${f.$1['device']['device_id']}/${f.$2['key']}'),
                    onTap: () => _set(f.$1['device']['device_id'] as String, f.$2, f.$2['value'] != true),
                  ),
              ]),
            ],
          ]),
      'groups': () => _org == null || (groups.isEmpty && views.isEmpty) ? null : Section(icon: Icons.grid_view_rounded,
          title: s.t('sec.groups'), hint: s.t('sec.groups_hint'), children: [
            HScroll(height: 64, moreLabel: s.t('common.more_next'), children: [
              for (final g in groups) _GroupCard(state: s, group: g, views: views, onTap: () => _openGroup(g)),
              _NewGroupCard(label: s.t('groups.new'), onTap: () => _editGroup(null)),
            ]),
          ]),
      'devices': () => Section(icon: Icons.home_outlined, title: s.t('sec.devices'), hint: s.t('sec.devices_hint'), children: [
            if (loaded && views.isEmpty && error == null) EmptyCard(icon: Icons.qr_code_scanner_rounded, text: s.t('home.empty')),
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
    };
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_load(), s.alerts.load()]);
      },
      child: Scrollbar(child: ListView(padding: const EdgeInsets.fromLTRB(20, 52, 20, 130), children: [
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
          ListenableBuilder(
            listenable: s.alerts,
            builder: (context, _) => Badge(
              isLabelVisible: s.alerts.unseen.isNotEmpty,
              backgroundColor: alarmRed,
              smallSize: 10,
              child: CircleIconButton(icon: Icons.notifications_none_rounded, tooltip: s.t('nav.notifications'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(state: s)))),
            ),
          ),
          const SizedBox(width: 10),
          Avatar(name: '${s.me?['display_name'] ?? ''}', onTap: widget.openMe),
        ]),
        AlarmBar(state: s),                // a pulsing red bar while a PIR / magnet / smoke alert is open
        if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!)),
        ...[for (final (key, on) in s.homeLayout) if (on) blocks[key]!()].nonNulls,
      ])),
    );
  }

  /// The person's own section: what they picked, in their order (custom_edit.dart).
  Widget _custom(AppState s, Tk tk) {
    final items = s.customItems;
    Future<void> edit() async {
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => CustomEditScreen(state: s, views: views, scenes: scenes)));
      if (mounted) setState(() {});
    }
    final tiles = <Widget>[];
    final sensors = <Widget>[];
    for (final x in items) {
      if (x['type'] == 'scene') {
        final sc = scenes.where((sc) => '${sc['scene_id']}' == '${x['scene_id']}').firstOrNull;
        if (sc != null) {
          tiles.add(ScenePill(icon: iconFor(sc['icon'] as String?), tone: tk.tone(sc['icon'] as String?),
              label: '${sc['name']}', onTap: () => _runScene(sc)));
        }
        continue;
      }
      final v = views.where((v) => v['device']['device_id'] == x['device_id']).firstOrNull;
      final t = (v?['tags'] as List?)?.cast<Map<String, dynamic>>().where((t) => t['key'] == x['key']).firstOrNull;
      if (v == null || t == null) continue;
      if (x['type'] == 'out') {
        tiles.add(_FavChip(state: s, view: v, tag: t,
            busy: _busy.contains('${v['device']['device_id']}/${t['key']}'),
            onTap: () => _set(v['device']['device_id'] as String, t, t['value'] != true)));
      } else {
        final on = t['value'] == true;
        final alarm = s.alerts.of(v['device']['device_id'] as String, t['key'] as String) != null;
        sensors.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(iconFor(outIcon(t)), size: 20, color: alarm ? alarmRed : on ? tk.ok : tk.muted),
              const SizedBox(width: 10),
              Expanded(child: Text('${s.i18n.name(t['display_name'])} · ${v['device']['name']}',
                  style: TextStyle(fontSize: 13, color: tk.text))),
              Text(alarm ? s.t('alarm.badge') : s.t(on ? 'sensor.active' : 'sensor.idle'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: alarm ? alarmRed : on ? tk.ok : tk.muted)),
            ]),
          ),
        ));
      }
    }
    return Section(
      icon: Icons.dashboard_customize_rounded,
      title: s.customTitle.isEmpty ? s.t('custom.title_default') : s.customTitle,
      hint: s.t('custom.hint'),
      action: CircleIconButton(icon: Icons.edit_outlined, tooltip: s.t('custom.edit'), onTap: edit),
      children: [
        if (items.isEmpty)
          EmptyCard(icon: Icons.add_rounded, text: s.t('custom.empty'), onTap: edit, dashed: true),
        if (tiles.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: tiles),
        if (tiles.isNotEmpty && sensors.isNotEmpty) const SizedBox(height: 10),
        ...sensors,
      ],
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

  Future<void> _editGroup(Map<String, dynamic>? g) async {
    final org = _org;
    if (org == null) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => GroupEditScreen(state: widget.state, orgId: org, group: g)));
    if (changed == true) _load();
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
            leading: IconTile(icon: iconFor(outIcon(t)), size: 38, radius: 13,
                on: t['value'] == true),
            title: Text(s.i18n.name(t['display_name'])),
            subtitle: Text('${v['device']['name'] ?? ''}'),
            trailing: TiSwitch(value: t['value'] == true, onChanged: t['writable'] == true
                ? (on) async { await _set(v['device']['device_id'] as String, t, on); set(() {}); } : null),
          ));
        }
        return SafeArea(child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 8, 8), child: Row(children: [
            Expanded(child: Text('${g['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(tooltip: s.t('groups.edit'), icon: const Icon(Icons.edit_rounded), onPressed: () {
              Navigator.pop(c);
              _editGroup(g);
            }),
          ])),
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
            IconTile(icon: iconFor(outIcon(tag)), size: 38, radius: 13,
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
            Text(state.t('groups.count', {'n': state.i18n.num(ids.length), 'on': state.i18n.num(online)}),
                style: TextStyle(fontSize: 11, color: tk.muted)),
          ]),
        ]),
      ),
    );
  }
}

/// .group-card.add: the dashed card at the end of the groups row that makes a new group.
class _NewGroupCard extends StatelessWidget {
  const _NewGroupCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return CustomPaint(
      foregroundPainter: _Dashes(color: tk.line2),
      child: Material(
        color: tk.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 148, minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: tk.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.add_rounded, size: 19, color: tk.muted)),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tk.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  _Dashes({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

/// The protocol line of a device card (the web app's protoLabel): a native module's transports
/// ("MQTT · HTTP"), else the protocol's name.
String protoLabel(AppState s, Map<String, dynamic> d) {
  const transport = {'mqtt': 'MQTT', 'http': 'HTTP', 'tcp': 'TCP/IP'};
  final p = '${d['protocol'] ?? ''}';
  if (p == 'native' || p.isEmpty) {
    final tr = ((d['connection'] as Map?)?['transports'] as List?) ?? const ['mqtt', 'http', 'tcp'];
    return tr.map((x) => transport[x] ?? '$x').take(2).join(' · ');
  }
  return s.i18n.has('proto.$p') ? s.t('proto.$p') : p;
}

/// .dev: icon tile and the all-outputs switch on top, name and state, then the protocol chip
/// (and the access when it is not the owner's); lit when any output is on.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.state, required this.view, required this.outputs, required this.open,
      required this.toggle});

  final AppState state;
  final Map<String, dynamic> view;
  final List<Map<String, dynamic>> outputs;
  final VoidCallback open;
  final ValueChanged<bool> toggle;

  /// The state line as the web app's card(): offline (since), "n of m on", on · reading, a reading.
  String _state(Map<String, dynamic> d, bool online, int on) {
    final s = state;
    final reading = ((view['tags'] as List?) ?? const []).cast<Map<String, dynamic>>()
        .where((t) => t['value'] is num && t['writable'] != true).firstOrNull;
    String readingText(Map<String, dynamic> r) =>
        '${s.i18n.num(r['value'])}${r['unit'] == '°C' ? '°' : ' ${r['unit'] ?? ''}'}';
    if (!online) return s.t('device.offline');
    if (outputs.length > 1) {
      return on > 0 ? s.t('device.on_count', {'n': s.i18n.num(on), 'total': s.i18n.num(outputs.length)}) : s.t('device.all_off');
    }
    if (outputs.length == 1) {
      final text = on > 0 ? s.t('device.on') : s.t('device.off');
      return on > 0 && reading != null ? '$text · ${readingText(reading)}' : text;
    }
    if (reading != null) return '${s.i18n.num(reading['value'])} ${reading['unit'] ?? ''}'.trim();
    return s.t('device.online');
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final tk = Tk.of(context);
    final d = view['device'] as Map<String, dynamic>;
    final on = outputs.where((t) => t['value'] == true).length;
    final online = d['state'] == 'online';
    final writable = outputs.any((t) => t['writable'] == true);
    final lit = on > 0 && online;
    Widget proto(String text, {bool ltr = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: tk.surface2, borderRadius: BorderRadius.circular(8)),
          child: Text(text, textDirection: ltr ? TextDirection.ltr : null,
              style: TextStyle(fontSize: 10, letterSpacing: 0.3, color: tk.muted)),
        );
    return Opacity(
      opacity: online ? 1 : 0.55,
      child: GlassCard(
        lit: lit,
        padding: const EdgeInsets.all(14),
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(icon: Icons.grid_view_rounded, on: lit),
            const Spacer(),
            if (outputs.isNotEmpty && online) TiSwitch(value: on > 0, onChanged: writable ? toggle : null),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['name'] ?? d['identifier']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: tk.text)),
            const SizedBox(height: 2),
            Text(_state(d, online, on), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: !online ? tk.warn : lit ? tk.accent : tk.muted)),
          ]),
          Wrap(spacing: 6, runSpacing: 4, children: [
            proto(protoLabel(s, d), ltr: true),
            if (d['access'] != null && d['access'] != 'owner') proto(s.t('access.${d['access']}')),
          ]),
        ]),
      ),
    );
  }
}
