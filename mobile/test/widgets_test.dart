// Widget tests: the accent colour reaches the tokens, the switch, arrive / leave, account links,
// and the sign-in page opens the account pages. No server is needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titiswitch/core/app_state.dart';
import 'package:titiswitch/core/presence.dart';
import 'package:titiswitch/screens/account.dart';
import 'package:titiswitch/screens/login.dart';
import 'package:titiswitch/ui/kit.dart';
import 'package:titiswitch/ui/theme.dart';

void main() {
  testWidgets('the chosen accent colour is the tokens\' accent', (tester) async {
    late Tk tk;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, 'violet'),
      home: Builder(builder: (context) {
        tk = Tk.of(context);
        return const SizedBox();
      }),
    ));
    expect(tk.accent, const Color(0xFFA99BFF));
    expect(buildTheme(Brightness.dark).colorScheme.primary, Brand.cyan);
    expect(buildTheme(Brightness.light, 'nonsense').colorScheme.primary, Brand.cyanLight);
  });

  testWidgets('the switch reports the new value; without a handler it is read-only', (tester) async {
    bool? got;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: Column(children: [
      TiSwitch(key: const Key('a'), value: false, onChanged: (v) => got = v),
      const TiSwitch(key: Key('b'), value: true),
    ])))));
    await tester.tap(find.byKey(const Key('a')));
    expect(got, isTrue);
    await tester.tap(find.byKey(const Key('b')));                 // nothing happens, no error
  });

  test('arrive / leave: inside the home\'s circle', () {
    final home = {'latitude': 35.7000, 'longitude': 51.4000, 'radius_m': 150};
    expect(insideHome(home, 35.7005, 51.4005), isTrue);             // about 70 m
    expect(insideHome(home, 35.7100, 51.4000), isFalse);            // about 1.1 km
    expect(insideHome({'latitude': null, 'longitude': null}, 35.7, 51.4), isNull);
  });

  test('account links from the e-mails', () {
    final token = 'a' * 32;
    expect(parseAccountLink('https://hub.example/app/#/account/reset/$token'), ('reset', token));
    expect(parseAccountLink('#/account/invitation/$token'), ('invitation', token));
    expect(parseAccountLink('https://hub.example/app/#/home'), isNull);
    expect(parseAccountLink('#/account/reset/short'), isNull);
  });

  testWidgets('sign-in opens the sign-up and forgotten-password pages', (tester) async {
    SharedPreferences.setMockInitialValues({'lang': 'en'});
    final state = await tester.runAsync(AppState.open);
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: LoginScreen(state: state!, done: () {}, changeServer: () {}),
    ));
    expect(find.text(state.t('auth.sign_in')), findsOneWidget);
    await tester.tap(find.text(state.t('auth.create')));
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(state.t('auth.forgot')));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotScreen), findsOneWidget);
  });
}
