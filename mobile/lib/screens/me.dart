// Me: the user, homes, preferences (language, theme), about TiTiSwitch, sign out.

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/logo.dart';
import '../ui/widgets.dart';
import 'energy.dart';
import 'members.dart';
import 'tickets.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key, required this.state, required this.signedOut});

  final AppState state;
  final VoidCallback signedOut;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final me = s.me ?? const {};
    final name = '${me['display_name'] ?? ''}';
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 120), children: [
      Row(children: [
        Avatar(name: name, size: 56),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('${me['email'] ?? me['username'] ?? ''}', textDirection: TextDirection.ltr,
              style: TextStyle(color: Theme.of(context).hintColor)),
        ])),
      ]),
      Section(icon: Icons.home_rounded, title: s.t('me.homes'), hint: s.t('sec.homes_hint'), children: [
        Card(child: Column(children: [
          for (final h in s.homes)
            ListTile(
              leading: const Icon(Icons.home_rounded),
              title: Text('${h['name']}'),
              subtitle: Text(s.i18n.has('roles.${h['role_id']}') ? s.t('roles.${h['role_id']}') : s.t('levels.custom')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (s.home == h['org_id']) Icon(Icons.check_rounded, color: cs.primary),
                if (h['role_id'] == 'customer_owner')
                  IconButton(
                    tooltip: s.t('members.title'),
                    icon: const Icon(Icons.group_rounded),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                        MembersScreen(state: s, orgId: h['org_id'] as String, homeName: '${h['name']}'))),
                  ),
              ]),
              onTap: () => s.setHome(h['org_id'] as String),
            ),
        ])),
      ]),
      Section(icon: Icons.tune_rounded, title: s.t('sec.tools'), hint: s.t('sec.tools_hint'), children: [
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.bolt_rounded), title: Text(s.t('energy.title')),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EnergyScreen(state: s)))),
          ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(s.t('tickets.title')),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketsScreen(state: s)))),
        ])),
      ]),
      Section(icon: Icons.settings_rounded, title: s.t('me.preferences'), hint: s.t('sec.prefs_hint'), children: [
        Card(child: Column(children: [
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(s.t('me.language')),
            trailing: TextButton(onPressed: () => s.setLanguage(s.i18n.lang == 'fa' ? 'en' : 'fa'),
                child: Text(s.i18n.lang == 'fa' ? 'English' : 'فارسی')),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded),
            title: Text(s.t('me.theme')),
            trailing: TextButton(onPressed: s.toggleTheme, child: Text(s.t('me.toggle'))),
          ),
        ])),
      ]),
      Section(icon: Icons.star_rounded, title: s.t('company.title'), hint: s.t('company.hint'), children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const LogoMark(size: 110),
            const SizedBox(height: 10),
            ListTile(leading: const Icon(Icons.person_rounded), title: Text(s.t('company.ceo')),
                trailing: Text(s.t('company.ceo_name'), style: const TextStyle(fontWeight: FontWeight.w700))),
            ListTile(leading: const Icon(Icons.call_rounded), title: Text(s.t('company.phone')),
                trailing: Text(s.t('company.phone_text'), textDirection: TextDirection.ltr)),
            ListTile(leading: const Icon(Icons.public_rounded), title: Text(s.t('company.site')),
                trailing: Text(s.t('company.site_text'), textDirection: TextDirection.ltr)),
          ]),
        )),
      ]),
      Section(icon: Icons.person_rounded, title: s.t('sec.account'), children: [
        OutlinedButton.icon(
          onPressed: () async { await s.logout(); signedOut(); },
          icon: const Icon(Icons.logout_rounded),
          label: Text(s.t('me.sign_out')),
          style: OutlinedButton.styleFrom(foregroundColor: cs.error, minimumSize: const Size.fromHeight(50)),
        ),
      ]),
    ]);
  }
}
