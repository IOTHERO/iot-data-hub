// Energy: this month's use (and cost when the home has a tariff), the last 30 days as bars and
// the share of each device (GET /api/platform/my/energy).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/widgets.dart';

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
    final d = data;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('energy.title'))),
      body: d == null
          ? Center(child: error == null ? const CircularProgressIndicator() : Text(error!))
          : ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
              () {
                final month = d['month'] as Map<String, dynamic>;
                return Section(icon: Icons.bolt_rounded, title: s.t('energy.month', {'m': month['jalali']}), children: [
                  Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s.i18n.num((month['kwh'] as num).toDouble())} kWh',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                      if (month['cost'] != null)
                        Text('${s.t('energy.cost')}: ${s.i18n.num(month['cost'])} ${month['currency'] ?? ''}')
                      else
                        Text(s.t('energy.set_tariff'), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                    ]),
                  )),
                ]);
              }(),
              Section(icon: Icons.bar_chart_rounded, title: s.t('energy.chart'), children: [
                Card(child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                  child: SizedBox(height: 160, child: _Bars(days: (d['days'] as List).cast<Map<String, dynamic>>(), color: cs.primary)),
                )),
              ]),
              Section(icon: Icons.devices_rounded, title: s.t('energy.by_device'), children: [
                Card(child: Column(children: [
                  for (final x in (d['devices'] as List).cast<Map<String, dynamic>>())
                    ListTile(title: Text('${x['name']}'),
                        trailing: Text('${s.i18n.num((x['kwh'] as num).toDouble())} kWh',
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                ])),
              ]),
            ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.days, required this.color});

  final List<Map<String, dynamic>> days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final values = [for (final x in days) ((x['kwh'] as num?) ?? 0).toDouble()];
    final top = values.fold<double>(0, (a, b) => b > a ? b : a);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < values.length; i++)
        Expanded(
          child: Tooltip(
            message: '${days[i]['jalali']}: ${values[i].toStringAsFixed(1)} kWh',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              height: top == 0 ? 2 : 4 + 150 * values[i] / top,
              decoration: BoxDecoration(
                color: color.withValues(alpha: i == values.length - 1 ? 1 : 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
    ]);
  }
}
