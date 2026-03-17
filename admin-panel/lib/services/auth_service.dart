import 'dart:async';

import '../models/app_user.dart';

class AuthService {
  AppUser? _user;

  AppUser? get currentUser => _user;

  bool get isAuthenticated => _user != null;

  Future<bool> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (email.isEmpty || password.length < 4) {
      return false;
    }
    _user = AppUser(email: email, displayName: email.split('@').first);
    return true;
  }

  void logout() {
    _user = null;
  }
}

final authService = AuthService();
