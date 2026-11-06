// Energy: this month's use (and cost when the home has a tariff), the last 30 days as bars and
// the share of each device (GET /api/platform/my/energy).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'home_settings.dart';
import 'device.dart';
import '../ui/kit.dart';

class EnergyScreen extends StatefulWidget {
  const EnergyScreen({super.key, required this.state});

  final AppState state;

  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _EnergyScreenState extends State<EnergyScreen> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await widget.state.api.call('GET', '/api/platform/my/energy${widget.state.query()}') as Map<String, dynamic>;
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final d = data;
    if (d == null) {
      return WebPage(title: s.t('energy.title'), children: [
        Center(child: error == null ? const CircularProgressIndicator() : Text(error!)),
      ]);
    }
    final month = d['month'] as Map<String, dynamic>;
    final days = (d['days'] as List).cast<Map<String, dynamic>>();
    final devices = (d['devices'] as List).cast<Map<String, dynamic>>();
    double kwh(Object? v) => ((v as num?) ?? 0).toDouble();
    final top = days.fold<double>(1, (a, x) => kwh(x['kwh']) > a ? kwh(x['kwh']) : a);
    final cost = month['cost'];
    final home = s.homes.where((h) => h['org_id'] == s.home).firstOrNull
        ?? s.homes.where((h) => h['personal'] == true).firstOrNull;
    final small = TextStyle(fontSize: 11, color: tk.muted);
    return WebPage(title: s.t('energy.title'), children: [
      Row(children: [            // .stats
        StatTile(label: s.t('energy.month', {'m': s.i18n.num(month['jalali'])}), value: s.i18n.num(kwh(month['kwh'])), unit: 'kWh'),
        const SizedBox(width: 10),
        StatTile(label: s.t('energy.today'), value: days.isEmpty ? '—' : s.i18n.num(kwh(days.last['kwh'])), unit: 'kWh'),
        const SizedBox(width: 10),
        StatTile(label: s.t('energy.cost'), value: cost != null ? s.i18n.num(cost) : '—', unit: '${month['currency'] ?? ''}'),
      ]),
      WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(s.t('energy.days'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text))),
          Text(s.t('energy.max', {'n': s.i18n.num((top * 10).round() / 10)}), style: small),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 120, child: _Bars(days: days, color: tk.accent)),
        const SizedBox(height: 8),
        if (days.isNotEmpty)
          Row(children: [
            Text(s.i18n.num(days.first['jalali']), style: small),
            const Spacer(),
            Text(s.i18n.num(days.last['jalali']), style: small),
          ]),
      ])),
      if (month['peak_kwh'] != null && kwh(month['peak_kwh']) > 0)
        Text(s.t('energy.peak', {'n': s.i18n.num(kwh(month['peak_kwh']))}), style: TextStyle(fontSize: 13, color: tk.muted)),
      if (cost == null && home != null)
        WebCard(
          tight: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HomeSettingsScreen(state: s, home: home))),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: tk.surface2, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.bolt_rounded, color: tk.text)),
            const SizedBox(width: 12),
            Expanded(child: Text(s.t('energy.set_tariff'), style: TextStyle(fontSize: 13, color: tk.text))),
            Icon(Icons.chevron_left_rounded, color: tk.muted),
          ]),
        ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('energy.by_device'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text)),
        const SizedBox(height: 12),
        if (devices.isEmpty) Text(s.t('energy.none'), style: TextStyle(fontSize: 13, color: tk.muted)),
        for (final x in devices) ...[
          Reading(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => DeviceScreen(state: s, deviceId: x['device_id'] as String))),
            start: Text('${x['name']}', style: TextStyle(color: tk.text)),
            end: Text.rich(TextSpan(children: [
              TextSpan(text: s.i18n.num(kwh(x['kwh'])), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
              TextSpan(text: ' kWh', style: small),
            ])),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    ]);
  }
}

/// svg.bars: one 6 px bar a day, rounded, in the accent (85 %).
class _Bars extends StatelessWidget {
  const _Bars({required this.days, required this.color});

  final List<Map<String, dynamic>> days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final values = [for (final x in days) ((x['kwh'] as num?) ?? 0).toDouble()];
    final top = values.fold<double>(1, (a, b) => b > a ? b : a);
    return Directionality(
      textDirection: TextDirection.ltr,           // oldest at the left, as the web chart
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Tooltip(
              message: '${days[i]['jalali']}: ${values[i].toStringAsFixed(1)} kWh',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: (values[i] / top * 108).clamp(1, 108).toDouble(),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
      ]),
    );
  }
}
