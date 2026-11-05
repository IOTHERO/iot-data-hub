// The TiTiSwitch logo, drawn from the same geometry as the web app (app/js/logo.js), with the
// start-up animation of app/css/app.css: the line traces the "T", the switches pop in and
// flip, the signals ripple, the name rises. progress 0..1 over the splash; 1 = the still logo.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.progress = 1, this.wordmark = true, this.size = 120});

  final double progress;
  final bool wordmark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size * (wordmark ? 1560 / 1150 : 1120 / 1100),
      child: CustomPaint(painter: _LogoPainter(progress, wordmark, ink)),
    );
  }
}

double _phase(double t, double start, double length) => ((t - start) / length).clamp(0.0, 1.0);

double _spring(double x) =>                   // overshoot like cubic-bezier(.34,1.56,.64,1)
    x >= 1 ? 1 : 1 - math.pow(1 - x, 3) * math.cos(x * math.pi * 1.2);

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t, this.wordmark, this.ink);

  final double t;
  final bool wordmark;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final viewW = wordmark ? 1150.0 : 1100.0;
    final scale = size.width / viewW;
    canvas.scale(scale);
    canvas.translate(-400, -150);

    // 1. the line traces the T
    final line = Path()..moveTo(1199, 327.5);
    for (final p in const [
      [499.5, 327.5], [499.5, 554.5], [726.5, 554.5], [726.5, 1006], [953.5, 1006], [953.5, 554.5],
      [1180.5, 554.5], [1180.5, 1006], [1444.5, 1006], [1444.5, 1233], [702.0, 1233]
    ]) {
      line.lineTo(p[0].toDouble(), p[1].toDouble());
    }
    final drawn = Curves.easeInOutCubic.transform(_phase(t, 0.05, 0.47));
    final metric = line.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * drawn),
        Paint()
          ..color = const Color(0xFF00B4CD)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 37
          ..strokeJoin = StrokeJoin.miter);

    // 2. the switches pop in and their knobs flip
    _switch(canvas, 783, 529, 600, 170, _phase(t, 0.25, 0.25), _phase(t, 0.36, 0.19));
    _switch(canvas, 1011, 739, 946, -170, _phase(t, 0.31, 0.25), _phase(t, 0.43, 0.19));

    // 3. the signals ripple out
    _signal(canvas, 1264, 320, 33, 20, const [[88, 216, 293, 0], [143, 214, 295, 1], [86, 38, 113, 0], [142, 34, 116, 1]]);
    _signal(canvas, 647, 1233, 32, 32, const [[80, 135, 225, 0], [137, 135, 225, 1], [195, 135, 225, 2]]);

    // 4. the name rises
    if (wordmark) {
      final rise = Curves.easeOut.transform(_phase(t, 0.56, 0.3));
      _text(canvas, 'تی‌تی‌سویچ', 1500 + 60 * (1 - rise), 250, FontWeight.w900, ink.withValues(alpha: 0.78 * rise),
          TextDirection.rtl, 0);
      final track = _phase(t, 0.65, 0.35);
      _text(canvas, 'TiTiSwitch', 1680, 150, FontWeight.w600, ink.withValues(alpha: 0.6 * track), TextDirection.ltr,
          22 + 62 * (1 - Curves.easeOut.transform(track)));
    }
  }

  void _switch(Canvas canvas, double x, double y, double knobY, double from, double pop, double flip) {
    if (pop <= 0) return;
    final s = _spring(pop);
    canvas.save();
    canvas.translate(x + 56, y + 139.5);
    canvas.scale(s);
    canvas.rotate((1 - pop) * -0.14);
    canvas.translate(-(x + 56), -(y + 139.5));
    final o = (255 * pop).round();
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 112, 279), const Radius.circular(56)),
        Paint()..color = Brand.orange.withAlpha(o));
    canvas.drawCircle(Offset(x + 56, knobY + from * (1 - _spring(flip))), 28, Paint()..color = Colors.white.withAlpha(o));
    canvas.restore();
  }

  void _signal(Canvas canvas, double cx, double cy, double dot, double width, List<List<num>> arcs) {
    final d = _phase(t, 0.47, 0.22);
    if (d > 0) {
      canvas.drawCircle(Offset(cx, cy), dot * _spring(d), Paint()..color = const Color(0xFF00B4CD));
    }
    for (final a in arcs) {
      final w = _phase(t, 0.52 + 0.06 * a[3], 0.45);
      if (w <= 0) continue;
      final opacity = w < 0.35 ? w / 0.35 : (w < 0.65 ? 1 - (w - 0.35) / 0.3 * 0.55 : 0.45 + (w - 0.65) / 0.35 * 0.55);
      final r = a[0].toDouble();
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), a[1] * math.pi / 180,
          (a[2] - a[1]) * math.pi / 180, false,
          Paint()
            ..color = const Color(0xFF00B4CD).withValues(alpha: opacity.clamp(0.0, 1.0))
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round);
    }
  }

  void _text(Canvas canvas, String text, double baseline, double size, FontWeight weight, Color color,
      TextDirection dir, double spacing) {
    final p = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing)),
      textDirection: dir,
    )..layout();
    p.paint(canvas, Offset(990 - p.width / 2, baseline - p.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t || old.ink != ink;
}

/// Two seconds of the logo drawing itself, then [next].
class Splash extends StatefulWidget {
  const Splash({super.key, required this.next});

  final VoidCallback next;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
        ..forward().whenComplete(widget.next);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.next,                               // a tap skips it
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Stack(alignment: Alignment.center, children: [
              Opacity(
                opacity: (_c.value * 1.6).clamp(0.0, 0.75),
                child: Container(
                  width: 420,
                  height: 420,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Color(0x3800B4CD), Color(0x14F58634), Color(0x00000000)],
                        stops: [0, 0.45, 0.7]),
                  ),
                ),
              ),
              LogoMark(progress: _c.value, size: 240),
            ]),
          ),
        ),
      );
}
