import 'package:flutter/material.dart';

import 'package:admin_panel/screens/dashboard_screen.dart';
import 'package:admin_panel/screens/login_screen.dart';
import 'package:admin_panel/screens/token_action_screen.dart';
import 'package:admin_panel/services/auth_service.dart';
import 'package:admin_panel/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await authService.restoreSession();
  runApp(const AdminPanelApp());
}

class AdminPanelApp extends StatefulWidget {
  const AdminPanelApp({super.key});

  @override
  State<AdminPanelApp> createState() => _AdminPanelAppState();
}

class _AdminPanelAppState extends State<AdminPanelApp> {
  bool _isAuthenticated = authService.isAuthenticated;
  String? _routeOverride;

  void _handleLogin() =>
      setState(() => _isAuthenticated = authService.isAuthenticated);

  void _handleLogout() {
    authService.logout();
    setState(() => _isAuthenticated = false);
  }

  void _backToLogin() {
    setState(() {
      _routeOverride = '';
      _isAuthenticated = authService.isAuthenticated;
    });
  }

  ({String path, String token}) _resolvePublicRoute() {
    final raw = _routeOverride ?? Uri.base.fragment;
    if (raw.trim().isEmpty) {
      return (path: '', token: '');
    }

    final normalized = raw.startsWith('/') ? raw.substring(1) : raw;
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return (path: '', token: '');
    }
    return (
      path: uri.path.trim().toLowerCase(),
      token: uri.queryParameters['token']?.trim() ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final publicRoute = _resolvePublicRoute();
    final tokenAction = !_isAuthenticated &&
            publicRoute.token.isNotEmpty &&
            (publicRoute.path == 'accept-invite' ||
                publicRoute.path == 'reset-password')
        ? TokenActionScreen(
            mode: publicRoute.path == 'accept-invite'
                ? TokenActionMode.acceptInvite
                : TokenActionMode.resetPassword,
            token: publicRoute.token,
            onBackToLogin: _backToLogin,
          )
        : null;

    final baseTheme = AdminAppTheme.build();

    return MaterialApp(
      title: 'Painel do Chatbot',
      theme: baseTheme,
      darkTheme: baseTheme,
      themeMode: ThemeMode.dark,
      home: tokenAction ??
          (_isAuthenticated
          ? DashboardScreen(onLogout: _handleLogout)
          : LoginScreen(onLogin: _handleLogin)),
    );
  }
}
