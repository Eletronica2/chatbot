import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import 'api_config.dart';

class AuthService extends ChangeNotifier {
  static const String _storageKey = 'admin_panel.auth.session';
  static const String _selectedTenantKey = 'admin_panel.auth.selected_tenant';
  static const Set<String> _superadminRoles = <String>{
    'superadmin',
    'system-admin',
    'system_admin',
    'systemadmin',
  };

  AppUser? _user;
  String? _lastError;
  String? _selectedTenantId;
  String? _selectedTenantDisplayName;

  AppUser? get currentUser => _user;
  bool get isAuthenticated => _user != null && (_user!.accessToken.isNotEmpty);
  bool get isSuperadmin =>
      _user != null && _superadminRoles.contains(_user!.role.toLowerCase());
  String? get accessToken => _user?.accessToken;
  String? get homeTenantId => _user?.tenantId;
  String? get tenantId => _selectedTenantId ?? _user?.tenantId;
  /// Nome comercial em memória (preenchido ao selecionar empresa em Clientes).
  String? get activeTenantDisplayName => _selectedTenantDisplayName;
  String? get lastError => _lastError;

  Future<void> restoreSession() async {
    _lastError = null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _clearStoredSession();
        return;
      }

      final storedUser = AppUser.fromStorageJson(decoded);
      if (storedUser.accessToken.isEmpty) {
        await _clearStoredSession();
        return;
      }

      final currentUser = await _fetchCurrentUser(storedUser.accessToken);
      if (currentUser == null) {
        await _clearStoredSession();
        return;
      }

      _user = currentUser;
      final storedTenantId = prefs.getString(_selectedTenantKey);
      _selectedTenantId = isSuperadmin
          ? (storedTenantId?.trim().isNotEmpty == true
              ? storedTenantId!.trim()
              : currentUser.tenantId)
          : currentUser.tenantId;
      _selectedTenantDisplayName = null;
      await _persistSession(currentUser);
      notifyListeners();
    } catch (_) {
      await _clearStoredSession();
    }
  }

  Future<bool> login(String email, String password) async {
    _lastError = null;
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/v1/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _lastError =
            _extractError(response.body) ?? 'Email ou senha incorretos.';
        return false;
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        _lastError = 'Resposta invalida do servidor.';
        return false;
      }
      _user = AppUser.fromLoginJson(data);
      if (_user == null || _user!.accessToken.isEmpty) {
        _lastError = 'Não foi possível iniciar a sessão.';
        return false;
      }
      _selectedTenantId = _user!.tenantId;
      _selectedTenantDisplayName = null;
      await _persistSession(_user!);
      notifyListeners();
      return true;
    } on TimeoutException {
      _lastError = 'O servidor demorou para responder.';
      return false;
    } catch (_) {
      _lastError = 'Não foi possível conectar ao servidor.';
      return false;
    }
  }

  Future<String?> completeInvite({
    required String token,
    required String newPassword,
  }) async {
    return _submitTokenPassword(
      path: '/api/v1/auth/complete-invite',
      token: token,
      newPassword: newPassword,
    );
  }

  Future<String?> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    return _submitTokenPassword(
      path: '/api/v1/auth/reset-password/confirm',
      token: token,
      newPassword: newPassword,
    );
  }

  Future<void> refreshCurrentUser() async {
    final token = _user?.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }
    final currentUser = await _fetchCurrentUser(token);
    if (currentUser == null) {
      logout();
      return;
    }
    _user = currentUser;
    _selectedTenantId ??= currentUser.tenantId;
    if (!isSuperadmin) {
      _selectedTenantId = currentUser.tenantId;
      _selectedTenantDisplayName = null;
    }
    await _persistSession(currentUser);
    notifyListeners();
  }

  Future<void> setActiveTenantId(
    String tenantId, {
    String? displayName,
  }) async {
    final normalized = tenantId.trim();
    if (normalized.isEmpty) return;
    _selectedTenantId =
        isSuperadmin ? normalized : (_user?.tenantId ?? normalized);
    final home = _user?.tenantId.trim() ?? '';
    if (!isSuperadmin ||
        _selectedTenantId == home ||
        _selectedTenantId == 'default') {
      _selectedTenantDisplayName = null;
    } else {
      final name = displayName?.trim();
      _selectedTenantDisplayName =
          (name != null && name.isNotEmpty) ? name : null;
    }
    if (_user != null) {
      await _persistSession(_user!);
    }
    notifyListeners();
  }

  Future<void> resetActiveTenantId() async {
    if (_user == null) return;
    _selectedTenantId = _user!.tenantId;
    _selectedTenantDisplayName = null;
    await _persistSession(_user!);
    notifyListeners();
  }

  void logout() {
    _user = null;
    _lastError = null;
    _selectedTenantId = null;
    _selectedTenantDisplayName = null;
    unawaited(_clearStoredSession());
    notifyListeners();
  }

  Future<AppUser?> _fetchCurrentUser(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/api/v1/auth/me'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return null;
      }
      return AppUser.fromUserJson(data, accessToken: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSession(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(user.toStorageJson()));
    final tenantId = _selectedTenantId ?? user.tenantId;
    await prefs.setString(_selectedTenantKey, tenantId);
  }

  Future<void> _clearStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_selectedTenantKey);
  }

  String? _extractError(String rawBody) {
    if (rawBody.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _submitTokenPassword({
    required String path,
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractError(response.body) ?? 'Não foi possível concluir a ação.';
      }
      return null;
    } on TimeoutException {
      return 'O servidor demorou para responder.';
    } catch (_) {
      return 'Não foi possível conectar ao servidor.';
    }
  }
}

final authService = AuthService();
