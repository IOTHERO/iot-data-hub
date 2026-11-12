// A central hub (ESP32, firmware/esp32-hub) on its device page, as the web app's hubCard
// (views.js): its link, the modules behind it, its alarms, its scenes (run one) and what they
// did; for a module behind a hub one line saying so. Nothing for any other device.
// GET /api/platform/my/devices/{id}/hub, POST .../hub/scenes/{scene}/run.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'kit.dart';

class HubCard extends StatefulWidget {
  const HubCard({super.key, required this.state, required this.deviceId, required this.owner});

  final AppState state;
  final String deviceId;
  final bool owner;

  @override
  State<HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<HubCard> {
  Map<String, dynamic>? data;

  AppState get s => widget.state;
  String get _base => '/api/platform/my/devices/${widget.deviceId}/hub';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await s.api.call('GET', _base) as Map<String, dynamic>;
    } on ApiError {
      data = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _run(String sceneId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.api.call('POST', '$_base/scenes/${Uri.encodeComponent(sceneId)}/run');
      messenger.showSnackBar(SnackBar(content: Text(s.t('hub.scene_sent'))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) return const SizedBox.shrink();
    final tk = Tk.of(context);
    if (d['state'] == 'unknown') {
      if (d['behind_hub'] == null) return const SizedBox.shrink();
      return WebCard(tight: true, child: Row(children: [
        Icon(Icons.hub_outlined, color: tk.accent),
        const SizedBox(width: 12),
        Expanded(child: Text(s.t('hub.behind'), style: TextStyle(fontSize: 13, color: tk.text))),
      ]));
    }
    final online = d['state'] == 'online';
    final modules = (d['modules'] as List?) ?? const [];
    final alarms = ((d['alarms'] as List?) ?? const []).whereType<Map>().toList();
    final scenes = ((d['scenes'] as List?) ?? const []).whereType<Map>().toList();
    final log = ((d['scene_log'] as List?) ?? const []).whereType<Map>().toList().reversed.take(5).toList();
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: tk.muted))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
          ]),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(text, style: TextStyle(fontSize: 12, color: tk.muted)),
        );
    return WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.hub_outlined, color: tk.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(s.t('hub.title'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text))),
        Text(s.t(online ? 'device.online' : 'device.offline'),
            style: TextStyle(color: online ? tk.ok : tk.warn, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      row(s.t('hub.modules'),
          '${s.i18n.num(d['online_count'] ?? modules.length)} / ${s.i18n.num(d['module_count'] ?? modules.length)}'),
      if (d['local_addr'] != null) row(s.t('hub.address'), '${d['local_addr']}'),
      if (alarms.isNotEmpty) ...[
        label(s.t('hub.alarms')),
        for (final a in alarms)
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: tk.warn),
            const SizedBox(width: 6),
            Expanded(child: Text('${a['text'] ?? a['code']}', style: TextStyle(color: tk.warn))),
          ]),
      ],
      if (scenes.isNotEmpty) ...[
        label(s.t('hub.scenes')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final sc in scenes)
            ActionChip(
              avatar: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text('${sc['name'] ?? sc['id']}'),
              onPressed: widget.owner && online ? () => _run('${sc['id']}') : null,
            ),
        ]),
      ],
      if (log.isNotEmpty) ...[
        label(s.t('hub.scene_log')),
        for (final e in log) row('${e['scene'] ?? '—'}', s.i18n.when(e['at'])),
      ],
      const SizedBox(height: 8),
      Text(s.t('hub.help'), style: TextStyle(fontSize: 12, height: 1.7, color: tk.muted)),
    ]));
  }
}
