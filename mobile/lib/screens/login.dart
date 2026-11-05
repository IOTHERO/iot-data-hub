// Sign-in with the same accounts as the web app (two-step sign-in accounts: the web app for now).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state, required this.done, required this.changeServer});

  final AppState state;
  final VoidCallback done;
  final VoidCallback changeServer;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final s = widget.state;
    setState(() { _busy = true; _error = null; });
    try {
      await s.api.login(_user.text.trim(), _password.text);
      if (await s.load()) {
        widget.done();
        return;
      }
    } on ApiError catch (e) {
      _error = s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      body: GlowPage(child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
          const Align(alignment: AlignmentDirectional.centerStart, child: LogoMark(size: 120)),
          const SizedBox(height: 18),
          Text(s.t('auth.welcome'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(s.t('auth.lead'), style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 28),
          TextField(controller: _user, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.username],
              decoration: InputDecoration(labelText: s.t('auth.email'))),
          const SizedBox(height: 14),
          TextField(controller: _password, obscureText: true, autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(), decoration: InputDecoration(labelText: s.t('auth.password'))),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(s.t('auth.sign_in'))),
          const SizedBox(height: 12),
          TextButton(onPressed: widget.changeServer, child: Text(s.t('mobile.change_server'))),
        ]),
      )),
    );
  }
}
