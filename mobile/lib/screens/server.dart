// The hub address, asked on first start (and from the sign-in page to change it).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
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

  Future<void> _save() async {
    final url = _url.text.trim();
    if (!Api.allowedServer(url)) {
      setState(() => _error = widget.state.t('mobile.server_bad'));
      return;
    }
    await widget.state.api.setServer(url);
    widget.done();
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
          FilledButton(onPressed: _save, child: Text(s.t('mobile.connect'))),
        ]),
      )),
    );
  }
}
