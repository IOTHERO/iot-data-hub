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

import 'device.dart';
import 'tickets.dart';
import 'home.dart' show protoLabel;
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
  List<Map<String, dynamic>>? tickets;  // this device's support requests
  late final _smsPhone = TextEditingController();

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
      if (mounted) setState(() { sms = r as Map<String, dynamic>; _smsPhone.text = '${sms!['phone'] ?? ''}'; });
    }).catchError((_) {});
    if (owner) _loadTickets();
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
          WebField(label: s.t('tickets.subject'), child: TextField(controller: subject, decoration: InputDecoration(hintText: s.t('tickets.subject_hint')))),
          const SizedBox(height: 10),
          WebField(label: s.t('tickets.body'), child: TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(hintText: s.t('tickets.body_hint')))),
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

  Future<void> _loadTickets() async {
    try {
      final r = await s.api.call('GET', '/api/platform/my/tickets?device=${Uri.encodeQueryComponent(id)}') as List;
      if (mounted) setState(() => tickets = r.cast<Map<String, dynamic>>());
    } on ApiError {
      // no support desk: the section keeps only its button
    }
  }

  // --- signed SMS ----------------------------------------------------------------------------

  Future<void> _smsSave({bool newKey = false}) async {
    if (newKey && !await _confirm(s.t('sms.new_key_help'))) return;
    await _do(() async {
      final phone = _smsPhone.text.trim();
      final r = await s.api.call('PUT', '/api/platform/my/devices/$id/sms',
          {'phone': phone.isEmpty ? null : phone, if (newKey) 'new_key': true});
      sms = await s.api.call('GET', '/api/platform/my/devices/$id/sms') as Map<String, dynamic>;
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            s.t(r is Map && r['sent_to_device'] == true ? 'sms.saved_sent' : 'sms.saved_later'))));
      }
    });
  }

  Future<void> _smsOff() async {
    await _do(() async {
      await s.api.call('DELETE', '/api/platform/my/devices/$id/sms');
      sms = await s.api.call('GET', '/api/platform/my/devices/$id/sms') as Map<String, dynamic>;
      setState(() {});
    });
  }

  Future<void> _smsCompose() => showSmsSheet(context, s, id, settings: sms,
      outputs: (widget.view['tags'] as List).cast<Map<String, dynamic>>()
          .where((t) => t['kind'] == 'digital_output' && t['writable'] == true).toList());

  Future<void> _share() async {
    final ok = await _do(() => s.api.call('POST', '/api/platform/devices/$id/shares',
        {'email': _shareEmail.text.trim(), 'level': _shareLevel}), s.t('share.sent'));
    if (!ok) return;
    _shareEmail.clear();
    final r = await s.api.call('GET', '/api/platform/devices/$id/shares');
    if (mounted) setState(() => shares = r as Map<String, dynamic>);
  }

  Future<void> _revoke(Map<String, dynamic> x) async {
    if (!await _confirm(s.t('share.revoke_confirm'))) return;
    final ok = await _do(() => x['pending'] == true
        ? s.api.call('DELETE', '/api/platform/organizations/${x['org_id']}/invitations/${x['invitation_id']}')
        : s.api.call('DELETE', '/api/platform/devices/$id/shares/${x['access_id']}'));
    if (!ok) return;
    final r = await s.api.call('GET', '/api/platform/devices/$id/shares');
    if (mounted) setState(() => shares = r as Map<String, dynamic>);
  }

  Widget _h2(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Tk.of(context).text)),
      );

  /// .reading as the web app's fact(): the muted name at the start, the value at the end.
  Widget _fact(String label, Widget value) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Reading(start: Text(label, style: TextStyle(color: Tk.of(context).muted)), end: value),
      );

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final shared = [
      ...((shares?['shares'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      for (final i in ((shares?['invitations'] as List?) ?? const []).cast<Map<String, dynamic>>()) {...i, 'pending': true},
    ];
    final outputs = (widget.view['tags'] as List).cast<Map<String, dynamic>>()
        .where((t) => t['kind'] == 'digital_output' && t['writable'] == true).toList();
    final warrantyUntil = d['warranty_until'] == null ? null : DateTime.tryParse('${d['warranty_until']}');
    final value = TextStyle(color: tk.text);
    const ticketTone = {'answered': ChipTone.accent, 'in_progress': ChipTone.violet, 'approved': ChipTone.ok,
      'rejected': ChipTone.warn};          // the web app's TICKET_TONE
    final sms = this.sms;
    final smsOn = sms?['enabled'] == true;
    return WebPage(title: s.t('device.settings_page'), sub: '${d['name'] ?? ''}', children: [
      // picture and facts
      WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 64, height: 64, color: tk.surface2,
              child: image != null
                  ? Image.memory(image!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.memory_rounded, size: 28, color: tk.accent))
                  : Icon(Icons.memory_rounded, size: 28, color: tk.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.view['product'] ?? d['product_name'] ?? '—'}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text)),
            Text('${d['identifier']}', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: tk.muted)),
          ])),
        ]),
        _fact(s.t('device.protocol'), Text(protoLabel(s, d), textDirection: TextDirection.ltr, style: value)),
        _fact(s.t('device.firmware'), Text('${d['firmware_version'] ?? '—'}', textDirection: TextDirection.ltr, style: value)),
        _fact(s.t('device.warranty'), Text(
            warrantyUntil != null ? s.t('device.warranty_until', {'date': s.i18n.date(warrantyUntil)})
                : d['warranty_months'] != null ? s.t('device.warranty_months', {'n': s.i18n.num(d['warranty_months'])}) : '—',
            style: value)),
        _fact(s.t('device.access'), Text(s.t('access.${d['access']}'), style: value)),
        if (brand != null)
          _fact(s.t('device.maker'), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${brand!['display_name']}', style: value),
            if (brand!['support_phone'] != null)
              InkWell(onTap: () => launchUrl(Uri(scheme: 'tel', path: '${brand!['support_phone']}')),
                  child: Text('${brand!['support_phone']}', textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11, color: tk.accent))),
            if (brand!['support_email'] != null)
              InkWell(onTap: () => launchUrl(Uri(scheme: 'mailto', path: '${brand!['support_email']}')),
                  child: Text('${brand!['support_email']}', textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11, color: tk.accent))),
          ])),
      ])),
      // name and room
      WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _h2(s.t('device.name_room')),
        WebField(label: s.t('device.name'), child: TextField(controller: _name, enabled: owner)),
        const SizedBox(height: 12),
        WebField(label: s.t('device.room'),
            child: TextField(controller: _room, decoration: InputDecoration(hintText: s.t('device.room_hint')))),
        const SizedBox(height: 14),
        WebButton(s.t('common.save'), kind: BtnKind.primary, block: true, onTap: _saveNameRoom),
      ])),
      if (children != null && owner)
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _h2(s.t('edge.behind')),
          if (children!.isEmpty) Text(s.t('edge.none'), style: TextStyle(fontSize: 13, color: tk.muted)),
          for (final c in children!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reading(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DeviceScreen(state: s, deviceId: c['device_id'] as String))),
                start: Text('${c['name']}', style: TextStyle(color: tk.accent)),
                end: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: WebChip(protoLabel(s, c), ltr: true)),
                  const SizedBox(width: 6),
                  CircleIconButton(icon: Icons.delete_outline_rounded, tooltip: s.t('edge.remove'), onTap: () async {
                    if (!await _confirm(s.t('edge.remove_confirm', {'name': '${c['name']}'}))) return;
                    if (await _do(() => s.api.call('DELETE', '/api/platform/my/devices/$id/children/${c['device_id']}'))) {
                      _loadChildren();
                    }
                  }),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          WebButton(s.t('edge.add'), icon: Icons.add_rounded, block: true, onTap: () async {
            final added = await Navigator.push<bool>(context, MaterialPageRoute(
                builder: (_) => EdgeAddScreen(state: s, hubId: id)));
            if (added == true) _loadChildren();
          }),
        ])),
      if (sms != null && d['protocol'] == 'native' && d['access'] != 'viewer' && outputs.isNotEmpty)
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _h2(s.t('sms.title')),
          Text(s.t('sms.help'), style: TextStyle(fontSize: 13, height: 1.8, color: tk.muted)),
          const SizedBox(height: 12),
          WebField(label: s.t('sms.phone'), child: TextField(controller: _smsPhone, enabled: owner,
              keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: '+98912…'))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            WebButton(s.t(smsOn ? 'common.save' : 'sms.enable'), onTap: owner ? () => _smsSave() : null),
            if (smsOn && owner) WebButton(s.t('sms.new_key'), onTap: () => _smsSave(newKey: true)),
            if (smsOn && owner) WebButton(s.t('sms.disable'), kind: BtnKind.danger, onTap: _smsOff),
          ]),
          if (smsOn) ...[
            const SizedBox(height: 10),
            Text(s.t('sms.key_kept'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
            const SizedBox(height: 10),
            WebButton(s.t('sms.compose'), icon: Icons.sms_outlined, kind: BtnKind.primary, block: true, onTap: _smsCompose),
          ],
        ])),
      if (rules != null)
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _h2(s.t('local.title')),
          Text(s.t('local.help'), style: TextStyle(fontSize: 13, height: 1.8, color: tk.muted)),
          const SizedBox(height: 10),
          if (((rules!['rules'] as List?) ?? const []).isEmpty)
            Text(s.t('local.none'), style: TextStyle(fontSize: 13, color: tk.muted)),
          for (final r in ((rules!['rules'] as List?) ?? const []).cast<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reading(start: Text('${r['name']}', style: TextStyle(fontSize: 13, color: tk.text)),
                  end: WebChip(s.t('local.on_device'), tone: ChipTone.ok)),
            ),
          Text(s.t('local.how'), style: TextStyle(fontSize: 14, color: tk.accent)),
        ])),
      if (owner)
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _h2(s.t('tickets.title')),
          for (final r in tickets ?? const <Map<String, dynamic>>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reading(
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => TicketScreen(state: s, ticketId: (r['ticket_id'] as num).toInt())));
                  _loadTickets();
                },
                start: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['subject']}', style: TextStyle(fontSize: 13, color: tk.text)),
                  Text('${s.t('tickets.kind_${r['kind']}')} · ${s.i18n.when(r['updated_at'])}',
                      style: TextStyle(fontSize: 11, color: tk.muted)),
                ]),
                end: WebChip(s.t('tickets.status_${r['status']}'), tone: ticketTone[r['status']] ?? ChipTone.plain),
              ),
            ),
          WebButton(s.t('tickets.new'), icon: Icons.add_rounded, block: true, onTap: () async {
            await _newTicket();
            _loadTickets();
          }),
        ])),
      if (owner)
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _h2(s.t('share.title')),
          if (shared.isEmpty) Text(s.t('share.none'), style: TextStyle(fontSize: 13, color: tk.muted)),
          for (final x in shared)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reading(
                start: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${x['org_name'] ?? x['email'] ?? '—'}', style: TextStyle(fontSize: 13, color: tk.text)),
                  Text('${s.t('access.${x['level']}')}${x['pending'] == true ? ' · ${s.t('share.pending')}' : ''}',
                      style: TextStyle(fontSize: 11, color: tk.muted)),
                ]),
                end: CircleIconButton(icon: Icons.close_rounded, tooltip: s.t('share.revoke'), onTap: () => _revoke(x)),
              ),
            ),
          const SizedBox(height: 4),
          WebField(label: s.t('share.email'), child: TextField(controller: _shareEmail,
              keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr)),
          const SizedBox(height: 12),
          WebField(label: s.t('share.level'), child: DropdownButtonFormField<String>(
            initialValue: _shareLevel,
            items: [
              DropdownMenuItem(value: 'operator', child: Text(s.t('access.operator'))),
              DropdownMenuItem(value: 'viewer', child: Text(s.t('access.viewer'))),
            ],
            onChanged: (v) => setState(() => _shareLevel = v ?? 'viewer'),
          )),
          const SizedBox(height: 12),
          WebButton(s.t('share.send'), kind: BtnKind.primary, block: true, onTap: _share),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            WebButton(s.t('owner.transfer'), onTap: _transfer),
            WebButton(s.t('owner.remove'), kind: BtnKind.danger, onTap: _remove),
          ]),
          if (code != null) ...[
            const SizedBox(height: 12),
            Text(s.t('owner.transfer_hint'), style: TextStyle(fontSize: 13, color: tk.muted)),
            const SizedBox(height: 8),
            SelectableText(code!, textDirection: TextDirection.ltr, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, color: tk.text)),
          ],
        ])),
    ]);
  }
}
