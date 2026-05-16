import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

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
      ? 'Defina uma senha para concluir o acesso ao painel.'
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
      setState(() => _error = 'Token inválido ou ausente no link.');
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
      backgroundColor: const Color(0xFF05060B),
      body: PremiumPageBackground(
        intensity: AmbientIntensity.vivid,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: PremiumGlassCard(
                padding: const EdgeInsets.all(32),
                child: _done ? _buildSuccessState() : _buildFormState(),
              ),
            ),
          ),
        ),
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
                  gradient: AppGradients.premiumOrange,
                  borderRadius: AppRadius.md,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Icon(
                  _isInvite ? Icons.person_add_alt_1_rounded : Icons.lock_reset_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: GoogleFonts.inter(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
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
            style: GoogleFonts.inter(color: AppColors.text, fontSize: 14),
            decoration: _inputDecoration('Digite sua nova senha').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.textSoft,
                  size: 18,
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
            style: GoogleFonts.inter(color: AppColors.text, fontSize: 14),
            decoration: _inputDecoration('Repita a senha').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.textSoft,
                  size: 18,
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
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: AppRadius.md,
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(color: AppColors.danger, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          _PrimaryActionButton(
            label: _primaryLabel,
            loading: _loading,
            onTap: _loading ? null : _submit,
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: widget.onBackToLogin,
              child: Text(
                'Voltar para o login',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.35),
                blurRadius: 28,
                spreadRadius: -8,
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: AppColors.success, size: 34),
        ),
        const SizedBox(height: 18),
        Text(
          _isInvite ? 'Acesso liberado' : 'Senha redefinida',
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isInvite
              ? 'Seu acesso foi ativado. Agora você já pode entrar no painel com o e-mail convidado.'
              : 'Sua nova senha foi salva com sucesso. Entre novamente no painel para continuar.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        _PrimaryActionButton(
          label: 'Ir para o login',
          loading: false,
          onTap: widget.onBackToLogin,
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppColors.textSoft, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF080A12).withValues(alpha: 0.85),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
      ),
      errorStyle: GoogleFonts.inter(color: AppColors.danger, fontSize: 11.5),
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
      style: GoogleFonts.inter(
        color: AppColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _PrimaryActionButton extends StatefulWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.onTap,
    required this.loading,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  State<_PrimaryActionButton> createState() => _PrimaryActionButtonState();
}

class _PrimaryActionButtonState extends State<_PrimaryActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppGradients.premiumOrange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: _hovered ? 0.55 : 0.4),
                blurRadius: _hovered ? 30 : 22,
                spreadRadius: _hovered ? -4 : -8,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
        ),
      ),
    );
  }
}
