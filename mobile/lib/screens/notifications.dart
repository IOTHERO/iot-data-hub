// What happened lately (GET /api/platform/my/notifications): a device went offline, a command
// failed or expired, an automation did not complete. A tap opens the device.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import 'alerts.dart';
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

  static const _tone = {'offline': BadgeTone.warn, 'command_failed': BadgeTone.warn, 'command_expired': BadgeTone.warn,
    'automation_failed': BadgeTone.warn, 'automation_partial': BadgeTone.wait};

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final list = rows;
    return WebPage(title: s.t('nav.notifications'), children: [
      AlarmBar(state: s),                       // open alarms first, they need a person
      if (list == null)
        const Center(child: CircularProgressIndicator())
      else if (list.isEmpty)
        EmptyCard(icon: Icons.notifications_none_rounded, text: s.t('note.none'))
      else
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final n in list) ...[
            CmdRow(
              icon: _icons[n['kind']] ?? Icons.notifications_none_rounded,
              tone: _tone[n['kind']] ?? BadgeTone.wait,
              text: s.t('note.${n['kind']}', {'device': n['device'] ?? '', 'automation': n['automation'] ?? '', 'tag': n['tag'] ?? ''}),
              sub: s.i18n.when(n['at']),
              onTap: n['device_id'] == null ? null : () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DeviceScreen(state: s, deviceId: n['device_id'] as String))),
            ),
            const SizedBox(height: 10),
          ],
        ]),
    ]);
  }
}
