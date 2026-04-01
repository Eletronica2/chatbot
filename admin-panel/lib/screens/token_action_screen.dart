import 'package:flutter/material.dart';

import '../services/auth_service.dart';

const _kPageBg = Color(0xFF0B1120);
const _kSurface = Color(0xFF1E293B);
const _kBorder = Color(0xFF334155);
const _kText = Colors.white;
const _kMuted = Color(0xFF94A3B8);
const _kAccent = Color(0xFF4F46E5);
const _kDanger = Color(0xFFEF4444);
const _kSuccess = Color(0xFF10B981);

enum TokenActionMode { acceptInvite, resetPassword }

class TokenActionScreen extends StatefulWidget {
  const TokenActionScreen({
    super.key,
    required this.mode,
    required this.token,
    required this.onBackToLogin,
  });

  final TokenActionMode mode;
  final String token;
  final VoidCallback onBackToLogin;

  @override
  State<TokenActionScreen> createState() => _TokenActionScreenState();
}

class _TokenActionScreenState extends State<TokenActionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _done = false;
  String? _error;

  bool get _isInvite => widget.mode == TokenActionMode.acceptInvite;

  String get _title => _isInvite ? 'Aceitar convite' : 'Redefinir senha';

  String get _subtitle => _isInvite
      ? 'Defina uma senha para concluir o acesso ao painel do cliente.'
      : 'Cadastre uma nova senha para continuar usando o painel.';

  String get _primaryLabel => _isInvite ? 'Concluir convite' : 'Salvar nova senha';

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.token.trim().isEmpty) {
      setState(() => _error = 'Token invalido ou ausente no link.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = _isInvite
        ? await authService.completeInvite(
            token: widget.token.trim(),
            newPassword: _passwordCtrl.text.trim(),
          )
        : await authService.confirmPasswordReset(
            token: widget.token.trim(),
            newPassword: _passwordCtrl.text.trim(),
          );

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result;
      _done = result == null;
    });
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
                colors: [Color(0xFF0F172A), Color(0xFF172554)],
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 42,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: _done ? _buildSuccessState() : _buildFormState(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isInvite ? Icons.person_add_alt_1_rounded : Icons.lock_reset_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: const TextStyle(color: _kMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _Label(text: 'Nova senha'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            style: const TextStyle(color: _kText),
            decoration: _inputDecoration('Digite sua nova senha').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: _kMuted,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().length < 6) {
                return 'Use pelo menos 6 caracteres.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _Label(text: 'Confirmar senha'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            style: const TextStyle(color: _kText),
            decoration: _inputDecoration('Repita a senha').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: _kMuted,
                ),
              ),
            ),
            validator: (value) {
              if (value != _passwordCtrl.text) {
                return 'As senhas precisam ser iguais.';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kDanger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kDanger.withValues(alpha: 0.35)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: _kDanger, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_primaryLabel),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: widget.onBackToLogin,
              child: const Text('Voltar para o login'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _kSuccess.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Icon(Icons.check_rounded, color: _kSuccess, size: 34),
        ),
        const SizedBox(height: 18),
        Text(
          _isInvite ? 'Acesso liberado' : 'Senha redefinida',
          style: const TextStyle(
            color: _kText,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isInvite
              ? 'Seu acesso foi ativado. Agora voce ja pode entrar no painel com o email convidado.'
              : 'Sua nova senha foi salva com sucesso. Entre novamente no painel para continuar.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            onPressed: widget.onBackToLogin,
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ir para o login'),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kDanger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kDanger, width: 2),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
