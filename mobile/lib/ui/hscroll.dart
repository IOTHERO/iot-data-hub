// A row that scrolls sideways (quick scenes, shortcuts, groups), as the web app's scroller():
// a glass arrow at an edge while more items wait past it, gently moving so the eye finds it;
// a touch on it scrolls, dragging by hand still works.

import 'dart:ui';

import 'package:flutter/material.dart';

import 'kit.dart';

class HScroll extends StatefulWidget {
  const HScroll({super.key, required this.height, required this.children, this.gap = 10, this.moreLabel});

  final double height;
  final List<Widget> children;
  final double gap;
  final String? moreLabel;

  @override
  State<HScroll> createState() => _HScrollState();
}

class _HScrollState extends State<HScroll> with SingleTickerProviderStateMixin {
  final _ctl = ScrollController();
  late final _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  bool _before = false;          // items past the start edge
  bool _after = false;           // items past the end edge

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(HScroll old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _ctl.dispose();
    _nudge.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_ctl.hasClients) return;
    final p = _ctl.position;
    final before = p.pixels > 2;
    final after = p.pixels < p.maxScrollExtent - 2;
    if (before != _before || after != _after) setState(() { _before = before; _after = after; });
  }

  void _go(int dir) {
    if (!_ctl.hasClients) return;
    final p = _ctl.position;
    final to = (p.pixels + dir * p.viewportDimension * 0.7).clamp(0.0, p.maxScrollExtent);
    _ctl.animateTo(to, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  Widget _arrow(bool end) {
    final tk = Tk.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // the chevron points toward the hidden items; Material mirrors it in Persian by itself
    final icon = end ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    return PositionedDirectional(
      start: end ? null : -4,
      end: end ? -4 : null,
      top: 0,
      bottom: 0,
      child: Center(child: AnimatedBuilder(
        animation: _nudge,
        builder: (_, child) => Transform.translate(
          offset: Offset(((end != rtl) ? 1 : -1) * 3 * Curves.easeInOut.transform(_nudge.value), 0),
          child: child,
        ),
        child: Semantics(
          button: true,
          label: widget.moreLabel,
          child: GestureDetector(
            onTap: () => _go(end ? 1 : -1),
            child: ClipOval(child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tk.dark ? const Color(0x8C0E1117) : const Color(0xB3FFFFFF),
                  border: Border.all(color: tk.line2),
                ),
                child: Icon(icon, size: 22, color: tk.text),
              ),
            )),
          ),
        ),
      )),
    );
  }

  Widget _fade(bool end) {
    final bg = Tk.of(context).bg;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toward = (end != rtl) ? Alignment.centerRight : Alignment.centerLeft;
    return PositionedDirectional(
      start: end ? null : 0,
      end: end ? 0 : null,
      top: 0,
      bottom: 0,
      width: 30,
      child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: toward == Alignment.centerRight ? Alignment.centerLeft : Alignment.centerRight,
        end: toward,
        colors: [bg.withValues(alpha: 0), bg],
      )))),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _update();
            return false;
          },
          child: Stack(clipBehavior: Clip.none, children: [
            ListView.separated(
              controller: _ctl,
              scrollDirection: Axis.horizontal,
              itemCount: widget.children.length,
              separatorBuilder: (_, __) => SizedBox(width: widget.gap),
              itemBuilder: (_, i) => widget.children[i],
            ),
            if (_before) _fade(false),
            if (_after) _fade(true),
            if (_before) _arrow(false),
            if (_after) _arrow(true),
          ]),
        ),
      );
}
