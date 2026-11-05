// Members of a home: their role or access level, change it, remove, invite by e-mail; and the
// home's access levels (level_edit.dart).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'level_edit.dart';

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
  List<Map<String, dynamic>> levels = [];
  final _email = TextEditingController();
  String _role = 'customer_member';
  String? error;

  String get _base => '/api/platform/organizations/${widget.orgId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      members = (await widget.state.api.call('GET', '$_base/members') as List).cast<Map<String, dynamic>>();
      final l = await widget.state.api.call('GET', '$_base/levels') as Map<String, dynamic>;
      levels = (l['levels'] as List).cast<Map<String, dynamic>>();
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() {});
  }

  List<(String, String)> get _roles {
    final s = widget.state;
    return [
      for (final r in ['customer_owner', 'customer_member', 'customer_viewer']) (r, s.t('roles.$r')),
      for (final l in levels) (l['role_id'] as String, '${l['name']}'),
    ];
  }

  String _roleName(String id) => _roles.where((r) => r.$1 == id).firstOrNull?.$2 ?? widget.state.t('levels.custom');

  Future<void> _editLevel(Map<String, dynamic>? level) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => LevelEditScreen(state: widget.state, orgId: widget.orgId, level: level)));
    if (saved == true) _load();
  }

  Future<void> _act(Future<dynamic> Function() action, [String? done]) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text('${s.t('members.title')} · ${widget.homeName}')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (error != null) Text(error!),
        Card(child: Column(children: [
          for (final m in members)
            ListTile(
              leading: CircleAvatar(child: Text('${m['display_name'] ?? '?'}'.characters.first)),
              title: Text('${m['display_name']}'),
              subtitle: Text('${m['email'] ?? ''}', textDirection: TextDirection.ltr),
              trailing: PopupMenuButton<String>(
                child: Chip(label: Text(_roleName('${m['role_id']}'))),
                onSelected: (v) => v == '_remove'
                    ? _act(() => s.api.call('DELETE', '$_base/members/${m['user_role_id']}'))
                    : _act(() => s.api.call('PATCH', '$_base/members/${m['user_role_id']}', {'role': v}),
                        s.t('common.saved')),
                itemBuilder: (_) => [
                  for (final r in _roles) PopupMenuItem(value: r.$1, child: Text(r.$2)),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: '_remove', child: Text(s.t('members.remove'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
        ])),
        const SizedBox(height: 20),
        Text(s.t('levels.title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          for (final l in levels)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text('${l['name']}'),
              subtitle: Text(s.t('levels.members_n',
                  {'n': members.where((m) => m['role_id'] == l['role_id']).length})),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => _editLevel(l),
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: Text(s.t('levels.new')),
            onTap: () => _editLevel(null),
          ),
        ])),
        const SizedBox(height: 20),
        Text(s.t('members.invite'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s.t('share.email'))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: InputDecoration(labelText: s.t('members.role')),
          items: [for (final r in _roles.where((r) => r.$1 != 'customer_owner'))
            DropdownMenuItem(value: r.$1, child: Text(r.$2))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => _act(() async {
            await s.api.call('POST', '$_base/invitations', {'email': _email.text.trim(), 'role': _role});
            _email.clear();
          }, s.t('share.sent')),
          child: Text(s.t('share.send')),
        ),
      ]),
    );
  }
}
