// Сохраняем совместимость с Material API исходного Flutter-проекта.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_data.dart';
import '../services/auth_service.dart';
import '../services/balance_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.auth,
    required this.onAuthenticated,
  });
  final AuthService auth;
  final ValueChanged<AuthData> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _keyController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = true;
  bool _hasCredentials = false;
  bool _ready = false;
  String? _error;
  Registration? _created;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hasCredentials = await widget.auth.hasAuth();
      if (!mounted) return;
      setState(() {
        _hasCredentials = hasCredentials;
        _ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Не удалось открыть базу данных. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_loading || !_ready) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_hasCredentials) {
        final credentials = await widget.auth.unlock(_pinController.text);
        if (mounted) widget.onAuthenticated(credentials);
      } else {
        final credentials = await widget.auth.register(_keyController.text);
        _keyController.clear();
        if (mounted) setState(() => _created = credentials);
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
      _pinController.clear();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось прочитать или сохранить данные входа. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.reset();
      _keyController.clear();
      _pinController.clear();
      if (mounted) {
        setState(() {
          _hasCredentials = false;
          _created = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось сбросить ключ. Повторите попытку.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в AI Chat')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 24),
                  if (created != null) ...[
                    Text(
                      'Ключ ${AuthUtils.labelForProvider(AuthUtils.detectProviderFromApiKey(created.auth.apiKey)!)} сохранён. Ваш PIN:',
                    ),
                    Text(
                      'Баланс: ${created.balance.toStringAsFixed(2)} ${created.auth.provider == 'vsegpt' ? '₽' : 'USD'}',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      created.pin,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Запомните PIN. Он потребуется при следующем запуске приложения.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => widget.onAuthenticated(created.auth),
                      child: const Text('Я запомнил PIN — открыть чат'),
                    ),
                  ] else if (_ready) ...[
                    Text(
                      _hasCredentials
                          ? 'Введите четырёхзначный PIN'
                          : 'Введите API-ключ OpenRouter или VSEGPT',
                    ),
                    const SizedBox(height: 16),
                    if (_hasCredentials)
                      TextField(
                        key: const ValueKey('pin'),
                        controller: _pinController,
                        enabled: !_loading,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(labelText: 'PIN'),
                        onSubmitted: (_) => _submit(),
                      )
                    else
                      TextField(
                        key: const ValueKey('apiKey'),
                        controller: _keyController,
                        enabled: !_loading,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'API-ключ',
                          hintText: 'sk-or-v1-… / sk-or-vv-… / sk-or-vis-…',
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Text(
                        _hasCredentials ? 'Войти' : 'Проверить ключ и баланс',
                      ),
                    ),
                    if (_hasCredentials)
                      TextButton(
                        onPressed: _loading ? null : _reset,
                        child: const Text('Сбросить ключ'),
                      ),
                  ],
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  if (!_ready && !_loading)
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
