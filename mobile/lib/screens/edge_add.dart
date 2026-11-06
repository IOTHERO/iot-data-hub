// Industrial equipment behind an edge hub (the web app's addEdge): pick the hub, the product from
// the catalogue, its protocol and its address on the site network (the protocol's required
// connection fields, plus port and unit id). POST /api/platform/my/devices/{hub}/children.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/widgets.dart';

class EdgeAddScreen extends StatefulWidget {
  const EdgeAddScreen({super.key, required this.state, this.hubId});

  final AppState state;
  final String? hubId;

  @override
  State<EdgeAddScreen> createState() => _EdgeAddScreenState();
}

class _EdgeAddScreenState extends State<EdgeAddScreen> {
  List<Map<String, dynamic>>? hubs;
  List<Map<String, dynamic>> catalog = [];
  Map<String, dynamic> protocols = {};
  String? error;
  String? hub;
  String? product;
  String? protocol;
  final _name = TextEditingController();
  final Map<String, TextEditingController> fields = {};
  bool _busy = false;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        s.api.call('GET', '/api/platform/my/devices'),
        s.api.call('GET', '/api/platform/catalog'),
        s.api.call('GET', '/api/platform/protocols'),
      ]);
      hubs = (r[0] as List).cast<Map<String, dynamic>>()
          .where((d) => d['product_kind'] == 'edge_hub' && d['access'] == 'owner').toList();
      catalog = (r[1] as List).cast<Map<String, dynamic>>();
      protocols = r[2] as Map<String, dynamic>;
      hub = hubs!.any((d) => d['device_id'] == widget.hubId) ? widget.hubId : hubs!.firstOrNull?['device_id'] as String?;
      _pickProduct(catalog.firstOrNull?['product_id'] as String?);
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? get _product => catalog.where((p) => p['product_id'] == product).firstOrNull;

  List<String> get _protocols =>
      ((_product?['protocols'] as List?) ?? const []).cast<String>().where((x) => x != 'native').toList();

  /// The address fields of the chosen protocol: the required ones, and port and unit id.
  List<Map<String, dynamic>> get _spec => ((protocols[protocol]?['connection'] as List?) ?? const [])
      .cast<Map<String, dynamic>>()
      .where((f) => f['required'] == true || f['name'] == 'port' || f['name'] == 'unit_id')
      .toList();

  void _pickProduct(String? id) {
    product = id;
    final list = _protocols;
    _pickProtocol(list.firstOrNull);
  }

  void _pickProtocol(String? p) {
    protocol = p;
    fields.clear();
    for (final f in _spec) {
      fields[f['name'] as String] = TextEditingController();
    }
  }

  String _label(String group, String key) => s.i18n.has('$group.$key') ? s.t('$group.$key') : key;

  Future<void> _submit() async {
    final p = _product;
    if (hub == null || p == null || protocol == null) return;
    final connection = <String, dynamic>{};
    for (final f in _spec) {
      final text = fields[f['name']]!.text.trim();
      if (text.isEmpty) continue;
      final numeric = f['type'] == 'integer' || f['type'] == 'number';
      connection[f['name'] as String] = numeric ? (num.tryParse(text) ?? text) : text;
    }
    setState(() => _busy = true);
    try {
      await s.api.call('POST', '/api/platform/my/devices/$hub/children', {
        'product_id': p['product_id'],
        'version': p['latest_published'],
        'protocol': protocol,
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        'connection': connection,
        'enabled': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('edge.added'))));
      Navigator.pop(context, true);
      return;
    } on ApiError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message)));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final list = hubs;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('edge.link'))),
      body: GlowPage(child: list == null
          ? Center(child: error == null ? const CircularProgressIndicator() : Text(error!))
          : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
              Text(s.t('edge.lead'), style: TextStyle(fontSize: 13, height: 1.6, color: tk.muted)),
              const SizedBox(height: 14),
              if (list.isEmpty)
                GlassCard(child: Column(children: [
                  Icon(iconFor('hub'), size: 40, color: tk.accent),
                  const SizedBox(height: 10),
                  Text(s.t('edge.no_hub'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.t('edge.add_hub_first'))),
                ]))
              else
                GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  WebField(label: s.t('edge.hub'), child: DropdownButtonFormField<String>(
                    initialValue: hub, isExpanded: true,
                    decoration: const InputDecoration(),
                    items: [for (final d in list)
                      DropdownMenuItem(value: d['device_id'] as String, child: Text('${d['name']}'))],
                    onChanged: (v) => setState(() => hub = v),
                  )),
                  const SizedBox(height: 12),
                  WebField(label: s.t('edge.product'), child: DropdownButtonFormField<String>(
                    initialValue: product, isExpanded: true,
                    decoration: const InputDecoration(),
                    items: [for (final p in catalog)
                      DropdownMenuItem(value: p['product_id'] as String, child: Text('${p['name']} · ${p['code']}',
                          overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _pickProduct(v)),
                  )),
                  const SizedBox(height: 12),
                  WebField(label: s.t('edge.protocol'), child: DropdownButtonFormField<String>(
                    key: ValueKey(product),
                    initialValue: protocol, isExpanded: true,
                    decoration: const InputDecoration(),
                    items: [for (final p in _protocols) DropdownMenuItem(value: p, child: Text(_label('proto', p)))],
                    onChanged: (v) => setState(() => _pickProtocol(v)),
                  )),
                  const SizedBox(height: 12),
                  WebField(label: s.t('device.name'), child: TextField(controller: _name,
                      decoration: InputDecoration(hintText: s.t('edge.name_hint')))),
                  const SizedBox(height: 16),
                  RowLabel(s.t('edge.address')),
                  for (final f in _spec)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: WebField(label: _label('conn', f['name'] as String), child: TextField(
                        controller: fields[f['name']],
                        textDirection: TextDirection.ltr,
                        keyboardType: f['type'] == 'integer' || f['type'] == 'number'
                            ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                        decoration: InputDecoration(hintText: f['default'] == null ? null : '${f['default']}'),
                      )),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _busy || protocol == null ? null : _submit, child: Text(s.t('edge.add'))),
                ])),
            ])),
    );
  }
}
