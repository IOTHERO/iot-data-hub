// Support and warranty requests to the device's maker: the list, one conversation, and a reply
// (GET /api/platform/my/tickets, /my/tickets/{id}, POST …/messages).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  List<Map<String, dynamic>> tickets = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      tickets = (await widget.state.api.call('GET', '/api/platform/my/tickets') as List).cast<Map<String, dynamic>>();
    } on ApiError {
      tickets = [];
    }
    if (mounted) setState(() => loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tickets.title'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (loaded && tickets.isEmpty) Text(s.t('mobile.no_tickets')),
          for (final t in tickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text('${t['subject']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${t['product_name']} · ${t['identifier']}'),
                  trailing: Chip(label: Text(s.t('tickets.status_${t['status']}'))),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => TicketScreen(state: s, ticketId: t['ticket_id'] as int)));
                    _load();
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.state, required this.ticketId});

  final AppState state;
  final int ticketId;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  Map<String, dynamic>? data;
  final _reply = TextEditingController();
  bool _busy = false;

  String get _path => '/api/platform/my/tickets/${widget.ticketId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await widget.state.api.call('GET', _path) as Map<String, dynamic>;
    } on ApiError {
      // left as it was
    }
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.state.api.call('POST', '$_path/messages', {'body': _reply.text.trim()});
      _reply.clear();
      await _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final d = data;
    if (d == null) {
      return const WebPage(title: '', children: [Center(child: CircularProgressIndicator())]);
    }
    final t = d['ticket'] as Map<String, dynamic>;
    final closed = t['status'] == 'closed';
    const tone = {'answered': ChipTone.accent, 'in_progress': ChipTone.violet, 'approved': ChipTone.ok,
      'rejected': ChipTone.warn};
    return WebPage(title: '${t['subject']}', sub: '${t['product_name']} · ${t['identifier']}', children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        WebChip(s.t('tickets.kind_${t['kind']}')),
        WebChip(s.t('tickets.status_${t['status']}'), tone: tone[t['status']] ?? ChipTone.plain),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final m in (d['messages'] as List).cast<Map<String, dynamic>>())
          Align(           // .bubble: the buyer at the start, the maker at the end in the accent
            alignment: m['side'] == 'maker' ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m['side'] == 'maker' ? tk.accentSoft : tk.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: m['side'] == 'maker' ? tk.accentLine : tk.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['side'] == 'maker' ? m['author_name'] : s.t('tickets.you')} · ${s.i18n.when(m['created_at'])}',
                    style: TextStyle(fontSize: 11, color: tk.muted)),
                const SizedBox(height: 4),
                Text('${m['body']}', style: TextStyle(fontSize: 13, height: 1.8, color: tk.text)),
              ]),
            ),
          ),
      ]),
      if (closed)
        Text(s.t('tickets.closed'), style: TextStyle(fontSize: 13, color: tk.muted))
      else
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _reply, minLines: 3, maxLines: 6,
              decoration: InputDecoration(hintText: s.t('tickets.reply_hint'))),
          const SizedBox(height: 12),
          WebButton(s.t('tickets.send'), kind: BtnKind.primary, block: true, onTap: _busy ? null : _send),
        ]),
    ]);
  }
}
