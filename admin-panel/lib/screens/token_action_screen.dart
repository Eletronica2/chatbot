import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/public_surface.dart';

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

  String get _primaryLabel =>
      _isInvite ? 'Concluir convite' : 'Salvar nova senha';

  bool get _tokenMissing => widget.token.trim().isEmpty;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tokenMissing) {
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
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: PublicAtmosphere()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 20 : 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                      child: _done ? _buildSuccessState() : _buildFormState(),
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

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandLockup(markSize: 36, fontSize: 20)),
          const SizedBox(height: 22),
          Text(
            _title,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (_tokenMissing) ...[
            const SizedBox(height: 16),
            const PublicErrorBanner(text: 'Token inválido ou ausente no link.'),
          ],
          const SizedBox(height: 24),
          Text(
            'Nova senha',
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            enabled: !_tokenMissing,
            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
            decoration: publicInputDecoration(
              hint: 'Digite sua nova senha',
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
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
          Text(
            'Confirmar senha',
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            enabled: !_tokenMissing,
            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
            decoration: publicInputDecoration(
              hint: 'Repita a senha',
              suffix: IconButton(
                tooltip: _obscureConfirm ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
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
            PublicErrorBanner(text: _error!),
          ],
          const SizedBox(height: 22),
          PublicPrimaryButton(
            label: _primaryLabel,
            loading: _loading,
            onTap: _loading || _tokenMissing ? null : _submit,
            expand: true,
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: widget.onBackToLogin,
              child: Text(
                'Voltar para o login',
                style: GoogleFonts.manrope(
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
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
          ),
          child: const Icon(Icons.check_rounded, color: AppColors.success, size: 32),
        ),
        const SizedBox(height: 18),
        Text(
          _isInvite ? 'Acesso liberado' : 'Senha redefinida',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isInvite
              ? 'Seu acesso foi ativado. Agora você já pode entrar no painel com o e-mail convidado.'
              : 'Sua nova senha foi salva com sucesso. Entre novamente no painel para continuar.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        PublicPrimaryButton(
          label: 'Ir para o login',
          loading: false,
          onTap: widget.onBackToLogin,
          expand: true,
        ),
      ],
    );
  }
}

