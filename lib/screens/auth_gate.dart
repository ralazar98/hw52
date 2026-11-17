// Сохраняем совместимость с Material API исходного Flutter-проекта.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/openrouter_client.dart';
import '../models/auth_data.dart';
import '../providers/chat_provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.auth, this.chatBuilder});
  final AuthService? auth;
  final Widget Function(AuthData auth, VoidCallback lock)? chatBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final _auth = widget.auth ?? AuthService(store: DatabaseService());
  AuthData? _session;

  void _lock() => setState(() => _session = null);

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return AuthScreen(
        auth: _auth,
        onAuthenticated: (auth) => setState(() => _session = auth),
      );
    }
    if (widget.chatBuilder != null) return widget.chatBuilder!(session, _lock);
    return ChangeNotifierProvider(
      create: (_) =>
          ChatProvider(api: OpenRouterClient(apiKey: session.apiKey)),
      child: ChatScreen(onLock: _lock),
    );
  }
}
