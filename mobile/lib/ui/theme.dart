// The web app's theme (app/css/app.css) for Material widgets: midnight background, TiTiSwitch
// cyan, the same text, field, button and card styles. The tokens themselves live in kit.dart.

import 'package:flutter/material.dart';

class Brand {
  static const cyan = Color(0xFF19B8D0);
  static const cyanLight = Color(0xFF0089A0);
  static const orange = Color(0xFFF58634);
  static const ok = Color(0xFF7FD1C7);
  static const warn = Color(0xFFFF9F7A);
  static const bg = Color(0xFF0B0D12);
  static const bg2 = Color(0xFF0E1117);
}

/// The accent colours of Me (views.js ACCENTS, app.css [data-accent]); '' = TiTiSwitch cyan.
const accents = {'': Brand.cyan, 'gold': Color(0xFFE8B86A), 'teal': Color(0xFF7FD1C7),
    'violet': Color(0xFFA99BFF), 'coral': Color(0xFFFF9F7A)};

/// The accent nearest to a maker's colour ("#RRGGBB"): the app keeps to its own five.
String nearestAccent(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return '';
  final v = int.parse(hex.substring(1), radix: 16);
  final rgb = [(v >> 16) & 255, (v >> 8) & 255, v & 255];
  int distance(Color c) {
    final o = [(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()];
    return [for (var i = 0; i < 3; i++) (o[i] - rgb[i]) * (o[i] - rgb[i])].reduce((a, b) => a + b);
  }
  return (accents.entries.toList()..sort((a, b) => distance(a.value).compareTo(distance(b.value)))).first.key;
}

ThemeData buildTheme(Brightness brightness, [String accentKey = '']) {
  final dark = brightness == Brightness.dark;
  final text = dark ? const Color(0xFFF2F2F4) : const Color(0xFF15171C);
  final muted = dark ? const Color(0xFFA3A8B5) : const Color(0xFF5B606C);
  final accent = accentKey.isEmpty || !accents.containsKey(accentKey)
      ? (dark ? Brand.cyan : Brand.cyanLight) : accents[accentKey]!;
  final surface = dark ? const Color(0x0DFFFFFF) : const Color(0x0A14161B);
  final line = dark ? const Color(0x14FFFFFF) : const Color(0x1414161B);
  final line2 = dark ? const Color(0x24FFFFFF) : const Color(0x2914161B);
  final scheme = ColorScheme.fromSeed(seedColor: Brand.cyan, brightness: brightness).copyWith(
    primary: accent,
    onPrimary: dark ? Brand.bg : Colors.white,
    secondary: Brand.orange,
    surface: dark ? Brand.bg2 : Colors.white,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: line2,
    outlineVariant: line,
  );
  final radius16 = BorderRadius.circular(16);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Brand.bg : const Color(0xFFF6F4EF),
    canvasColor: dark ? Brand.bg2 : Colors.white,
    hintColor: muted,
    // scroll bars: thin and calm, the accent while dragged (as the web app's)
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(4),
      radius: const Radius.circular(4),
      crossAxisMargin: 2,
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.dragged) ? accent : line2),
    ),
    dividerColor: line,
    fontFamily: 'Vazirmatn',
    fontFamilyFallback: const ['Tahoma', 'Roboto'],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'Vazirmatn', fontSize: 18, fontWeight: FontWeight.w800, color: text),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: line)),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(iconColor: muted, textColor: text),
    inputDecorationTheme: InputDecorationTheme(           // .input: 48 px, radius 16, hairline
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted),
      border: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: line2)),
      enabledBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: line2)),
      focusedBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: accent, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(                // .btn.primary
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: accent,
        foregroundColor: dark ? Brand.bg : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius16),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(            // .btn
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: text,
        side: BorderSide(color: line2),
        shape: RoundedRectangleBorder(borderRadius: radius16),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      side: BorderSide(color: line2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      selectedColor: accent.withValues(alpha: 0.18),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Brand.bg2 : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF1A1E26) : const Color(0xFF15171C),
      contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', color: Color(0xFFF2F2F4)),
      shape: RoundedRectangleBorder(borderRadius: radius16),
    ),
  );
}
