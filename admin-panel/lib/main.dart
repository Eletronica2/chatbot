import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:admin_panel/screens/dashboard_screen.dart';
import 'package:admin_panel/screens/login_screen.dart';
import 'package:admin_panel/screens/token_action_screen.dart';
import 'package:admin_panel/services/auth_service.dart';

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

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF081120),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF7C8CFF),
        secondary: Color(0xFF38BDF8),
        surface: Color(0xFF111827),
        error: Color(0xFFEF4444),
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(
        bodyColor: const Color(0xFFE2E8F0),
        displayColor: const Color(0xFFE2E8F0),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF111827),
        contentTextStyle: TextStyle(color: Color(0xFFE2E8F0)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF7C8CFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF243041)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF243041)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF7C8CFF), width: 1.8),
        ),
      ),
    );

    return MaterialApp(
      title: 'Chatbot Admin',
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
