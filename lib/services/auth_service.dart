import '../models/auth_data.dart';
import 'balance_service.dart';

class Registration {
  const Registration(this.auth, this.pin, this.balance);
  final AuthData auth;
  final String pin;
  final double balance;
}

class AuthService {
  AuthService({required this.store, BalanceService? balanceService})
      : _balanceService = balanceService ?? BalanceService();
  final AuthStore store;
  final BalanceService _balanceService;

  Future<bool> hasAuth() async => await store.readAuth() != null;

  Future<Registration> register(String input) async {
    final key = input.trim();
    final provider = AuthUtils.detectProviderFromApiKey(key);
    if (provider == null) {
      throw const AuthException(
        'Введите ключ OpenRouter (sk-or-v1-…) или VSEGPT (sk-or-vv-… / sk-or-vis-…).',
      );
    }
    final balance = await _balanceService.getBalance(key);
    if (balance <= 0) {
      throw const AuthException(
        'Баланс должен быть больше нуля. Пополните счёт.',
      );
    }
    final pin = AuthUtils.generatePin();
    final salt = AuthUtils.generateSalt();
    final auth = AuthData(
      apiKey: key,
      provider: provider.name,
      baseUrl: AuthUtils.baseUrlForProvider(provider),
      pinHash: AuthUtils.hashPin(pin, salt: salt),
      salt: salt,
    );
    await store.saveAuth(auth);
    return Registration(auth, pin, balance);
  }

  Future<AuthData> unlock(String pin) async {
    final auth = await store.readAuth();
    if (auth == null) {
      throw const AuthException(
        'Ключ не сохранён. Сбросьте вход и введите ключ заново.',
      );
    }
    if (!AuthUtils.verifyPin(pin, auth.pinHash, salt: auth.salt)) {
      throw const AuthException('Неверный PIN. Попробуйте ещё раз.');
    }
    return auth;
  }

  Future<void> reset() => store.deleteAuth();
}
