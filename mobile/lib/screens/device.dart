// One device: its outputs (switches), settings (set-points, modes) and readings, as the product
// template describes them (GET /api/platform/my/devices/{id}/view). Refreshed every 5 s.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/live.dart';
import '../ui/chart.dart';
import '../ui/climate.dart';
import '../ui/kit.dart';
import '../ui/outputs.dart';
import '../ui/remotes.dart';
import '../ui/widgets.dart';
import '../ui/sms_sheet.dart';
import 'alerts.dart';
import 'home.dart' show protoLabel;
import 'device_settings.dart';
import 'timers.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.state, required this.deviceId, this.focus});

  final AppState state;
  final String deviceId;
  final String? focus;                  // a sensor to bring into view and light up (from an alarm)

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  Map<String, dynamic>? view;
  String? error;
  Timer? _timer;
  StreamSubscription<LiveEvent>? _live;
  final Set<String> _busy = {};
  bool editing = false;                  // name and define: outputs and inputs open their sheets
  final Map<String, GlobalKey> _rows = {};
  String? _flash;                        // the sensor lit up for a moment
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _load();
    // live values; a slow refresh as well, for anything the stream did not carry
    _live = widget.state.live.events.listen((e) {
      final v = view;
      if (v == null) return;
      final changed = e.type == 'samples' ? applySamples([v], e.data) : applyStatus([v], e.data);
      if (changed && mounted) setState(() {});
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = widget.state;
    try {
      final v = await s.api.call('GET', '/api/platform/my/devices/${widget.deviceId}/view');
      view = v as Map<String, dynamic>;
      error = null;
    } on ApiError catch (e) {
      // offline: the device's entry in the kept home views
      final all = await s.api.call('GET', '/api/platform/my/views${s.query()}').catchError((_) => null);
      if (all is List) {
        view = all.cast<Map<String, dynamic>>().where((x) => x['device']['device_id'] == widget.deviceId).firstOrNull;
      }
      if (view == null) error = e.message;
    }
    if (mounted) setState(() {});
    _focus();
  }

  /// From an alarm: scroll to the sensor it came from and light it up once.
  void _focus() {
    final key = widget.focus;
    if (key == null || _focused || view == null) return;
    _focused = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _rows[key]?.currentContext;
      if (ctx == null || !mounted) return;
      await Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic);
      if (!mounted) return;
      setState(() => _flash = key);
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      if (mounted) setState(() => _flash = null);
    });
  }

  Future<void> _rename(Map<String, dynamic> t) async {
    final ok = t['kind'] == 'digital_output'
        ? await showLabelSheet(context, widget.state, widget.deviceId, t)
        : await showSensorSheet(context, widget.state, widget.deviceId, t);
    if (ok) _load();
  }

  /// A command of several parameters at once ("evening": relay 1 and 2 on, 8 off).
  Future<void> _action(Map<String, dynamic> c) async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.api.call('POST', '/api/platform/my/devices/${widget.deviceId}/actions/${c['key']}');
      messenger.showSnackBar(SnackBar(content: Text(s.t('device.done'))));
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _write(String key, Object? value) async {
    setState(() => _busy.add(key));
    final r = await sendCommand(context, widget.state, widget.deviceId, key, value,
        offline: view?['device']?['state'] != 'online');
    if (r != null && r['result'] == 'applied') {
      for (final t in (view!['tags'] as List)) {
        if (t['key'] == key) t['value'] = r['value'] ?? value;
      }
    }
    if (mounted) setState(() => _busy.remove(key));
  }

  /// A momentary output: lit for its push length, then the hub's state again.
  Future<void> _push(Map<String, dynamic> t) async {
    final key = t['key'] as String;
    setState(() { _busy.add(key); t['value'] = true; });
    await pulseOutput(context, widget.state, widget.deviceId, t);
    await Future<void>.delayed(Duration(milliseconds: (((t['pulse_s'] as num?) ?? 1) * 1000).round() + 400));
    if (!mounted) return;
    setState(() => _busy.remove(key));
    _load();
  }

  /// Write every listed output (all on / all off), one command each through the control layer.
  Future<void> _all(List<Map<String, dynamic>> outputs, bool on) async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    for (final t in outputs.where((t) => t['writable'] == true && (t['value'] == true) != on)) {
      await _write(t['key'] as String, on);
    }
    messenger.showSnackBar(SnackBar(content: Text(s.t('device.done'))));
  }

  Future<void> _settings(Map<String, dynamic> v) async {
    final gone = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => DeviceSettingsScreen(state: widget.state, view: v)));
    if (gone == true && mounted) {
      Navigator.pop(context);                  // removed or handed over: back home
    } else {
      _load();
    }
  }

  final Map<String, GlobalKey> _sections = {};
  String _lit = 'control';

  /// .jumpbar: a sticky row of the page's sections; a touch scrolls to one and lights it.
  Widget _jumpBar(List<(String, IconData, String)> items) {
    final tk = Tk.of(context);
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final (key, icon, title) in items)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Material(
              color: _lit == key ? tk.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() => _lit = key);
                  final ctx = _sections[key]?.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Icon(icon, size: 16, color: _lit == key ? tk.text : tk.muted),
                    const SizedBox(width: 6),
                    Text(title, style: TextStyle(fontSize: 13, color: _lit == key ? tk.text : tk.muted,
                        fontWeight: _lit == key ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final v = view;
    if (v == null) {
      return Scaffold(body: GlowPage(child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(children: [
          const TopBar(title: ''),
          Expanded(child: Center(child: error == null ? const CircularProgressIndicator() : Text(error!))),
        ]),
      ))));
    }
    final d = v['device'] as Map<String, dynamic>;
    final tags = (v['tags'] as List).cast<Map<String, dynamic>>()
        .where((t) => (t['ui']?['visible'] ?? true) != false).toList()
      ..sort((a, b) => ((a['ui']?['order'] ?? 999) as num).compareTo((b['ui']?['order'] ?? 999) as num));
    final climate = climateSet(tags);              // the AC card takes these tags
    final rest = tags.where((t) => !climate.values.contains(t)).toList();
    bool rf(Map<String, dynamic> t) => '${t['ui']?['role'] ?? ''}'.startsWith('rf_');   // the remotes card
    final outputs = rest.where((t) => t['kind'] == 'digital_output').toList();
    final settings = rest.where((t) => !rf(t) &&
        (t['kind'] == 'parameter' || (t['writable'] == true && t['kind'] != 'digital_output'))).toList();
    final readings = rest.where((t) => !rf(t) && !outputs.contains(t) && !settings.contains(t)).toList();
    final sensors = readings.where((t) => t['data_type'] == 'bool').toList();
    final values = readings.where((t) => t['data_type'] != 'bool').toList();
    final operate = d['access'] != 'viewer';
    final charted = tags.where((t) => t['value'] is num && t['data_type'] != 'bool' && t['ui']?['chart'] != false
        && !outputs.contains(t)).toList();
    final commands = ((v['commands'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final online = d['state'] == 'online';
    final onCount = outputs.where((t) => t['value'] == true).length;
    final sub = [d['room'], v['product']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    Widget editChip(String off) => WebChip(s.t(editing ? 'out.edit_done' : off),
        icon: editing ? Icons.check_rounded : Icons.edit_outlined, tone: editing ? ChipTone.accent : ChipTone.plain,
        onTap: () => setState(() => editing = !editing));

    final control = <Widget>[
      if (climate.isNotEmpty) ClimateCard(state: s, set: climate, busy: _busy, write: _write),
      if (outputs.isNotEmpty)
        Container(               // .card.big-card: 18 px in, 28 px corners
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: tk.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(s.t('device.outputs'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text))),
              Text(s.t('device.on_count', {'n': s.i18n.num(onCount), 'total': s.i18n.num(outputs.length)}),
                  style: TextStyle(fontSize: 13, color: tk.accent)),
              if (operate) ...[const SizedBox(width: 8), editChip('out.edit_mode')],
            ]),
            if (editing) ...[
              const SizedBox(height: 8),
              Text(s.t('out.edit_hint'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
            ],
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 4,                     // .outputs: four square tiles a row
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [for (final t in outputs) _OutputTile(state: s, tag: t, busy: _busy.contains(t['key']),
                  editing: editing,
                  write: editing && operate ? (_) => _rename(t)
                      : t['writable'] == true ? (on) => _write(t['key'] as String, on) : null,
                  push: editing && operate ? () => _rename(t) : t['writable'] == true ? () => _push(t) : null,
                  rename: d['access'] == 'owner' || d['access'] == 'operator'
                      ? () async { if (await showLabelSheet(context, s, widget.deviceId, t)) _load(); } : null)],
            ),
            if (outputs.length > 1 && operate) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: WebButton(s.t('device.all_on'), kind: BtnKind.primary, onTap: () => _all(outputs, true))),
                const SizedBox(width: 10),
                Expanded(child: WebButton(s.t('device.all_off_btn'), onTap: () => _all(outputs, false))),
              ]),
            ],
            if (operate) ...[
              const SizedBox(height: 12),
              WebButton(s.t('sms.quick'), icon: Icons.sms_outlined, block: true,
                  kind: online ? BtnKind.plain : BtnKind.danger,
                  onTap: () => showSmsSheet(context, s, widget.deviceId, outputs: outputs)),
            ],
          ]),
        ),
      if (outputs.isNotEmpty && !online)
        WebCard(tight: true, warn: true, onTap: () => _settings(v), child: Row(children: [
          Icon(Icons.error_outline_rounded, color: tk.warn),
          const SizedBox(width: 12),
          Expanded(child: Text(s.t('sms.offline_hint'), style: TextStyle(fontSize: 13, color: tk.text))),
          Icon(Icons.chevron_left_rounded, color: tk.muted),
        ])),
      RemotesCard(state: s, deviceId: widget.deviceId, canOperate: operate),
      if (settings.isNotEmpty)
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('device.settings'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text)),
          const SizedBox(height: 12),
          for (final t in settings) _SettingRow(state: s, tag: t, busy: _busy.contains(t['key']),
              write: (value) => _write(t['key'] as String, value)),
        ])),
    ];
    final data = <Widget>[
      if (charted.isNotEmpty) HistoryChart(key: ValueKey(widget.deviceId), state: s, deviceId: widget.deviceId, tags: charted),
      for (final t in values)
        Reading(
          start: Text(s.i18n.name(t['display_name']), style: TextStyle(color: tk.muted)),
          end: Text(_value(s, t), textDirection: TextDirection.ltr,
              style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
        ),
      if (sensors.isNotEmpty)
        ListenableBuilder(listenable: s.alerts, builder: (context, _) => Column(children: [
          for (final t in sensors)
            _SensorRow(
              key: _rows.putIfAbsent(t['key'] as String, GlobalKey.new),
              state: s, tag: t, flash: _flash == t['key'], editing: editing && operate,
              alarm: s.alerts.of(widget.deviceId, t['key'] as String),
              onTap: editing && operate ? () => _rename(t) : null,
            ),
        ])),
    ];
    final plan = <Widget>[
      if (commands.isNotEmpty)
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in commands)
            ScenePill(
              icon: iconFor(c['icon'] as String?),
              tone: tk.tone(c['icon'] as String?),
              label: s.i18n.name(c['display_name']),
              onTap: () => _action(c),
            ),
        ]),
      if (outputs.isNotEmpty && operate)
        TimersCard(state: s, deviceId: widget.deviceId, outputs: outputs.where((t) => t['writable'] == true).toList()),
    ];
    final log = <Widget>[
      CommandLog(state: s, deviceId: widget.deviceId,
          names: {for (final t in tags) t['key'] as String: s.i18n.name(t['display_name'])}),
    ];
    final sections = [
      ('control', Icons.power_settings_new_rounded, s.t('sec.control'), s.t('sec.control_hint'), control),
      ('data', Icons.sensors_rounded, s.t('sec.data'), s.t('sec.data_hint'), data),
      ('plan', Icons.schedule_rounded, s.t('sec.plan'), s.t('sec.plan_hint'), plan),
      ('log', Icons.repeat_rounded, s.t('sec.log'), s.t('sec.log_hint'), log),
    ].where((x) => x.$5.isNotEmpty).toList();

    return Scaffold(
      body: GlowPage(child: SafeArea(child: RefreshIndicator(
        onRefresh: _load,
        child: Scrollbar(child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
          TopBar(title: '${d['name'] ?? d['identifier']}', sub: sub,
              right: CircleIconButton(icon: Icons.settings_outlined, tooltip: s.t('device.settings_page'),
                  onTap: () => _settings(v))),
          const SizedBox(height: 18),
          Wrap(spacing: 8, runSpacing: 8, children: [
            WebChip('${online ? s.t('device.online') : s.t('device.offline')}'
                '${d['last_seen'] != null ? ' · ${s.i18n.when(d['last_seen'])}' : ''}',
                tone: online ? ChipTone.ok : ChipTone.warn, dot: true),
            WebChip([protoLabel(s, d), if (d['firmware_version'] != null) 'FW ${d['firmware_version']}'].join(' · '), ltr: true),
            if (d['warranty_until'] != null)
              WebChip(s.t('device.warranty_until', {'date': s.i18n.date(DateTime.parse('${d['warranty_until']}'))})),
            if (d['access'] != 'owner') WebChip(s.t('access.${d['access']}'), tone: ChipTone.accent),
            if (operate) editChip('out.edit_all'),
          ]),
          if (editing) ...[
            const SizedBox(height: 10),
            Text(s.t('out.edit_all_hint'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
          ],
          if (sections.length > 1) ...[
            const SizedBox(height: 18),
            _jumpBar([for (final x in sections) (x.$1, x.$2, x.$3)]),
          ],
          for (final (key, icon, title, hint, parts) in sections)
            Section(
              key: _sections.putIfAbsent(key, GlobalKey.new),
              icon: icon, title: title, hint: hint,
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  parts[i],
                ],
              ],
            ),
        ])),
      ))),
    );
  }
}

String _value(AppState s, Map<String, dynamic> t) {
  final v = t['value'];
  if (v == null) return '—';
  final states = t['states'] as Map?;
  if (states != null && states['$v'] != null) return '${states['$v']}';
  if (v is bool) return s.t(v ? 'device.on' : 'device.off');
  final unit = t['unit'] as String?;
  return '${s.i18n.num(v is num ? v.toDouble() : v)}${unit == null ? '' : ' $unit'}';
}

/// .out: a square tile, filled with the accent when on; a long press names it (outputs.dart).
/// Two keys (.dual): separate on and off halves. Momentary: a push the hub releases.
class _OutputTile extends StatelessWidget {
  const _OutputTile({required this.state, required this.tag, required this.busy, this.write, this.push, this.rename,
      this.editing = false});

  final AppState state;
  final Map<String, dynamic> tag;
  final bool busy;
  final ValueChanged<bool>? write;
  final VoidCallback? push;
  final VoidCallback? rename;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final on = tag['value'] == true;
    final tk = Tk.of(context);
    final fg = on ? tk.accentInk : tk.muted;
    final mode = editing ? 'toggle' : '${tag['mode'] ?? 'toggle'}';
    final enabled = write != null && !busy;
    final label = Text(state.i18n.name(tag['display_name']), maxLines: 2, textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: on ? FontWeight.w700 : FontWeight.w400));
    Widget key(String text, bool value) => Expanded(child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled && on != value ? () => write!(value) : null,
          child: Container(
            margin: const EdgeInsets.all(2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on == value ? (on ? tk.accentInk.withValues(alpha: 0.18) : tk.surface2) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(text, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w700)),
          ),
        ));
    final body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (tag['favorite'] == true) Align(alignment: AlignmentDirectional.topEnd,
          child: Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Icon(Icons.star_rounded, size: 11, color: fg))),
      Icon(editing ? Icons.edit_outlined : iconFor(outIcon(tag)), size: 24, color: fg),
      const SizedBox(height: 4),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: label),
      if (mode == 'dual')
        SizedBox(height: 24, child: Row(children: [key(state.t('device.on'), true), key(state.t('device.off'), false)])),
    ]);
    return Semantics(
      button: true,
      toggled: mode == 'toggle' ? on : null,
      label: mode == 'momentary' ? '${state.t('out.push')}: ${state.i18n.name(tag['display_name'])}' : null,
      child: Opacity(
        opacity: write == null ? 0.45 : (busy && mode != 'momentary' ? 0.6 : 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: on ? tk.accent : tk.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: on ? Colors.transparent : (mode == 'momentary' || editing ? tk.accentLine : tk.line2)),
            boxShadow: on ? [BoxShadow(color: tk.accentSoft, blurRadius: 22, offset: const Offset(0, 8))] : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onLongPress: rename,
              onTap: !enabled || mode == 'dual' ? null : (mode == 'momentary' ? push : () => write!(!on)),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.state, required this.tag, required this.busy, required this.write});

  final AppState state;
  final Map<String, dynamic> tag;
  final bool busy;
  final ValueChanged<Object?> write;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final states = (tag['states'] as Map?)?.map((k, v) => MapEntry(int.parse('$k'), '$v'));
    final writable = tag['writable'] == true && !busy;
    Widget control;
    if (states != null) {
      control = Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in states.entries)
          WebTab(e.value, on: tag['value'] == e.key, onTap: writable ? () => write(e.key) : null),
      ]);
    } else if (tag['data_type'] == 'bool') {
      control = TiSwitch(value: tag['value'] == true, onChanged: writable ? (v) => write(v) : null);
    } else {
      final value = (tag['value'] as num?)?.toDouble();
      final min = (tag['min'] as num?)?.toDouble() ?? 0;
      final max = (tag['max'] as num?)?.toDouble() ?? 100;
      control = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(onPressed: writable && value != null && value > min ? () => write(value - 1) : null,
            icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 72, child: Text(_value(s, tag), textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        IconButton.filledTonal(onPressed: writable && value != null && value < max ? () => write(value + 1) : null,
            icon: const Icon(Icons.add_rounded)),
      ]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.i18n.name(tag['display_name']), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          control,
        ]),
      ),
    ).withBottom(10);
  }
}

extension on Widget {
  Widget withBottom(double gap) => Padding(padding: EdgeInsets.only(bottom: gap), child: this);
}

/// An on/off input as a live state (the web app's sensorRow): red and pulsing while its security
/// alert is open; while naming, a touch opens its sheet.
class _SensorRow extends StatefulWidget {
  const _SensorRow({super.key, required this.state, required this.tag, this.alarm, this.flash = false,
      this.editing = false, this.onTap});

  final AppState state;
  final Map<String, dynamic> tag;
  final Map<String, dynamic>? alarm;
  final bool flash;
  final bool editing;
  final VoidCallback? onTap;

  @override
  State<_SensorRow> createState() => _SensorRowState();
}

class _SensorRowState extends State<_SensorRow> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final t = widget.tag;
    final live = widget.alarm != null && widget.alarm!['seen_at'] == null;
    if (live && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!live && _pulse.isAnimating) _pulse.stop();
    final on = t['value'] == true;
    final icon = outIcon(t) ?? 'sensor';
    final key = 'sensor.${icon}_${on ? 'on' : 'off'}';
    final words = s.i18n.has(key) ? s.t(key) : s.t(on ? 'sensor.active' : 'sensor.idle');
    final state = t['value'] == null ? '—' : live ? s.t('alarm.badge') : words;
    final color = widget.alarm != null ? alarmRed : on ? tk.ok : tk.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: widget.alarm != null ? alarmRed.withValues(alpha: 0.10 + 0.08 * _pulse.value) : tk.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.flash ? tk.accent : widget.alarm != null ? alarmRed.withValues(alpha: 0.5)
                  : widget.editing ? tk.accentLine : tk.line,
              width: widget.flash ? 2.5 : 1),
            boxShadow: widget.flash ? [BoxShadow(color: tk.accentGlow, blurRadius: 24)] : null,
          ),
          child: child,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                      color: live ? alarmRed : color.withValues(alpha: 0.14)),
                  child: Icon(iconFor(icon), size: 20, color: live ? Colors.white : color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.i18n.name(t['display_name']), style: TextStyle(color: tk.text))),
                if (widget.editing) Icon(Icons.edit_outlined, size: 18, color: tk.accent),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                      color: live ? alarmRed : color.withValues(alpha: 0.14)),
                  child: Text(state, style: TextStyle(fontSize: 12, fontWeight: live ? FontWeight.w800 : FontWeight.w500,
                      color: live ? Colors.white : color)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
