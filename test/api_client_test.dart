import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_chat_flutter/api/openrouter_client.dart';
import 'package:ai_chat_flutter/models/auth_data.dart';

void main() {
  for (final key in ['sk-or-vv-test', 'sk-or-vis-test', 'sk-or-v1-test']) {
    test('$key: models, chat and balance use matching provider', () async {
      final provider = AuthUtils.detectProviderFromApiKey(key)!;
      final paths = <String>[];
      final client = OpenRouterClient(
        apiKey: key,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            startsWith(AuthUtils.baseUrlForProvider(provider)),
          );
          expect(request.headers['Authorization'], 'Bearer $key');
          paths.add(request.url.path);
          if (request.url.path.endsWith('/models')) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'data': [
                    {
                      'id': 'test/model',
                      'name': 'Модель',
                      'pricing': {'prompt': 0.1, 'completion': '0.2'},
                    },
                    {'id': 'test/model', 'name': 'Duplicate'},
                  ],
                }),
              ),
              200,
            );
          }
          if (request.url.path.endsWith('/chat/completions')) {
            final body = jsonDecode(request.body);
            expect(body['model'], 'test/model');
            expect(body['stream'], isFalse);
            expect(body['messages'][0]['content'], 'Привет');
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {'content': 'Ответ'},
                    },
                  ],
                }),
              ),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': provider == AuthProvider.vsegpt
                  ? {'credits': 12.5}
                  : {'total_credits': 20, 'total_usage': 7.5},
            }),
            200,
          );
        }),
      );
      final models = await client.getModels();
      expect(models.length, 1);
      expect(models.single['name'], 'Модель');
      expect(models.single['pricing']['prompt'], '0.1');
      expect(models.single['context_length'], '0');
      final reply = await client.sendMessage('Привет', 'test/model');
      expect(reply['choices'][0]['message']['content'], 'Ответ');
      expect(
        await client.getBalance(),
        provider == AuthProvider.vsegpt ? '12.50₽' : '\$12.50',
      );
      expect(paths.length, 3);
    });
  }

  test('model retrieval failure does not invent fallback model IDs', () async {
    final client = OpenRouterClient(
      apiKey: 'sk-or-v1-test',
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await expectLater(client.getModels(), throwsException);
  });

  test('chat errors do not expose server bodies or keys', () async {
    final client = OpenRouterClient(
      apiKey: 'sk-or-v1-secret',
      client: MockClient((_) async => http.Response('sk-or-v1-secret', 401)),
    );
    expect(
      (await client.sendMessage('test', 'model'))['error'],
      isNot(contains('secret')),
    );
  });
}
