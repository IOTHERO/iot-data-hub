// Adding a device with the identifier and claim code of its label (POST /api/platform/claim):
// scanned with the camera, typed, or a pasted label link (…/#/claim/<identifier>/<code>).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'scan.dart';
import 'edge_add.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key, required this.state});

  final AppState state;

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  void _fromLink(String text) {
    final label = parseLabel(text);
    if (label == null) return;
    _identifier.text = label.$1;
    _code.text = label.$2;
  }

  Future<void> _scan() async {
    final label = await Navigator.push<(String, String)>(context,
        MaterialPageRoute(builder: (_) => ScanScreen(state: widget.state)));
    if (label == null) return;
    setState(() { _identifier.text = label.$1; _code.text = label.$2; });
  }

  Future<void> _submit() async {
    final s = widget.state;
    setState(() { _busy = true; _error = null; });
    try {
      final owned = s.homes.where((h) => h['role_id'] == 'customer_owner' && h['personal'] != true);
      final target = s.home != null ? owned.where((h) => h['org_id'] == s.home).firstOrNull : null;
      await s.api.call('POST', '/api/platform/claim', {
        'identifier': _identifier.text.trim(),
        'code': _code.text.trim(),
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        if (target != null) 'organization': target['org_id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('add.added'))));
      Navigator.pop(context, true);
      return;
    } on ApiError catch (e) {
      _error = s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('nav.add'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        FilledButton.tonalIcon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(s.t('add.scan'))),
        const SizedBox(height: 14),
        Text('${s.t('add.or_manual')} · ${s.t('add.hint')}', style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 18),
        TextField(controller: _identifier, textDirection: TextDirection.ltr, onChanged: _fromLink,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: s.t('add.identifier'), hintText: 'CTRL-8R-0001',
                hintTextDirection: TextDirection.ltr)),
        const SizedBox(height: 12),
        TextField(controller: _code, textDirection: TextDirection.ltr, onChanged: _fromLink,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: s.t('add.code'), hintText: 'XXXX-XXXX-XXXX',
                hintTextDirection: TextDirection.ltr)),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: InputDecoration(labelText: s.t('add.name'))),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(s.t('add.submit'))),
        const SizedBox(height: 26),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EdgeAddScreen(state: s))),
          icon: const Icon(Icons.hub_rounded),
          label: Text(s.t('edge.link')),
        ),
      ]),
    );
  }
}
