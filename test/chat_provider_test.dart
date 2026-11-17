import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_chat_flutter/api/openrouter_client.dart';
import 'package:ai_chat_flutter/providers/chat_provider.dart';
import 'package:ai_chat_flutter/services/database_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  for (final withUsage in [false, true]) {
    test('chat persists replies and handles usage=$withUsage', () async {
      final directory =
          await Directory.systemTemp.createTemp('aichat-provider-');
      final db = DatabaseService.forTesting(
          factory: databaseFactoryFfi, path: p.join(directory.path, 'test.db'));
      final client = OpenRouterClient(
          apiKey: 'sk-or-vis-test',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/models')) {
              return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'id': 'test/model',
                        'name': 'Test model',
                        'pricing': {'prompt': 0.1, 'completion': 0.2}
                      }
                    ]
                  }),
                  200);
            }
            if (request.url.path.endsWith('/balance')) {
              return http.Response(
                  '{"status":"ok","data":{"credits":12}}', 200);
            }
            return http.Response.bytes(
                utf8.encode(jsonEncode({
                  'choices': [
                    {
                      'message': {'content': 'Ответ'}
                    }
                  ],
                  if (withUsage)
                    'usage': {
                      'total_tokens': 3,
                      'prompt_tokens': 1,
                      'completion_tokens': 2,
                      'cost': '0.5'
                    },
                })),
                200);
          }));
      final provider = ChatProvider(api: client, database: db);
      try {
        await provider.ready;
        expect(provider.currentModel, 'test/model');
        expect(provider.balance, '12.00₽');
        await provider.sendMessage('Привет', trackAnalytics: false);
        expect(provider.messages.length, 2);
        expect(provider.messages.last.content, 'Ответ');
        expect(provider.messages.last.cost, withUsage ? 0.5 : 0);
        expect(provider.isLoading, isFalse);
        expect((await db.getMessages()).length, 2);
      } finally {
        provider.dispose();
        await db.close();
        await directory.delete(recursive: true);
      }
    });
  }
}
