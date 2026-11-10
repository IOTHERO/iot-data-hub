// The hub address, asked on first start (and from the sign-in page to change it).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/tls.dart';
import '../ui/kit.dart';
import '../ui/logo.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.state, required this.done});

  final AppState state;
  final VoidCallback done;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final _url = TextEditingController(text: widget.state.api.server);
  String? _error;

  bool _busy = false;

  Future<void> _save() async {
    final s = widget.state;
    final url = _url.text.trim();
    if (!Api.allowedServer(url)) {
      setState(() => _error = s.t('mobile.server_bad'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await s.api.setServer(url);
      if (!kIsWeb) {
        // a hub with its own certificate: show it once and let the user approve it (core/tls.dart)
        final untrusted = await checkServer(Uri.parse(s.api.server), s.trusted);
        if (untrusted != null) {
          if (!mounted || !await _approve(untrusted)) return;
          await s.trusted.approve(untrusted.host, untrusted.port, untrusted.print);
        }
      }
      widget.done();
    } catch (e) {
      if (mounted) setState(() => _error = s.t('mobile.server_unreachable', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _approve(UntrustedServer u) async {
    final s = widget.state;
    final end = u.cert.endValidity;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(label),
            SelectableText(value, textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5)),
          ]),
        );
    return await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: Text(s.t('mobile.cert_title')),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('mobile.cert_help'), style: const TextStyle(fontSize: 13, height: 1.7)),
            row(s.t('mobile.cert_host'), '${u.host}:${u.port}'),
            row(s.t('mobile.cert_print'), u.print),
            row(s.t('mobile.cert_valid'), s.i18n.date(end)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('mobile.cert_trust'))),
          ],
        )) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      body: GlowPage(child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 56, 24, 24), children: [
          const Center(child: LogoMark(size: 140)),
          const SizedBox(height: 28),
          Text(s.t('mobile.server_title'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(s.t('mobile.server_hint'), style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 18),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(hintText: 'https://', hintTextDirection: TextDirection.ltr, errorText: _error),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(s.t('mobile.connect')),
          ),
        ]),
      )),
    );
  }
}
