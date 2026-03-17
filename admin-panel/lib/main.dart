import 'package:flutter/material.dart';

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
    return MaterialApp(
      title: 'Chatbot Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: _isAuthenticated
          ? DashboardScreen(onLogout: _handleLogout)
          : LoginScreen(onLogin: _handleLogin),
    );
  }
}
