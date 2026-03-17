import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:admin_panel/screens/dashboard_screen.dart';
import 'package:admin_panel/screens/login_screen.dart';

void main() {
  runApp(const AdminPanelApp());
}

class AdminPanelApp extends StatefulWidget {
  const AdminPanelApp({super.key});

  @override
  State<AdminPanelApp> createState() => _AdminPanelAppState();
}

class _AdminPanelAppState extends State<AdminPanelApp> {
  bool _isAuthenticated = false;

  void _handleLogin() => setState(() => _isAuthenticated = true);

  void _handleLogout() => setState(() => _isAuthenticated = false);

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.light(useMaterial3: true);
    return MaterialApp(
      title: 'ChatBot Admin',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF4F46E5),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFEEF2FF),
          onPrimaryContainer: Color(0xFF4338CA),
          secondary: Color(0xFF10B981),
          onSecondary: Colors.white,
          error: Color(0xFFEF4444),
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
          surfaceContainerHighest: Color(0xFFF8FAFC),
          outline: Color(0xFFE2E8F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), space: 1),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: _isAuthenticated
          ? DashboardScreen(onLogout: _handleLogout)
          : LoginScreen(onLogin: _handleLogin),
    );
  }
}
