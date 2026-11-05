// What happened lately (GET /api/platform/my/notifications): a device went offline, a command
// failed or expired, an automation did not complete. A tap opens the device.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'device.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>>? rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      rows = (await widget.state.api.call('GET', '/api/platform/my/notifications${widget.state.query()}') as List)
          .cast<Map<String, dynamic>>();
    } on ApiError {
      rows = [];
    }
    if (mounted) setState(() {});
  }

  static const _icons = {
    'offline': Icons.wifi_off_rounded,
    'command_failed': Icons.error_outline_rounded,
    'command_expired': Icons.hourglass_bottom_rounded,
    'automation_failed': Icons.error_outline_rounded,
    'automation_partial': Icons.warning_amber_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final list = rows;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('nav.notifications'))),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (list.isEmpty) Text(s.t('note.none')),
                for (final n in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(_icons[n['kind']] ?? Icons.notifications_rounded),
                      title: Text(s.t('note.${n['kind']}', {
                        'device': n['device'] ?? '', 'automation': n['automation'] ?? '', 'tag': n['tag'] ?? ''})),
                      subtitle: Text(_when(s, '${n['at']}')),
                      onTap: n['device_id'] == null ? null : () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => DeviceScreen(state: s, deviceId: n['device_id'] as String))),
                    ),
                  ),
              ]),
            ),
    );
  }

  String _when(AppState s, String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${s.i18n.num('${two(t.hour)}:${two(t.minute)}')} · ${s.i18n.date(t)}';
  }
}
