// The home's access page, as the web app's (levels.js members): the members - each with their
// own mobile number (whose this account is; the alarms reach it), role or access level, change
// or remove - the people without an account and the SMS PIN (contacts.dart), an invitation by
// e-mail, and the home's access levels as cards of permission icons (level_edit.dart).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/contacts.dart';
import '../ui/kit.dart';
import 'level_edit.dart';

const _builtIn = ['customer_owner', 'customer_member', 'customer_viewer'];
const permIcons = {
  'device.view': Icons.home_outlined, 'device.operate': Icons.power_settings_new_rounded,
  'scene.run': Icons.star_outline_rounded, 'automation.manage': Icons.tune_rounded,
  'timer.manage': Icons.schedule_rounded, 'energy.view': Icons.bolt_rounded,
  'device.share': Icons.share_outlined, 'org.members': Icons.groups_outlined,
  'home.settings': Icons.settings_outlined, 'ticket.manage': Icons.chat_bubble_outline_rounded,
};

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.state, required this.orgId, required this.homeName});

  final AppState state;
  final String orgId;
  final String homeName;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Map<String, dynamic>> members = [];
  Map<String, dynamic> lv = {};
  final _email = TextEditingController();
  String _role = 'customer_member';
  String? error;
  int _contactsKey = 0;

  AppState get s => widget.state;
  String get _base => '/api/platform/organizations/${widget.orgId}';
  List<Map<String, dynamic>> get _levels => ((lv['levels'] as List?) ?? const []).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      members = (await s.api.call('GET', '$_base/members') as List).cast<Map<String, dynamic>>();
      lv = await s.api.call('GET', '$_base/levels') as Map<String, dynamic>;
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => _contactsKey++);
  }

  String _roleName(String id) => id.startsWith('lvl_')
      ? '${_levels.where((l) => l['role_id'] == id).firstOrNull?['name'] ?? s.t('levels.custom')}'
      : s.t('roles.$id');

  List<String> get _allRoles => [..._builtIn, for (final l in _levels) l['role_id'] as String];

  String _perm(String p) => s.t('perm.${p.replaceAll('.', '_')}');

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Tap a member: their mobile number, their role or level, or remove them.
  Future<void> _member(Map<String, dynamic> m) async {
    final phone = TextEditingController(text: '${m['phone'] ?? ''}');
    var role = '${m['role_id']}';
    final answer = await showDialog<String>(context: context, builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final tk = Tk.of(c);
        return AlertDialog(
          title: Text('${m['display_name']}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${m['email'] ?? ''}', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: tk.muted)),
            const SizedBox(height: 12),
            Label(s.t('members.phone')),
            const SizedBox(height: 4),
            TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: '0912…')),
            const SizedBox(height: 4),
            Text(s.t('members.phone_help'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
            const SizedBox(height: 12),
            Label(s.t('members.role')),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _allRoles.contains(role) ? role : null,
              isExpanded: true,
              items: [for (final r in _allRoles) DropdownMenuItem(value: r, child: Text(_roleName(r)))],
              onChanged: (v) => set(() => role = v ?? role),
            ),
            const SizedBox(height: 4),
            Text(s.t('levels.change_help'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'remove'),
                child: Text(s.t('members.remove'), style: TextStyle(color: tk.warn))),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('common.cancel'))),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(c, 'save'), child: Text(s.t('common.save'))),
          ],
        );
      },
    ));
    try {
      if (answer == 'save') {
        const fa = '۰۱۲۳۴۵۶۷۸۹';
        final number = phone.text.trim().split('').map((ch) => fa.contains(ch) ? '${fa.indexOf(ch)}' : ch).join()
            .replaceAll(RegExp(r'[\s-]'), '');
        if (number != '${m['phone'] ?? ''}') {
          await s.api.call('PUT', '$_base/members/${m['user_role_id']}/phone',
              {'phone': number.isEmpty ? null : number});
        }
        if (role != m['role_id']) {
          await s.api.call('PATCH', '$_base/members/${m['user_role_id']}', {'role': role});
        }
        _toast(s.t('common.saved'));
      } else if (answer == 'remove') {
        if (!mounted) return;
        final sure = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          content: Text(s.t('members.remove_confirm')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(c, true), child: Text(s.t('members.remove'))),
          ],
        ));
        if (sure != true) return;
        await s.api.call('DELETE', '$_base/members/${m['user_role_id']}');
      } else {
        return;
      }
      _load();
    } on ApiError catch (e) {
      _toast(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message);
    }
  }

  Future<void> _invite() async {
    try {
      await s.api.call('POST', '$_base/invitations', {'email': _email.text.trim(), 'role': _role});
      _email.clear();
      _toast(s.t('share.sent'));
    } on ApiError catch (e) {
      _toast(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message);
    }
  }

  Future<void> _editLevel(Map<String, dynamic>? level) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => LevelEditScreen(state: s, orgId: widget.orgId, level: level)));
    if (saved == true) _load();
  }

  Widget _levelCard(String title, List perms, Widget extra, {VoidCallback? onEdit}) {
    final tk = Tk.of(context);
    final all = ((lv['permissions'] as List?) ?? const []).cast<String>();
    return WebCard(
      onTap: onEdit,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tk.text))),
          onEdit != null ? Icon(Icons.edit_outlined, size: 18, color: tk.muted) : WebChip(s.t('levels.built_in')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in all) PermChip(icon: permIcons[p] ?? Icons.check_rounded, on: perms.contains(p), tooltip: _perm(p)),
        ]),
        const SizedBox(height: 10),
        extra,
      ]),
    );
  }

  String _limits(Map<String, dynamic> l) {
    final sc = (l['scope'] as Map?) ?? const {};
    int n(String k) => ((sc[k] as List?) ?? const []).length;
    final parts = [
      n('rooms') + n('groups') + n('outputs') > 0
          ? s.t('levels.scope_some', {'r': n('rooms'), 'g': n('groups'), 'o': n('outputs')})
          : s.t('levels.scope_all'),
      if (l['schedule'] is Map) s.t('levels.hours_x', {'from': l['schedule']['from'], 'to': l['schedule']['to']}),
      if (l['own_only'] == true) s.t('levels.own_only_short'),
      s.t('levels.members_n', {'n': l['members'] ?? 0}),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final builtIn = ((lv['built_in'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return WebPage(
      title: s.t('members.title'),
      sub: widget.homeName,
      children: [
        if (error != null) Text(error!, style: TextStyle(color: tk.warn)),
        // members: tap one to set their number, change their level or remove them
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('members.title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tk.text)),
          for (final m in members)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Reading(
                onTap: () => _member(m),
                start: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m['display_name']}', style: TextStyle(color: tk.text)),
                  Text('${m['email'] ?? ''}', textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11, color: tk.muted)),
                  Text('${m['phone'] ?? s.t('members.no_phone')}', textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11, color: m['phone'] == null ? tk.warn : tk.muted)),
                ]),
                end: WebChip(_roleName('${m['role_id']}'),
                    tone: '${m['role_id']}'.startsWith('lvl_') ? ChipTone.violet
                        : m['role_id'] == 'customer_owner' ? ChipTone.accent : ChipTone.plain),
              ),
            ),
        ]),
        ContactsSection(key: ValueKey(_contactsKey), state: s, orgId: widget.orgId, owner: true),
        // invite
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('members.invite'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tk.text)),
          const SizedBox(height: 10),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'name@example.com')),
          const SizedBox(height: 10),
          Label(s.t('members.role')),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _role,
            isExpanded: true,
            items: [for (final r in _allRoles) DropdownMenuItem(value: r, child: Text(_roleName(r)))],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
        ])),
        WebButton(s.t('members.invite'), kind: BtnKind.primary, block: true, onTap: _invite),
        // levels: the built-in ones (read only) and the home's own
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(s.t('levels.title'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tk.text))),
            Text(s.t('levels.help_short'), style: TextStyle(fontSize: 11, color: tk.muted)),
          ]),
          for (final b in builtIn)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _levelCard(s.t('roles.${b['role_id']}'), (b['permissions'] as List?) ?? const [],
                  Text(s.t('levels.about_${b['role_id']}'), style: TextStyle(fontSize: 11, color: tk.muted))),
            ),
          for (final l in _levels)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _levelCard('${l['name']}', (l['permissions'] as List?) ?? const [],
                  Text(_limits(l), style: TextStyle(fontSize: 11, color: tk.muted)), onEdit: () => _editLevel(l)),
            ),
          const SizedBox(height: 10),
          WebButton(s.t('levels.new'), kind: BtnKind.dashed, icon: Icons.add_rounded, block: true,
              onTap: () => _editLevel(null)),
        ]),
      ],
    );
  }
}
