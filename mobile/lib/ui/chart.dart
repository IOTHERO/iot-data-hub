// The device page's 24-hour chart (the web app's sparkline: GET .../history) and its command
// log (GET .../commands: what was switched, by whom, and how far it got).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'kit.dart';

class HistoryChart extends StatefulWidget {
  const HistoryChart({super.key, required this.state, required this.deviceId, required this.tags});

  final AppState state;
  final String deviceId;
  final List<Map<String, dynamic>> tags;        // numeric readings the template marks for charts

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> {
  late Map<String, dynamic> tag = widget.tags.first;
  List<double> values = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.state.api.call('GET',
          '/api/platform/my/devices/${widget.deviceId}/history?tag=${tag['key']}&hours=24&points=96') as List;
      values = [for (final r in rows) if (r['value'] is num) (r['value'] as num).toDouble()];
      if (values.isNotEmpty && tag['value'] is num) values.add((tag['value'] as num).toDouble());   // up to now
    } on ApiError {
      values = [];
    }
    if (mounted) setState(() => loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final unit = tag['unit'] as String?;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the web app's head: a plain select of the charted values, the value now in large type
        Row(children: [
          Expanded(child: widget.tags.length > 1
              ? DropdownButtonHideUnderline(child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  value: tag['key'] as String,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tk.text),
                  items: [
                    for (final t in widget.tags)
                      DropdownMenuItem(value: t['key'] as String, child: Text(s.i18n.name(t['display_name']),
                          overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (k) {
                    final t = widget.tags.firstWhere((x) => x['key'] == k);
                    setState(() { tag = t; loaded = false; });
                    _load();
                  },
                ))
              : Text(s.i18n.name(tag['display_name']), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tk.text))),
          const SizedBox(width: 12),
          Text.rich(TextSpan(children: [
            TextSpan(text: tag['value'] is num ? s.i18n.num((tag['value'] as num).toDouble()) : '—',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: tk.text)),
            if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontSize: 12, color: tk.muted)),
          ]), textDirection: TextDirection.ltr),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: !loaded
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : values.length < 2
                  ? Center(child: Text(s.t('device.no_history'), style: TextStyle(color: tk.muted)))
                  : CustomPaint(painter: _Spark(values, tk.accent), size: Size.infinite),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(s.t('device.h24'), style: TextStyle(fontSize: 11, color: tk.muted)),
          const Spacer(),
          Text(s.t('device.now'), style: TextStyle(fontSize: 11, color: tk.muted)),
        ]),
      ]),
    );
  }
}

class _Spark extends CustomPainter {
  _Spark(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi - lo == 0 ? 1 : hi - lo;
    Offset at(int i) => Offset(size.width * i / (values.length - 1),
        size.height - 6 - (size.height - 12) * (values[i] - lo) / span);
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)]).createShader(Offset.zero & size));
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(at(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Spark old) => old.values != values || old.color != color;
}

class CommandLog extends StatefulWidget {
  const CommandLog({super.key, required this.state, required this.deviceId, required this.names});

  final AppState state;
  final String deviceId;
  final Map<String, String> names;                // tag key -> display name

  @override
  State<CommandLog> createState() => _CommandLogState();
}

class _CommandLogState extends State<CommandLog> {
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      rows = (await widget.state.api.call('GET', '/api/platform/my/devices/${widget.deviceId}/commands?limit=10') as List)
          .cast<Map<String, dynamic>>();
    } on ApiError {
      rows = [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();          // the web app shows nothing then
    const badge = {'confirmed': (BadgeTone.ok, Icons.check_rounded), 'executed': (BadgeTone.ok, Icons.check_rounded),
      'failed': (BadgeTone.warn, Icons.close_rounded), 'expired': (BadgeTone.warn, Icons.schedule_rounded)};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(s.t('device.commands'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text))),
      for (final c in rows.take(5)) ...[
        Builder(builder: (_) {
          final key = '${c['tag_path']}'.split('.').last;
          final name = widget.names[key] ?? key;
          final v = c['value'];
          final (tone, icon) = badge[c['status']] ?? (BadgeTone.wait, Icons.schedule_rounded);
          return CmdRow(icon: icon, tone: tone,
              text: v is bool ? s.t(v ? 'device.turned_on' : 'device.turned_off', {'name': name}) : '$name ← ${s.i18n.num(v)}',
              sub: '${s.t('command.${c['status']}')} · ${_who(s, '${c['reason'] ?? ''}')} · ${s.i18n.when(c['created_at'])}');
        }),
        const SizedBox(height: 10),
      ],
    ]);
  }

  String _who(AppState s, String reason) {
    if (reason.isEmpty || reason == 'app') return s.t('device.by_app');
    final m = RegExp(r'^(automation|scene):\d+\s*(.*)$').firstMatch(reason);
    if (m != null) return s.t(m[1] == 'automation' ? 'device.by_automation' : 'device.by_scene', {'name': m[2] ?? ''});
    return reason;
  }
}
