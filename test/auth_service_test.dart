import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_chat_flutter/models/auth_data.dart';
import 'package:ai_chat_flutter/services/auth_service.dart';
import 'package:ai_chat_flutter/services/balance_service.dart';

import 'support/memory_auth_store.dart';

void main() {
  for (final key in ['sk-or-vv-test', 'sk-or-vis-test', 'sk-or-v1-test']) {
    final provider = key.startsWith('sk-or-v1-')
        ? AuthProvider.openrouter
        : AuthProvider.vsegpt;
    test('$key: validates endpoint, saves a salted PIN hash, unlocks offline',
        () async {
      final store = MemoryAuthStore();
      var calls = 0;
      final auth = AuthService(
        store: store,
        balanceService: BalanceService(
          client: MockClient((request) async {
            calls++;
            expect(request.method, 'GET');
            expect(
              request.url.toString(),
              '${AuthUtils.baseUrlForProvider(provider)}/${provider == AuthProvider.vsegpt ? 'balance' : 'credits'}',
            );
            expect(request.headers['Authorization'], 'Bearer $key');
            return http.Response(
              jsonEncode({
                'data': provider == AuthProvider.vsegpt
                    ? {'credits': '12.50'}
                    : {'total_credits': 20, 'total_usage': 7.5},
              }),
              200,
            );
          }),
        ),
      );
      expect(await auth.hasAuth(), isFalse);
      final result = await auth.register('  $key  ');
      expect(result.balance, 12.5);
      expect(result.pin, matches(RegExp(r'^[1-9]\d{3}$')));
      expect(result.auth.provider, provider.name);
      expect(store.value!.pinHash, isNot(result.pin));
      expect(store.value!.salt, isNotEmpty);
      expect(
        AuthUtils.verifyPin(
          result.pin,
          store.value!.pinHash,
          salt: store.value!.salt,
        ),
        isTrue,
      );
      expect(await auth.hasAuth(), isTrue);
      final nextLaunch = AuthService(store: store);
      expect((await nextLaunch.unlock(result.pin)).apiKey, key);
      expect(calls, 1);
      for (final wrongPin in ['0000', '', '123', '12345', 'abcd']) {
        await expectLater(
          nextLaunch.unlock(wrongPin),
          throwsA(isA<AuthException>()),
        );
      }
      await nextLaunch.reset();
      expect(await auth.hasAuth(), isFalse);
      await expectLater(
        nextLaunch.unlock(result.pin),
        throwsA(isA<AuthException>()),
      );
    });

    for (final balance in [0, -1]) {
      test('$key: rejects balance $balance without saving', () async {
        final store = MemoryAuthStore();
        final auth = AuthService(
          store: store,
          balanceService: BalanceService(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'data': provider == AuthProvider.vsegpt
                      ? {'credits': balance}
                      : {'total_credits': 5, 'total_usage': 5 - balance},
                }),
                200,
              ),
            ),
          ),
        );
        await expectLater(auth.register(key), throwsA(isA<AuthException>()));
        expect(store.saves, 0);
      });
    }
  }

  test('invalid prefixes do not make network calls', () async {
    var calls = 0;
    final store = MemoryAuthStore();
    final auth = AuthService(
      store: store,
      balanceService: BalanceService(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ),
    );
    for (final key in [
      '',
      'sk-test',
      'sk-or-v1-',
      'sk-or-vv-',
      'sk-or-vis-',
      'sk-or-v1-a b',
    ]) {
      await expectLater(auth.register(key), throwsA(isA<AuthException>()));
    }
    expect(calls, 0);
    expect(store.value, isNull);
  });

  for (final status in [401, 402, 403, 429, 500]) {
    test('HTTP $status never saves a key', () async {
      final store = MemoryAuthStore();
      final auth = AuthService(
        store: store,
        balanceService: BalanceService(
          client: MockClient((_) async => http.Response('{}', status)),
        ),
      );
      await expectLater(
        auth.register('sk-or-v1-test'),
        throwsA(isA<AuthException>()),
      );
      expect(store.value, isNull);
    });
  }

  for (final body in [
    'not json',
    '{}',
    '{"data":null}',
    '{"data":{"total_credits":5}}',
    '{"data":{"total_credits":"NaN","total_usage":0}}',
    '{"data":{"total_credits":"Infinity","total_usage":0}}',
    '{"error":{"message":"secret key"}}',
    '{"status":"error","reason":"invalid key","data":{"total_credits":20,"total_usage":0}}',
  ]) {
    test('malformed or error response is rejected: $body', () async {
      final store = MemoryAuthStore();
      final auth = AuthService(
        store: store,
        balanceService: BalanceService(
          client: MockClient((_) async => http.Response(body, 200)),
        ),
      );
      await expectLater(
        auth.register('sk-or-v1-test'),
        throwsA(isA<AuthException>()),
      );
      expect(store.value, isNull);
    });
  }

  test('disabled VSEGPT balance gives actionable settings message', () async {
    final store = MemoryAuthStore();
    final auth = AuthService(
      store: store,
      balanceService: BalanceService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'error',
              'reason':
                  'Balance call disable for this API key; enable it in settings on website.',
            }),
            200,
          ),
        ),
      ),
    );
    await expectLater(
      auth.register('sk-or-vis-test'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Разрешить запрашивать баланс'),
        ),
      ),
    );
    expect(store.saves, 0);
  });

  test('network failure does not leak key or save data', () async {
    final store = MemoryAuthStore();
    final auth = AuthService(
      store: store,
      balanceService: BalanceService(
        client: MockClient(
          (_) async => throw http.ClientException('sk-or-vv-secret'),
        ),
      ),
    );
    await expectLater(
      auth.register('sk-or-vv-test'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          isNot(contains('secret')),
        ),
      ),
    );
    expect(store.value, isNull);
  });

  test('timeout is handled and nothing is saved', () async {
    final store = MemoryAuthStore();
    final auth = AuthService(
      store: store,
      balanceService: BalanceService(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) => Completer<http.Response>().future),
      ),
    );
    await expectLater(
      auth.register('sk-or-vv-test'),
      throwsA(isA<AuthException>()),
    );
    expect(store.value, isNull);
  });

  test('storage failure does not return a successful registration', () async {
    final store = MemoryAuthStore()..failSave = true;
    final auth = AuthService(
      store: store,
      balanceService: BalanceService(
        client: MockClient(
          (_) async => http.Response('{"data":{"credits":10}}', 200),
        ),
      ),
    );
    await expectLater(auth.register('sk-or-vv-test'), throwsStateError);
    expect(store.value, isNull);
  });

  test(
    'reset and registration can switch provider without reusing old key',
    () async {
      final store = MemoryAuthStore()..value = savedAuth();
      final auth = AuthService(
        store: store,
        balanceService: BalanceService(
          client: MockClient(
            (_) async => http.Response('{"data":{"credits":10}}', 200),
          ),
        ),
      );
      await auth.reset();
      final result = await auth.register('sk-or-vis-new');
      expect((await auth.unlock(result.pin)).apiKey, 'sk-or-vis-new');
      expect(store.value!.provider, 'vsegpt');
    },
  );
}
