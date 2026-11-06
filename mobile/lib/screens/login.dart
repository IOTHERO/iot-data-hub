// Sign-in with the same accounts as the web app, including the two-step code; links to make an
// account, to a forgotten password and to the links the hub e-mails (account.dart).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/logo.dart';
import 'account.dart';

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
  final _code = TextEditingController();
  String? _mfaToken;                 // set: the second step is asked
  bool _busy = false;
  String? _error;
  late bool _remember = widget.state.store.get('remember_off') == null;

  @override
  void initState() {
    super.initState();
    final kept = widget.state.rememberedUser;      // remember me: the e-mail, never the password
    if (kept != null) _user.text = kept;
  }

  Future<void> _submit() async {
    final s = widget.state;
    setState(() { _busy = true; _error = null; });
    try {
      if (_mfaToken != null) {
        await s.api.verifyMfa(_mfaToken!, _code.text.trim());
      } else {
        _mfaToken = await s.api.login(_user.text.trim(), _password.text);
        if (_mfaToken != null) {
          if (mounted) setState(() => _busy = false);
          return;                                       // the code field appears
        }
      }
      if (await s.load()) {
        await s.remember(_remember ? _user.text.trim() : null);
        await s.store.set('remember_off', _remember ? null : '1');
        widget.done();
        return;
      }
    } on ApiError catch (e) {
      _error = s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    return Scaffold(
      body: GlowPage(child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
          const Align(alignment: AlignmentDirectional.centerStart, child: LogoMark(size: 120)),
          if (s.brand != null) ...[                   // a maker's link (?brand=): its name and logo
            const SizedBox(height: 14),
            Row(children: [
              if (s.brandLogo != null)
                ClipRRect(borderRadius: BorderRadius.circular(12),
                    child: Image.memory(s.brandLogo!, width: 44, height: 44, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              if (s.brandLogo != null) const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.brand!['display_name']}', style: TextStyle(fontWeight: FontWeight.w800, color: tk.text)),
                if (s.brand!['support_phone'] != null)
                  Text('${s.brand!['support_phone']}', textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 12, color: tk.muted)),
              ])),
            ]),
          ],
          const SizedBox(height: 18),
          Text(s.t('auth.welcome'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tk.text)),
          const SizedBox(height: 8),
          Text(s.t('auth.lead'), style: TextStyle(color: tk.muted)),
          const SizedBox(height: 28),
          WebField(label: s.t('auth.email'), child: TextField(controller: _user, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.username], enabled: _mfaToken == null,
              )),
          const SizedBox(height: 14),
          WebField(label: s.t('auth.password'), child: TextField(controller: _password, obscureText: true, autofocus: s.rememberedUser != null, autofillHints: const [AutofillHints.password],
              enabled: _mfaToken == null, onSubmitted: (_) => _submit(),
              )),
          if (_mfaToken != null) ...[
            const SizedBox(height: 14),
            WebField(label: s.t('auth.mfa_code'), child: TextField(controller: _code, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                autofocus: true, autofillHints: const [AutofillHints.oneTimeCode], onSubmitted: (_) => _submit(),
                )),
          ],
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? true),
            title: Text(s.t('auth.remember')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: tk.warn))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(s.t('auth.sign_in'))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: TextButton(onPressed: () => _open(SignupScreen(state: s)),
                child: Text(s.t('auth.create'), overflow: TextOverflow.ellipsis))),
            Flexible(child: TextButton(onPressed: () => _open(ForgotScreen(state: s)),
                child: Text(s.t('auth.forgot'), overflow: TextOverflow.ellipsis))),
          ]),
          TextButton(onPressed: () => _open(EmailLinkScreen(state: s, signedIn: false)),
              child: Text(s.t('mobile.email_link'))),
          TextButton(onPressed: widget.changeServer, child: Text(s.t('mobile.change_server'))),
        ]),
      )),
    );
  }
}
