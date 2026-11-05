// The app's shared state: API, language, the signed-in user and the chosen home.

import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';
import 'store.dart';

class AppState extends ChangeNotifier {
  AppState._(this.store, this.api, this.i18n);

  static Future<AppState> open() async {
    final store = await Store.open();
    final i18n = await I18n.load(store.get('lang') ?? 'fa');
    return AppState._(store, Api(store), i18n);
  }

  final Store store;
  final Api api;
  I18n i18n;
  Map<String, dynamic>? me;
  List<Map<String, dynamic>> homes = [];

  String t(String key, [Map<String, Object?> params = const {}]) => i18n.t(key, params);

  ThemeMode get themeMode => store.get('theme') == 'light' ? ThemeMode.light : ThemeMode.dark;

  Future<void> toggleTheme() async {
    await store.set('theme', themeMode == ThemeMode.light ? 'dark' : 'light');
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
    notifyListeners();
  }

  String query([String prefix = '?']) => home == null ? '' : '${prefix}org=${Uri.encodeQueryComponent(home!)}';

  /// After sign-in or at start: who is signed in, his homes, and the local keys.
  Future<bool> load() async {
    try {
      me = await api.call('GET', '/api/auth/me') as Map<String, dynamic>;
      final rows = (await api.call('GET', '/api/account/organizations') as List).cast<Map<String, dynamic>>();
      homes = rows.where((m) => m['kind'] != 'manufacturer').toList();
      api.refreshLocalKeys();
      notifyListeners();
      return true;
    } on ApiError catch (e) {
      if (e.status == 401) me = null;
      return me != null;
    }
  }

  Future<void> logout() async {
    await api.logout();
    me = null;
    homes = [];
    notifyListeners();
  }
}
