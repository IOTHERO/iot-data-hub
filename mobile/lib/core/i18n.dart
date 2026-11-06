// Translations: the web app's own files (app/i18n/fa.json, en.json), so both apps say the same.
// t("device.on_count", {"n": 2, "total": 9}) -> "۲ از ۹ روشن"; Persian digits in Persian.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class I18n {
  I18n._(this.lang, this._words);

  final String lang;
  final Map<String, dynamic> _words;

  static Future<I18n> load(String lang) async {
    final text = await rootBundle.loadString('assets/i18n/$lang.json');
    return I18n._(lang, json.decode(text) as Map<String, dynamic>);
  }

  bool get rtl => lang == 'fa';

  String t(String key, [Map<String, Object?> params = const {}]) {
    Object? node = _words;
    for (final part in key.split('.')) {
      if (node is Map<String, dynamic> && node.containsKey(part)) {
        node = node[part];
      } else {
        return key;
      }
    }
    var text = node is String ? node : key;
    params.forEach((k, v) => text = text.replaceAll('{$k}', num(v)));
    return text;
  }

  bool has(String key) => t(key) != key;

  /// Numbers in the reader's digits (Persian digits in Persian).
  String num(Object? value) {
    final s = value is double ? _trim(value) : '${value ?? ''}';
    if (!rtl) return s;
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => fa[int.parse(m[0]!)]).replaceAll('.', '٫');
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// A date for the reader: Jalali (1405/08/14) in Persian, ISO (2026-11-05) in English.
  String date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (!rtl) return '${d.year}-${two(d.month)}-${two(d.day)}';
    final j = jalali(d.year, d.month, d.day);
    return num('${j[0]}/${two(j[1])}/${two(j[2])}');
  }

  /// How long ago, as the web app's when(): "now", "5 min ago", "3 h ago", else the date and time.
  String when(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return '';
    final secs = DateTime.now().toUtc().difference(d.toUtc()).inSeconds;
    if (secs < 60) return t('time.now');
    if (secs < 3600) return t('time.minutes', {'n': (secs / 60).round()});
    if (secs < 86400) return t('time.hours', {'n': (secs / 3600).round()});
    final local = d.toUtc().add(const Duration(hours: 3, minutes: 30));        // Tehran
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date(local)} ${num('${two(local.hour)}:${two(local.minute)}')}';
  }

  /// Gregorian -> Jalali [year, month, day] (the arithmetic of hub/jalali.py).
  static List<int> jalali(int gy, int gm, int gd) {
    const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    final gy2 = gm > 2 ? gy + 1 : gy;
    var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + gdm[gm - 1];
    var jy = -1595 + 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
    final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
    return [jy, jm, jd];
  }

  /// A {"fa": ..., "en": ...} name from the server in the reader's language.
  String name(Object? names) {
    if (names is Map) return '${names[lang] ?? names['en'] ?? names['fa'] ?? names.values.first}';
    return '${names ?? ''}';
  }
}
