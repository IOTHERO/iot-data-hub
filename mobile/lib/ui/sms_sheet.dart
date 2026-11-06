// The signed SMS for a device (the web app's smsSheet): choose outputs on / off / unchanged and
// send or copy "HUB <counter> relay_1=1 <sig>". Used from the device settings and as the last way
// to a device when neither the internet nor the home Wi-Fi reaches it (connection.dart).

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'kit.dart';

/// "HUB <counter> relay_1=1 relay_3=0 <sig>": sig = the first 8 bytes of
/// HMAC-SHA256(key, "<device_id> <counter> <items...>") in hex (backend/api/home.py sms_signature).
String smsSignature(String key, String deviceId, int counter, List<String> items) {
  final raw = base64Url.decode(key + '=' * ((4 - key.length % 4) % 4));
  final mac = Hmac(sha256, raw).convert(utf8.encode([deviceId, '$counter', ...items].join(' ')));
  return mac.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The sheet; [outputs] and [settings] are read from the hub (or the phone's copy) when not given,
/// [preset] chooses changes in advance (the command that did not get through).
Future<void> showSmsSheet(BuildContext context, AppState s, String deviceId,
    {List<Map<String, dynamic>>? outputs, Map<String, dynamic>? settings, Map<String, bool> preset = const {}}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    settings ??= await s.api.call('GET', '/api/platform/my/devices/$deviceId/sms') as Map<String, dynamic>;
  } on ApiError {
    settings = null;
  }
  if (settings == null || settings['enabled'] != true || settings['key'] == null) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('sms.not_enabled'))));
    return;
  }
  if (outputs == null) {
    try {
      final view = await s.api.call('GET', '/api/platform/my/devices/$deviceId/view') as Map<String, dynamic>;
      outputs = (view['tags'] as List).cast<Map<String, dynamic>>()
          .where((t) => t['kind'] == 'digital_output' && t['writable'] == true).toList();
    } on ApiError {
      outputs = [for (final k in preset.keys) {'key': k, 'display_name': k}];
    }
  }
  if (!context.mounted) return;
  final key = '${settings['key']}';
  final phone = settings['phone'];
  final list = outputs;
  final states = Map<String, bool>.of(preset);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final items = [for (final e in states.entries) '${e.key}=${e.value ? 1 : 0}'];
      var message = '';
      if (items.isNotEmpty) {
        final last = int.tryParse(s.store.get('sms.n.$deviceId') ?? '') ?? 0;   // above every earlier one
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final n = now > last ? now : last + 1;
        message = 'HUB $n ${items.join(' ')} ${smsSignature(key, deviceId, n, items)}';
      }
      return SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
        Text(s.t('sms.compose'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(s.t('sms.offline_hint'), style: TextStyle(fontSize: 12, color: Tk.of(c).muted)),
        for (final t in list)
          ListTile(
            title: Text(s.i18n.name(t['display_name'])),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: -1, label: Text(s.t('sms.no_change'))),
                ButtonSegment(value: 1, label: Text(s.t('device.on'))),
                ButtonSegment(value: 0, label: Text(s.t('device.off'))),
              ],
              selected: {states.containsKey(t['key']) ? (states[t['key']]! ? 1 : 0) : -1},
              onSelectionChanged: (v) => set(() => v.first == -1 ? states.remove(t['key']) : states[t['key'] as String] = v.first == 1),
            ),
          ),
        const SizedBox(height: 10),
        SelectableText(message.isEmpty ? s.t('sms.pick') : message, textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace')),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.sms_rounded),
          label: Text(s.t('sms.send')),
          onPressed: message.isEmpty || phone == null ? null : () async {
            await s.store.set('sms.n.$deviceId', message.split(' ')[1]);
            await launchUrl(Uri(scheme: 'sms', path: '$phone', queryParameters: {'body': message}));
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: message.isEmpty ? null : () async {
            await s.store.set('sms.n.$deviceId', message.split(' ')[1]);
            await Clipboard.setData(ClipboardData(text: message));
            if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s.t('sms.copied'))));
          },
          child: Text(s.t('sms.copy')),
        ),
      ]));
    }),
  );
}
