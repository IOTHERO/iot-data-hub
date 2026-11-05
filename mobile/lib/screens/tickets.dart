// Support and warranty requests to the device's maker: the list, one conversation, and a reply
// (GET /api/platform/my/tickets, /my/tickets/{id}, POST …/messages).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';

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
    final d = data;
    final cs = Theme.of(context).colorScheme;
    if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final t = d['ticket'] as Map<String, dynamic>;
    final closed = t['status'] == 'closed' || t['status'] == 'rejected';
    return Scaffold(
      appBar: AppBar(title: Text('${t['subject']}')),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final m in (d['messages'] as List).cast<Map<String, dynamic>>())
            Align(
              alignment: m['side'] == 'buyer' ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: m['side'] == 'buyer' ? cs.primary.withValues(alpha: 0.14) : cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['side'] == 'buyer' ? s.t('tickets.you') : '${m['author_name']}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                  const SizedBox(height: 4),
                  Text('${m['body']}'),
                ]),
              ),
            ),
        ])),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: closed
                ? Text(s.t('tickets.closed'))
                : Row(children: [
                    Expanded(child: TextField(controller: _reply, minLines: 1, maxLines: 4,
                        decoration: InputDecoration(hintText: s.t('tickets.reply_hint')))),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_rounded)),
                  ]),
          ),
        ),
      ]),
    );
  }
}
