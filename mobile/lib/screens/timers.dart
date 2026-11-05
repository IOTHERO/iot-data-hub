// Timers of one device (GET/POST/DELETE /api/platform/my/devices/{id}/timers): what is set to
// switch when, cancel, and a new one-off timer ("turn X off in N minutes").

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';

class TimersCard extends StatefulWidget {
  const TimersCard({super.key, required this.state, required this.deviceId, required this.outputs});

  final AppState state;
  final String deviceId;
  final List<Map<String, dynamic>> outputs;       // writable digital outputs of the device

  @override
  State<TimersCard> createState() => _TimersCardState();
}

class _TimersCardState extends State<TimersCard> {
  List<Map<String, dynamic>> timers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _base => '/api/platform/my/devices/${widget.deviceId}/timers';

  Future<void> _load() async {
    try {
      final rows = await widget.state.api.call('GET', _base) as List;
      if (mounted) setState(() => timers = rows.cast<Map<String, dynamic>>());
    } on ApiError {
      // no timer rights: the card stays empty
    }
  }

  String _name(String key) {
    final t = widget.outputs.where((o) => o['key'] == key).firstOrNull;
    return t == null ? key : widget.state.i18n.name(t['display_name']);
  }

  String _describe(Map<String, dynamic> x) {
    final s = widget.state;
    final at = DateTime.tryParse('${x['at']}')?.toLocal();
    final when = at == null ? '' : ' · ${s.t('timer.at', {'at': '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'})}';
    if (x['mode'] == 'cycle') {
      return '${s.t('timer.running')} · ${_name('${x['tag']}')}';
    }
    return s.t(x['value'] == true ? 'timer.will_on' : 'timer.will_off', {'name': _name('${x['tag']}')}) + when;
  }

  Future<void> _cancel(Map<String, dynamic> x) async {
    try {
      await widget.state.api.call('DELETE', '$_base/${x['automation_id']}');
      _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _new() async {
    final s = widget.state;
    if (widget.outputs.isEmpty) return;
    var key = widget.outputs.first['key'] as String;
    var on = false;
    var minutes = 15.0;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('timer.new'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: key,
              items: [for (final o in widget.outputs)
                DropdownMenuItem(value: o['key'] as String, child: Text(s.i18n.name(o['display_name'])))],
              onChanged: (v) => set(() => key = v ?? key),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(s.t('device.turn_on'))),
                ButtonSegment(value: false, label: Text(s.t('device.turn_off'))),
              ],
              selected: {on},
              onSelectionChanged: (v) => set(() => on = v.first),
            ),
            const SizedBox(height: 12),
            Text('${s.t('timer.minutes')}: ${s.t('timer.min_n', {'n': minutes.round()})}'),
            Slider(value: minutes, min: 1, max: 240, divisions: 239, onChanged: (v) => set(() => minutes = v)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('timer.start'))),
          ]),
        ),
      )),
    );
    if (ok != true) return;
    try {
      await s.api.call('POST', _base, {'tag': key, 'mode': 'once', 'value': on, 'minutes': minutes.round()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('timer.started', {'n': minutes.round()}))));
      }
      _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (timers.isEmpty) ListTile(title: Text(s.t('timer.none'))),
        for (final x in timers)
          ListTile(
            leading: Icon(x['mode'] == 'cycle' ? Icons.repeat_rounded : Icons.timer_outlined),
            title: Text(_describe(x)),
            trailing: IconButton(tooltip: s.t('timer.cancel'), icon: const Icon(Icons.close_rounded),
                onPressed: () => _cancel(x)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: OutlinedButton.icon(onPressed: widget.outputs.isEmpty ? null : _new,
              icon: const Icon(Icons.add_rounded), label: Text(s.t('timer.new'))),
        ),
      ]),
    );
  }
}
