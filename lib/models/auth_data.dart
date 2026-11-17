import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Данные локальной авторизации. PIN хранится как хэш с отдельной солью.
class AuthData {
  final int? id;
  final String apiKey;
  final String provider;
  final String baseUrl;
  final String pinHash;
  final String salt;
  final DateTime createdAt;
  final DateTime updatedAt;

  AuthData({
    this.id,
    required this.apiKey,
    required this.provider,
    required this.baseUrl,
    required this.pinHash,
    required this.salt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id ?? 1,
        'api_key': apiKey,
        'provider': provider,
        'base_url': baseUrl,
        'pin_hash': pinHash,
        'salt': salt,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory AuthData.fromMap(Map<String, Object?> map) => AuthData(
        id: map['id'] as int?,
        apiKey: map['api_key'] as String,
        provider: map['provider'] as String,
        baseUrl: map['base_url'] as String,
        pinHash: map['pin_hash'] as String,
        salt: map['salt'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  String toString() => 'AuthData(provider: $provider)';
}

enum AuthProvider { vsegpt, openrouter }

abstract interface class AuthStore {
  Future<AuthData?> readAuth();
  Future<void> saveAuth(AuthData auth);
  Future<void> deleteAuth();
}

class AuthUtils {
  static AuthProvider? detectProviderFromApiKey(String input) {
    final key = input.trim();
    if (RegExp(r'^sk-or-(vv|vis)-\S+$').hasMatch(key)) {
      return AuthProvider.vsegpt;
    }
    if (RegExp(r'^sk-or-v1-\S+$').hasMatch(key)) {
      return AuthProvider.openrouter;
    }
    return null;
  }

  static String baseUrlForProvider(AuthProvider provider) => switch (provider) {
        AuthProvider.vsegpt => 'https://api.vsegpt.ru/v1',
        AuthProvider.openrouter => 'https://openrouter.ai/api/v1',
      };

  static String labelForProvider(AuthProvider provider) => switch (provider) {
        AuthProvider.vsegpt => 'VSEGPT',
        AuthProvider.openrouter => 'OpenRouter',
      };

  static String generatePin() =>
      (1000 + Random.secure().nextInt(9000)).toString();

  static String generateSalt() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  static String hashPin(String pin, {required String salt}) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool verifyPin(
    String enteredPin,
    String storedHash, {
    required String salt,
  }) {
    if (!RegExp(r'^\d{4}$').hasMatch(enteredPin)) return false;
    final candidate = hashPin(enteredPin, salt: salt);
    if (candidate.length != storedHash.length) return false;
    var difference = 0;
    for (var i = 0; i < candidate.length; i++) {
      difference |= candidate.codeUnitAt(i) ^ storedHash.codeUnitAt(i);
    }
    return difference == 0;
  }
}
