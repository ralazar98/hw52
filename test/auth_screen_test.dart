import 'dart:convert';

// Сохраняем совместимость с Material API исходного Flutter-проекта.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_chat_flutter/models/auth_data.dart';
import 'package:ai_chat_flutter/screens/auth_gate.dart';
import 'package:ai_chat_flutter/screens/auth_screen.dart';
import 'package:ai_chat_flutter/services/auth_service.dart';
import 'package:ai_chat_flutter/services/balance_service.dart';

import 'support/memory_auth_store.dart';

void main() {
  testWidgets(
    'key registration shows PIN before chat; restart requires PIN; reset switches provider',
    (tester) async {
      final store = MemoryAuthStore();
      final keys = <String>[];
      final auth = AuthService(
        store: store,
        balanceService: BalanceService(
          client: MockClient((request) async {
            keys.add(request.headers['Authorization']!);
            return http.Response(
              jsonEncode({
                'data': request.url.path.endsWith('/balance')
                    ? {'credits': 5}
                    : {'total_credits': 10, 'total_usage': 2},
              }),
              200,
            );
          }),
        ),
      );
      AuthData? session;
      Widget app() => MaterialApp(
            home: AuthGate(
              auth: auth,
              chatBuilder: (value, lock) {
                session = value;
                return Scaffold(
                  body: TextButton(
                      onPressed: lock, child: const Text('TEST CHAT')),
                );
              },
            ),
          );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('apiKey')),
        'sk-or-vis-test',
      );
      await tester.tap(find.text('Проверить ключ и баланс'));
      await tester.pumpAndSettle();
      expect(session, isNull);
      expect(find.text('TEST CHAT'), findsNothing);
      final pinFinder = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^[1-9]\d{3}$').hasMatch(w.data ?? ''),
      );
      final pin = tester.widget<Text>(pinFinder).data!;
      await tester.tap(find.text('Я запомнил PIN — открыть чат'));
      await tester.pumpAndSettle();
      expect(session!.apiKey, 'sk-or-vis-test');
      expect(find.text('TEST CHAT'), findsOneWidget);
      // Уничтожаем дерево: имитация следующего запуска, хранилище остаётся.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin')), findsOneWidget);
      expect(find.text('TEST CHAT'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('pin')), '0000');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(find.text('Неверный PIN. Попробуйте ещё раз.'), findsOneWidget);
      expect(find.text('TEST CHAT'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('pin')), pin);
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(find.text('TEST CHAT'), findsOneWidget);
      expect(keys.length, 1); // Вход по PIN не обращался к API.
      await tester.tap(find.text('TEST CHAT')); // Lock
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить ключ'));
      await tester.pumpAndSettle();
      expect(store.value, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('apiKey')),
        'sk-or-v1-new',
      );
      await tester.tap(find.text('Проверить ключ и баланс'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Я запомнил PIN — открыть чат'));
      await tester.pumpAndSettle();
      expect(session!.provider, 'openrouter');
      expect(session!.apiKey, 'sk-or-v1-new');
      expect(keys, ['Bearer sk-or-vis-test', 'Bearer sk-or-v1-new']);
    },
  );

  testWidgets('storage errors block entry and allow retry', (tester) async {
    final store = MemoryAuthStore()..failRead = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          auth: AuthService(store: store),
          onAuthenticated: (_) => fail('Must stay locked'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.byKey(const ValueKey('apiKey')), findsNothing);
    store.failRead = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('apiKey')), findsOneWidget);
  });

  testWidgets('small phone displays balance error without layout exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryAuthStore();
    final auth = AuthService(
      store: store,
      balanceService: BalanceService(
        client: MockClient(
          (_) async => http.Response('{"data":{"credits":0}}', 200),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          auth: auth,
          onAuthenticated: (_) => fail('Must not open chat'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('apiKey')),
      'sk-or-vv-test',
    );
    await tester.tap(find.text('Проверить ключ и баланс'));
    await tester.pumpAndSettle();
    expect(
      find.text('Баланс должен быть больше нуля. Пополните счёт.'),
      findsOneWidget,
    );
    expect(store.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reset preserves saved credentials and PIN screen', (
    tester,
  ) async {
    final store = MemoryAuthStore()
      ..value = savedAuth()
      ..failReset = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          auth: AuthService(store: store),
          onAuthenticated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить ключ'));
    await tester.pumpAndSettle();
    expect(store.value, isNotNull);
    expect(find.byKey(const ValueKey('pin')), findsOneWidget);
    expect(
      find.text('Не удалось сбросить ключ. Повторите попытку.'),
      findsOneWidget,
    );
  });
}
