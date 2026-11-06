// RF remotes of a device with an RF module (433 or 315 MHz), as the web app's remotes.js: the
// home names a remote and its keys; each key is a button. A new key is learnt from the remote -
// the module listens, the person presses that key on the remote, the module keeps its code in a
// slot - and a touch makes the module send that code again (both through the control layer).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'kit.dart';
import 'widgets.dart';

const _keyIcons = ['remote', 'power', 'door', 'lock', 'bulb', 'curtain', 'fan', 'tv', 'bell', 'arrive', 'out'];

class RemotesCard extends StatefulWidget {
  const RemotesCard({super.key, required this.state, required this.deviceId, required this.canOperate});

  final AppState state;
  final String deviceId;
  final bool canOperate;

  @override
  State<RemotesCard> createState() => _RemotesCardState();
}

class _RemotesCardState extends State<RemotesCard> {
  Map<String, dynamic>? data;
  bool editing = false;
  final Set<int> _pushing = {};

  AppState get s => widget.state;
  String get _base => '/api/platform/my/devices/${widget.deviceId}/remotes';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await s.api.call('GET', _base) as Map<String, dynamic>;
    } on ApiError {
      data = null;
    }
    if (mounted) setState(() {});
  }

  void _toast(String text, {bool bad = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), backgroundColor: bad ? const Color(0xFFB4532A) : null));

  String _result(Map r) {
    final res = '${r['result']}';
    return s.i18n.has('write.$res') ? s.t('write.$res') : '${r['message'] ?? res}';
  }

  List<Map<String, dynamic>> get _remotes => ((data?['remotes'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _send(Map<String, dynamic> r, Map<String, dynamic> k) async {
    HapticFeedback.lightImpact();
    setState(() => _pushing.add(k['key_id'] as int));
    try {
      final res = await s.api.call('POST', '$_base/${r['remote_id']}/keys/${k['key_id']}/send') as Map;
      if (res['result'] != 'applied') _toast(_result(res), bad: true);
    } on ApiError catch (e) {
      _toast(e.message, bad: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _pushing.remove(k['key_id']));
  }

  Future<void> _remoteDialog(Map<String, dynamic>? r) async {
    final bands = ((data?['bands'] as List?) ?? const [433]).cast<int>();
    final name = TextEditingController(text: '${r?['name'] ?? ''}');
    var band = (r?['band'] as int?) ?? bands.last;
    final answer = await showDialog<String>(context: context, builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(s.t(r == null ? 'rf.add_remote' : 'rf.edit_remote')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, maxLength: 40, autofocus: r == null,
              decoration: InputDecoration(labelText: s.t('rf.remote_name'), hintText: s.t('rf.remote_hint'))),
          const SizedBox(height: 6),
          RowLabel(s.t('rf.band')),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: [for (final b in bands) ButtonSegment(value: b, label: Text('$b MHz', textDirection: TextDirection.ltr))],
            selected: {band},
            onSelectionChanged: (v) => set(() => band = v.first),
          ),
          const SizedBox(height: 8),
          Text(s.t('rf.band_help'), style: TextStyle(fontSize: 12, color: Tk.of(c).muted)),
        ]),
        actions: [
          if (r != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(s.t('auto.delete'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('common.cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(c, 'save'), child: Text(s.t('common.save'))),
        ],
      ),
    ));
    try {
      if (answer == 'delete') {
        if (!await _confirm(s.t('rf.delete_remote_confirm', {'name': '${r!['name']}'}))) return;
        await s.api.call('DELETE', '$_base/${r['remote_id']}');
      } else if (answer == 'save') {
        final body = {'name': name.text.trim().isEmpty ? s.t('rf.title') : name.text.trim(), 'band': band};
        if (r == null) {
          final saved = await s.api.call('POST', _base, body) as Map<String, dynamic>;
          await _load();
          _newKey({...saved, 'keys': []});                   // straight on to its first key
          return;
        }
        await s.api.call('PUT', '$_base/${r['remote_id']}', body);
      } else {
        return;
      }
    } on ApiError catch (e) {
      _toast(e.message, bad: true);
    }
    _load();
  }

  Future<bool> _confirm(String text) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(c, true), child: Text(s.t('auto.delete'))),
        ],
      )) == true;

  Future<void> _newKey(Map<String, dynamic> r) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(s.t('rf.add_key')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, autofocus: true, maxLength: 40,
            decoration: InputDecoration(labelText: s.t('rf.key_name'), hintText: s.t('rf.key_hint'))),
        Text(s.t('rf.add_key_help', {'band': r['band']}), style: TextStyle(fontSize: 12, color: Tk.of(c).muted)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(c, true), child: Text(s.t('rf.learn_now'))),
      ],
    ));
    if (ok != true) return;
    try {
      final k = await s.api.call('POST', '$_base/${r['remote_id']}/keys', {
        'name': name.text.trim().isEmpty
            ? s.t('rf.key_default', {'n': s.i18n.num(((r['keys'] as List?)?.length ?? 0) + 1)}) : name.text.trim(),
      }) as Map<String, dynamic>;
      await _load();
      _learn(r, k);
    } on ApiError catch (e) {
      _toast(s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message, bad: true);
    }
  }

  /// The learning window: the module listens; the person presses the key on the remote.
  Future<void> _learn(Map<String, dynamic> r, Map<String, dynamic> k) async {
    if (!mounted) return;
    final nav = Navigator.of(context);
    var open = true;
    showDialog<void>(context: context, barrierDismissible: false, builder: (c) => AlertDialog(
      title: Text(s.t('rf.learning')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const _Listening(),
        const SizedBox(height: 12),
        Text(s.t('rf.press_now', {'key': '${k['name']}', 'band': r['band']}), textAlign: TextAlign.center),
      ]),
      actions: [TextButton(onPressed: () { open = false; Navigator.pop(c); }, child: Text(s.t('common.cancel')))],
    ));
    Map res;
    try {
      res = await s.api.call('POST', '$_base/${r['remote_id']}/keys/${k['key_id']}/learn') as Map;
    } on ApiError catch (e) {
      res = {'result': 'failed', 'message': e.message};
    }
    if (open && mounted) nav.pop();
    if (!mounted) return;
    if (res['result'] == 'learnt') {
      HapticFeedback.mediumImpact();
      _toast(s.t('rf.learnt', {'key': '${k['name']}'}));
    } else if (res['result'] == 'timeout') {
      final again = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text(s.t('rf.learning')),
        content: Text(s.t('rf.timeout')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(c, true), child: Text(s.t('rf.try_again'))),
        ],
      ));
      if (again == true) return _learn(r, k);
    } else {
      _toast(_result(res), bad: true);
    }
    _load();
  }

  Future<void> _keyDialog(Map<String, dynamic> r, Map<String, dynamic> k) async {
    final name = TextEditingController(text: '${k['name']}');
    var icon = (k['icon'] as String?) ?? 'remote';
    final answer = await showDialog<String>(context: context, builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final tk = Tk.of(c);
        return AlertDialog(
          title: Text(s.t('rf.edit_key')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, maxLength: 40, decoration: InputDecoration(labelText: s.t('rf.key_name'))),
            RowLabel(s.t('out.icon')),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final i in _keyIcons)
                GestureDetector(
                  onTap: () => set(() => icon = i),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: icon == i ? tk.accentSoft : tk.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: icon == i ? tk.accentLine : tk.line),
                    ),
                    child: Icon(iconFor(i), size: 20, color: icon == i ? tk.accent : tk.muted),
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(s.t('auto.delete'))),
            TextButton(onPressed: () => Navigator.pop(c, 'learn'), child: Text(s.t('rf.learn_again'))),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(c, 'save'), child: Text(s.t('common.save'))),
          ],
        );
      },
    ));
    final path = '$_base/${r['remote_id']}/keys/${k['key_id']}';
    try {
      if (answer == 'save') {
        await s.api.call('PUT', path, {'name': name.text.trim().isEmpty ? k['name'] : name.text.trim(),
          'icon': icon == 'remote' ? null : icon});
      } else if (answer == 'delete') {
        if (!await _confirm(s.t('rf.delete_key_confirm', {'name': '${k['name']}'}))) return;
        await s.api.call('DELETE', path);
      } else if (answer == 'learn') {
        await _learn(r, k);
        return;
      } else {
        return;
      }
    } on ApiError catch (e) {
      _toast(e.message, bad: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (data?['supported'] != true) return const SizedBox.shrink();
    final tk = Tk.of(context);
    final used = _remotes.fold<int>(0, (n, r) => n + ((r['keys'] as List?)?.length ?? 0));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(iconFor('remote'), color: tk.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(s.t('rf.title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tk.text))),
          if (widget.canOperate && _remotes.isNotEmpty)
            IconButton(
              tooltip: s.t(editing ? 'out.edit_done' : 'out.edit_mode'),
              icon: Icon(editing ? Icons.check_rounded : Icons.edit_outlined, color: editing ? tk.accent : null),
              onPressed: () => setState(() => editing = !editing),
            ),
          if (widget.canOperate)
            TextButton.icon(onPressed: () => _remoteDialog(null), icon: const Icon(Icons.add_rounded),
                label: Text(s.t('rf.add_remote'))),
        ]),
        Text(s.t('rf.help', {'used': s.i18n.num(used), 'total': s.i18n.num(data!['slots'] ?? 0)}),
            style: TextStyle(fontSize: 12, height: 1.6, color: tk.muted)),
        if (_remotes.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(s.t('rf.none'), style: TextStyle(color: tk.muted))),
        for (final r in _remotes) ...[
          const Divider(height: 24),
          Row(children: [
            Expanded(child: Text('${r['name']}', style: TextStyle(fontWeight: FontWeight.w800, color: tk.text))),
            Chip(label: Text('${r['band']} MHz', textDirection: TextDirection.ltr), visualDensity: VisualDensity.compact),
            if (editing)
              IconButton(tooltip: s.t('rf.edit_remote'), icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _remoteDialog(r)),
          ]),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: [
              for (final k in ((r['keys'] as List?) ?? const []).cast<Map<String, dynamic>>())
                _KeyTile(
                  name: '${k['name']}', icon: iconFor((k['icon'] as String?) ?? 'remote'),
                  learnt: k['learnt_at'] != null, editing: editing, pushing: _pushing.contains(k['key_id']),
                  hint: s.t('rf.tap_to_learn'),
                  onTap: !widget.canOperate ? null
                      : editing ? () => _keyDialog(r, k)
                      : k['learnt_at'] == null ? () => _learn(r, k) : () => _send(r, k),
                  onLongPress: widget.canOperate ? () => _keyDialog(r, k) : null,
                ),
              if (widget.canOperate)
                _KeyTile(name: s.t('rf.add_key'), icon: Icons.add_rounded, learnt: false, add: true,
                    onTap: () => _newKey(r)),
            ],
          ),
        ],
      ])),
    );
  }
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.name, required this.icon, required this.learnt, this.onTap, this.onLongPress,
      this.editing = false, this.pushing = false, this.add = false, this.hint});

  final String name;
  final IconData icon;
  final bool learnt;
  final bool editing;
  final bool pushing;
  final bool add;
  final String? hint;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final fg = pushing ? tk.accentInk : add ? tk.accent : learnt ? tk.text : tk.muted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: pushing ? tk.accent : add ? Colors.transparent : tk.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: learnt && !editing ? tk.line2 : tk.accentLine,
            width: learnt && !editing ? 1 : 1.2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(editing && !add ? Icons.edit_outlined : icon, size: 24, color: fg),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: fg)),
            ),
            if (!learnt && !add && hint != null)
              Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: tk.accent)),
          ]),
        ),
      ),
    );
  }
}

/// Waves going out from the remote while the module listens.
class _Listening extends StatefulWidget {
  const _Listening();

  @override
  State<_Listening> createState() => _ListeningState();
}

class _ListeningState extends State<_Listening> with SingleTickerProviderStateMixin {
  late final _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return SizedBox(
      width: 120, height: 120,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          for (final shift in [0.0, 1 / 3, 2 / 3])
            Builder(builder: (_) {
              final t = (_ctl.value + shift) % 1;
              return Transform.scale(
                scale: 0.6 + 1.2 * t,
                child: Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: tk.accent.withValues(alpha: 1 - t), width: 2))),
              );
            }),
          Icon(iconFor('remote'), size: 34, color: tk.accent),
        ]),
      ),
    );
  }
}
