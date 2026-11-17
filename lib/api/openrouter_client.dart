import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_data.dart';
import '../services/balance_service.dart';

/// OpenAI-совместимый клиент для обоих провайдеров.
class OpenRouterClient {
  OpenRouterClient({required this.apiKey, http.Client? client})
      : provider = AuthUtils.detectProviderFromApiKey(apiKey) ??
            (throw const AuthException('Неизвестный формат API-ключа.')),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String apiKey;
  final AuthProvider provider;
  final http.Client _client;
  final bool _ownsClient;
  String get baseUrl => AuthUtils.baseUrlForProvider(provider);
  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'X-Title': 'AI Chat Flutter',
      };

  Future<List<Map<String, dynamic>>> getModels() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/models'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const AuthException(
          'Не удалось загрузить модели. Проверьте ключ и подключение.',
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map || body['data'] is! List) {
        throw const AuthException(
          'Провайдер вернул некорректный список моделей.',
        );
      }
      final models = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final raw in body['data'] as List) {
        if (raw is! Map || raw['id'] is! String) continue;
        final id = raw['id'] as String;
        if (!seen.add(id)) continue;
        final pricing =
            raw['pricing'] is Map ? raw['pricing'] as Map : const {};
        final topProvider =
            raw['top_provider'] is Map ? raw['top_provider'] as Map : const {};
        models.add({
          'id': id,
          'name': (raw['name'] ?? id).toString(),
          'pricing': {
            'prompt': (pricing['prompt'] ?? '0').toString(),
            'completion': (pricing['completion'] ?? '0').toString(),
          },
          'context_length':
              (raw['context_length'] ?? topProvider['context_length'] ?? 0)
                  .toString(),
        });
      }
      return models;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Не удалось загрузить модели. Проверьте подключение и повторите.',
      );
    }
  }

  Future<Map<String, dynamic>> sendMessage(String message, String model) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': message},
              ],
              'max_tokens': 1000,
              'temperature': 0.7,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        return {
          'error':
              'Ошибка API (${response.statusCode}). Проверьте ключ, баланс и выбранную модель.',
        };
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) {
        return {'error': 'Некорректный ответ провайдера.'};
      }
      if (body['error'] != null || body['status'] == 'error') {
        return {
          'error':
              'Провайдер отклонил запрос. Проверьте баланс и выбранную модель.',
        };
      }
      return body;
    } catch (_) {
      return {
        'error':
            'Не удалось получить ответ. Проверьте подключение и повторите.',
      };
    }
  }

  Future<String> getBalance() async {
    try {
      final balance = await BalanceService(client: _client).getBalance(apiKey);
      return provider == AuthProvider.vsegpt
          ? '${balance.toStringAsFixed(2)}₽'
          : '\$${balance.toStringAsFixed(2)}';
    } on AuthException catch (e) {
      return e.message;
    }
  }

  String formatPricing(double pricing) => provider == AuthProvider.vsegpt
      ? '${pricing.toStringAsFixed(3)}₽/K'
      : '\$${(pricing * 1000000).toStringAsFixed(3)}/M';

  void close() {
    if (_ownsClient) _client.close();
  }
}
