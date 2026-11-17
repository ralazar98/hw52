import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_data.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BalanceService {
  BalanceService({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client;
  final http.Client? _client;
  final Duration timeout;

  Future<double> getBalance(String key) async {
    final provider = AuthUtils.detectProviderFromApiKey(key);
    if (provider == null) {
      throw const AuthException(
        'Неизвестный формат ключа. Используйте OpenRouter или VSEGPT.',
      );
    }
    final client = _client ?? http.Client();
    try {
      final path = provider == AuthProvider.vsegpt ? 'balance' : 'credits';
      final response = await client.get(
        Uri.parse('${AuthUtils.baseUrlForProvider(provider)}/$path'),
        headers: {'Authorization': 'Bearer ${key.trim()}'},
      ).timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AuthException(
          'Ключ недействителен или доступ запрещён. Проверьте ключ.',
        );
      }
      if (response.statusCode == 402) {
        throw const AuthException(
          'Баланс должен быть больше нуля. Пополните счёт.',
        );
      }
      if (response.statusCode != 200) {
        throw const AuthException(
          'Не удалось проверить баланс. Повторите позже.',
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map) throw const FormatException();
      if (body['status'] == 'error' || body['error'] != null) {
        final reason = body['reason'];
        if (provider == AuthProvider.vsegpt &&
            reason is String &&
            reason.toLowerCase().contains('balance call disabl')) {
          throw const AuthException(
            'В кабинете VSEGPT включите «Разрешить запрашивать баланс по API» и сохраните настройки.',
          );
        }
        throw const AuthException(
          'Провайдер отклонил проверку баланса. Проверьте ключ и настройки аккаунта.',
        );
      }
      if (body['data'] is! Map) throw const FormatException();
      final data = body['data'] as Map;
      final balance = provider == AuthProvider.vsegpt
          ? _number(data['credits'])
          : _number(data['total_credits']) - _number(data['total_usage']);
      if (!balance.isFinite) throw const FormatException();
      return balance;
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException(
        'Сервер не ответил вовремя. Попробуйте ещё раз.',
      );
    } on FormatException {
      throw const AuthException(
        'Сервер вернул некорректный баланс. Повторите позже.',
      );
    } catch (_) {
      throw const AuthException(
        'Ошибка сети. Проверьте подключение и повторите.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  double _number(Object? value) {
    final number = value is num
        ? value.toDouble()
        : value is String
            ? double.tryParse(value)
            : null;
    if (number == null || !number.isFinite) throw const FormatException();
    return number;
  }
}
