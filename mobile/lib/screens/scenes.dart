// Scenes of the home, as the web app's #/auto/scenes: the page header with "+", the
// Scenes | Automations switch, the security scenarios, then the scene cards - a tap runs one (with
// the caller's rights; the hub checks every step), the small buttons edit or schedule it.

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/widgets.dart';
import '../ui/kit.dart';
import '../ui/security.dart';
import 'automations.dart';
import 'scene_edit.dart';

class ScenesScreen extends StatefulWidget {
  const ScenesScreen({super.key, required this.state, this.onSeg});

  final AppState state;
  final ValueChanged<bool>? onSeg;          // the Scenes | Automations switch

  @override
  State<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends State<ScenesScreen> {
  List<Map<String, dynamic>> scenes = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The home of this page: the chosen one, else the user's own (the web app's homeOrg()).
  String? get _org => autoOrg(widget.state);

  Future<void> _load() async {
    final s = widget.state;
    final org = _org;
    var all = <Map<String, dynamic>>[];
    if (org != null) {
      try {
        all = (await s.api.call('GET', '/api/platform/organizations/$org/scenes') as List).cast<Map<String, dynamic>>();
      } on ApiError {
        // a home without scene rights (viewer): none from it
      }
    }
    if (mounted) setState(() { scenes = all; loaded = true; });
  }

  Future<void> _edit(Map<String, dynamic>? scene) async {
    final org = (scene?['org_id'] as String?) ?? _org;
    if (org == null) return;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => SceneEditScreen(state: widget.state, orgId: org, scene: scene)));
    if (saved == true) _load();
  }

  Future<void> _run(Map<String, dynamic> scene) async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await s.api.call('POST', '/api/platform/organizations/${scene['org_id']}/scenes/${scene['scene_id']}/run');
      final detail = r is Map ? (r['detail'] as List? ?? const []) : const [];
      final failed = detail.where((x) => x is Map && x['tag'] != null && x['result'] != 'applied').length;
      messenger.showSnackBar(SnackBar(content: Text(failed == 0 ? s.t('auto.scene_done')
          : s.t('auto.scene_partial', {'n': s.i18n.num(failed)}))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Run the scene at a time of day (Jalali weekdays, holidays): an automation with one action,
  /// as the web app's scheduleScene().
  Future<void> _schedule(Map<String, dynamic> scene) async {
    final s = widget.state;
    var at = const TimeOfDay(hour: 20, minute: 0);
    final chosen = {0, 1, 2, 3, 4, 5, 6};
    var holidays = 'any';
    String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final save = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final tk = Tk.of(ctx);
      return AlertDialog(
        title: Text(s.t('auto.schedule_x', {'x': scene['name']})),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Label(s.t('auto.at')),
          const SizedBox(height: 6),
          WebButton(s.i18n.num(hhmm(at)), icon: Icons.schedule_rounded, block: true, onTap: () async {
            final picked = await showTimePicker(context: ctx, initialTime: at);
            if (picked != null) set(() => at = picked);
          }),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 0; d < 7; d++)
              WebTab(s.t('week.$d'), on: chosen.contains(d),
                  onTap: () => set(() => chosen.contains(d) ? chosen.remove(d) : chosen.add(d))),
          ]),
          const SizedBox(height: 12),
          Label(s.t('auto.holidays')),
          DropdownButton<String>(
            isExpanded: true,
            value: holidays,
            items: [
              for (final k in const ['any', 'skip', 'only'])
                DropdownMenuItem(value: k, child: Text(s.t('auto.holidays_$k'))),
            ],
            onChanged: (v) => set(() => holidays = v ?? 'any'),
          ),
          const SizedBox(height: 6),
          Text(s.t('auto.schedule_help'), style: TextStyle(fontSize: 11, height: 1.8, color: tk.muted)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('auto.save'))),
        ],
      );
    }));
    if (save != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final trigger = <String, dynamic>{'type': 'time', 'at': hhmm(at)};
    if (chosen.isNotEmpty && chosen.length < 7) trigger['weekdays'] = chosen.toList()..sort();
    if (holidays != 'any') trigger['holidays'] = holidays;
    try {
      await s.api.call('POST', '/api/platform/organizations/${scene['org_id']}/automations', {
        'name': s.t('auto.scene_at', {'name': scene['name'], 'at': trigger['at']}),
        'trigger': trigger,
        'actions': [{'type': 'scene', 'scene_id': scene['scene_id']}],
      });
      messenger.showSnackBar(SnackBar(content: Text(s.t('auto.saved'))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final org = _org;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 130), children: [
        AutoHeader(state: s, scenes: true, onSeg: widget.onSeg, onPlus: org == null ? null : () => _edit(null)),
        const SizedBox(height: 18),
        if (org == null) Text(s.t('auto.no_home'), style: TextStyle(color: tk.muted)),
        // the home's security scenarios first: burglar, night, fire, connection loss
        if (org != null) ...[
          SecurityCard(key: ValueKey('security-$org'), state: s, orgId: org),
          const SizedBox(height: 18),
        ],
        Text(s.t('auto.scenes'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tk.text)),
        const SizedBox(height: 14),
        if (loaded && scenes.isEmpty)
          EmptyCard(icon: Icons.star_outline_rounded, text: s.t('auto.no_scenes')),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final sc in scenes)
              _SceneCard(state: s, scene: sc, onTap: () => _run(sc), onEdit: () => _edit(sc),
                  onPlan: () => _schedule(sc)),
          ],
        ),
      ]),
    );
  }
}

/// .scene-wrap: the .scene-card (112 px, toned by its icon: moon violet, leaving green, cinema
/// orange, else accent) that runs the scene, with the edit and schedule buttons at its top end.
class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.state, required this.scene, required this.onTap, required this.onEdit,
      required this.onPlan});

  final AppState state;
  final Map<String, dynamic> scene;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final tone = tk.tone(scene['icon'] as String?);
    Widget small(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: Material(
            color: tk.surface,
            shape: CircleBorder(side: BorderSide(color: tk.line)),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
                child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 17, color: tk.accent))),
          ),
        );
    return Stack(children: [
      Positioned.fill(child: Material(
        color: tone.withValues(alpha: 0.13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: tone.withValues(alpha: 0.35))),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Icon(iconFor(scene['icon'] as String?), size: 26, color: tone),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${scene['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tk.text)),
                Text(state.t('auto.actions', {'n': state.i18n.num((scene['actions'] as List).length)}),
                    style: TextStyle(fontSize: 12, color: tk.muted)),
              ]),
            ]),
          ),
        ),
      )),
      PositionedDirectional(top: 10, end: 10,
          child: small(Icons.edit_outlined, state.t('auto.edit_x', {'x': scene['name']}), onEdit)),
      PositionedDirectional(top: 10, end: 52,
          child: small(Icons.schedule_rounded, state.t('auto.schedule_x', {'x': scene['name']}), onPlan)),
    ]);
  }
}
