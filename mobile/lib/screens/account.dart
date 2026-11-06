// Account pages without signing in, as the web app's: make an account, ask for a reset link,
// and act on a link the hub e-mailed (…/#/account/verify|reset|invitation/<token>): pasted or
// opened in the app, it verifies the address, sets a new password or accepts an invitation.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';

/// (kind, token) from an e-mailed account link, or null.
(String, String)? parseAccountLink(String text) {
  final m = RegExp(r'#/account/(verify|reset|invitation)/([A-Za-z0-9_-]{20,200})').firstMatch(text);
  return m == null ? null : (m[1]!, m[2]!);
}

class _Form extends StatelessWidget {
  const _Form({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: GlowPage(child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 30), children: children)),
      );
}

String _error(AppState s, ApiError e) => s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message;

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.state, this.invitationToken});

  final AppState state;
  final String? invitationToken;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _message;
  bool _busy = false;

  Future<void> _submit() async {
    final s = widget.state;
    setState(() { _busy = true; _message = null; });
    try {
      await s.api.public('POST', '/api/account/signup', {
        'display_name': _name.text.trim(), 'email': _email.text.trim(), 'password': _password.text,
        'language': s.i18n.lang,
        if (widget.invitationToken != null) 'invitation_token': widget.invitationToken,
      });
      _message = s.t('auth.check_email');
    } on ApiError catch (e) {
      _message = _error(s, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return _Form(title: s.t('auth.create'), children: [
      if (widget.invitationToken != null)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(s.t('auth.invited'))),
      WebField(label: s.t('auth.name'), child: TextField(controller: _name, autofillHints: const [AutofillHints.name],
          )),
      const SizedBox(height: 12),
      WebField(label: s.t('auth.email'), child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
          )),
      const SizedBox(height: 12),
      WebField(label: s.t('auth.password_new'), child: TextField(controller: _password, obscureText: true, autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(helperText: s.t('auth.password_rule')))),
      const SizedBox(height: 18),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(s.t('auth.create'))),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message!)),
    ]);
  }
}

class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  final _email = TextEditingController();
  String? _message;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return _Form(title: s.t('auth.forgot'), children: [
      WebField(label: s.t('auth.email'), child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
          )),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: () async {
          try {
            await s.api.public('POST', '/api/account/password/forgot', {'email': _email.text.trim()});
            setState(() => _message = s.t('auth.check_email'));
          } on ApiError catch (e) {
            setState(() => _message = _error(s, e));
          }
        },
        child: Text(s.t('auth.send_link')),
      ),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message!)),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmailLinkScreen(state: s, signedIn: false))),
        child: Text(s.t('mobile.email_link')),
      ),
    ]);
  }
}

/// Paste the link the hub e-mailed; the app does what the web page at that link would.
class EmailLinkScreen extends StatefulWidget {
  const EmailLinkScreen({super.key, required this.state, required this.signedIn});

  final AppState state;
  final bool signedIn;

  @override
  State<EmailLinkScreen> createState() => _EmailLinkScreenState();
}

class _EmailLinkScreenState extends State<EmailLinkScreen> {
  final _link = TextEditingController();
  final _password = TextEditingController();
  (String, String)? link;
  String? _message;

  Future<void> _go() async {
    final s = widget.state;
    final l = link;
    if (l == null) return;
    try {
      switch (l.$1) {
        case 'verify':
          await s.api.public('POST', '/api/account/verify', {'token': l.$2});
          _message = s.t('auth.verified');
        case 'reset':
          await s.api.public('POST', '/api/account/password/reset', {'token': l.$2, 'new_password': _password.text});
          _message = s.t('auth.password_changed');
        case 'invitation':
          if (!widget.signedIn) {
            if (!mounted) return;
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => SignupScreen(state: s, invitationToken: l.$2)));
            return;
          }
          await s.api.call('POST', '/api/account/invitations/accept', {'token': l.$2});
          await s.load();
          _message = s.t('invite.accepted');
      }
    } on ApiError catch (e) {
      _message = _error(s, e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return _Form(title: s.t('mobile.email_link'), children: [
      Text(s.t('mobile.email_link_help'), style: TextStyle(color: Tk.of(context).muted)),
      const SizedBox(height: 12),
      TextField(controller: _link, textDirection: TextDirection.ltr, minLines: 1, maxLines: 3,
          onChanged: (v) => setState(() => link = parseAccountLink(v)),
          decoration: const InputDecoration(hintText: 'https://…/#/account/…', hintTextDirection: TextDirection.ltr)),
      if (link?.$1 == 'reset') ...[
        const SizedBox(height: 12),
        WebField(label: s.t('auth.password_new'), child: TextField(controller: _password, obscureText: true,
            decoration: InputDecoration(helperText: s.t('auth.password_rule')))),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: link == null ? null : _go,
        child: Text(switch (link?.$1) {
          'verify' => s.t('auth.verify'),
          'reset' => s.t('auth.save_password'),
          'invitation' => s.t('invite.title'),
          _ => s.t('mobile.connect'),
        }),
      ),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message!)),
    ]);
  }
}
