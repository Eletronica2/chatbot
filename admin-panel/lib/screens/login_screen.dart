import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/public_surface.dart';
import 'signup_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    this.onBackToLanding,
  });

  final VoidCallback onLogin;
  final VoidCallback? onBackToLanding;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _openSignupDialog() {
    showAppDialog(
      context: context,
      builder: (_) => const SignupDialog(),
    );
  }

  /// Recuperação por e-mail NÃO existe. O reset público exige token no link.
  /// Mantemos o atalho visível com o aviso já existente — sem inventar fluxo.
  void _onForgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Em breve: recuperação de senha por e-mail.'),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await authService.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      widget.onLogin();
    } else {
      setState(() {
        _error = authService.lastError ?? 'Email ou senha incorretos.';
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = false);
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
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BrandLockup(onTap: widget.onBackToLanding),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 20 : 24,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _formCard(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrandLockup(markSize: 40, fontSize: 22)),
              const SizedBox(height: 28),
              Text(
                'E-mail',
                style: GoogleFonts.manrope(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
                decoration: publicInputDecoration(
                  hint: 'seu@email.com',
                  prefix: const Icon(Icons.mail_outline_rounded, size: 18),
                ),
                validator: (v) =>
                    v != null && v.contains('@') ? null : 'E-mail inválido',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Senha',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _onForgotPassword,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Esqueceu sua senha?',
                      style: GoogleFonts.manrope(
                        color: AppColors.primarySoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
                onFieldSubmitted: (_) => _submit(),
                decoration: publicInputDecoration(
                  hint: '••••••••',
                  prefix: const Icon(Icons.lock_outline_rounded, size: 18),
                  suffix: IconButton(
                    tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSoft,
                      size: 18,
                    ),
                  ),
                ),
                validator: (v) =>
                    v != null && v.length >= 3 ? null : 'Senha muito curta',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Lembrar de mim',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                PublicErrorBanner(text: _error!),
              ],
              const SizedBox(height: 20),
              PublicPrimaryButton(
                label: 'Entrar na plataforma',
                onTap: _loading ? null : _submit,
                loading: _loading,
                expand: true,
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    'Ainda não tem conta? ',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _openSignupDialog,
                      child: Text(
                        'Cadastre-se',
                        style: GoogleFonts.manrope(
                          color: AppColors.primarySoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
