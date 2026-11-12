// Me, as the web app's (views.js me): the user, the invitations waiting, the homes (role, their
// settings, their access page) and a new home, tools (energy, notifications), preferences
// (language, theme, accent colour, arrive / leave detection, home layout), about TiTiSwitch, sign
// out and deleting the account.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../ui/logo.dart';
import '../ui/widgets.dart';
import 'account.dart';
import 'energy.dart';
import 'home_settings.dart';
import 'members.dart';
import 'notifications.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key, required this.state, required this.signedOut});

  final AppState state;
  final VoidCallback signedOut;

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _error(ApiError e) => state.i18n.has('errors.${e.code}') ? state.t('errors.${e.code}') : e.message;

  /// Another home (a villa, the office): the user owns it and may invite others.
  Future<void> _newHome(BuildContext context) async {
    final s = state;
    final name = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(s.t('homes.new')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        WebField(label: s.t('homes.name'), child: TextField(controller: name, autofocus: true, maxLength: 80,
            decoration: InputDecoration(hintText: s.t('homes.name_hint')))),
        Text(s.t('homes.help'), style: TextStyle(fontSize: 12, color: Tk.of(c).muted)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('homes.create'))),
      ],
    ));
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final r = await s.api.call('POST', '/api/account/homes', {'name': name.text.trim()}) as Map<String, dynamic>;
      await s.load();
      await s.setHome(r['org_id'] as String);
      if (context.mounted) _toast(context, s.t('homes.created'));
    } on ApiError catch (e) {
      if (context.mounted) _toast(context, _error(e));
    }
  }

  /// Deleting the account: the password and DELETE typed, as the web app asks.
  Future<void> _deleteAccount(BuildContext context) async {
    final s = state;
    final password = TextEditingController();
    final typed = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(s.t('account.delete')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s.t('account.delete_help'), style: const TextStyle(height: 1.6)),
        const SizedBox(height: 10),
        WebField(label: s.t('auth.password'), child: TextField(controller: password, obscureText: true, autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration())),
        const SizedBox(height: 10),
        WebField(label: s.t('account.type_delete'), child: TextField(controller: typed, textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'DELETE'))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error, minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(s.t('account.delete')),
        ),
      ],
    ));
    if (ok != true) return;
    if (typed.text.trim() != 'DELETE') {
      if (context.mounted) _toast(context, s.t('account.type_delete'));
      return;
    }
    try {
      await s.api.call('POST', '/api/account/delete', {'password': password.text, 'confirm': 'DELETE'});
      await s.logout();
      if (context.mounted) _toast(context, s.t('account.deleted'));
      signedOut();
    } on ApiError catch (e) {
      if (context.mounted) _toast(context, _error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final me = s.me ?? const {};
    final name = '${me['display_name'] ?? ''}';
    final tk = Tk.of(context);
    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    // a row of the preferences card: an icon and its name, the control at the end (.row.between)
    Widget pref(IconData icon, String label, Widget end) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(icon, size: 18, color: tk.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: tk.text))),
            end,
          ]),
        );
    // .card.tight.row.link-card: an icon tile, the name, the arrow
    Widget link(IconData icon, String label, VoidCallback onTap) => WebCard(
          tight: true,
          onTap: onTap,
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: tk.surface2, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 20, color: tk.text)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: tk.text))),
            Icon(Icons.chevron_left_rounded, color: tk.muted),
          ]),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 120), children: [
      Row(children: [
        Avatar(name: name, size: 56),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tk.text)),
          Text('${me['email'] ?? me['username'] ?? ''}', textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 12, color: tk.muted)),
        ])),
      ]),
      _Invitations(state: s),
      Section(icon: Icons.home_outlined, title: s.t('me.homes'), hint: s.t('sec.homes_hint'), children: [
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final h in s.homes) ...[
            Reading(
              start: InkWell(
                onTap: () => s.setHome(h['org_id'] as String),
                child: Row(children: [
                  Icon(Icons.home_outlined, size: 18, color: tk.accent),
                  const SizedBox(width: 8),
                  Flexible(child: Text(h['personal'] == true ? s.t('me.my_home') : '${h['name']}',
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: tk.accent))),
                ]),
              ),
              end: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: WebChip('${h['role_id']}'.startsWith('lvl_') ? s.t('levels.custom') : s.t('roles.${h['role_id']}'))),
                const SizedBox(width: 8),
                CircleIconButton(icon: Icons.settings_outlined, tooltip: s.t('homeset.title'),
                    onTap: () => open(HomeSettingsScreen(state: s, home: h))),
                if (h['role_id'] == 'customer_owner' || '${h['role_id']}'.startsWith('lvl_')) ...[
                  const SizedBox(width: 6),
                  CircleIconButton(icon: Icons.groups_outlined, tooltip: s.t('members.title'),
                      onTap: () => open(MembersScreen(state: s, orgId: h['org_id'] as String,
                          homeName: h['personal'] == true ? s.t('me.my_home') : '${h['name']}'))),
                ],
              ]),
            ),
            const SizedBox(height: 10),
          ],
          WebButton(s.t('homes.new'), icon: Icons.add_rounded, block: true, onTap: () => _newHome(context)),
        ])),
      ]),
      Section(icon: Icons.tune_rounded, title: s.t('sec.tools'), hint: s.t('sec.tools_hint'), children: [
        link(Icons.bolt_rounded, s.t('energy.title'), () => open(EnergyScreen(state: s))),
        const SizedBox(height: 12),
        link(Icons.notifications_none_rounded, s.t('nav.notifications'), () => open(NotificationsScreen(state: s))),
      ]),
      Section(icon: Icons.settings_outlined, title: s.t('me.preferences'), hint: s.t('sec.prefs_hint'), children: [
        WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          pref(Icons.public_rounded, s.t('me.language'), WebButton(s.i18n.lang == 'fa' ? 'English' : 'فارسی',
              onTap: () => s.setLanguage(s.i18n.lang == 'fa' ? 'en' : 'fa'))),
          pref(Icons.nightlight_round, s.t('me.theme'), WebButton(s.t('me.toggle'), onTap: s.toggleTheme)),
          pref(Icons.star_outline_rounded, s.t('me.accent'), Wrap(spacing: 8, children: [
            for (final e in accents.entries)
              Semantics(
                button: true,
                selected: s.accent == e.key,
                label: s.t('me.accent_x', {'x': '#${e.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}'}),
                child: GestureDetector(
                  onTap: () => s.setAccent(e.key),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: e.value, shape: BoxShape.circle,
                        border: Border.all(color: s.accent == e.key ? tk.text : Colors.transparent, width: 2)),
                  ),
                ),
              ),
          ])),
          pref(Icons.home_outlined, s.t('me.presence'), WebButton(s.t(s.presence ? 'me.on' : 'me.off'), onTap: () async {
            await s.setPresence(!s.presence);
            if (s.presence) s.checkHome();
          })),
          Text(s.t('me.presence_help'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
          const SizedBox(height: 10),
          _LayoutEditor(state: s),
        ])),
      ]),
      Section(icon: Icons.star_outline_rounded, title: s.t('company.title'), hint: s.t('company.hint'), children: [
        WebCard(child: Column(children: [
          const LogoMark(size: 112),
          const SizedBox(height: 10),
          for (final (icon, label, value) in [
            (Icons.person_outline_rounded, s.t('company.ceo'), s.t('company.ceo_name')),
            (Icons.call_outlined, s.t('company.phone'), s.t('company.phone_text')),
            (Icons.public_rounded, s.t('company.site'), s.t('company.site_text')),
          ]) ...[
            Reading(
              start: Row(children: [Icon(icon, size: 18, color: tk.muted), const SizedBox(width: 8),
                Flexible(child: Text(label, style: TextStyle(color: tk.text)))]),
              end: Text(value, textDirection: icon == Icons.person_outline_rounded ? null : TextDirection.ltr,
                  style: TextStyle(fontWeight: FontWeight.w700, color: icon == Icons.person_outline_rounded ? tk.text : tk.accent)),
            ),
            const SizedBox(height: 10),
          ],
        ])),
      ]),
      Section(icon: Icons.person_outline_rounded, title: s.t('sec.account'), children: [
        WebButton(s.t('me.sign_out'), kind: BtnKind.danger, icon: Icons.logout_rounded, block: true,
            onTap: () async { await s.logout(); signedOut(); }),
        Center(child: TextButton(
          onPressed: () => _deleteAccount(context),
          child: Text(s.t('account.delete'), style: TextStyle(color: tk.warn)),
        )),
      ]),
    ]);
  }
}

/// Invitations waiting for this user (a home, or a device shared with them): accepted with the
/// link in the e-mail (EmailLinkScreen).
class _Invitations extends StatefulWidget {
  const _Invitations({required this.state});

  final AppState state;

  @override
  State<_Invitations> createState() => _InvitationsState();
}

class _InvitationsState extends State<_Invitations> {
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    widget.state.api.call('GET', '/api/account/invitations').then((r) {
      if (mounted) setState(() => rows = (r as List).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (rows.isEmpty) return const SizedBox.shrink();
    final tk = Tk.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(children: [
        for (final i in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WebCard(
              tight: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => EmailLinkScreen(state: s, signedIn: true))),
              child: Row(children: [
                Expanded(child: Text(s.t(i['kind'] == 'device' ? 'invite.device' : 'invite.organization',
                    {'org': '${i['org_name'] ?? ''}'}), style: TextStyle(fontSize: 12, color: tk.text))),
                const SizedBox(width: 8),
                Flexible(child: WebChip(s.t('invite.open_email'), tone: ChipTone.accent)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Me > home layout: the home screen's sections; hold one by its handle and drag it up or down,
/// switch off the ones not wanted. Kept on this phone.
class _LayoutEditor extends StatelessWidget {
  const _LayoutEditor({required this.state});

  final AppState state;

  static const _icons = {'today': Icons.bolt_rounded, 'custom': Icons.dashboard_customize_rounded,
    'quick': Icons.star_outline_rounded,
    'groups': Icons.grid_view_rounded, 'devices': Icons.home_outlined};

  @override
  Widget build(BuildContext context) {
    final s = state;
    final tk = Tk.of(context);
    final rows = s.homeLayout;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.dashboard_customize_outlined, color: tk.muted),
          const SizedBox(width: 12),
          Text(s.t('layout.title'), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
        ]),
        const SizedBox(height: 4),
        Text(s.t('layout.help'), style: TextStyle(fontSize: 12, height: 1.6, color: tk.muted)),
        const SizedBox(height: 10),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, animation) => AnimatedBuilder(
            animation: animation,
            builder: (_, __) => Transform.scale(
              scale: 1 + 0.03 * Curves.easeOut.transform(animation.value),
              child: Material(color: Colors.transparent, elevation: 8 * animation.value,
                  shadowColor: tk.accentGlow, borderRadius: BorderRadius.circular(14), child: child),
            ),
          ),
          onReorderItem: (from, to) {               // to: already adjusted for the removed row
            final next = [...rows];
            final item = next.removeAt(from);
            next.insert(to, item);
            s.setHomeLayout(next);
          },
          children: [
            for (final (i, (key, on)) in rows.indexed)
              Container(
                key: ValueKey(key),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tk.line)),
                child: Opacity(
                  opacity: on ? 1 : 0.55,
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Semantics(
                        label: '${s.t('layout.drag')}: ${s.t('layout.$key')}',
                        child: Padding(padding: const EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle_rounded, color: tk.muted)),
                      ),
                    ),
                    Icon(_icons[key], size: 20, color: tk.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.t('layout.$key'), style: TextStyle(color: tk.text))),
                    TiSwitch(value: on, onChanged: (v) => s.setHomeLayout(
                        [for (final r in rows) r.$1 == key ? (key, v) : r])),
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(                    // always at the bottom of the editor
          onPressed: () => s.setHomeLayout(null),
          icon: const Icon(Icons.restart_alt_rounded, size: 20),
          label: Text(s.t('layout.reset')),
        ),
      ]),
    );
  }
}
