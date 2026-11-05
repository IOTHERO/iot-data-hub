// TiTiSwitch customer app (Flutter, Android and iOS). Start: the logo splash, then the hub
// address (first start only), sign-in, and the app: home, scenes, me (screens/).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'screens/login.dart';
import 'screens/server.dart';
import 'screens/shell.dart';
import 'ui/logo.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.open();
  runApp(TiTiSwitchApp(state: state));
}

class TiTiSwitchApp extends StatelessWidget {
  const TiTiSwitchApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'TiTiSwitch',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          locale: Locale(state.i18n.lang),
          supportedLocales: const [Locale('fa'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Start(state: state),
        ),
      );
}

/// Splash -> (server address) -> sign-in or the app.
class Start extends StatefulWidget {
  const Start({super.key, required this.state});

  final AppState state;

  @override
  State<Start> createState() => _StartState();
}

enum _Stage { splash, server, login, app }

class _StartState extends State<Start> {
  _Stage stage = _Stage.splash;

  Future<void> _afterSplash() async {
    final s = widget.state;
    if (s.api.server.isEmpty) return setState(() => stage = _Stage.server);
    final ok = await s.api.signedIn && await s.load();
    if (mounted) setState(() => stage = ok ? _Stage.app : _Stage.login);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    switch (stage) {
      case _Stage.splash:
        return Splash(next: () { if (stage == _Stage.splash) _afterSplash(); });
      case _Stage.server:
        return ServerScreen(state: s, done: () => setState(() => stage = _Stage.login));
      case _Stage.login:
        return LoginScreen(
          state: s,
          done: () => setState(() => stage = _Stage.app),
          changeServer: () => setState(() => stage = _Stage.server),
        );
      case _Stage.app:
        return Shell(state: s, signedOut: () => setState(() => stage = _Stage.login));
    }
  }
}
