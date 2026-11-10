// The app's shared state: API, language, the signed-in user and the chosen home.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';

import 'alerts.dart';
import 'api.dart';
import 'i18n.dart';
import 'live.dart';
import 'notify.dart';
import 'presence.dart';
import 'store.dart';
import 'tls.dart';

class AppState extends ChangeNotifier {
  AppState._(this.store, this.api, this.i18n) : live = Live(api), alerts = Alerts(api) {
    live.events.listen((e) {
      if (e.type == 'alert') alerts.event(e.data);
    });
  }

  static Future<AppState> open() async {
    final store = await Store.open();
    final i18n = await I18n.load(store.get('lang') ?? 'fa');
    return AppState._(store, Api(store), i18n);
  }

  final Store store;
  /// Server certificates the user approved (a hub with its own CA; core/tls.dart).
  late final TrustedCerts trusted = TrustedCerts(store);
  final Api api;
  final Live live;                   // server-sent updates while signed in
  final Alerts alerts;               // open security alerts (PIR, magnet, smoke)
  I18n i18n;
  Map<String, dynamic>? me;
  List<Map<String, dynamic>> homes = [];

  String t(String key, [Map<String, Object?> params = const {}]) => i18n.t(key, params);

  ThemeMode get themeMode => store.get('theme') == 'light' ? ThemeMode.light : ThemeMode.dark;

  Future<void> toggleTheme() async {
    await store.set('theme', themeMode == ThemeMode.light ? 'dark' : 'light');
    notifyListeners();
  }

  /// The chosen accent colour (theme.dart accents; '' = TiTiSwitch cyan).
  String get accent => store.get('accent') ?? '';

  /// What the theme shows: the chosen accent, else the maker's nearest one (?brand=).
  String get themeAccent => accent.isNotEmpty ? accent : nearestAccent(brand?['accent'] as String?);

  /// The maker of a ?brand= link: name, colour, support contact and logo, for the start page.
  Map<String, dynamic>? brand;
  Uint8List? brandLogo;

  Future<void> loadBrand() async {
    final id = store.get('brand');
    if (id == null || api.server.isEmpty) return;
    try {
      brand = await api.public('GET', '/api/public/brand/${Uri.encodeComponent(id)}', null) as Map<String, dynamic>;
      brandLogo = brand!['has_logo'] == true
          ? await api.bytes('/api/public/brand/${Uri.encodeComponent(id)}/logo', auth: false) : null;
      notifyListeners();
    } on ApiError catch (e) {
      if (e.status == 404) await store.set('brand', null);       // no such maker any more
    }
  }

  Future<void> setAccent(String key) async {
    await store.set('accent', key.isEmpty ? null : key);
    notifyListeners();
  }

  /// Arrive / leave detection while the app is open (on unless turned off, as the web app).
  bool get presence => store.get('presence') != 'off';

  Future<void> setPresence(bool on) async {
    await store.set('presence', on ? null : 'off');
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    i18n = await I18n.load(lang);
    await store.set('lang', lang);
    notifyListeners();
  }

  /// The home the screens show (null = every home of the user).
  String? get home => store.get('home');

  Future<void> setHome(String? orgId) async {
    await store.set('home', orgId);
    alerts.query = query();
    alerts.load();
    notifyListeners();
  }

  /// The home screen's sections in the person's order, each on or off (Me > home layout).
  static const homeSections = ['today', 'custom', 'quick', 'groups', 'devices'];

  List<(String, bool)> get homeLayout {
    final out = <(String, bool)>[];
    for (final part in (store.get('layout') ?? '').split(',')) {
      final key = part.replaceFirst('-', '');
      if (homeSections.contains(key) && !out.any((x) => x.$1 == key)) out.add((key, !part.startsWith('-')));
    }
    for (final key in homeSections) {
      if (!out.any((x) => x.$1 == key)) out.add((key, true));
    }
    return out;
  }

  Future<void> setHomeLayout(List<(String, bool)>? rows) async {
    await store.set('layout', rows?.map((r) => r.$2 ? r.$1 : '-${r.$1}').join(','));
    notifyListeners();
  }

  /// The person's own home section (Me > home layout > my own section): its name and the
  /// outputs, sensors and scenes in their order (the web app's custom.js; kept on this phone).
  /// Items: {"type": "out" | "sensor", "device_id", "key"} or {"type": "scene", "scene_id"}.
  String get customTitle => (_custom()['title'] as String?) ?? '';

  List<Map<String, dynamic>> get customItems =>
      ((_custom()['items'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Map<String, dynamic> _custom() {
    try {
      final v = json.decode(store.get('custom') ?? '{}');
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> setCustom(String title, List<Map<String, dynamic>> items) async {
    await store.set('custom', json.encode({'title': title, 'items': items}));
    notifyListeners();
  }

  /// Remember me: the e-mail of the last sign-in (never the password).
  String? get rememberedUser => store.get('remember');

  Future<void> remember(String? user) => store.set('remember', user);

  String query([String prefix = '?']) => home == null ? '' : '${prefix}org=${Uri.encodeQueryComponent(home!)}';

  /// After sign-in or at start: who is signed in, his homes, and the local keys.
  Future<bool> load() async {
    try {
      me = await api.call('GET', '/api/auth/me') as Map<String, dynamic>;
      final rows = (await api.call('GET', '/api/account/organizations') as List).cast<Map<String, dynamic>>();
      homes = rows.where((m) => m['kind'] != 'manufacturer').toList();
      api.refreshLocalKeys();
      live.start();
      alerts.query = query();
      alerts.load();
      checkHome();
      if (store.get('notify_asked') == null) {          // once: may alarms show as notifications?
        store.set('notify_asked', '1');
        Notify.ask();
      }
      _resumed ??= AppLifecycleListener(onResume: checkHome);
      notifyListeners();
      return true;
    } on ApiError catch (e) {
      if (e.status == 401) me = null;
      return me != null;
    }
  }

  AppLifecycleListener? _resumed;

  /// The chosen home, else the first one (the web app's homeOrg).
  String? get homeOrg => home ?? (homes.isEmpty ? null : homes.first['org_id'] as String?);

  /// Arrive / leave for that home (presence.dart).
  void checkHome() {
    if (me == null) return;
    checkPresence(api, store, homeOrg);
  }

  Future<void> logout() async {
    live.stop();
    await api.logout();
    me = null;
    homes = [];
    alerts.reset();
    notifyListeners();
  }
}
