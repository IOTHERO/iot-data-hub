// The app's frame, as the web app's (.dock in app/css/app.css): the glow behind the pages and
// the glass capsule dock - home, scenes, the round add button, automations, me - whose lit pill
// slides to the open tab; the "local mode" strip while the internet is down.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import 'add_device.dart';
import 'automations.dart';
import 'home.dart';
import 'me.dart';
import 'scenes.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.state, required this.signedOut});

  final AppState state;
  final VoidCallback signedOut;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;                      // 0 home, 1 scenes, 2 automations, 3 me
  int _homeKey = 0;

  Future<void> _add() async {
    final added = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => AddDeviceScreen(state: widget.state)));
    if (added == true) setState(() { tab = 0; _homeKey++; });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final pages = [
      HomeScreen(key: ValueKey(_homeKey), state: s, openMe: () => setState(() => tab = 3)),
      ScenesScreen(state: s),
      AutomationsPage(state: s),
      MeScreen(state: s, signedOut: widget.signedOut),
    ];
    return Scaffold(
      extendBody: true,
      backgroundColor: Tk.of(context).bg,
      body: GlowPage(
        child: Stack(children: [
          IndexedStack(index: tab, children: pages),
          ValueListenableBuilder<bool>(
            valueListenable: s.api.offline,
            builder: (_, offline, __) => offline ? _LocalStrip(text: s.t('local.mode')) : const SizedBox.shrink(),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: _Dock(
          index: tab,
          items: [
            (Icons.home_rounded, s.t('nav.home')),
            (Icons.star_outline_rounded, s.t('nav.scenes')),
            (Icons.tune_rounded, s.t('nav.automations')),
            (Icons.person_outline_rounded, s.t('nav.me')),
          ],
          addLabel: s.t('nav.add'),
          onTap: (i) => setState(() => tab = i),
          onAdd: _add,
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.items, required this.index, required this.onTap, required this.onAdd,
      required this.addLabel});

  final List<(IconData, String)> items;       // four tabs; the add button sits in the middle
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final slot = index < 2 ? index : index + 1;              // column of the open tab (2 = add)
    return SizedBox(
      height: 100,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(33),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 66,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
                  Colors.white.withValues(alpha: tk.dark ? 0.10 : 0.55),
                  Colors.white.withValues(alpha: tk.dark ? 0.03 : 0.35),
                ]),
                color: tk.bg2.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(33),
                border: Border.all(color: Colors.white.withValues(alpha: tk.dark ? 0.12 : 0.6)),
              ),
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth / 5;
                return Stack(children: [
                  AnimatedPositionedDirectional(                       // the lit pill slides
                    duration: const Duration(milliseconds: 550),
                    curve: const Cubic(.34, 1.4, .5, 1),
                    start: w * slot, top: 0, bottom: 0, width: w,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
                          Colors.white.withValues(alpha: tk.dark ? 0.16 : 0.9),
                          Colors.white.withValues(alpha: tk.dark ? 0.05 : 0.6),
                        ]),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        boxShadow: [BoxShadow(color: tk.accentGlow, blurRadius: 22)],
                      ),
                    ),
                  ),
                  Row(children: [
                    for (var i = 0; i < 5; i++)
                      Expanded(
                        child: i == 2
                            ? const SizedBox.shrink()
                            : _DockItem(
                                icon: items[i < 2 ? i : i - 1].$1,
                                label: items[i < 2 ? i : i - 1].$2,
                                on: slot == i,
                                onTap: () => onTap(i < 2 ? i : i - 1),
                              ),
                      ),
                  ]),
                ]);
              }),
            ),
          ),
        ),
        Positioned(bottom: 42, child: _AddLens(onTap: onAdd, label: addLabel)),   // 30 px above the glass
      ]),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final color = on ? tk.accent : tk.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedScale(
          scale: on ? 1.12 : 1,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          child: Icon(icon, size: 22, color: color,
              shadows: on ? [Shadow(color: tk.accentGlow, blurRadius: 8)] : null),
        ),
        const SizedBox(height: 3),
        AnimatedOpacity(
          opacity: on ? 1 : 0.75,
          duration: const Duration(milliseconds: 300),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
        ),
      ]),
    );
  }
}

/// .dock-add: the round accent lens above the glass, with a slow breathing glow.
class _AddLens extends StatefulWidget {
  const _AddLens({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  State<_AddLens> createState() => _AddLensState();
}

class _AddLensState extends State<_AddLens> with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Tooltip(
      message: widget.label,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _breath,
          builder: (_, child) => Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: const Alignment(-0.4, -0.5), colors: [
                Color.lerp(tk.accent, Colors.white, 0.4)!, tk.accent,
              ], stops: const [0, 0.6]),
              boxShadow: [
                BoxShadow(color: tk.accentGlow.withValues(alpha: 0.25 + 0.3 * _breath.value),
                    blurRadius: 18 + 10 * _breath.value, spreadRadius: 2 * _breath.value),
                BoxShadow(color: tk.bg.withValues(alpha: 0.55), spreadRadius: 5),
              ],
            ),
            child: child,
          ),
          child: Icon(Icons.add_rounded, size: 28, color: tk.accentInk),
        ),
      ),
    );
  }
}

class _LocalStrip extends StatelessWidget {
  const _LocalStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: tk.bg2.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tk.accentLine),
        ),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: tk.orange, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: tk.text))),
        ]),
      ),
    );
  }
}
