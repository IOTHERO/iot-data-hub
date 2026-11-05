// Scenes of the home: one tap runs them (with the caller's rights; the hub checks every step).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/widgets.dart';
import '../ui/kit.dart';

class ScenesScreen extends StatefulWidget {
  const ScenesScreen({super.key, required this.state});

  final AppState state;

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

  Future<void> _load() async {
    final s = widget.state;
    final orgs = s.home != null ? [s.home!] : s.homes.map((h) => h['org_id'] as String).toList();
    final all = <Map<String, dynamic>>[];
    for (final org in orgs) {
      try {
        all.addAll((await s.api.call('GET', '/api/platform/organizations/$org/scenes') as List).cast<Map<String, dynamic>>());
      } on ApiError {
        // a home without scene rights (viewer): none from it
      }
    }
    if (mounted) setState(() { scenes = all; loaded = true; });
  }

  Future<void> _run(Map<String, dynamic> scene) async {
    final s = widget.state;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await s.api.call('POST', '/api/platform/organizations/${scene['org_id']}/scenes/${scene['scene_id']}/run');
      final detail = r is Map ? (r['detail'] as List? ?? const []) : const [];
      final failed = detail.where((x) => x is Map && x['tag'] != null && x['result'] != 'applied').length;
      messenger.showSnackBar(SnackBar(content: Text(failed == 0 ? s.t('auto.scene_done') : s.t('auto.scene_partial', {'n': failed}))));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 130), children: [
        Text(s.t('auto.scenes'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: tk.text)),
        const SizedBox(height: 16),
        if (loaded && scenes.isEmpty) GlassCard(child: Text(s.t('auto.no_scenes'))),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final sc in scenes) _SceneCard(state: s, scene: sc, onTap: () => _run(sc)),
          ],
        ),
      ]),
    );
  }
}

/// .scene-card: 112 px, toned by its icon (moon violet, leaving green, cinema orange, else accent).
class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.state, required this.scene, required this.onTap});

  final AppState state;
  final Map<String, dynamic> scene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final tone = tk.tone(scene['icon'] as String?);
    return Material(
      color: tone.withValues(alpha: 0.13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: tone.withValues(alpha: 0.35))),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Icon(iconFor(scene['icon'] as String?), size: 26, color: tone),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${scene['name']}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tk.text)),
              Text(state.t('auto.actions', {'n': (scene['actions'] as List).length}),
                  style: TextStyle(fontSize: 12, color: tk.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}
