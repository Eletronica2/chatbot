import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';
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
  final _emailCtrl = TextEditingController(text: 'admin@bellamassa.com.br');
  final _passwordCtrl = TextEditingController(text: 'Bella@2026!');
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
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => const SignupDialog(),
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
      setState(() => _error = authService.lastError ?? 'Email ou senha incorretos.');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060B),
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 1080;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 24 : 64,
                    vertical: compact ? 24 : 40,
                  ),
                  child: compact
                      ? _compactLayout()
                      : _splitLayout(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 6, child: _LoginIntroPanel(onBackToLanding: widget.onBackToLanding)),
        const SizedBox(width: 48),
        Expanded(flex: 5, child: Center(child: _formCard(maxWidth: 460))),
      ],
    );
  }

  Widget _compactLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LoginIntroPanel(
            onBackToLanding: widget.onBackToLanding,
            compact: true,
          ),
          const SizedBox(height: 28),
          Center(child: _formCard(maxWidth: 460)),
        ],
      ),
    );
  }

  Widget _formCard({required double maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _GlassFormCard(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4060A5FA),
                          blurRadius: 22,
                          spreadRadius: -4,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppGradients.brandIcon,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Chatbot Ops',
                    style: GoogleFonts.inter(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Bem-vindo de volta',
                style: GoogleFonts.inter(
                  color: AppColors.text,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Acesse sua conta e continue transformando\natendimentos em resultados.',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 28),
              _LoginLabel('E-mail'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.inter(color: AppColors.text, fontSize: 14),
                decoration: _input(hint: 'seu@email.com'),
                validator: (v) => v != null && v.contains('@') ? null : 'E-mail inválido',
              ),
              const SizedBox(height: 16),
              _LoginLabel('Senha'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                style: GoogleFonts.inter(color: AppColors.text, fontSize: 14),
                onFieldSubmitted: (_) => _submit(),
                decoration: _input(
                  hint: '••••••••••••',
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textSoft,
                      size: 18,
                    ),
                  ),
                ),
                validator: (v) => v != null && v.length >= 3 ? null : 'Senha muito curta',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _RememberCheck(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v),
                  ),
                  const Spacer(),
                  _LinkText(
                    label: 'Esqueci minha senha',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Em breve: recuperação de senha por e-mail.')),
                      );
                    },
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
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
              _PrimaryLoginButton(
                label: 'Entrar na plataforma',
                loading: _loading,
                onTap: _loading ? null : _submit,
              ),
              const SizedBox(height: 26),
              Center(
                child: RichText(
                  text: TextSpan(
                    text: 'Ainda não tem conta? ',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: GestureDetector(
                          onTap: _openSignupDialog,
                          child: ShaderMask(
                            shaderCallback: (rect) => const LinearGradient(
                              colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                            ).createShader(rect),
                            child: Text(
                              'Cadastrar-se',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _input({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppColors.textSoft, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF080A12).withValues(alpha: 0.85),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffix,
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

// ============================================================================
// Backdrop cinematográfico para o login
// ============================================================================

class _LoginBackdrop extends StatefulWidget {
  const _LoginBackdrop();

  @override
  State<_LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<_LoginBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.heroBackdrop),
        ),
        AnimatedAmbientLayer(
          controller: _ctrl,
          intensity: AmbientIntensity.vivid,
          showGrid: false,
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => IgnorePointer(
              child: CustomPaint(painter: _LoginLinesPainter(_ctrl.value)),
            ),
          ),
        ),
        // WhatsApp orb flutuante (canto inferior esquerdo do card direito)
        const Positioned(
          left: 40,
          bottom: 80,
          child: _FloatingBadge(
            icon: Icons.chat_rounded,
            gradient: LinearGradient(
              colors: [Color(0xFF22C55E), Color(0xFF15803D)],
            ),
            glow: Color(0xFF22C55E),
          ),
        ),
        // Ícone de IA roxo flutuante (canto direito)
        const Positioned(
          right: 60,
          top: 100,
          child: _FloatingBadge(
            icon: Icons.auto_awesome_rounded,
            gradient: LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            ),
            glow: Color(0xFF8B5CF6),
          ),
        ),
      ],
    );
  }
}

class _LoginLinesPainter extends CustomPainter {
  _LoginLinesPainter(this.phase);

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          const Color(0xFF8B5CF6).withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    final phaseShift = phase * 60.0;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.18 + i * 0.12);
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 8) {
        final amplitude = (i.isEven ? 6 : 10).toDouble();
        final wave = amplitude *
            math.sin(((x + phaseShift * (i.isEven ? 1 : -1)) / 60) + i.toDouble());
        path.lineTo(x, y + wave);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoginLinesPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _FloatingBadge extends StatelessWidget {
  const _FloatingBadge({
    required this.icon,
    required this.gradient,
    required this.glow,
  });

  final IconData icon;
  final Gradient gradient;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 40, spreadRadius: -8),
            const BoxShadow(color: Color(0x55000000), blurRadius: 30, offset: Offset(0, 18)),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}

// ============================================================================
// Painel esquerdo (intro estratégico)
// ============================================================================

class _LoginIntroPanel extends StatelessWidget {
  const _LoginIntroPanel({this.onBackToLanding, this.compact = false});

  final VoidCallback? onBackToLanding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (onBackToLanding != null)
          _BackPill(onTap: onBackToLanding!),
        if (onBackToLanding != null) const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.accentPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.accentPurple.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 13, color: AppColors.accentPurple),
              const SizedBox(width: 8),
              Text(
                'PLATAFORMA ENTERPRISE',
                style: GoogleFonts.inter(
                  color: AppColors.accentPurple,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: compact ? 36 : 54,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: -1.8,
            ),
            children: [
              const TextSpan(text: 'O cockpit da sua\noperação com '),
              TextSpan(
                text: 'IA',
                style: GoogleFonts.inter(
                  fontSize: compact ? 36 : 54,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -1.8,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                    ).createShader(const Rect.fromLTWH(0, 0, 200, 60)),
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Atendimento, automações, consumo e contexto em uma experiência refinada e pronta para escala enterprise.',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 15,
            height: 1.65,
          ),
        ),
        const SizedBox(height: 32),
        const _IntroBullets(),
      ],
    );
  }
}

class _BackPill extends StatefulWidget {
  const _BackPill({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_BackPill> createState() => _BackPillState();
}

class _BackPillState extends State<_BackPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Voltar para a apresentação',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroBullets extends StatelessWidget {
  const _IntroBullets();

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('IA com contexto real do seu negócio', AppColors.accentBlue),
      ('Automações que escalam sua operação', AppColors.primary),
      ('Métricas e governança de nível enterprise', AppColors.success),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: item.$2.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: item.$2.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.check_rounded, size: 13, color: item.$2),
                ),
                const SizedBox(width: 12),
                Text(
                  item.$1,
                  style: GoogleFonts.inter(
                    color: AppColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// Glass card que envolve o formulário
// ============================================================================

class _GlassFormCard extends StatelessWidget {
  const _GlassFormCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141823), Color(0xFF0A0C14)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: AppShadows.cinematic,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Componentes auxiliares
// ============================================================================

class _LoginLabel extends StatelessWidget {
  const _LoginLabel(this.text);
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

class _RememberCheck extends StatelessWidget {
  const _RememberCheck({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: value
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.18),
                ),
                boxShadow: value
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: value
                  ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              'Lembrar de mim',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkText extends StatefulWidget {
  const _LinkText({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: GoogleFonts.inter(
            color: _hovered ? AppColors.text : AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _PrimaryLoginButton extends StatefulWidget {
  const _PrimaryLoginButton({required this.label, required this.onTap, required this.loading});

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  State<_PrimaryLoginButton> createState() => _PrimaryLoginButtonState();
}

class _PrimaryLoginButtonState extends State<_PrimaryLoginButton> {
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
          duration: const Duration(milliseconds: 200),
          height: 50,
          decoration: BoxDecoration(
            gradient: AppGradients.premiumOrange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: _hovered ? 0.55 : 0.4),
                blurRadius: _hovered ? 30 : 22,
                spreadRadius: _hovered ? -4 : -8,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
        ),
      ),
    );
  }
}

