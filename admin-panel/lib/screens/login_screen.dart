import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'admin@bellamassa.com.br');
  final _passwordCtrl = TextEditingController(text: 'Bella@2026!');
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await authService.login(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      widget.onLogin();
    } else {
      setState(() => _error = authService.lastError ?? 'Email ou senha incorretos.');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: _Glow(size: 380, color: const Color(0xFF4F46E5).withValues(alpha: 0.18)),
          ),
          Positioned(
            bottom: -160,
            right: -100,
            child: _Glow(size: 480, color: const Color(0xFF818CF8).withValues(alpha: 0.12)),
          ),
          Positioned(
            top: 80,
            right: 60,
            child: _Glow(size: 220, color: const Color(0xFF06B6D4).withValues(alpha: 0.08)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 48,
                        offset: const Offset(0, 24),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(36),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 21),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'ChatBot Admin',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Bem-vindo de volta',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Acesse o painel de controle',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 28),
                        _DarkLabel('Email'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: _darkInput('admin@empresa.com'),
                          validator: (v) =>
                              v != null && v.contains('@') ? null : 'Email inválido',
                        ),
                        const SizedBox(height: 16),
                        _DarkLabel('Senha'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onFieldSubmitted: (_) => _submit(),
                          decoration: _darkInput('Digite sua senha').copyWith(
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: const Color(0xFF64748B),
                                size: 18,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              v != null && v.length >= 3 ? null : 'Senha muito curta',
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: _GradientButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    'Entrar',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _darkInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
      errorStyle: const TextStyle(color: Color(0xFFEF4444)),
    );
  }
}

class _DarkLabel extends StatelessWidget {
  const _DarkLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w500),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFF4F46E5)])
            : const LinearGradient(colors: [Color(0xFF475569), Color(0xFF334155)]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: child,
      ),
    );
  }
}

