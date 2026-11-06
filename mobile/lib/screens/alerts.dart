// Security alarms, as the web app's alerts.js: a pulsing red bar on the home screen while a
// hallway PIR, a door magnet or a smoke detector alert is open; the alarm list - each marked
// seen, swiped away to clear, all cleared at once - and a touch opens the device it came from.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import '../ui/widgets.dart';
import 'device.dart';

const alarmRed = Color(0xFFFF4D5E);

IconData alarmIcon(String? kind) => kind == 'offline' ? Icons.wifi_off_rounded
    : iconFor(kind == 'motion' || kind == 'magnet' || kind == 'smoke' ? kind : 'alert');

/// Date and time, in the person's calendar and digits.
String alarmWhen(AppState s, DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${s.i18n.date(d)} · ${s.i18n.num('${two(d.hour)}:${two(d.minute)}')}';
}

String alarmLabel(AppState s, Map<String, dynamic> a) =>
    s.t('alarm.kind_${a['kind']}', {'name': s.i18n.name(a['tag_name'])});

void openAlarmSource(BuildContext context, AppState s, Map<String, dynamic> a) => Navigator.push(context,
    MaterialPageRoute(builder: (_) => DeviceScreen(state: s, deviceId: a['device_id'] as String, focus: a['tag_key'] as String?)));

/// The home screen's live alarm: nothing while all is quiet.
class AlarmBar extends StatefulWidget {
  const AlarmBar({super.key, required this.state});

  final AppState state;

  @override
  State<AlarmBar> createState() => _AlarmBarState();
}

class _AlarmBarState extends State<AlarmBar> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListenableBuilder(
      listenable: s.alerts,
      builder: (context, _) {
        final list = s.alerts.list;
        if (list.isEmpty) return const SizedBox.shrink();
        final fresh = s.alerts.unseen;
        final first = fresh.isNotEmpty ? fresh.first : list.first;
        final live = fresh.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = live ? (1 - (2 * _pulse.value - 1).abs()) : 0.0;     // 0..1..0
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: live
                      ? LinearGradient(colors: [Color.lerp(alarmRed, const Color(0xFFFF7A86), t)!, const Color(0xFFB5172B)])
                      : null,
                  color: live ? null : alarmRed.withValues(alpha: 0.14),
                  border: live ? null : Border.all(color: alarmRed.withValues(alpha: 0.45)),
                  boxShadow: live ? [BoxShadow(color: alarmRed.withValues(alpha: 0.30 + 0.25 * t), blurRadius: 18 + 14 * t)] : null,
                ),
                child: child,
              );
            },
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlertsScreen(state: s))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    _Ring(animation: _pulse, live: live, icon: alarmIcon(first['kind'] as String?)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(live ? s.t('alarm.active', {'n': s.i18n.num(fresh.length)}) : s.t('alarm.open', {'n': s.i18n.num(list.length)}),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: live ? Colors.white : alarmRed)),
                      Text('${alarmLabel(s, first)} · ${first['device_name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: live ? Colors.white70 : alarmRed)),
                    ])),
                    Icon(Icons.chevron_left_rounded, color: live ? Colors.white : alarmRed),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.animation, required this.live, required this.icon});

  final Animation<double> animation;
  final bool live;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40, height: 40,
        child: AnimatedBuilder(
          animation: animation,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            if (live)
              Transform.scale(
                scale: 1 + animation.value * 0.9,
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 1 - animation.value), width: 2))),
              ),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: live ? Colors.white.withValues(alpha: 0.18) : alarmRed.withValues(alpha: 0.14)),
              child: Icon(icon, color: live ? Colors.white : alarmRed, size: 20),
            ),
          ]),
        ),
      );
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.state});

  final AppState state;

  Future<void> _do(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final tk = Tk.of(context);
    s.alerts.load();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('alarm.title'))),
      body: GlowPage(child: ListenableBuilder(
        listenable: s.alerts,
        builder: (context, _) {
          final list = s.alerts.list;
          if (list.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_user_rounded, size: 56, color: tk.ok),
              const SizedBox(height: 12),
              Text(s.t('alarm.none'), style: TextStyle(color: tk.muted)),
            ]));
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(s.t('alarm.swipe_hint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: tk.muted)),
            ),
            Expanded(child: Scrollbar(child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = list[i];
                final live = a['seen_at'] == null;
                final trips = (a['trips'] as num?) ?? 1;
                final last = DateTime.tryParse('${a['last_at']}')?.toLocal();
                return Dismissible(
                  key: ValueKey('alert-${a['alert_id']}'),
                  background: _swipeBack(s, Alignment.centerRight),
                  secondaryBackground: _swipeBack(s, Alignment.centerLeft),
                  onDismissed: (_) {
                    HapticFeedback.mediumImpact();
                    _do(context, () => s.alerts.clear(a['alert_id'] as int));
                  },
                  child: GlassCard(
                    lit: live,
                    onTap: () => openAlarmSource(context, s, a),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                            color: live ? alarmRed : tk.surface2),
                        child: Icon(alarmIcon(a['kind'] as String?), color: live ? Colors.white : tk.muted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(alarmLabel(s, a), style: TextStyle(fontWeight: FontWeight.w800, color: tk.text)),
                        Text([a['device_name'], a['room']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 12, color: tk.muted)),
                        if (last != null)
                          Text(trips > 1 ? s.t('alarm.trips', {'n': s.i18n.num(trips), 'when': alarmWhen(s, last)}) : alarmWhen(s, last),
                              style: TextStyle(fontSize: 11, color: tk.faint)),
                      ])),
                      const SizedBox(width: 8),
                      live
                          ? FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: alarmRed, foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              onPressed: () => _do(context, () => s.alerts.seen(a['alert_id'] as int)),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(s.t('alarm.mark_seen')),
                            )
                          : Chip(avatar: Icon(Icons.check_rounded, size: 16, color: tk.ok), label: Text(s.t('alarm.seen'))),
                    ]),
                  ),
                );
              },
            ))),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Column(children: [
                if (s.alerts.unseen.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _do(context, s.alerts.seenAll),
                    icon: const Icon(Icons.done_all_rounded), label: Text(s.t('alarm.seen_all')),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: alarmRed,
                      side: BorderSide(color: alarmRed.withValues(alpha: 0.5))),
                  onPressed: () => _do(context, s.alerts.clearAll),
                  icon: const Icon(Icons.delete_sweep_rounded), label: Text(s.t('alarm.clear_all')),
                ),
              ]),
            ),
          ]);
        },
      )),
    );
  }

  Widget _swipeBack(AppState s, Alignment side) => Container(
        alignment: side,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: alarmRed.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(24)),
        child: const Icon(Icons.delete_outline_rounded, color: alarmRed),
      );
}
