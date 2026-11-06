// A device's settings (the web app's device settings page): name and room, sharing with other
// people, handing it over or removing it (with the one-time code for the next owner), the
// signed-SMS fallback for when both internet and Wi-Fi are gone, a support request to its
// maker, and what it is (product, firmware, warranty).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/sms_sheet.dart';
import '../ui/widgets.dart';

import 'device.dart';
import 'edge_add.dart';

export '../ui/sms_sheet.dart' show smsSignature;

class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key, required this.state, required this.view});

  final AppState state;
  final Map<String, dynamic> view;

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  late final Map<String, dynamic> d = widget.view['device'] as Map<String, dynamic>;
  late final _name = TextEditingController(text: '${d['name'] ?? ''}');
  late final _room = TextEditingController(text: '${d['room'] ?? ''}');
  final _shareEmail = TextEditingController();
  String _shareLevel = 'viewer';
  Map<String, dynamic>? shares;
  Map<String, dynamic>? sms;
  String? code;                         // a one-time code just made (transfer / removal)
  Uint8List? image;                     // the product's picture
  Map<String, dynamic>? brand;          // the maker as it presents itself
  Map<String, dynamic>? rules;          // what the device decides by itself (native devices)
  List<Map<String, dynamic>>? children; // equipment behind an edge hub

  String get id => d['device_id'] as String;
  bool get owner => d['access'] == 'owner';
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    if (owner) {
      s.api.call('GET', '/api/platform/devices/$id/shares').then((r) {
        if (mounted) setState(() => shares = r as Map<String, dynamic>);
      }).catchError((_) {});
    }
    s.api.call('GET', '/api/platform/my/devices/$id/sms').then((r) {
      if (mounted) setState(() => sms = r as Map<String, dynamic>);
    }).catchError((_) {});
    if (d['product_has_image'] == true) {
      s.api.bytes('/api/platform/products/${d['product_id']}/image').then((b) {
        if (mounted && b != null) setState(() => image = b);
      });
    }
    if (d['maker_org_id'] != null) {
      s.api.public('GET', '/api/public/brand/${d['maker_org_id']}', null).then((r) {
        if (mounted) setState(() => brand = r as Map<String, dynamic>);
      }).catchError((_) {});
    }
    if (d['protocol'] == 'native') {
      s.api.call('GET', '/api/platform/my/devices/$id/local-rules').then((r) {
        if (mounted) setState(() => rules = r as Map<String, dynamic>);
      }).catchError((_) {});
    }
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    if (d['product_kind'] != 'edge_hub' || !owner) return;
    try {
      final mine = (await s.api.call('GET', '/api/platform/my/devices') as List).cast<Map<String, dynamic>>();
      children = mine.where((x) => x['parent_device_id'] == id).toList();
    } on ApiError {
      children = [];
    }
    if (mounted) setState(() {});
  }

  Future<bool> _do(Future<dynamic> Function() action, [String? done]) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      return true;
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message)));
      return false;
    }
  }

  Future<bool> _confirm(String text) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('device.yes'))),
        ],
      )) == true;

  Future<void> _saveNameRoom() async {
    await _do(() async {
      if (_name.text.trim() != '${d['name'] ?? ''}' && owner) {
        await s.api.call('PATCH', '/api/platform/my/devices/$id', {'name': _name.text.trim()});
      }
      await s.api.call('PUT', '/api/platform/my/devices/$id/room', {'room': _room.text.trim()});
    }, s.t('common.saved'));
  }

  Future<void> _transfer() async {
    if (!await _confirm(s.t('owner.transfer_confirm'))) return;
    await _do(() async {
      final r = await s.api.call('POST', '/api/platform/my/devices/$id/transfer') as Map<String, dynamic>;
      setState(() => code = '${r['claim_code']}');
    });
  }

  Future<void> _remove() async {
    if (!await _confirm(s.t('owner.remove_confirm'))) return;
    final ok = await _do(() async {
      final r = await s.api.call('DELETE', '/api/platform/my/devices/$id') as Map<String, dynamic>;
      code = '${r['claim_code']}';
    }, s.t('owner.removed'));
    if (!ok || !mounted) return;
    await showDialog(context: context, builder: (c) => AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s.t('owner.removed_hint')),
        const SizedBox(height: 12),
        SelectableText(code ?? '', textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(s.t('owner.done')))],
    ));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _newTicket() async {
    final subject = TextEditingController();
    final body = TextEditingController();
    var kind = 'support';
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('tickets.new'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'support', label: Text(s.t('tickets.kind_support'))),
              ButtonSegment(value: 'warranty', label: Text(s.t('tickets.kind_warranty'))),
            ],
            selected: {kind},
            onSelectionChanged: (v) => set(() => kind = v.first),
          ),
          const SizedBox(height: 10),
          TextField(controller: subject, decoration: InputDecoration(labelText: s.t('tickets.subject'),
              hintText: s.t('tickets.subject_hint'))),
          const SizedBox(height: 10),
          TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: s.t('tickets.body'),
              hintText: s.t('tickets.body_hint'))),
          const SizedBox(height: 6),
          Text(s.t('tickets.privacy'), style: TextStyle(fontSize: 11, color: Tk.of(c).muted)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('tickets.send'))),
        ]),
      )),
    );
    if (sent != true) return;
    await _do(() => s.api.call('POST', '/api/platform/my/devices/$id/tickets',
        {'kind': kind, 'subject': subject.text.trim(), 'body': body.text.trim()}), s.t('tickets.sent'));
  }

  // --- signed SMS ----------------------------------------------------------------------------

  Future<void> _smsSave({bool newKey = false, String? phone}) async {
    await _do(() async {
      await s.api.call('PUT', '/api/platform/my/devices/$id/sms', {'phone': phone ?? sms?['phone'], 'new_key': newKey});
      sms = await s.api.call('GET', '/api/platform/my/devices/$id/sms') as Map<String, dynamic>;
      setState(() {});
    }, s.t('common.saved'));
  }

  Future<void> _smsCompose() => showSmsSheet(context, s, id, settings: sms,
      outputs: (widget.view['tags'] as List).cast<Map<String, dynamic>>()
          .where((t) => t['kind'] == 'digital_output' && t['writable'] == true).toList());

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final list = [
      ...((shares?['shares'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      for (final i in ((shares?['invitations'] as List?) ?? const []).cast<Map<String, dynamic>>()) {...i, 'pending': true},
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('device.settings_page'))),
      body: GlowPage(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Section(icon: Icons.edit_outlined, title: s.t('device.name_room'), children: [
          if (owner) ...[
            TextField(controller: _name, decoration: InputDecoration(labelText: s.t('device.name'))),
            const SizedBox(height: 10),
          ],
          TextField(controller: _room, decoration: InputDecoration(labelText: s.t('device.room'), hintText: s.t('device.room_hint'))),
          const SizedBox(height: 12),
          FilledButton(onPressed: _saveNameRoom, child: Text(s.t('common.save'))),
        ]),
        if (owner)
          Section(icon: Icons.share_outlined, title: s.t('share.title'), children: [
            GlassCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [
              if (list.isEmpty) ListTile(title: Text(s.t('share.none'), style: TextStyle(color: tk.muted))),
              for (final x in list)
                ListTile(
                  title: Text('${x['org_name'] ?? x['email'] ?? '—'}'),
                  subtitle: Text('${s.t('access.${x['level']}')}${x['pending'] == true ? ' · ${s.t('share.pending')}' : ''}'),
                  trailing: IconButton(
                    tooltip: s.t('share.revoke'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      if (!await _confirm(s.t('share.revoke_confirm'))) return;
                      final ok = await _do(() => x['pending'] == true
                          ? s.api.call('DELETE', '/api/platform/organizations/${x['org_id']}/invitations/${x['invitation_id']}')
                          : s.api.call('DELETE', '/api/platform/devices/$id/shares/${x['access_id']}'));
                      if (ok) setState(() => shares = null);
                      s.api.call('GET', '/api/platform/devices/$id/shares').then((r) {
                        if (mounted) setState(() => shares = r as Map<String, dynamic>);
                      });
                    },
                  ),
                ),
            ])),
            const SizedBox(height: 10),
            TextField(controller: _shareEmail, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('share.email'))),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'operator', label: Text(s.t('access.operator'))),
                ButtonSegment(value: 'viewer', label: Text(s.t('access.viewer'))),
              ],
              selected: {_shareLevel},
              onSelectionChanged: (v) => setState(() => _shareLevel = v.first),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                final ok = await _do(() => s.api.call('POST', '/api/platform/devices/$id/shares',
                    {'email': _shareEmail.text.trim(), 'level': _shareLevel}), s.t('share.sent'));
                if (ok) {
                  _shareEmail.clear();
                  final r = await s.api.call('GET', '/api/platform/devices/$id/shares');
                  if (mounted) setState(() => shares = r as Map<String, dynamic>);
                }
              },
              child: Text(s.t('share.send')),
            ),
          ]),
        if (sms != null)
          Section(icon: Icons.sms_outlined, title: s.t('sms.title'), hint: s.t('sms.help'), children: [
            GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (sms!['enabled'] == true) ...[
                Text('${s.t('sms.phone')}: ${sms!['phone'] ?? '—'}', textDirection: TextDirection.ltr),
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: _smsCompose, icon: const Icon(Icons.edit_note_rounded), label: Text(s.t('sms.compose'))),
                if (owner) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: () => _smsSave(newKey: true), child: Text(s.t('sms.new_key'))),
                  Text(s.t('sms.new_key_help'), style: TextStyle(fontSize: 11, color: tk.muted)),
                ],
              ] else
                Text(s.t(owner ? 'sms.not_enabled' : 'sms.go_settings'), style: TextStyle(color: tk.muted)),
              if (owner && sms!['enabled'] != true) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () async {
                    final phone = TextEditingController();
                    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                      title: Text(s.t('sms.phone')),
                      content: TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr),
                      actions: [FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('sms.enable')))],
                    ));
                    if (ok == true) _smsSave(phone: phone.text.trim());
                  },
                  child: Text(s.t('sms.enable')),
                ),
              ],
            ])),
          ]),
        Section(icon: Icons.support_agent_rounded, title: s.t('tickets.title'), children: [
          OutlinedButton.icon(onPressed: _newTicket, icon: const Icon(Icons.add_comment_outlined), label: Text(s.t('tickets.new'))),
        ]),
        if (children != null)
          Section(icon: Icons.hub_rounded, title: s.t('edge.behind'), children: [
            GlassCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [
              if (children!.isEmpty) ListTile(title: Text(s.t('edge.none'), style: TextStyle(color: tk.muted))),
              for (final c in children!)
                ListTile(
                  title: Text('${c['name']}'),
                  subtitle: Text(s.i18n.has('proto.${c['protocol']}') ? s.t('proto.${c['protocol']}') : '${c['protocol']}'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DeviceScreen(state: s, deviceId: c['device_id'] as String))),
                  trailing: IconButton(
                    tooltip: s.t('edge.remove'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (!await _confirm(s.t('edge.remove_confirm', {'name': '${c['name']}'}))) return;
                      if (await _do(() => s.api.call('DELETE', '/api/platform/my/devices/$id/children/${c['device_id']}'))) {
                        _loadChildren();
                      }
                    },
                  ),
                ),
            ])),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final added = await Navigator.push<bool>(context, MaterialPageRoute(
                    builder: (_) => EdgeAddScreen(state: s, hubId: id)));
                if (added == true) _loadChildren();
              },
              icon: const Icon(Icons.add_rounded), label: Text(s.t('edge.add')),
            ),
          ]),
        if (rules != null)
          Section(icon: Icons.memory_rounded, title: s.t('local.title'), hint: s.t('local.help'), children: [
            GlassCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [
              if (((rules!['rules'] as List?) ?? const []).isEmpty)
                ListTile(title: Text(s.t('local.none'), style: TextStyle(color: tk.muted))),
              for (final r in ((rules!['rules'] as List?) ?? const []).cast<Map>())
                ListTile(
                  dense: true,
                  title: Text('${r['name']}'),
                  trailing: Text(s.t('local.on_device'), style: TextStyle(color: tk.ok, fontWeight: FontWeight.w700)),
                ),
              ListTile(dense: true, leading: Icon(Icons.info_outline_rounded, color: tk.muted),
                  title: Text(s.t('local.how'), style: TextStyle(fontSize: 12, color: tk.muted))),
            ])),
          ]),
        Section(icon: Icons.info_outline_rounded, title: s.t('device.settings'), children: [
          GlassCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: image != null
                    ? Image.memory(image!, width: 48, height: 48, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.memory_rounded, color: tk.accent))
                    : SizedBox(width: 48, height: 48, child: Icon(Icons.memory_rounded, color: tk.accent)),
              ),
              title: Text('${widget.view['product'] ?? d['product_name'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${d['identifier']}', textDirection: TextDirection.ltr),
            ),
            if (brand != null)
              ListTile(
                dense: true,
                title: Text(s.t('device.maker')),
                trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${brand!['display_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (brand!['support_phone'] != null)
                    InkWell(onTap: () => launchUrl(Uri(scheme: 'tel', path: '${brand!['support_phone']}')),
                        child: Text('${brand!['support_phone']}', textDirection: TextDirection.ltr,
                            style: TextStyle(fontSize: 11, color: tk.accent))),
                  if (brand!['support_email'] != null)
                    InkWell(onTap: () => launchUrl(Uri(scheme: 'mailto', path: '${brand!['support_email']}')),
                        child: Text('${brand!['support_email']}', textDirection: TextDirection.ltr,
                            style: TextStyle(fontSize: 11, color: tk.accent))),
                ]),
              ),
            ListTile(dense: true, title: Text(s.t('device.firmware')),
                trailing: Text('${d['firmware_version'] ?? '—'}', textDirection: TextDirection.ltr)),
            ListTile(dense: true, title: Text(s.t('device.protocol')), trailing: Text('${d['protocol'] ?? ''} · ${d['identifier']}',
                textDirection: TextDirection.ltr)),
            if (d['warranty_until'] != null)
              ListTile(dense: true, title: Text(s.t('device.warranty')),
                  trailing: Text(s.i18n.date(DateTime.parse('${d['warranty_until']}')))),
            ListTile(dense: true, title: Text(s.t('device.access')), trailing: Text(s.t('access.${d['access']}'))),
          ])),
        ]),
        if (owner)
          Section(icon: Icons.swap_horiz_rounded, title: s.t('owner.transfer'), children: [
            OutlinedButton(onPressed: _transfer, child: Text(s.t('owner.transfer'))),
            if (code != null) ...[
              const SizedBox(height: 10),
              Text(s.t('owner.transfer_hint')),
              SelectableText(code!, textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
            ],
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _remove,
              style: OutlinedButton.styleFrom(foregroundColor: tk.warn, side: BorderSide(color: tk.warn.withValues(alpha: 0.5))),
              child: Text(s.t('owner.remove')),
            ),
          ]),
      ])),
    );
  }
}
