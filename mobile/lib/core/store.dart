// What the phone keeps: settings and the last answers of the server (shared preferences), and
// the secrets (refresh token, local keys) in the phone's keystore (Android Keystore, iOS Keychain).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Store {
  Store._(this._prefs);

  static Future<Store> open() async => Store._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  static const _secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));

  String? get(String key) => _prefs.getString(key);

  Future<void> set(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  Future<String?> secret(String key) => _secure.read(key: key);

  Future<void> setSecret(String key, String? value) =>
      value == null ? _secure.delete(key: key) : _secure.write(key: key, value: value);
}
