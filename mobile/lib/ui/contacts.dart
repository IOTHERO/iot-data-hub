// People without an account whom the home alerts by SMS or a call (a neighbour), who may run
// scenes by SMS, and the SMS PIN - on the home's access page, as the web app's contactsSection.
// Members' own numbers are set with the member (members.dart), so this lists only the others.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'kit.dart';

class ContactsSection extends StatefulWidget {
  const ContactsSection({super.key, required this.state, required this.orgId, required this.owner});

  final AppState state;
  final String orgId;
  final bool owner;

  @override
  State<ContactsSection> createState() => _ContactsSectionState();
}

class _ContactsSectionState extends State<ContactsSection> {
  Map<String, dynamic>? data;
  final _pin = TextEditingController();

  AppState get s => widget.state;
  String get _base => '/api/platform/organizations/${widget.orgId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await s.api.call('GET', '$_base/contacts') as Map<String, dynamic>;
    } on ApiError {
      data = null;
    }
    if (mounted) setState(() {});
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _contact(Map<String, dynamic>? c) async {
    final name = TextEditingController(text: '${c?['name'] ?? ''}');
    final phone = TextEditingController(text: '${c?['phone'] ?? ''}');
    var sms = c == null ? true : c['sms'] == true;
    var call = c?['call'] == true;
    var command = c?['command'] == true;
    final answer = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final tk = Tk.of(ctx);
        Widget check(String label, IconData icon, bool value, ValueChanged<bool> onChanged) => InkWell(
              onTap: () => set(() => onChanged(!value)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Checkbox(value: value, onChanged: (v) => set(() => onChanged(v ?? false))),
                  Icon(icon, size: 18, color: tk.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            );
        return AlertDialog(
          title: Text(s.t(c == null ? 'contacts.add' : 'contacts.edit')),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label(s.t('contacts.name')),
            TextField(controller: name, maxLength: 60),
            Label(s.t('contacts.phone')),
            TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: '0912…')),
            const SizedBox(height: 8),
            check(s.t('contacts.sms_long'), Icons.sms_outlined, sms, (v) => sms = v),
            check(s.t('contacts.call_long'), Icons.call_outlined, call, (v) => call = v),
            check(s.t('contacts.command_long'), Icons.tune_rounded, command, (v) => command = v),
            Text(s.t('contacts.command_help'), style: TextStyle(fontSize: 11, height: 1.6, color: tk.muted)),
          ])),
          actions: [
            if (c != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text(s.t('auto.delete'), style: TextStyle(color: tk.warn))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('common.cancel'))),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(ctx, 'save'), child: Text(s.t('common.save'))),
          ],
        );
      },
    ));
    final base = '$_base/contacts';
    try {
      if (answer == 'delete') {
        await s.api.call('DELETE', '$base/${c!['contact_id']}');
      } else if (answer == 'save') {
        const fa = '۰۱۲۳۴۵۶۷۸۹';
        final number = phone.text.trim().split('').map((ch) => fa.contains(ch) ? '${fa.indexOf(ch)}' : ch).join()
            .replaceAll(RegExp(r'[\s-]'), '');
        final body = {'name': name.text.trim().isEmpty ? number : name.text.trim(), 'phone': number,
          'sms': sms, 'call': call, 'command': command};
        c == null ? await s.api.call('POST', base, body) : await s.api.call('PUT', '$base/${c['contact_id']}', body);
        _toast(s.t('common.saved'));
      } else {
        return;
      }
      _load();
    } on ApiError catch (e) {
      _toast(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message);
    }
  }

  Future<void> _setPin(String? pin) async {
    if (pin != null && !RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      _toast(s.t('contacts.pin_bad'));
      return;
    }
    try {
      await s.api.call('PUT', '$_base/sms-pin', {'pin': pin});
      _pin.clear();
      _toast(s.t('common.saved'));
      _load();
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) return const SizedBox.shrink();
    final tk = Tk.of(context);
    final owner = widget.owner;
    final all = ((d['contacts'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final list = all.where((c) => c['member_id'] == null).toList();
    final pinSet = d['pin_set'] == true;
    return WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(s.t('contacts.title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tk.text))),
        Icon(Icons.call_outlined, size: 18, color: tk.muted),
      ]),
      const SizedBox(height: 6),
      Text(s.t('contacts.help'), style: TextStyle(fontSize: 12, height: 1.8, color: tk.muted)),
      const SizedBox(height: 10),
      if (d['gateway'] != true) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: tk.warn.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
          child: Text(s.t('contacts.no_gateway'), style: TextStyle(fontSize: 12, height: 1.8, color: tk.warn)),
        ),
        const SizedBox(height: 10),
      ],
      if (list.isEmpty) Text(s.t('contacts.none'), style: TextStyle(fontSize: 12, color: tk.muted)),
      for (final c in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Reading(
            onTap: owner ? () => _contact(c) : null,
            start: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', style: TextStyle(color: tk.text)),
              Text('${c['phone']}', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: tk.muted)),
            ]),
            end: Wrap(spacing: 6, children: [
              if (c['sms'] == true) WebChip(s.t('contacts.sms'), tone: ChipTone.ok, icon: Icons.sms_outlined),
              if (c['call'] == true) WebChip(s.t('contacts.call'), tone: ChipTone.accent, icon: Icons.call_outlined),
              if (c['command'] == true) WebChip(s.t('contacts.command'), tone: ChipTone.violet, icon: Icons.tune_rounded),
            ]),
          ),
        ),
      WebButton(s.t('contacts.add'), icon: Icons.add_rounded, block: true,
          onTap: owner && all.length < 10 ? () => _contact(null) : null),
      const SizedBox(height: 14),
      Label(s.t('contacts.pin')),
      const SizedBox(height: 4),
      Text(s.t('contacts.pin_help'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: TextField(controller: _pin, enabled: owner, obscureText: true, maxLength: 8,
            keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: pinSet ? '••••' : s.t('contacts.pin_hint'), counterText: ''))),
        const SizedBox(width: 10),
        WebButton(s.t(pinSet ? 'contacts.pin_change' : 'contacts.pin_set'),
            onTap: owner ? () => _setPin(_pin.text.trim()) : null),
      ]),
      if (pinSet && owner) ...[
        const SizedBox(height: 10),
        WebButton(s.t('contacts.pin_off'), kind: BtnKind.danger, onTap: () => _setPin(null)),
      ],
    ]));
  }
}
