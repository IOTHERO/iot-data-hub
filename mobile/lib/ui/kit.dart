// The web app's look (app/css/app.css) as Flutter widgets: its colour tokens, the glow behind
// the page, cards, the round icon buttons and avatar, the switch, and the tiles of the home and
// device pages. One place, so both apps stay alike.

import 'dart:ui';

import 'package:flutter/material.dart';

/// The CSS variables of app.css (:root and the light theme).
class Tk {
  Tk._(this.dark, this.accent);

  /// The accent is the theme's primary colour: TiTiSwitch cyan or the one chosen in Me.
  factory Tk.of(BuildContext context) {
    final theme = Theme.of(context);
    return Tk._(theme.brightness == Brightness.dark, theme.colorScheme.primary);
  }

  final bool dark;
  final Color accent;

  Color get bg => dark ? const Color(0xFF0B0D12) : const Color(0xFFF6F4EF);
  Color get bg2 => dark ? const Color(0xFF0E1117) : Colors.white;
  Color get surface => dark ? const Color(0x0DFFFFFF) : const Color(0x0A14161B);     // 5 % / 4 %
  Color get surface2 => dark ? const Color(0x14FFFFFF) : const Color(0x1214161B);    // 8 % / 7 %
  Color get line => dark ? const Color(0x14FFFFFF) : const Color(0x1414161B);        // 8 %
  Color get line2 => dark ? const Color(0x24FFFFFF) : const Color(0x2914161B);       // 14 % / 16 %
  Color get text => dark ? const Color(0xFFF2F2F4) : const Color(0xFF15171C);
  Color get muted => dark ? const Color(0xFFA3A8B5) : const Color(0xFF5B606C);
  Color get faint => dark ? const Color(0xFF7D8290) : const Color(0xFF7A7F8A);
  Color get accentInk => dark ? const Color(0xFF0B0D12) : Colors.white;
  Color get accentSoft => accent.withValues(alpha: dark ? 0.13 : 0.10);
  Color get accentLine => accent.withValues(alpha: dark ? 0.45 : 0.40);
  Color get accentGlow => accent.withValues(alpha: 0.35);
  Color get ok => dark ? const Color(0xFF7FD1C7) : const Color(0xFF1E7F74);
  Color get warn => dark ? const Color(0xFFFF9F7A) : const Color(0xFFB4532A);
  Color get violet => dark ? const Color(0xFFA99BFF) : const Color(0xFF5B4BC4);
  Color get orange => const Color(0xFFF58634);

  /// Scene icon -> tone (core.js SCENE_TONE).
  Color tone(String? icon) => switch (icon) {
        'moon' => violet,
        'out' || 'home' => ok,
        'cinema' => warn,
        _ => accent,
      };
}

/// The page background with the blurred accent glow of the web app (.glow).
class GlowPage extends StatelessWidget {
  const GlowPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: tk.bg)),
      PositionedDirectional(
        top: -140, start: -90,
        child: IgnorePointer(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
            child: Container(width: 340, height: 340,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tk.accent.withValues(alpha: 0.09))),
          ),
        ),
      ),
      Positioned.fill(child: child),
    ]);
  }
}

/// .card: surface, hairline border, radius 24.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24,
      this.lit = false, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool lit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: lit ? tk.accentSoft : tk.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: lit ? tk.accentLine : tk.line),
        boxShadow: lit ? const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 10))] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap,
            child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// .icon-btn: a 44 px round button.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: tk.surface,
        shape: CircleBorder(side: BorderSide(color: tk.line)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: tk.accent))),
      ),
    );
  }
}

/// .avatar: the initial on a dark gradient.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 44, this.onTap});

  final String name;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: tk.dark ? const [Color(0xFF3A3F4B), Color(0xFF22262E)] : const [Color(0xFFE9E4DA), Color(0xFFD8D1C4)]),
        ),
        child: Text(name.isEmpty ? '?' : name.characters.first,
            style: TextStyle(color: tk.accent, fontWeight: FontWeight.w700, fontSize: size * 0.36)),
      ),
    );
  }
}

/// .switch: a 42 x 24 track, the knob slides to the end when on.
class TiSwitch extends StatelessWidget {
  const TiSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Opacity(
        opacity: onChanged == null ? 0.5 : 1,
        child: SizedBox(
          width: 48, height: 44,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42, height: 24,
              decoration: BoxDecoration(color: value ? tk.accent : tk.line2, borderRadius: BorderRadius.circular(12)),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  margin: const EdgeInsets.all(3), width: 18, height: 18,
                  decoration: BoxDecoration(color: value ? tk.accentInk : tk.text, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded square icon tile (.dev .ico, .fav .ico, .group-card .ico).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 42, this.radius = 14, this.on = false, this.strong = false,
      this.color});

  final IconData icon;
  final double size;
  final double radius;
  final bool on;
  final bool strong;        // .fav.on: filled with the accent
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final bg = strong && on ? tk.accent : (on ? tk.accentSoft : tk.surface2);
    final fg = strong && on ? tk.accentInk : (on ? tk.accent : (color ?? tk.muted));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size, height: size,
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(radius),
        boxShadow: strong && on ? [BoxShadow(color: tk.accentGlow, blurRadius: 16)] : null,
      ),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// .stat: label, value, small unit.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit, this.warn = false, this.onTap});

  final String label;
  final String value;
  final String? unit;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Expanded(
      child: GestureDetector(
       onTap: onTap,
       child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: warn ? tk.warn.withValues(alpha: 0.13) : tk.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: warn ? tk.warn.withValues(alpha: 0.35) : tk.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: warn ? tk.warn : tk.muted)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: tk.text)),
            if (unit != null)
              TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: warn ? tk.warn : tk.muted)),
          ])),
        ]),
       ),
      ),
    );
  }
}

/// .scene-btn: a 52 px pill with a toned icon.
class ScenePill extends StatelessWidget {
  const ScenePill({super.key, required this.icon, required this.tone, required this.label, this.onTap});

  final IconData icon;
  final Color tone;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Material(
      color: tk.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: tk.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: tone),
              const SizedBox(width: 8),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: tk.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// .label: the small muted heading above a row.
class RowLabel extends StatelessWidget {
  const RowLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Tk.of(context).text));
}

// --- the web app's small parts (app/css/app.css), one widget each, so every page can be built the
// way its web page is: .chip, .btn, .reading, .card, .top-bar, .page, .label, .perm-chip ----------

enum ChipTone { plain, ok, warn, accent, violet, danger }

/// .chip: a small rounded label, toned (ok, warn, accent, violet; danger is the alarm red).
class WebChip extends StatelessWidget {
  const WebChip(this.text, {super.key, this.tone = ChipTone.plain, this.icon, this.onTap, this.ltr = false,
      this.dot = false});

  final String text;
  final bool dot;                        // .dot: a 7 px light before the text (online, offline)
  final ChipTone tone;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final (bg, fg) = switch (tone) {
      ChipTone.ok => (tk.ok.withValues(alpha: 0.13), tk.ok),
      ChipTone.warn => (tk.warn.withValues(alpha: 0.13), tk.warn),
      ChipTone.accent => (tk.accentSoft, tk.accent),
      ChipTone.violet => (tk.violet.withValues(alpha: 0.14), tk.violet),
      ChipTone.danger => (const Color(0xFFFF4D5E), Colors.white),
      ChipTone.plain => (tk.surface2, tk.muted),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6)],
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis,
            textDirection: ltr ? TextDirection.ltr : null, style: TextStyle(fontSize: 12, color: fg))),
      ]),
    );
    return onTap == null ? chip : GestureDetector(onTap: onTap, child: chip);
  }
}

enum BtnKind { plain, primary, danger, dashed }

/// .btn: 48 px high, 16 px corners; primary filled with the accent, danger in the warn colour.
class WebButton extends StatelessWidget {
  const WebButton(this.text, {super.key, this.onTap, this.kind = BtnKind.plain, this.icon, this.block = false,
      this.small = false});

  final String text;
  final VoidCallback? onTap;
  final BtnKind kind;
  final IconData? icon;
  final bool block;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final primary = kind == BtnKind.primary;
    final fg = primary ? tk.accentInk : kind == BtnKind.danger ? tk.warn : kind == BtnKind.dashed ? tk.muted : tk.text;
    final child = Row(mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 13 : 15,
          fontWeight: primary ? FontWeight.w700 : FontWeight.w500, color: fg))),
    ]);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: primary ? tk.accent : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: primary ? BorderSide.none
              : BorderSide(color: kind == BtnKind.danger ? tk.warn.withValues(alpha: 0.35) : tk.line2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: small ? 40 : 48),
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 18),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// .reading: a 16 px rounded row, the label at the start and the value at the end; .pick when
/// it can be touched (outlined with the accent while on).
class Reading extends StatelessWidget {
  const Reading({super.key, required this.start, this.end, this.onTap, this.on = false});

  final Widget start;
  final Widget? end;
  final VoidCallback? onTap;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? tk.accentLine : Colors.transparent),
      ),
      child: Row(children: [
        Expanded(flex: 2, child: start),
        if (end != null) ...[const SizedBox(width: 12), Flexible(flex: 3, child: end!)],
      ]),
    );
    if (onTap == null) return row;
    return Material(type: MaterialType.transparency,
        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: row));
  }
}

/// .card: the surface with a thin line and 24 px corners (tight: 18 px, less padding; warn: the
/// .warn-card colours).
class WebCard extends StatelessWidget {
  const WebCard({super.key, required this.child, this.tight = false, this.warn = false, this.onTap});

  final Widget child;
  final bool tight;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final radius = BorderRadius.circular(tight ? 18 : 24);
    final box = Container(
      width: double.infinity,
      padding: tight ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warn ? tk.warn.withValues(alpha: 0.13) : tk.surface,
        borderRadius: radius,
        border: Border.all(color: warn ? tk.warn.withValues(alpha: 0.35) : tk.line),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: box));
  }
}

/// .top-bar: the round back button, the title (and a line under it) in the middle, an optional
/// button at the end - the web app's page header instead of a Material app bar.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.sub, this.right, this.back = true});

  final String title;
  final String? sub;
  final Widget? right;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Row(children: [
      if (back && Navigator.of(context).canPop())
        CircleIconButton(icon: Icons.arrow_back_rounded, tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop())
      else
        const SizedBox(width: 44),
      Expanded(child: Column(children: [
        Text(title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tk.text)),
        if (sub != null && sub!.isNotEmpty)
          Text(sub!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: tk.muted)),
      ])),
      right ?? const SizedBox(width: 44),
    ]);
  }
}

/// .page: the web app's page - the glow behind, the parts 18 px apart, 20 px at the sides - with
/// its TopBar first.
class WebPage extends StatelessWidget {
  const WebPage({super.key, required this.title, required this.children, this.sub, this.right, this.bottom});

  final String title;
  final String? sub;
  final Widget? right;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: GlowPage(child: SafeArea(child: Column(children: [
          Expanded(child: Scrollbar(child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              TopBar(title: title, sub: sub, right: right),
              for (final c in children) Padding(padding: const EdgeInsets.only(top: 18), child: c),
            ],
          ))),
          if (bottom != null) bottom!,
        ]))),
      );
}

/// .label: the small muted caption above a field.
class Label extends StatelessWidget {
  const Label(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12, color: Tk.of(context).muted));
}

/// .perm-chip: a 30 px square with the permission's icon, lit when the level has it.
class PermChip extends StatelessWidget {
  const PermChip({super.key, required this.icon, required this.on, this.tooltip});

  final IconData icon;
  final bool on;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final box = Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        color: on ? tk.accentSoft : tk.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? tk.accentLine : tk.line),
      ),
      child: Icon(icon, size: 15, color: on ? tk.accent : tk.faint),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

/// .card.empty: the centred icon and line of an empty list (34 px above and below); dashed as
/// .custom-empty when it is a button that adds the first item.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.text, this.onTap, this.dashed = false});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 34),
      child: Column(children: [
        Icon(icon, size: 28, color: dashed ? tk.accent : tk.faint),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.7, color: tk.muted)),
      ]),
    );
    final radius = BorderRadius.circular(24);
    return CustomPaint(
      painter: _CardLine(color: tk.line2, dashed: dashed),
      child: Material(
        color: tk.surface,
        shape: RoundedRectangleBorder(borderRadius: radius,
            side: dashed ? BorderSide.none : BorderSide(color: tk.line)),
        child: InkWell(borderRadius: radius, onTap: onTap, child: SizedBox(width: double.infinity, child: body)),
      ),
    );
  }
}

class _CardLine extends CustomPainter {
  _CardLine({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    if (!dashed) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CardLine old) => old.color != color || old.dashed != dashed;
}

/// .tab: a 44 px pill for one choice of several; filled with the text colour while chosen.
class WebTab extends StatelessWidget {
  const WebTab(this.text, {super.key, required this.on, this.onTap, this.icon});

  final String text;
  final bool on;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    final fg = on ? tk.bg : tk.muted;
    return Semantics(
      button: true,
      selected: on,
      child: Opacity(
        opacity: onTap == null && !on ? 0.5 : 1,
        child: Material(
          color: on ? tk.text : Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: on ? tk.text : tk.line2)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                Text(text, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// .field: the label above its input (the web app's forms), not floating inside the border.
class WebField extends StatelessWidget {
  const WebField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
      children: [Label(label), const SizedBox(height: 6), child]);
}
