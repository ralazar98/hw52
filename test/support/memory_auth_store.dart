import 'package:ai_chat_flutter/models/auth_data.dart';

class MemoryAuthStore implements AuthStore {
  AuthData? value;
  bool failSave = false;
  bool failRead = false;
  bool failReset = false;
  int saves = 0;
  @override
  Future<AuthData?> readAuth() async {
    if (failRead) throw StateError('Read failure');
    return value;
  }

  @override
  Future<void> saveAuth(AuthData auth) async {
    if (failSave) throw StateError('Save failure');
    saves++;
    value = auth;
  }

  @override
  Future<void> deleteAuth() async {
    if (failReset) throw StateError('Reset failure');
    value = null;
  }
}

AuthData savedAuth({String key = 'sk-or-v1-test', String pin = '1234'}) {
  final provider = AuthUtils.detectProviderFromApiKey(key)!;
  const salt = 'test-salt';
  return AuthData(
    apiKey: key,
    provider: provider.name,
    baseUrl: AuthUtils.baseUrlForProvider(provider),
    pinHash: AuthUtils.hashPin(pin, salt: salt),
    salt: salt,
  );
}
