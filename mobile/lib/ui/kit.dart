// The web app's look (app/css/app.css) as Flutter widgets: its colour tokens, the glow behind
// the page, cards, the round icon buttons and avatar, the switch, and the tiles of the home and
// device pages. One place, so both apps stay alike.

import 'dart:ui';

import 'package:flutter/material.dart';

/// The CSS variables of app.css (:root and the light theme).
class Tk {
  Tk._(this.dark);

  factory Tk.of(BuildContext context) => Tk._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get bg => dark ? const Color(0xFF0B0D12) : const Color(0xFFF6F4EF);
  Color get bg2 => dark ? const Color(0xFF0E1117) : Colors.white;
  Color get surface => dark ? const Color(0x0DFFFFFF) : const Color(0x0A14161B);     // 5 % / 4 %
  Color get surface2 => dark ? const Color(0x14FFFFFF) : const Color(0x1214161B);    // 8 % / 7 %
  Color get line => dark ? const Color(0x14FFFFFF) : const Color(0x1414161B);        // 8 %
  Color get line2 => dark ? const Color(0x24FFFFFF) : const Color(0x2914161B);       // 14 % / 16 %
  Color get text => dark ? const Color(0xFFF2F2F4) : const Color(0xFF15171C);
  Color get muted => dark ? const Color(0xFFA3A8B5) : const Color(0xFF5B606C);
  Color get faint => dark ? const Color(0xFF7D8290) : const Color(0xFF7A7F8A);
  Color get accent => dark ? const Color(0xFF19B8D0) : const Color(0xFF0089A0);
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
  const StatTile({super.key, required this.label, required this.value, this.unit, this.warn = false});

  final String label;
  final String value;
  final String? unit;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final tk = Tk.of(context);
    return Expanded(
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
